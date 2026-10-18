import Carbon.HIToolbox

/// 密碼欄位專用：取得焦點時切到英文（ASCII）輸入法，離開時還原使用者原本的輸入法。
@MainActor
enum InputSourceGuard {
    private static var saved: TISInputSource?

    static func forceASCII() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()
        else { return }
        guard !CFEqual(current, ascii) else { return }   // 已經是英文
        if saved == nil { saved = current }
        TISSelectInputSource(ascii)
    }

    static func restore() {
        guard let source = saved else { return }
        saved = nil
        TISSelectInputSource(source)
    }
}
