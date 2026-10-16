import Cocoa

/// Custom panel subclass that allows borderless transparent HUD windows to become key
/// and accept keyboard focus and shortcuts, and intercept Escape key via cancelOperation.
final class CustomInterventionPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    var onCancelOperation: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        if let onCancel = onCancelOperation {
            onCancel()
        } else {
            super.cancelOperation(sender)
        }
    }
}

/// A dedicated, custom-designed intervention notification bubble that appears
/// in the top-right of the screen (classic macOS notification placement).
/// Ultra-minimal design with no emojis or censored words, displaying only the custom message and actions.
public final class InterventionModalController: NSWindowController {
    public static let shared = InterventionModalController()

    private var panel: CustomInterventionPanel!
    private var visualEffect: NSVisualEffectView!

    // Header & Badges (used for multi-button modals like Websites / Cinema Mode)
    private var badgeLabel: NSTextField!
    private var targetLabel: NSTextField!

    // Note Card & Text
    private var noteBox: NSBox!
    private var noteHeaderLabel: NSTextField!
    private var noteTextView: NSTextField!

    // Direct Minimal Text View (for blocked word popup notes - pure minimal message)
    private var minimalTextView: NSTextField!

    // Dynamic Action Buttons
    private var button1: NSButton!
    private var button2: NSButton!
    private var button3: NSButton!

    // Callbacks
    /// True while the blocked-website gate is the content currently on screen.
    public private(set) var isShowingBlockedWebsite = false
    /// Called when a blocked-website gate is replaced by another alert before the user answered it.
    private var onWebsiteGateAbandoned: (() -> Void)?

    public var isPanelVisible: Bool { panel.isVisible }

    private func beginPresentation(isWebsiteGate: Bool) {
        if let abandoned = onWebsiteGateAbandoned {
            onWebsiteGateAbandoned = nil
            abandoned()
        }
        isShowingBlockedWebsite = isWebsiteGate
    }

    private var onButton1Clicked: (() -> Void)?
    private var onButton2Clicked: (() -> Void)?
    private var onButton3Clicked: (() -> Void)?

    private convenience init() {
        let width: CGFloat = 370
        let height: CGFloat = 142

        let panel = CustomInterventionPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear

        self.init(window: panel)
        self.panel = panel

        setupUI()
    }

