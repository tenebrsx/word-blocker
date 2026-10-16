import Cocoa
import ApplicationServices

/// Monitors active web browser windows across Safari, Chrome, Arc, Brave, Edge, Firefox, Opera, and Vivaldi.
/// When a blocked domain is detected in the active browser, it immediately triggers the custom pop-up note
/// and optionally closes the offending tab.
public final class BrowserMonitor {
    public static let shared = BrowserMonitor()

    private let supportedBrowsers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "company.thebrowser.Browser", // Arc
        "company.thebrowser.dia",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "app.zen-browser.zen",
        "net.waterfox.waterfox",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS", // Orion
        "com.duckduckgo.macos.browser",
        "ai.perplexity.comet",
        "com.sigmaos.sigmaos.macos"
    ]

    private var pollTimer: Timer?
    private var isMonitoring = false
    private var lastBlockedDomain: String?
    private var lastBlockedTime: Date = .distantPast
    private var axEnabledPids: Set<pid_t> = []

    private init() {}

    /// Starts monitoring browser activity.
    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // One persistent timer in .common mode: it keeps firing during menu/modal tracking and
        // never depends on app-activation notifications arriving. When no browser is frontmost a
        // tick is just a bundle-ID comparison, so the cost is negligible.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.inspectActiveBrowser()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        inspectActiveBrowser()
    }

    /// Stops monitoring browser activity.
    public func stop() {
        isMonitoring = false
        pollTimer?.invalidate()
        pollTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appActivated(_ notification: Notification) {
        // Check immediately on switching apps instead of waiting for the next tick.
        DispatchQueue.main.async { [weak self] in self?.inspectActiveBrowser() }
    }

    private var isGatePromptActive = false
    private var gatePromptShownAt: Date = .distantPast

    /// Clears the gate flag if the gate is no longer actually on screen (replaced by another alert,
    /// closed some other way, etc.). This is what previously left blocking dead until an app restart.
    private func reconcileGateState() {
        guard isGatePromptActive else { return }
        let controller = InterventionModalController.shared
        let onScreen = controller.isShowingBlockedWebsite && controller.isPanelVisible
        if !onScreen && Date().timeIntervalSince(gatePromptShownAt) > 1.0 {
            isGatePromptActive = false
            lastBlockedDomain = nil
        }
    }

    /// Inspects the frontmost browser for blocked websites.
    public func inspectActiveBrowser() {
        guard isMonitoring, WordStore.shared.isEnabled else { return }
        reconcileGateState()

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              supportedBrowsers.contains(bundleId) else {
            return
        }

        let pid = frontApp.processIdentifier
        enableAccessibilityIfNeeded(pid: pid)

        // Check the focused window first, then the browser's other windows (second monitor, split view).
        for (window, isFocused) in browserWindows(pid: pid) {
            guard let url = extractURL(from: window, appRef: AXUIElementCreateApplication(pid)),
                  let match = WordStore.shared.matchBlockedWebsite(urlOrHost: url) else { continue }

            if WordStore.shared.isWebsiteTemporarilyAllowed(match.matchedDomain) { continue }
            if isGatePromptActive { return }

            let now = Date()
            if let lastDomain = lastBlockedDomain,
               lastDomain == match.matchedDomain,
               now.timeIntervalSince(lastBlockedTime) < 2.0 {
                return
            }

            if !isFocused {
                // Bring the offending window forward so "Leave Tab" closes the right tab.
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            }

            lastBlockedDomain = match.matchedDomain
            lastBlockedTime = now

            if WordStore.shared.requireAllowToEnter {
                showAccessGatePrompt(domain: match.matchedDomain, note: match.note, bundleId: bundleId)
            } else {
                handleBlockedWebsiteDetected(domain: match.matchedDomain, note: match.note, bundleId: bundleId)
            }
            return
        }
    }

    /// Displays an interactive access gate dialog. The user cannot enter the website unless they choose to allow it.
    private func showAccessGatePrompt(domain: String, note: String?, bundleId: String) {
        guard !isGatePromptActive else { return }
        isGatePromptActive = true
        gatePromptShownAt = Date()

        let noteText = note ?? "Access to \(domain) is blocked. Stay focused on your goals!"

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            InterventionModalController.shared.showBlockedWebsite(
                domain: domain,
                note: noteText,
                onLeave: { [weak self] in
                    guard let self = self else { return }
                    self.isGatePromptActive = false
                    self.leaveTab(bundleId: bundleId)
                },
                onAllow: { [weak self] minutes in
                    guard let self = self else { return }
                    self.isGatePromptActive = false
                    WordStore.shared.allowWebsiteTemporarily(domain, minutes: minutes)
                    self.activateBrowser(bundleId: bundleId)
                },
                onAbandoned: { [weak self] in
                    // Another alert took over the panel before an answer: re-arm so the site gets re-checked.
                    self?.isGatePromptActive = false
                    self?.lastBlockedDomain = nil
                }
            )
        }
    }

    /// Switches back to the browser, waits until it is really frontmost, then closes the tab
    /// and re-checks right away in case the close didn't land.
    private func leaveTab(bundleId: String) {
        activateBrowser(bundleId: bundleId)
        waitForFrontmost(bundleId: bundleId, attempts: 20) { [weak self] in
            ActionDispatcher.shared.closeCurrentTab(delay: 0.1) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self?.lastBlockedDomain = nil
                    self?.inspectActiveBrowser()
                }
            }
        }
    }

    private func waitForFrontmost(bundleId: String, attempts: Int, then action: @escaping () -> Void) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId || attempts <= 0 {
            action()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForFrontmost(bundleId: bundleId, attempts: attempts - 1, then: action)
        }
    }

    private func activateBrowser(bundleId: String) {
        if let browser = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            browser.activate()
        }
    }

    private func handleBlockedWebsiteDetected(domain: String, note: String?, bundleId: String) {
        let noteText = note ?? "Access to \(domain) is restricted. Stay focused on your goals!"

        if WordStore.shared.showWebsiteNotes {
            DispatchQueue.main.async { [weak self] in
                InterventionModalController.shared.showBlockedWebsite(
                    domain: domain,
                    note: noteText,
                    onLeave: { [weak self] in
                        self?.leaveTab(bundleId: bundleId)
                    },
                    onAllow: { minutes in
                        WordStore.shared.allowWebsiteTemporarily(domain, minutes: minutes)
                    }
                )
                _ = self
            }
        }

        if WordStore.shared.closeBlockedTabs {
            ActionDispatcher.shared.closeCurrentTab()
        }
    }

    /// Chromium and Firefox only build their accessibility tree when asked; without this the URL
    /// is often unreadable (Firefox especially).
    private func enableAccessibilityIfNeeded(pid: pid_t) {
        guard !axEnabledPids.contains(pid) else { return }
        axEnabledPids.insert(pid)
        let appRef = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appRef, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// The browser's focused window first, followed by its other standard, on-screen windows.
    private func browserWindows(pid: pid_t) -> [(AXUIElement, Bool)] {
        let appRef = AXUIElementCreateApplication(pid)
        var result: [(AXUIElement, Bool)] = []

        var focusedVal: CFTypeRef?
        var focused: AXUIElement?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedVal) == .success
            || AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &focusedVal) == .success,
           let f = focusedVal {
            focused = (f as! AXUIElement)
            result.append((focused!, true))
        }

        var windowsVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsVal) == .success,
           let windows = windowsVal as? [AXUIElement] {
            for w in windows.prefix(8) {
                if let f = focused, CFEqual(f, w) { continue }
                var minVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minVal) == .success,
                   (minVal as? Bool) == true { continue }
                var subVal: CFTypeRef?
                AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &subVal)
                if let sub = subVal as? String, sub != (kAXStandardWindowSubrole as String) { continue }
                result.append((w, false))
            }
        }
        return result
    }

    /// Public entry kept for callers/tests: URL of the focused browser window.
    public func extractActiveURL(for pid: pid_t, bundleId: String) -> String? {
        guard let (win, _) = browserWindows(pid: pid).first else { return nil }
        return extractURL(from: win, appRef: AXUIElementCreateApplication(pid))
    }

    /// Reads the loaded page's URL. Prefers what the page actually loaded (AXDocument / web area AXURL)
    /// over the address bar, because the address bar may hold text the user is still typing.
    private func extractURL(from win: AXUIElement, appRef: AXUIElement) -> String? {
        // Strategy 1: window document attribute (Chromium browsers)
        var docVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, kAXDocumentAttribute as CFString, &docVal) == .success,
           let docStr = docVal as? String, !docStr.isEmpty {
            return docStr
        }

        // Strategy 2: window AXURL
        var urlVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, "AXURL" as CFString, &urlVal) == .success,
           let urlStr = (urlVal as? URL)?.absoluteString ?? (urlVal as? String), !urlStr.isEmpty {
            return urlStr
        }

        // Strategy 3: the page's web area carries the real loaded URL (Safari, Firefox, others)
        if let webURL = findWebAreaURL(in: win, depth: 0) {
            return webURL
        }

        // Strategy 4: address bar, but only when the user isn't currently editing it
        var focusedUIVal: CFTypeRef?
        var focusedUI: AXUIElement?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedUIVal) == .success,
           let f = focusedUIVal {
            focusedUI = (f as! AXUIElement)
        }
        return findAddressBar(in: win, depth: 0, skipping: focusedUI)
    }

    private func findWebAreaURL(in element: AXUIElement, depth: Int) -> String? {
        if depth > 14 { return nil }
        var roleVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal)
        if (roleVal as? String) == "AXWebArea" {
            var urlVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &urlVal) == .success,
               let urlStr = (urlVal as? URL)?.absoluteString ?? (urlVal as? String), !urlStr.isEmpty {
                return urlStr
            }
            return nil // don't descend into page content
        }
        var childrenVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenVal) == .success,
           let children = childrenVal as? [AXUIElement] {
            for child in children {
                if let found = findWebAreaURL(in: child, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    private func findAddressBar(in element: AXUIElement, depth: Int, skipping editing: AXUIElement?) -> String? {
        if depth > 12 { return nil }
        if let editing = editing, CFEqual(editing, element) { return nil }
        var roleCheck: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleCheck)
        if (roleCheck as? String) == "AXWebArea" { return nil } // never read text fields inside pages

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
                if let found = findAddressBar(in: child, depth: depth + 1, skipping: editing) {
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
