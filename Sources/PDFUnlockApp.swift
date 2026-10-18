import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        InputSourceGuard.restore()   // 結束時還原使用者原本的輸入法
    }

    // 把 PDF 拖到 Dock 圖示、或在 Finder 以「打開方式」開啟時會進到這裡
    func application(_ application: NSApplication, open urls: [URL]) {
        UnlockModel.shared.add(urls)
    }
}

@main
struct PDFUnlockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("PDF 密碼移除工具", id: "main") {
            ContentView()
                .environmentObject(UnlockModel.shared)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 540, height: 600)
    }
}
