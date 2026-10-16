import Cocoa
import CoreGraphics
import ApplicationServices

/// Dispatches actions when a blocked word is detected or when system intervention actions are requested.
public final class ActionDispatcher {
    public static let shared = ActionDispatcher()

    /// Unique magic tag placed in event user data to distinguish synthetic events from real keystrokes.
    public static let syntheticEventTag: Int64 = 0x57424C4B // 'WBLK' in ASCII

    private let deleteKeyCode: CGKeyCode = 0x33 // Standard macOS Delete / Backspace keycode

    private init() {}

    /// Performs the auto-deletion by posting `count` backspaces to the active target application.
    public func executeAutoDelete(characterCount: Int, completion: (() -> Void)? = nil) {
        guard characterCount > 0 else {
            completion?()
            return
        }

        // Optional sound feedback
        if WordStore.shared.playAlertSound {
            NSSound.beep()
        }

        // Post on the main thread after a microscopic yield so the incoming keystroke settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self = self else { return }
            self.postBackspaces(count: characterCount)
            completion?()
        }
    }

    private func postBackspaces(count: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)

        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: deleteKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: deleteKeyCode, keyDown: false) else {
                continue
            }

            // Tag each event with our magic signature so the event tap ignores it
            keyDown.setIntegerValueField(.eventSourceUserData, value: ActionDispatcher.syntheticEventTag)
            keyUp.setIntegerValueField(.eventSourceUserData, value: ActionDispatcher.syntheticEventTag)

            // Post into the system HID event stream
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Synthesizes Cmd+W to close the active tab in the frontmost browser.
    public func closeCurrentTab(completion: (() -> Void)? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let wKeyCode: CGKeyCode = 0x0D // 'w' key
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: wKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: wKeyCode, keyDown: false) else {
                completion?()
                return
            }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.setIntegerValueField(.eventSourceUserData, value: ActionDispatcher.syntheticEventTag)
            keyUp.setIntegerValueField(.eventSourceUserData, value: ActionDispatcher.syntheticEventTag)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            completion?()
        }
    }

    /// Synthesizes an Escape keystroke with syntheticEventTag so it bypasses event interception.
    /// Posts directly to the target application PID and the system HID tap.
    public func postEscapeKey(pid: pid_t? = nil, completion: (() -> Void)? = nil) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let escapeKeyCode: CGKeyCode = 0x35 // Standard macOS Escape keycode
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: escapeKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: escapeKeyCode, keyDown: false) else {
            completion?()
            return
        }
        keyDown.setIntegerValueField(.eventSourceUserData, value: ActionDispatcher.syntheticEventTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: ActionDispatcher.syntheticEventTag)

        if let pid = pid {
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        completion?()
    }

    /// Synthesizes Cmd+Ctrl+F (universal macOS full-screen toggle shortcut) to exit native full screen.
    /// Posts directly to the target application PID and the system HID tap.
    public func postToggleFullScreenShortcut(pid: pid_t? = nil, completion: (() -> Void)? = nil) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let fKeyCode: CGKeyCode = 0x03 // 'f' key
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: fKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: fKeyCode, keyDown: false) else {
            completion?()
            return
        }
        keyDown.flags = [.maskCommand, .maskControl]
        keyUp.flags = [.maskCommand, .maskControl]
        keyDown.setIntegerValueField(.eventSourceUserData, value: ActionDispatcher.syntheticEventTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: ActionDispatcher.syntheticEventTag)

        if let pid = pid {
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        completion?()
    }

    /// Exits full-screen mode reliably across all apps and browsers using a layered strategy:
    /// 1. Re-activates the target application with activateIgnoringOtherApps so it receives input.
    /// 2. Sets AXFullScreen = false and clicks AXFullScreenButton via macOS Accessibility API.
    /// 3. Sends synthetic Escape key to exit HTML5 video players (YouTube, Netflix, etc.).
    /// 4. Sends synthetic Cmd+Ctrl+F shortcut to exit macOS native full screen.
    public func exitFullScreen(for targetApp: NSRunningApplication?, completion: (() -> Void)? = nil) {
        guard let app = targetApp ?? NSWorkspace.shared.frontmostApplication else {
            completion?()
            return
        }
        let pid = app.processIdentifier

        // 1. Activate the target application so it receives input
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }

        // 2. Direct macOS Accessibility API attribute manipulation
        let appRef = AXUIElementCreateApplication(pid)
        var windowVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowVal) != .success || windowVal == nil {
            AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &windowVal)
        }

        if let window = windowVal {
            let win = window as! AXUIElement
            // Set AXFullScreen to false
            AXUIElementSetAttributeValue(win, "AXFullScreen" as CFString, kCFBooleanFalse)

            // Also check full screen button
            var btnVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(win, "AXFullScreenButton" as CFString, &btnVal) == .success,
               let btn = btnVal {
                AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
            }
        }

        // 3. Post Escape (for in-browser HTML5 video players)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.postEscapeKey(pid: pid)
        }

        // 4. Post Cmd+Ctrl+F (for native macOS full-screen windows)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.postToggleFullScreenShortcut(pid: pid)
        }

        // 5. Follow-up Escape pass for nested video players
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            self?.postEscapeKey(pid: pid) {
                completion?()
            }
        }
    }
}
