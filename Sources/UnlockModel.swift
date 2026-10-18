import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PDFItem: Identifiable {
    enum Status {
        case pending
        case working
        case done(URL)
        case failed(String)
    }

    let id = UUID()
    let url: URL
    var status: Status = .pending

    var isFinished: Bool {
        if case .done = status { return true }
        return false
    }
}

@MainActor
final class UnlockModel: ObservableObject {
    static let shared = UnlockModel()

    @Published var items: [PDFItem] = []
    @Published var password = ""
    @Published var isRunning = false
    @Published var notice: String?

    var hasWork: Bool { items.contains { !$0.isFinished } }

    // MARK: - 加入／移除檔案

    func add(_ urls: [URL]) {
        var skipped = 0
        for url in urls {
            let isPDF = url.pathExtension.lowercased() == "pdf"
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            guard isPDF, exists, !isDir.boolValue else { skipped += 1; continue }
            guard !items.contains(where: { $0.url == url }) else { continue }
            items.append(PDFItem(url: url))
        }
        notice = skipped > 0 ? "已略過 \(skipped) 個非 PDF 項目" : nil
    }

    func remove(_ item: PDFItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
        notice = nil
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.title = "選擇要移除密碼的 PDF"
        panel.prompt = "加入"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 執行

    func run() {
        guard !isRunning else { return }
        let password = password
        let targets = items.filter { !$0.isFinished }.map { ($0.id, $0.url) }
        guard !targets.isEmpty else { return }

        isRunning = true
        notice = nil
        for (id, _) in targets { setStatus(.pending, for: id) }

        Task {
            for (id, url) in targets {
                setStatus(.working, for: id)
                let outcome = await Task.detached(priority: .userInitiated) {
                    Result { try PDFUnlocker.unlock(url, password: password) }
                }.value
                switch outcome {
                case .success(let output): setStatus(.done(output), for: id)
                case .failure(let error):  setStatus(.failed(error.localizedDescription), for: id)
                }
            }
            isRunning = false
        }
    }

    private func setStatus(_ status: PDFItem.Status, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
    }
}
