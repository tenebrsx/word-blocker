import Cocoa

/// Displays a sleek, floating HUD pop-up note whenever a user-specified blocked word is typed.
public final class PopupNoteController: NSWindowController {
    public static let shared = PopupNoteController()

    private var panel: NSPanel!
    private var iconLabel: NSTextField!
    private var wordLabel: NSTextField!
    private var messageTextView: NSTextField!
    private var dismissButton: NSButton!
    private var autoDismissTimer: Timer?

    private convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
            styleMask: [.titled, .closable, .hudWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.title = "Pop-Up Note"
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        self.init(window: panel)
        self.panel = panel
        setupUI()
    }

    private func setupUI() {
        guard let contentView = panel.contentView else { return }

        // Icon & Header
        iconLabel = NSTextField(labelWithString: "📝")
        iconLabel.font = NSFont.systemFont(ofSize: 24)
        iconLabel.frame = NSRect(x: 18, y: 135, width: 34, height: 32)
        contentView.addSubview(iconLabel)

        wordLabel = NSTextField(labelWithString: "Blocked Word Detected")
        wordLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        wordLabel.textColor = .labelColor
        wordLabel.frame = NSRect(x: 56, y: 140, width: 300, height: 22)
        contentView.addSubview(wordLabel)

        // Note Card Box
        let box = NSBox(frame: NSRect(x: 18, y: 52, width: 344, height: 76))
        box.boxType = .custom
        box.borderColor = NSColor.separatorColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6)

        messageTextView = NSTextField(labelWithString: "")
        messageTextView.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        messageTextView.textColor = .labelColor
        messageTextView.frame = NSRect(x: 10, y: 8, width: 324, height: 60)
        messageTextView.maximumNumberOfLines = 3
        messageTextView.cell?.wraps = true
        messageTextView.cell?.isScrollable = false
        box.contentView = messageTextView
        contentView.addSubview(box)

        // Dismiss Button
        dismissButton = NSButton(title: "Dismiss", target: self, action: #selector(dismissClicked))
        dismissButton.bezelStyle = .rounded
        dismissButton.keyEquivalent = "\r" // Enter key dismisses
        dismissButton.frame = NSRect(x: 272, y: 12, width: 92, height: 28)
        contentView.addSubview(dismissButton)
    }

    /// Presents the custom intervention modal for a matched blocked word (centered, non-system-notification).
    public func showNote(word: String, message: String) {
        InterventionModalController.shared.showBlockedWord(word: word, note: message)
    }

    /// Presents the custom intervention modal for a blocked website visit.
    public func showWebsiteNote(domain: String, message: String) {
        InterventionModalController.shared.showBlockedWebsite(
            domain: domain,
            note: message,
            onLeave: {
                ActionDispatcher.shared.closeCurrentTab()
            },
            onAllow: { minutes in
                WordStore.shared.allowWebsiteTemporarily(domain, minutes: minutes)
            }
        )
    }

    /// Presents the custom intervention modal for Cinema Mode interventions.
    public func showCinemaNote(message: String) {
        InterventionModalController.shared.showCinemaMode(
            note: message,
            onStay: {},
            onExit: {}
        )
    }

    /// Generic presentation method routed to custom intervention modal.
    public func showCard(title: String, message: String, icon: String = "📝") {
        InterventionModalController.shared.showBlockedWord(word: title, note: message)
    }

    @objc private func dismissClicked() {
        fadeOut()
    }

    private func fadeOut() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            self.panel.animator().alphaValue = 0.0
        }, completionHandler: {
            self.panel.orderOut(nil)
        })
    }
}