    private func setupUI() {
        guard let contentView = panel.contentView else { return }

        // Frosted Glass Notification Background
        visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        visualEffect.layer?.borderWidth = 1.0
        contentView.addSubview(visualEffect)

        // Category Badge (no emojis)
        badgeLabel = NSTextField(labelWithString: "WORD BLOCKER")
        badgeLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .secondaryLabelColor
        badgeLabel.frame = NSRect(x: 16, y: 182, width: 378, height: 16)
        visualEffect.addSubview(badgeLabel)

        // Target Label (no emojis, no censored word)
        targetLabel = NSTextField(labelWithString: "")
        targetLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        targetLabel.textColor = .labelColor
        targetLabel.frame = NSRect(x: 16, y: 160, width: 378, height: 20)
        visualEffect.addSubview(targetLabel)

        // Structured Note Box (for website / cinema mode)
        noteBox = NSBox(frame: NSRect(x: 14, y: 52, width: 382, height: 102))
        noteBox.boxType = .custom
        noteBox.cornerRadius = 10
        noteBox.fillColor = NSColor.white.withAlphaComponent(0.06)
        noteBox.borderColor = NSColor.white.withAlphaComponent(0.14)
        noteBox.borderWidth = 1

        let noteInnerView = NSView(frame: noteBox.bounds)

        noteHeaderLabel = NSTextField(labelWithString: "")
        noteHeaderLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        noteHeaderLabel.textColor = .tertiaryLabelColor
        noteHeaderLabel.frame = NSRect(x: 10, y: 82, width: 362, height: 14)
        noteInnerView.addSubview(noteHeaderLabel)

        noteTextView = NSTextField(labelWithString: "")
        noteTextView.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        noteTextView.textColor = .labelColor
        noteTextView.frame = NSRect(x: 10, y: 8, width: 362, height: 72)
        noteTextView.maximumNumberOfLines = 4
        noteTextView.cell?.wraps = true
        noteTextView.cell?.isScrollable = false
        noteInnerView.addSubview(noteTextView)

        noteBox.contentView = noteInnerView
        visualEffect.addSubview(noteBox)

        // Direct Minimal Text View (Ultra-clean, just the custom message)
        minimalTextView = NSTextField(labelWithString: "")
        minimalTextView.font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        minimalTextView.textColor = .labelColor
        minimalTextView.frame = NSRect(x: 18, y: 44, width: 334, height: 84)
        minimalTextView.maximumNumberOfLines = 4
        minimalTextView.cell?.wraps = true
        minimalTextView.cell?.isScrollable = false
        visualEffect.addSubview(minimalTextView)

        // Buttons
        button1 = NSButton(title: "Dismiss", target: self, action: #selector(button1Clicked))
        button1.bezelStyle = .rounded
        button1.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        visualEffect.addSubview(button1)

        button2 = NSButton(title: "Button 2", target: self, action: #selector(button2Clicked))
        button2.bezelStyle = .rounded
        button2.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        visualEffect.addSubview(button2)

        button3 = NSButton(title: "Button 3", target: self, action: #selector(button3Clicked))
        button3.bezelStyle = .rounded
        button3.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        visualEffect.addSubview(button3)
    }

    // MARK: - Presentation Modes

    /// Displays the top-right notification bubble for typed blocked words:
    /// Keeps the custom reminder note box, removes all emojis, removes the censored word, and provides a clean Dismiss button.
    public func showBlockedWord(word: String, note: String) {
        beginPresentation(isWebsiteGate: false)
        let width: CGFloat = 380
        let height: CGFloat = 180
        panel.setContentSize(NSSize(width: width, height: height))
        visualEffect.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: width, height: height)

        minimalTextView.isHidden = true

        // Clean app badge header without emojis
        badgeLabel.isHidden = false
        badgeLabel.stringValue = "WORD BLOCKER"
        badgeLabel.frame = NSRect(x: 16, y: 152, width: 348, height: 16)

        // Censored word is completely hidden / removed
        targetLabel.isHidden = true

        // The reminder note box is kept
        noteBox.isHidden = false
        noteBox.frame = NSRect(x: 14, y: 48, width: 352, height: 98)

        noteHeaderLabel.isHidden = false
        noteHeaderLabel.stringValue = "YOUR CUSTOM REMINDER NOTE:"
        noteHeaderLabel.frame = NSRect(x: 10, y: 76, width: 332, height: 14)

        noteTextView.isHidden = false
        noteTextView.frame = NSRect(x: 10, y: 8, width: 332, height: 64)
        noteTextView.stringValue = note.isEmpty ? "Stay focused on your goals." : note

        // Clean dismiss button without checkmark emoji
        button1.title = "Dismiss"
        button1.keyEquivalent = "\r"
        button1.bezelColor = nil
        button1.frame = NSRect(x: 130, y: 12, width: 120, height: 26)
        button1.isHidden = false

        button2.isHidden = true
        button3.isHidden = true

        onButton1Clicked = { [weak self] in
            self?.dismissModal()
        }

        panel.onCancelOperation = { [weak self] in
            self?.button1Clicked()
        }

        presentTopRight()
    }

    /// Displays the top-right notification bubble when visiting a blocked website (no emojis).
    public func showBlockedWebsite(
        domain: String,
        note: String,
        onLeave: @escaping () -> Void,
        onAllow: @escaping (Int) -> Void,
        onAbandoned: (() -> Void)? = nil
    ) {
        beginPresentation(isWebsiteGate: true)
        onWebsiteGateAbandoned = onAbandoned
        let width: CGFloat = 410
        let height: CGFloat = 210
        panel.setContentSize(NSSize(width: width, height: height))
        visualEffect.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: width, height: height)

        minimalTextView.isHidden = true
        badgeLabel.isHidden = false
        targetLabel.isHidden = false
        noteBox.isHidden = false

        badgeLabel.stringValue = "BLOCKED WEBSITE"
        badgeLabel.frame = NSRect(x: 16, y: 182, width: 378, height: 16)

        targetLabel.stringValue = domain
        targetLabel.frame = NSRect(x: 16, y: 160, width: 378, height: 20)

        noteBox.frame = NSRect(x: 14, y: 52, width: 382, height: 102)
        noteHeaderLabel.stringValue = "COMMITMENT NOTE:"
        noteTextView.stringValue = note.isEmpty ? "You chose to block \(domain) to stay productive." : note

        button1.title = "Leave Tab"
        button1.keyEquivalent = "\r"
        button1.bezelColor = NSColor.systemRed
        button1.frame = NSRect(x: 14, y: 12, width: 140, height: 30)
        button1.isHidden = false

        button2.title = "Allow 10 min"
        button2.keyEquivalent = ""
        button2.bezelColor = nil
        button2.frame = NSRect(x: 160, y: 12, width: 120, height: 30)
        button2.isHidden = false

        button3.title = "Allow 5 min"
        button3.keyEquivalent = ""
        button3.bezelColor = nil
        button3.frame = NSRect(x: 286, y: 12, width: 110, height: 30)
        button3.isHidden = false

        onButton1Clicked = { [weak self] in
            self?.dismissModal {
                onLeave()
            }
        }
        onButton2Clicked = { [weak self] in
            self?.dismissModal {
                onAllow(10)
            }
        }
        onButton3Clicked = { [weak self] in
            self?.dismissModal {
                onAllow(5)
            }
        }

        panel.onCancelOperation = { [weak self] in
            self?.button1Clicked()
        }

        presentTopRight()
    }

    /// Displays the top-right notification bubble for Cinema Mode full-screen exit attempts (no emojis).
    public func showCinemaMode(
        note: String,
        onStay: @escaping () -> Void,
        onExit: @escaping () -> Void
    ) {
        beginPresentation(isWebsiteGate: false)
        let width: CGFloat = 410
        let height: CGFloat = 210
        panel.setContentSize(NSSize(width: width, height: height))
        visualEffect.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: width, height: height)

        minimalTextView.isHidden = true
        badgeLabel.isHidden = false
        targetLabel.isHidden = false
        noteBox.isHidden = false

        badgeLabel.stringValue = "CINEMA MODE"
        badgeLabel.frame = NSRect(x: 16, y: 182, width: 378, height: 16)

        targetLabel.stringValue = "Full-Screen Media Active"
        targetLabel.frame = NSRect(x: 16, y: 160, width: 378, height: 20)

        noteBox.frame = NSRect(x: 14, y: 52, width: 382, height: 102)
        noteHeaderLabel.stringValue = "FOCUS COMMITMENT:"
        noteTextView.stringValue = note.isEmpty ? "Stay immersed! Remember your commitment to finish what you're watching without multitasking." : note

        button1.title = "Stay in Full Screen"
        button1.keyEquivalent = "\r"
        button1.bezelColor = NSColor.systemIndigo
        button1.frame = NSRect(x: 14, y: 12, width: 190, height: 30)
        button1.isHidden = false

        button2.title = "Exit Full Screen"
        button2.keyEquivalent = ""
        button2.bezelColor = nil
        button2.frame = NSRect(x: 210, y: 12, width: 186, height: 30)
        button2.isHidden = false

        button3.isHidden = true

        onButton1Clicked = { [weak self] in
            self?.dismissModal {
                onStay()
            }
        }
        onButton2Clicked = { [weak self] in
            self?.dismissModal {
                onExit()
            }
        }

        panel.onCancelOperation = { [weak self] in
            self?.button1Clicked()
        }

        presentTopRight()
    }

