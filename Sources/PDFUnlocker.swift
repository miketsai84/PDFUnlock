import Foundation
import PDFKit

enum UnlockError: LocalizedError {
    case cannotOpen
    case notEncrypted
    case wrongPassword
    case needOwnerPassword
    case writeFailed
    case verifyFailed

    var errorDescription: String? {
        switch self {
        case .cannotOpen:        return "無法開啟檔案（可能已損毀或不是 PDF）"
        case .notEncrypted:      return "此檔案沒有設定密碼，不需處理"
        case .wrongPassword:     return "密碼錯誤"
        case .needOwnerPassword: return "此檔案有使用限制（如禁止列印／複製），請輸入擁有者密碼"
        case .writeFailed:       return "無法寫入檔案（請確認資料夾的寫入權限）"
        case .verifyFailed:      return "輸出檔驗證失敗，已自動刪除"
        }
    }
}

enum PDFUnlocker {
    /// 解除 `sourceURL` 的密碼，並將無密碼版本存到同一資料夾，回傳輸出檔 URL。
    /// 原檔不會被修改；輸出檔名為「原檔名_unlocked.pdf」，若已存在則自動加編號，不覆蓋任何檔案。
    static func unlock(_ sourceURL: URL, password: String) throws -> URL {
        guard let source = PDFDocument(url: sourceURL) else { throw UnlockError.cannotOpen }
        guard source.isEncrypted else { throw UnlockError.notEncrypted }

        // 需要密碼才能開啟，或能開啟但有限制 → 必須提供有效密碼
        if source.isLocked {
            guard source.unlock(withPassword: password) else { throw UnlockError.wrongPassword }
        } else if isRestricted(source) {
            // 對本來就能開啟的文件，unlock 不論密碼對錯都回傳 true，
            // 所以改以「限制是否真的被解除」判斷擁有者密碼是否正確。
            if !password.isEmpty { _ = source.unlock(withPassword: password) }
            guard !isRestricted(source) else { throw UnlockError.needOwnerPassword }
        }

        // 注意：不能直接對 source 呼叫 write —— PDFKit 會沿用 AES-128 / RC4 的原加密再寫出。
        // 所以改建一份全新、無加密的文件，把頁面（內容串流、連結等註解）原樣搬過去。
        let outline = snapshotOutline(of: source)
        let output = PDFDocument()
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index) else { throw UnlockError.cannotOpen }
            output.insert(page, at: index)
        }
        if let attributes = source.documentAttributes { output.documentAttributes = attributes }
        restoreOutline(outline, in: output)

        let destination = uniqueDestination(for: sourceURL)
        guard output.write(to: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw UnlockError.writeFailed
        }

        // 驗證：輸出檔必須能直接開啟、已無加密、頁數與原檔一致
        guard let result = PDFDocument(url: destination),
              !result.isEncrypted,
              !result.isLocked,
              result.pageCount == source.pageCount
        else {
            try? FileManager.default.removeItem(at: destination)
            throw UnlockError.verifyFailed
        }
        return destination
    }

    // MARK: - 輸出檔名

    static func uniqueDestination(for source: URL) -> URL {
        let folder = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent + "_unlocked"
        let fm = FileManager.default

        var candidate = folder.appendingPathComponent(base).appendingPathExtension("pdf")
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(index)").appendingPathExtension("pdf")
            index += 1
        }
        return candidate
    }

    // MARK: - 權限

    private static func isRestricted(_ doc: PDFDocument) -> Bool {
        !(doc.allowsPrinting && doc.allowsCopying && doc.allowsDocumentChanges
          && doc.allowsDocumentAssembly && doc.allowsCommenting && doc.allowsFormFieldEntry)
    }

    // MARK: - 書籤（目錄）

    /// 先以「頁碼」記錄書籤樹，等頁面搬到新文件後再依頁碼重建。
    private struct OutlineNode {
        var label: String?
        var isOpen: Bool
        var pageIndex: Int?
        var point: CGPoint
        var action: PDFAction?
        var children: [OutlineNode]
    }

    private static func snapshotOutline(of doc: PDFDocument) -> [OutlineNode] {
        guard let root = doc.outlineRoot else { return [] }

        func snapshot(_ node: PDFOutline) -> OutlineNode {
            var pageIndex: Int?
            var point = CGPoint.zero
            if let destination = node.destination, let page = destination.page {
                let index = doc.index(for: page)
                if index != NSNotFound { pageIndex = index; point = destination.point }
            }
            let children = (0..<node.numberOfChildren).compactMap { node.child(at: $0) }.map(snapshot)
            return OutlineNode(label: node.label, isOpen: node.isOpen, pageIndex: pageIndex,
                               point: point, action: node.action, children: children)
        }
        return (0..<root.numberOfChildren).compactMap { root.child(at: $0) }.map(snapshot)
    }

    private static func restoreOutline(_ nodes: [OutlineNode], in doc: PDFDocument) {
        guard !nodes.isEmpty else { return }

        func build(_ node: OutlineNode) -> PDFOutline {
            let item = PDFOutline()
            item.label = node.label
            if let index = node.pageIndex, let page = doc.page(at: index) {
                item.destination = PDFDestination(page: page, at: node.point)
            } else if let action = node.action {
                item.action = action
            }
            for (i, child) in node.children.enumerated() { item.insertChild(build(child), at: i) }
            item.isOpen = node.isOpen
            return item
        }

        let root = PDFOutline()
        for (i, node) in nodes.enumerated() { root.insertChild(build(node), at: i) }
        doc.outlineRoot = root
    }
}
