import Cocoa
import ApplicationServices

/// Manages verification and user guidance for macOS Accessibility (TCC) privileges.
public final class PermissionsManager {
    public static let shared = PermissionsManager()

    private var pollTimer: Timer?
    public var onPermissionStatusChanged: ((Bool) -> Void)?

    private init() {}

    /// Checks whether the app currently has Accessibility trust.
    public func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Triggers the system prompt asking the user to grant Accessibility permissions.
    public func promptForAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens macOS System Settings directly to the Accessibility privacy pane.
    public func openSystemSettingsAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts polling in the background to detect when the user grants permission in System Settings.
    public func startObserving(interval: TimeInterval = 1.5) {
        stopObserving()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let granted = self.isAccessibilityGranted()
            self.onPermissionStatusChanged?(granted)
        }
    }

    /// Stops polling.
    public func stopObserving() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