    /// Displays the top-right notification bubble when user attempts to disable protection (no emojis).
    public func showDisableProtection(
        message: String,
        onKeepOn: @escaping () -> Void,
        onDisable: @escaping () -> Void
    ) {
        beginPresentation(isWebsiteGate: false)
        let width: CGFloat = 410
        let height: CGFloat = 210
        panel.setContentSize(NSSize(width: width, height: height))
        visualEffect.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: width, height: height)

        minimalTextView.isHidden = true
        badgeLabel.isHidden = false
        targetLabel.isHidden = false
        noteBox.isHidden = false

        badgeLabel.stringValue = "DISABLE PROTECTION"
        badgeLabel.frame = NSRect(x: 16, y: 182, width: 378, height: 16)

        targetLabel.stringValue = "Pause Protection"
        targetLabel.frame = NSRect(x: 16, y: 160, width: 378, height: 20)

        noteBox.frame = NSRect(x: 14, y: 52, width: 382, height: 102)
        noteHeaderLabel.stringValue = "COMMITMENT REMINDER:"
        noteTextView.stringValue = message.isEmpty ? "Are you sure you want to disable protection? Staying consistent is key to building good habits." : message

        button1.title = "Keep Protection ON"
        button1.keyEquivalent = "\r"
        button1.bezelColor = NSColor.systemBlue
        button1.frame = NSRect(x: 14, y: 12, width: 190, height: 30)
        button1.isHidden = false

