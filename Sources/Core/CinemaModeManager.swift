import Cocoa
import ApplicationServices

/// Manages Cinema Mode: detects when media or applications are in full screen,
/// intercepts attempts to exit full screen (Escape key, 'F' key, or on-player exit button),
/// and displays the user's customizable intervention pop-up while preventing unauthorized exits.
public final class CinemaModeManager {
    public static let shared = CinemaModeManager()

    private var isCinemaPromptActive = false
    private var exitCooldownUntil: Date = .distantPast
    private var isObserving = false
    private var monitorTimer: Timer?

    private var wasFullScreen = false
    private var lastFullScreenPid: pid_t = 0
    private var lastFullScreenApp: NSRunningApplication?

    private init() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("CinemaModeStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if WordStore.shared.isCinemaModeEnabled {
                self?.start()
            } else {
                self?.stop()
            }
        }
    }

    /// Starts real-time Cinema Mode observation.
    public func start() {
        guard !isObserving else { return }
        isObserving = true

        monitorTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkFullScreenState()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.monitorTimer = timer
    }

    /// Stops real-time Cinema Mode observation.
    public func stop() {
        isObserving = false
        monitorTimer?.invalidate()
        monitorTimer = nil
        wasFullScreen = false
        lastFullScreenApp = nil
        lastFullScreenPid = 0
    }

    /// Background monitor loop: detects when an app transitions out of full screen via mouse click
    /// or on-player UI controls, forces it back into full screen, and triggers the Cinema intervention pop-up.
    private func checkFullScreenState() {
        guard WordStore.shared.isCinemaModeEnabled else {
            wasFullScreen = false
            return
        }
        guard !isCinemaPromptActive else { return }
        guard Date() > exitCooldownUntil else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return
        }

        let isNowFullScreen = isFrontAppFullScreen(app: frontApp)

        if isNowFullScreen {
            wasFullScreen = true
            lastFullScreenPid = frontApp.processIdentifier
            lastFullScreenApp = frontApp
        } else if wasFullScreen && (lastFullScreenPid == frontApp.processIdentifier) {
            // The active media window WAS full screen, but suddenly dropped out of full screen
            // without authorization (e.g. user clicked the exit full-screen button on the player or double-clicked)!
            wasFullScreen = true // keep marked as full screen until authorized exit
            let mediaApp = lastFullScreenApp ?? frontApp

            print("[CinemaModeManager] Unauthorized exit detected via on-player click! Reversing and triggering prompt...")

            // 1. Immediately force the player back into full screen!
            ActionDispatcher.shared.reEnterFullScreen(for: mediaApp)

            // 2. Trigger the Cinema Mode intervention prompt
            _ = handleExitAttempt(for: mediaApp)
        }
    }

    /// Checks if the specified (or frontmost) active application has a window in full screen mode.
    public func isFrontAppFullScreen(app: NSRunningApplication? = nil) -> Bool {
        guard let targetApp = app ?? NSWorkspace.shared.frontmostApplication else { return false }
        if targetApp.processIdentifier == NSRunningApplication.current.processIdentifier {
            return false
        }

        let pid = targetApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        // 1. Check focused window
        var focusedWindowVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindowVal) == .success,
           let win = focusedWindowVal {
            if checkWindowIsFullScreen(win as! AXUIElement) {
                return true
            }
        }

        // 2. Check main window
        var mainWindowVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &mainWindowVal) == .success,
           let win = mainWindowVal {
            if checkWindowIsFullScreen(win as! AXUIElement) {
                return true
            }
        }

        // 3. Check all application windows (e.g. Chrome/Safari video overlay windows)
        var windowsVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsVal) == .success,
           let windows = windowsVal as? [AXUIElement] {
            for win in windows {
                if checkWindowIsFullScreen(win) {
                    return true
                }
            }
        }

        return false
    }

    private func checkWindowIsFullScreen(_ win: AXUIElement) -> Bool {
        // A. Direct AXFullScreen attribute
        var fsVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, "AXFullScreen" as CFString, &fsVal) == .success,
           let isFs = fsVal as? Bool, isFs {
            return true
        }

        // B. Window geometry matching any active display (custom HTML5 players)
        var sizeVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeVal) == .success,
           let sVal = sizeVal {
            var size = CGSize.zero
            AXValueGetValue(sVal as! AXValue, .cgSize, &size)
            for screen in NSScreen.screens {
                if size.width >= screen.frame.width - 10 && size.height >= screen.frame.height - 10 {
                    return true
                }
            }
        }

        return false
    }

    /// Checks if the focused UI element in the frontmost app is an editable text field
    /// (so typing 'f' in a search bar or text area is never blocked).
    public func isFocusedElementEditable(pid: pid_t? = nil) -> Bool {
        guard let targetApp = (pid != nil ? NSRunningApplication(processIdentifier: pid!) : NSWorkspace.shared.frontmostApplication) else {
            return false
        }
        let appRef = AXUIElementCreateApplication(targetApp.processIdentifier)
        var focusedUIVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedUIVal) == .success,
           let focusedUI = focusedUIVal {
            var roleVal: CFTypeRef?
            AXUIElementCopyAttributeValue(focusedUI as! AXUIElement, kAXRoleAttribute as CFString, &roleVal)
            let role = roleVal as? String ?? ""
            if role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox" {
                return true
            }
            var subroleVal: CFTypeRef?
            AXUIElementCopyAttributeValue(focusedUI as! AXUIElement, kAXSubroleAttribute as CFString, &subroleVal)
            let subrole = subroleVal as? String ?? ""
            if subrole == "AXSearchField" {
                return true
            }
        }
        return false
    }

    /// Intercepts the attempt to leave full screen mode (Escape key, 'F' key, or on-player exit button).
    /// Displays the Cinema Mode pop-up and swallows/blocks the exit until authorized.
    @discardableResult
    public func handleExitAttempt(for targetApp: NSRunningApplication? = nil) -> Bool {
        guard WordStore.shared.isCinemaModeEnabled else { return false }
        guard Date() > exitCooldownUntil else { return false }
        guard !isCinemaPromptActive else { return true }

        guard let app = targetApp ?? NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier else {
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
                    self.wasFullScreen = true
                    // Ensure the player stays in full screen
                    ActionDispatcher.shared.reEnterFullScreen(for: app)
                },
                onExit: { [weak self] in
                    guard let self = self else { return }
                    self.isCinemaPromptActive = false
                    self.wasFullScreen = false
                    // Set an 8-second cooldown so window transitions and subsequent key events don't re-trap the user
                    self.exitCooldownUntil = Date().addingTimeInterval(8.0)
                    ActionDispatcher.shared.exitFullScreen(for: app)
                }
            )
        }

        return true
    }
}
