import Cocoa
import ApplicationServices

/// Monitors active web browser windows across Safari, Chrome, Arc, Brave, Edge, Firefox, Opera, and Vivaldi.
/// When a blocked domain is detected in the active browser, it immediately triggers the custom pop-up note
/// and optionally closes the offending tab.
public final class BrowserMonitor {
    public static let shared = BrowserMonitor()

    private let supportedBrowsers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser", // Arc
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi"
    ]

    private var pollTimer: Timer?
    private var isMonitoring = false
    private var lastBlockedDomain: String?
    private var lastBlockedTime: Date = .distantPast

    private init() {}

    /// Starts monitoring browser activity.
    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Observe active application switches
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        scheduleTimerIfNeeded()
    }

    /// Stops monitoring browser activity.
    public func stop() {
        isMonitoring = false
        pollTimer?.invalidate()
        pollTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appActivated(_ notification: Notification) {
        scheduleTimerIfNeeded()
    }

    private func scheduleTimerIfNeeded() {
        guard isMonitoring else { return }
        pollTimer?.invalidate()
        pollTimer = nil

        // If the frontmost application is a supported browser, poll at 0.5s intervals.
        // If not a browser, timer stays nil (0% CPU impact while using other apps).
        if isBrowserActive() {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.inspectActiveBrowser()
            }
            inspectActiveBrowser()
        }
    }

    private func isBrowserActive() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else { return false }
        return supportedBrowsers.contains(bundleId)
    }

    /// Inspects the frontmost browser window for blocked websites.
    public func inspectActiveBrowser() {
        guard WordStore.shared.isEnabled else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              supportedBrowsers.contains(bundleId) else {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }

        guard let activeURL = extractActiveURL(for: frontApp.processIdentifier, bundleId: bundleId) else {
            return
        }

        // Match against blocked websites
        guard let match = WordStore.shared.matchBlockedWebsite(urlOrHost: activeURL) else {
            return
        }

        // Check if website has been temporarily allowed by user
        if WordStore.shared.isWebsiteTemporarilyAllowed(match.matchedDomain) {
            return
        }

        // Prevent repeated prompts while user is currently deciding on gate dialog
        if isGatePromptActive {
            return
        }

        // Prevent repeated alerts for the same domain within 6 seconds if gate not active
        let now = Date()
        if let lastDomain = lastBlockedDomain,
           lastDomain == match.matchedDomain,
           now.timeIntervalSince(lastBlockedTime) < 6.0 {
            return
        }

        lastBlockedDomain = match.matchedDomain
        lastBlockedTime = now

        if WordStore.shared.requireAllowToEnter {
            showAccessGatePrompt(domain: match.matchedDomain, note: match.note, bundleId: bundleId)
        } else {
            handleBlockedWebsiteDetected(domain: match.matchedDomain, note: match.note)
        }
    }

    private var isGatePromptActive = false

    /// Displays an interactive access gate dialog. The user cannot enter the website unless they choose to allow it.
    private func showAccessGatePrompt(domain: String, note: String?, bundleId: String) {
        guard !isGatePromptActive else { return }
        isGatePromptActive = true

        let noteText = note ?? "Access to \(domain) is blocked. Stay focused on your goals!"

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            InterventionModalController.shared.showBlockedWebsite(
                domain: domain,
                note: noteText,
                onLeave: { [weak self] in
                    guard let self = self else { return }
                    self.isGatePromptActive = false
                    self.activateBrowser(bundleId: bundleId)
                    ActionDispatcher.shared.closeCurrentTab()
                },
                onAllow: { [weak self] minutes in
                    guard let self = self else { return }
                    self.isGatePromptActive = false
                    WordStore.shared.allowWebsiteTemporarily(domain, minutes: minutes)
                    self.activateBrowser(bundleId: bundleId)
                }
            )
        }
    }

    private func activateBrowser(bundleId: String) {
        if let browser = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            browser.activate()
        }
    }

    private func handleBlockedWebsiteDetected(domain: String, note: String?) {
        let noteText = note ?? "Access to \(domain) is restricted. Stay focused on your goals!"

        // 1. Show Intervention Modal Card if enabled
        if WordStore.shared.showWebsiteNotes {
            DispatchQueue.main.async {
                InterventionModalController.shared.showBlockedWebsite(
                    domain: domain,
                    note: noteText,
                    onLeave: {
                        ActionDispatcher.shared.closeCurrentTab()
                    },
                    onAllow: { minutes in
                        WordStore.shared.allowWebsiteTemporarily(domain, minutes: minutes)
                    }
                )
            }
        }

        // 2. Close the offending tab if enabled
        if WordStore.shared.closeBlockedTabs {
            ActionDispatcher.shared.closeCurrentTab()
        }
    }

    /// Extracts the URL currently open in the active browser window using macOS Accessibility.
    public func extractActiveURL(for pid: pid_t, bundleId: String) -> String? {
        let appRef = AXUIElementCreateApplication(pid)

        var windowVal: CFTypeRef?
        var axResult = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowVal)
        if axResult != .success || windowVal == nil {
            axResult = AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &windowVal)
        }

        guard axResult == .success, let window = windowVal else {
            return nil
        }
        let win = window as! AXUIElement

        // Strategy 1: Direct document attribute (Chrome, Brave, Arc, Edge, Opera)
        var docVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, kAXDocumentAttribute as CFString, &docVal) == .success,
           let docStr = docVal as? String, !docStr.isEmpty {
            return docStr
        }

        // Strategy 2: Direct AXURL attribute
        var urlVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, "AXURL" as CFString, &urlVal) == .success,
           let urlStr = (urlVal as? URL)?.absoluteString ?? (urlVal as? String), !urlStr.isEmpty {
            return urlStr
        }

        // Strategy 3: Check focused UI element value
        var focusedUIVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedUIVal) == .success,
           let focusedUI = focusedUIVal {
            var val: CFTypeRef?
            if AXUIElementCopyAttributeValue(focusedUI as! AXUIElement, kAXValueAttribute as CFString, &val) == .success,
               let str = val as? String, isLikelyURL(str) {
                return str
            }
        }

        // Strategy 4: Hierarchy search for address field (Safari & fallback)
        return findAddressBar(in: win, depth: 0)
    }

    private func findAddressBar(in element: AXUIElement, depth: Int) -> String? {
        if depth > 9 { return nil }

        // Check Safari identifier
        var identVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &identVal)
        if let ident = identVal as? String, ident == "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" {
            var val: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &val) == .success,
               let str = val as? String, !str.isEmpty {
                return str
            }
        }

        // Check text field / combo box description or value
        var roleVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal)
        let role = roleVal as? String ?? ""

        if role == "AXTextField" || role == "AXComboBox" {
            var descVal: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descVal)
            let desc = (descVal as? String ?? "").lowercased()

            if desc.contains("address") || desc.contains("search") || desc.contains("url") {
                var val: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &val) == .success,
                   let str = val as? String, isLikelyURL(str) {
                    return str
                }
            }
        }

        // Search children
        var childrenVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenVal) == .success,
           let children = childrenVal as? [AXUIElement] {
            for child in children {
                if let found = findAddressBar(in: child, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    private func isLikelyURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains(" ") { return false }
        return trimmed.contains(".") || trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }
}