        button2.title = "Disable Protection"
        button2.keyEquivalent = ""
        button2.bezelColor = nil
        button2.frame = NSRect(x: 210, y: 12, width: 186, height: 30)
        button2.isHidden = false

        button3.isHidden = true

        onButton1Clicked = { [weak self] in
            self?.dismissModal {
                onKeepOn()
            }
        }
        onButton2Clicked = { [weak self] in
            self?.dismissModal {
                onDisable()
            }
        }

        panel.onCancelOperation = { [weak self] in
            self?.button1Clicked()
        }

        presentTopRight()
    }

    /// Displays the top-right notification bubble when user attempts to quit the app (no emojis).
    public func showQuitApp(
        message: String,
        onStay: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        beginPresentation(isWebsiteGate: false)
        let width: CGFloat = 410
        let height: CGFloat = 210
        panel.setContentSize(NSSize(width: width, height: height))
        visualEffect.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: width, height: height)

        minimalTextView.isHidden = true
        badgeLabel.isHidden = false
        targetLabel.isHidden = false
        noteBox.isHidden = false

        badgeLabel.stringValue = "QUIT APPLICATION"
        badgeLabel.frame = NSRect(x: 16, y: 182, width: 378, height: 16)

        targetLabel.stringValue = "Quit Confirmation"
        targetLabel.frame = NSRect(x: 16, y: 160, width: 378, height: 20)

        noteBox.frame = NSRect(x: 14, y: 52, width: 382, height: 102)
        noteHeaderLabel.stringValue = "COMMITMENT REMINDER:"
        noteTextView.stringValue = message.isEmpty ? "Are you sure you want to quit Word Blocker? Background protection will stop." : message

        button1.title = "Stay Protected"
        button1.keyEquivalent = "\r"
        button1.bezelColor = NSColor.systemBlue
        button1.frame = NSRect(x: 14, y: 12, width: 190, height: 30)
        button1.isHidden = false

        button2.title = "Quit Word Blocker"
        button2.keyEquivalent = ""
        button2.bezelColor = nil
        button2.frame = NSRect(x: 210, y: 12, width: 186, height: 30)
        button2.isHidden = false

        button3.isHidden = true

        onButton1Clicked = { [weak self] in
            self?.dismissModal {
                onStay()
            }
        }
        onButton2Clicked = { [weak self] in
            self?.dismissModal {
                onQuit()
            }
        }

        panel.onCancelOperation = { [weak self] in
            self?.button1Clicked()
        }

        presentTopRight()
    }

    // MARK: - Top-Right Presentation & Dismissal

    private func presentTopRight() {
        if WordStore.shared.playAlertSound {
            NSSound.beep()
        }

        guard let screen = NSScreen.main else {
            panel.center()
            return
        }

        let screenRect = screen.visibleFrame
        let targetX = screenRect.maxX - panel.frame.width - 20
        let targetY = screenRect.maxY - panel.frame.height - 16

        // Smooth slide-in from top right
        let initialY = targetY + 14
        panel.setFrameOrigin(NSPoint(x: targetX, y: initialY))
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(NSPoint(x: targetX, y: targetY))
            panel.animator().alphaValue = 1.0
        }
    }

    private func dismissModal(completion: (() -> Void)? = nil) {
        isShowingBlockedWebsite = false
        onWebsiteGateAbandoned = nil
        guard let screen = NSScreen.main else {
            self.panel.orderOut(nil)
            completion?()
            return
        }
        let screenRect = screen.visibleFrame
        let targetX = screenRect.maxX - panel.frame.width - 20
        let exitY = screenRect.maxY - panel.frame.height - 4

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel.animator().setFrameOrigin(NSPoint(x: targetX, y: exitY))
            self.panel.animator().alphaValue = 0.0
        }, completionHandler: {
            self.panel.orderOut(nil)
            completion?()
        })
    }

    @objc private func button1Clicked() {
        onButton1Clicked?()
    }

    @objc private func button2Clicked() {
        onButton2Clicked?()
    }

    @objc private func button3Clicked() {
        onButton3Clicked?()
    }
}
