import Cocoa
import ApplicationServices

/// Manages Cinema Mode: detects when media or applications are in full screen,
/// intercepts attempts to exit full screen (e.g. Escape key or Cmd+Ctrl+F), and displays the user's customizable intervention pop-up.
public final class CinemaModeManager {
    public static let shared = CinemaModeManager()

    private var isCinemaPromptActive = false
    private var exitCooldownUntil: Date = .distantPast
    private var isObserving = false

    private init() {}

    public func start() {
        guard !isObserving else { return }
        isObserving = true
    }

    public func stop() {
        isObserving = false
    }

    /// Checks if the specified (or frontmost) active application has a window in full screen mode.
    public func isFrontAppFullScreen(app: NSRunningApplication? = nil) -> Bool {
        guard let targetApp = app ?? NSWorkspace.shared.frontmostApplication else { return false }
        // WordBlocker itself is not the media app
        if targetApp.processIdentifier == NSRunningApplication.current.processIdentifier {
            return false
        }

        let pid = targetApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        var windowVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowVal) != .success || windowVal == nil {
            AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &windowVal)
        }
        guard let window = windowVal else { return false }
        let win = window as! AXUIElement

        // 1. Check AXFullScreen attribute
        var fsVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, "AXFullScreen" as CFString, &fsVal) == .success,
           let isFs = fsVal as? Bool, isFs {
            return true
        }

        // 2. Check window bounds against screen dimensions (for custom full-screen video players)
        var sizeVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeVal) == .success,
           let sVal = sizeVal {
            var size = CGSize.zero
            AXValueGetValue(sVal as! AXValue, .cgSize, &size)
            if let screen = NSScreen.main {
                if size.width >= screen.frame.width - 4 && size.height >= screen.frame.height - 4 {
                    return true
                }
            }
        }

        return false
    }

    /// Intercepts the attempt to leave full screen mode (e.g. Escape key or Cmd+Ctrl+F pressed in full screen).
    /// Returns true if the event should be swallowed/blocked.
    public func handleExitAttempt() -> Bool {
        guard WordStore.shared.isCinemaModeEnabled else { return false }
        guard Date() > exitCooldownUntil else { return false }
        guard !isCinemaPromptActive else { return true }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return false
        }

        isCinemaPromptActive = true

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            InterventionModalController.shared.showCinemaMode(
                note: WordStore.shared.cinemaModeMessage,
                onStay: { [weak self] in
                    guard let self = self else { return }
                    self.isCinemaPromptActive = false
                    if #available(macOS 14.0, *) {
                        frontApp.activate()
                    } else {
                        frontApp.activate(options: .activateIgnoringOtherApps)
                    }
                },
                onExit: { [weak self] in
                    guard let self = self else { return }
                    self.isCinemaPromptActive = false
                    // Set an 8-second cooldown so window transitions and subsequent key events don't re-trap the user
                    self.exitCooldownUntil = Date().addingTimeInterval(8.0)
                    ActionDispatcher.shared.exitFullScreen(for: frontApp)
                }
            )
        }

        return true
    }
}
