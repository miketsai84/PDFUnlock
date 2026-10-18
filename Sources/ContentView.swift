import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: UnlockModel
    @State private var isTargeted = false
    @State private var showPassword = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            dropZone
            if !model.items.isEmpty { fileList }
            passwordRow
            footer
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 560)
    }

    // MARK: - 拖放區

    private var dropZone: some View {
        Button(action: model.choose) {
            VStack(spacing: 8) {
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                    .font(.system(size: 34, weight: .light))
                Text(isTargeted ? "放開以加入檔案" : "拖曳 PDF 到這裡，或點擊選擇檔案")
                    .font(.headline)
                Text("可一次加入多個檔案")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: model.items.isEmpty ? 190 : 110)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return !urls.isEmpty
        } isTargeted: {
            isTargeted = $0
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    // MARK: - 檔案清單

    private var fileList: some View {
        VStack(spacing: 6) {
            List {
                ForEach(model.items) { item in
                    FileRow(item: item)
                        .listRowSeparator(.visible)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))

            HStack {
                if let notice = model.notice {
                    Text(notice).font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button("全部清除", action: model.clear)
                    .buttonStyle(.link)
                    .disabled(model.isRunning)
            }
        }
    }

    // MARK: - 密碼與執行

    private var passwordRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("現有密碼").font(.subheadline.weight(.medium))

            HStack(spacing: 8) {
                Group {
                    if showPassword {
                        TextField("輸入 PDF 目前的開啟密碼", text: $model.password)
                    } else {
                        SecureField("輸入 PDF 目前的開啟密碼", text: $model.password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .focused($passwordFocused)
                .onSubmit(model.run)

                Button {
                    showPassword.toggle()
                    // 切換欄位類型會失去焦點，補回去以維持英文輸入
                    DispatchQueue.main.async { passwordFocused = true }
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .frame(width: 18)
                }
                .help(showPassword ? "隱藏密碼" : "顯示密碼")
            }
            // 密碼欄位強制英文輸入：取得焦點時切換，離開／切到其他 App 時還原
            .onChange(of: passwordFocused) { focused in
                if focused { InputSourceGuard.forceASCII() } else { InputSourceGuard.restore() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                InputSourceGuard.restore()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if passwordFocused { InputSourceGuard.forceASCII() }
            }

            Text("輸入密碼時會自動切換為英文輸入法；若密碼含中文，請用 ⌘V 貼上。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: model.run) {
                HStack {
                    if model.isRunning { ProgressView().controlSize(.small) }
                    Text(model.isRunning ? "處理中…" : "移除密碼並另存")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.hasWork || model.isRunning)
        }
    }

    private var footer: some View {
        Text("輸出位置：與原檔案相同的資料夾，檔名加上「_unlocked」。原檔案不會被修改或覆蓋。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - 單一檔案列

private struct FileRow: View {
    @EnvironmentObject private var model: UnlockModel
    let item: PDFItem

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if case .done(let output) = item.status {
                Button { model.reveal(output) } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中顯示")
            }
            if !model.isRunning {
                Button { model.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("從清單移除")
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "lock.doc.fill").foregroundStyle(.secondary)
        case .working:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private var detail: String {
        switch item.status {
        case .pending, .working:
            return (item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        case .done(let output):
            return "已儲存：\(output.lastPathComponent)"
        case .failed(let message):
            return message
        }
    }

    private var detailColor: Color {
        switch item.status {
        case .done:   return .green
        case .failed: return .red
        default:      return .secondary
        }
    }
}
