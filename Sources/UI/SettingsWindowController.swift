import Cocoa

/// Custom NSTableView that intercepts the Backspace / Delete key to delete the selected row.
final class KeyHandlingTableView: NSTableView {
    var onDeleteKeyPressed: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Keycode 51 is Backspace / Delete, 117 is Forward Delete
        if event.keyCode == 51 || event.keyCode == 117 {
            if selectedRow >= 0 {
                onDeleteKeyPressed?()
                return
            }
        }
        super.keyDown(with: event)
    }
}

/// Manages the settings and preferences window with tabs for Blocked Words, Exceptions, Custom Prompts,
/// real-time search filtering, and keyboard backspace deletion.
public final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public static let shared = SettingsWindowController()

    // Top Controls
    private var permissionBanner: NSTextField!
    private var permissionHintLabel: NSTextField!
    private var permissionButton: NSButton!
    private var enableCheckbox: NSButton!
    private var soundCheckbox: NSButton!
    private var fuzzyCheckbox: NSButton!
    private var popupNoteCheckbox: NSButton!

    // Tab 1: Blocked Words & Notes
    private var blockedSearchField: NSSearchField!
    private var blockedTableView: KeyHandlingTableView!
    private var newWordField: NSTextField!
    private var newNoteField: NSTextField!
    private var currentBlockedSearch: String = ""

    // Tab 2: Exceptions
    private var exSearchField: NSSearchField!
    private var exceptionsTableView: KeyHandlingTableView!
    private var newExceptionField: NSTextField!
    private var currentExSearch: String = ""

    // Tab 3: Blocked Websites & Notes
    private var webSearchField: NSSearchField!
    private var websitesTableView: KeyHandlingTableView!
    private var newDomainField: NSTextField!
    private var newWebNoteField: NSTextField!
    private var gateCheckbox: NSButton!
    private var closeTabsCheckbox: NSButton!
    private var webNoteCheckbox: NSButton!
    private var currentWebSearch: String = ""

    // Tab 4: Cinema Mode
    private var cinemaEnableCheckbox: NSButton!
    private var cinemaMsgField: NSTextField!

    // Tab 5: Custom Prompts
    private var disableMsgField: NSTextField!
    private var quitMsgField: NSTextField!

    // Bottom Test Field
    private var testField: NSTextField!

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 790),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Word Blocker Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = contentView

        var currentY: CGFloat = 745

        // Title Header
        let titleLabel = NSTextField(labelWithString: "🛡️ Word Blocker")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.frame = NSRect(x: 24, y: currentY, width: 530, height: 28)
        contentView.addSubview(titleLabel)

        currentY -= 36

        // Permission Banner
        permissionBanner = NSTextField(labelWithString: "")
        permissionBanner.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        permissionBanner.frame = NSRect(x: 24, y: currentY, width: 370, height: 26)
        contentView.addSubview(permissionBanner)

        permissionButton = NSButton(title: "Grant Permission", target: self, action: #selector(permissionButtonClicked))
        permissionButton.bezelStyle = .rounded
        permissionButton.frame = NSRect(x: 400, y: currentY - 2, width: 154, height: 28)
        contentView.addSubview(permissionButton)

        currentY -= 20

        // Permission Troubleshooting Hint
        permissionHintLabel = NSTextField(labelWithString: "💡 Tip: If already listed in System Settings, toggle it OFF & ON once to refresh.")
        permissionHintLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        permissionHintLabel.textColor = .secondaryLabelColor
        permissionHintLabel.frame = NSRect(x: 24, y: currentY, width: 530, height: 16)
        contentView.addSubview(permissionHintLabel)

        currentY -= 22

        // Divider
        let div1 = createDivider(frame: NSRect(x: 24, y: currentY, width: 532, height: 1))
        contentView.addSubview(div1)

        currentY -= 28

        // General Switches
        enableCheckbox = NSButton(checkboxWithTitle: "Enable System-Wide Word Blocking", target: self, action: #selector(enableToggled(_:)))
        enableCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        enableCheckbox.state = WordStore.shared.isEnabled ? .on : .off
        enableCheckbox.frame = NSRect(x: 24, y: currentY, width: 360, height: 22)
        contentView.addSubview(enableCheckbox)

        currentY -= 24

        soundCheckbox = NSButton(checkboxWithTitle: "Play sound alert on auto-delete", target: self, action: #selector(soundToggled(_:)))
        soundCheckbox.state = WordStore.shared.playAlertSound ? .on : .off
        soundCheckbox.frame = NSRect(x: 24, y: currentY, width: 360, height: 22)
        contentView.addSubview(soundCheckbox)

        currentY -= 24

        popupNoteCheckbox = NSButton(checkboxWithTitle: "Show Pop-Up Note when blocked words are typed", target: self, action: #selector(popupNoteToggled(_:)))
        popupNoteCheckbox.state = WordStore.shared.showPopupNotes ? .on : .off
        popupNoteCheckbox.frame = NSRect(x: 24, y: currentY, width: 500, height: 22)
        contentView.addSubview(popupNoteCheckbox)

        currentY -= 24

        fuzzyCheckbox = NSButton(checkboxWithTitle: "Detect leetspeak & character evasions (e.g. b444aad, w0rd)", target: self, action: #selector(fuzzyToggled(_:)))
        fuzzyCheckbox.state = WordStore.shared.isFuzzyEnabled ? .on : .off
        fuzzyCheckbox.frame = NSRect(x: 24, y: currentY, width: 500, height: 22)
        contentView.addSubview(fuzzyCheckbox)

        currentY -= 330

        // NSTabView Container
        let tabView = NSTabView(frame: NSRect(x: 24, y: currentY, width: 532, height: 320))
        tabView.tabViewType = .topTabsBezelBorder

        // -------------------------------------------------------------
        // Tab 1: Blocked Words & Notes
        // -------------------------------------------------------------
        let blockedTab = NSTabViewItem(identifier: "BlockedTab")
        blockedTab.label = "🚫 Words"
        let blockedView = NSView(frame: tabView.contentRect)

        // Search Bar for Blocked Words
        blockedSearchField = NSSearchField(frame: NSRect(x: 12, y: 244, width: 508, height: 26))
        blockedSearchField.placeholderString = "Search blocked words or notes..."
        blockedSearchField.target = self
        blockedSearchField.action = #selector(blockedSearchChanged(_:))
        blockedView.addSubview(blockedSearchField)

        // Blocked Table with 2 columns
        let blockedScroll = NSScrollView(frame: NSRect(x: 12, y: 50, width: 508, height: 188))
        blockedScroll.hasVerticalScroller = true
        blockedScroll.borderType = .bezelBorder

        blockedTableView = KeyHandlingTableView(frame: blockedScroll.bounds)
        let bCol1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("WordColumn"))
        bCol1.title = "Blocked Word"
        bCol1.width = 150
        blockedTableView.addTableColumn(bCol1)

        let bCol2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NoteColumn"))
        bCol2.title = "Assigned Pop-Up Note"
        bCol2.width = 330
        blockedTableView.addTableColumn(bCol2)

        blockedTableView.dataSource = self
        blockedTableView.delegate = self
        blockedTableView.headerView = NSTableHeaderView()
        blockedTableView.allowsMultipleSelection = false
        blockedTableView.onDeleteKeyPressed = { [weak self] in
            self?.removeWordClicked()
        }
        blockedScroll.documentView = blockedTableView
        blockedView.addSubview(blockedScroll)

        // Blocked Inputs (Word + Note)
        newWordField = NSTextField(frame: NSRect(x: 12, y: 12, width: 130, height: 28))
        newWordField.placeholderString = "Word..."
        newWordField.target = self
        newWordField.action = #selector(addWordClicked)
        blockedView.addSubview(newWordField)

        newNoteField = NSTextField(frame: NSRect(x: 148, y: 12, width: 220, height: 28))
        newNoteField.placeholderString = "Pop-up note (e.g. Stay focused!)..."
        newNoteField.target = self
        newNoteField.action = #selector(addWordClicked)
        blockedView.addSubview(newNoteField)

        let addWordBtn = NSButton(title: "Save Note", target: self, action: #selector(addWordClicked))
        addWordBtn.bezelStyle = .rounded
        addWordBtn.frame = NSRect(x: 374, y: 12, width: 78, height: 28)
        blockedView.addSubview(addWordBtn)

        let removeWordBtn = NSButton(title: "Remove", target: self, action: #selector(removeWordClicked))
        removeWordBtn.bezelStyle = .rounded
        removeWordBtn.frame = NSRect(x: 454, y: 12, width: 66, height: 28)
        blockedView.addSubview(removeWordBtn)

        blockedTab.view = blockedView
        tabView.addTabViewItem(blockedTab)

        // -------------------------------------------------------------
        // Tab 2: Exceptions
        // -------------------------------------------------------------
        let exceptionsTab = NSTabViewItem(identifier: "ExceptionsTab")
        exceptionsTab.label = "✨ Exceptions"
        let exceptionsView = NSView(frame: tabView.contentRect)

        let exHeader = NSTextField(labelWithString: "Allowed Words (Exceptions): Words added here will NEVER be deleted.")
        exHeader.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        exHeader.textColor = .secondaryLabelColor
        exHeader.frame = NSRect(x: 12, y: 252, width: 508, height: 18)
        exceptionsView.addSubview(exHeader)

        // Search Bar for Exceptions
        exSearchField = NSSearchField(frame: NSRect(x: 12, y: 222, width: 508, height: 26))
        exSearchField.placeholderString = "Search allowed exceptions..."
        exSearchField.target = self
        exSearchField.action = #selector(exSearchChanged(_:))
        exceptionsView.addSubview(exSearchField)

        let exScroll = NSScrollView(frame: NSRect(x: 12, y: 50, width: 508, height: 166))
        exScroll.hasVerticalScroller = true
        exScroll.borderType = .bezelBorder

        exceptionsTableView = KeyHandlingTableView(frame: exScroll.bounds)
        let exCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ExceptionColumn"))
        exCol.title = "Allowed Word"
        exCol.width = 480
        exceptionsTableView.addTableColumn(exCol)
        exceptionsTableView.dataSource = self
        exceptionsTableView.delegate = self
        exceptionsTableView.headerView = nil
        exceptionsTableView.allowsMultipleSelection = false
        exceptionsTableView.onDeleteKeyPressed = { [weak self] in
            self?.removeExceptionClicked()
        }
        exScroll.documentView = exceptionsTableView
        exceptionsView.addSubview(exScroll)

        newExceptionField = NSTextField(frame: NSRect(x: 12, y: 12, width: 310, height: 28))
        newExceptionField.placeholderString = "Type allowed word (e.g. 'badger')..."
        newExceptionField.target = self
        newExceptionField.action = #selector(addExceptionClicked)
        exceptionsView.addSubview(newExceptionField)

        let addExBtn = NSButton(title: "Add Exception", target: self, action: #selector(addExceptionClicked))
        addExBtn.bezelStyle = .rounded
        addExBtn.frame = NSRect(x: 328, y: 12, width: 116, height: 28)
        exceptionsView.addSubview(addExBtn)

        let removeExBtn = NSButton(title: "Remove", target: self, action: #selector(removeExceptionClicked))
        removeExBtn.bezelStyle = .rounded
        removeExBtn.frame = NSRect(x: 448, y: 12, width: 72, height: 28)
        exceptionsView.addSubview(removeExBtn)

        exceptionsTab.view = exceptionsView
        tabView.addTabViewItem(exceptionsTab)

        // -------------------------------------------------------------
        // Tab 3: Blocked Websites & Notes
        // -------------------------------------------------------------
        let websitesTab = NSTabViewItem(identifier: "WebsitesTab")
        websitesTab.label = "🌐 Websites"
        let websitesView = NSView(frame: tabView.contentRect)

        // Options Checkboxes
        gateCheckbox = NSButton(checkboxWithTitle: "Enforce Access Gate: Pop up first, require 'Allow' to enter", target: self, action: #selector(gateToggled(_:)))
        gateCheckbox.state = WordStore.shared.requireAllowToEnter ? .on : .off
        gateCheckbox.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        gateCheckbox.frame = NSRect(x: 12, y: 254, width: 490, height: 18)
        websitesView.addSubview(gateCheckbox)

        webNoteCheckbox = NSButton(checkboxWithTitle: "Show Pop-Up Note on visit", target: self, action: #selector(webNoteToggled(_:)))
        webNoteCheckbox.state = WordStore.shared.showWebsiteNotes ? .on : .off
        webNoteCheckbox.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        webNoteCheckbox.frame = NSRect(x: 12, y: 232, width: 230, height: 18)
        websitesView.addSubview(webNoteCheckbox)

        closeTabsCheckbox = NSButton(checkboxWithTitle: "Auto-close tab if Access Gate disabled", target: self, action: #selector(closeTabsToggled(_:)))
        closeTabsCheckbox.state = WordStore.shared.closeBlockedTabs ? .on : .off
        closeTabsCheckbox.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        closeTabsCheckbox.frame = NSRect(x: 250, y: 232, width: 260, height: 18)
        websitesView.addSubview(closeTabsCheckbox)

        // Search Bar for Blocked Websites
        webSearchField = NSSearchField(frame: NSRect(x: 12, y: 202, width: 508, height: 26))
        webSearchField.placeholderString = "Search blocked websites or notes..."
        webSearchField.target = self
        webSearchField.action = #selector(webSearchChanged(_:))
        websitesView.addSubview(webSearchField)

        // Websites Table View
        let webScroll = NSScrollView(frame: NSRect(x: 12, y: 48, width: 508, height: 148))
        webScroll.hasVerticalScroller = true
        webScroll.borderType = .bezelBorder

        websitesTableView = KeyHandlingTableView(frame: webScroll.bounds)
        let wCol1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("DomainColumn"))
        wCol1.title = "Blocked Domain"
        wCol1.width = 160
        websitesTableView.addTableColumn(wCol1)

        let wCol2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("WebNoteColumn"))
        wCol2.title = "Assigned Pop-Up Note"
        wCol2.width = 320
        websitesTableView.addTableColumn(wCol2)

        websitesTableView.dataSource = self
        websitesTableView.delegate = self
        websitesTableView.headerView = NSTableHeaderView()
        websitesTableView.allowsMultipleSelection = false
        websitesTableView.onDeleteKeyPressed = { [weak self] in
            self?.removeWebsiteClicked()
        }
        webScroll.documentView = websitesTableView
        websitesView.addSubview(webScroll)

        // Websites Inputs (Domain + Note)
        newDomainField = NSTextField(frame: NSRect(x: 12, y: 12, width: 130, height: 28))
        newDomainField.placeholderString = "Domain (e.g. reddit.com)..."
        newDomainField.target = self
        newDomainField.action = #selector(addWebsiteClicked)
        websitesView.addSubview(newDomainField)

        newWebNoteField = NSTextField(frame: NSRect(x: 148, y: 12, width: 220, height: 28))
        newWebNoteField.placeholderString = "Pop-up note (e.g. Stay focused!)..."
        newWebNoteField.target = self
        newWebNoteField.action = #selector(addWebsiteClicked)
        websitesView.addSubview(newWebNoteField)

        let addWebBtn = NSButton(title: "Save Note", target: self, action: #selector(addWebsiteClicked))
        addWebBtn.bezelStyle = .rounded
        addWebBtn.frame = NSRect(x: 374, y: 12, width: 78, height: 28)
        websitesView.addSubview(addWebBtn)

        let removeWebBtn = NSButton(title: "Remove", target: self, action: #selector(removeWebsiteClicked))
        removeWebBtn.bezelStyle = .rounded
        removeWebBtn.frame = NSRect(x: 454, y: 12, width: 66, height: 28)
        websitesView.addSubview(removeWebBtn)

        websitesTab.view = websitesView
        tabView.addTabViewItem(websitesTab)

        // -------------------------------------------------------------
        // Tab 4: Cinema Mode
        // -------------------------------------------------------------
        let cinemaTab = NSTabViewItem(identifier: "CinemaTab")
        cinemaTab.label = "🎬 Cinema Mode"
        let cinemaView = NSView(frame: tabView.contentRect)

        cinemaEnableCheckbox = NSButton(checkboxWithTitle: "Enable Cinema Mode", target: self, action: #selector(cinemaEnableToggled(_:)))
        cinemaEnableCheckbox.state = WordStore.shared.isCinemaModeEnabled ? .on : .off
        cinemaEnableCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        cinemaEnableCheckbox.frame = NSRect(x: 14, y: 248, width: 300, height: 22)
        cinemaView.addSubview(cinemaEnableCheckbox)

        let cSub = NSTextField(labelWithString: "When watching media in full screen, intercepts attempts to leave full screen (e.g. pressing Escape) and displays your custom intervention message.")
        cSub.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        cSub.textColor = .secondaryLabelColor
        cSub.frame = NSRect(x: 14, y: 206, width: 490, height: 34)
        cSub.cell?.wraps = true
        cinemaView.addSubview(cSub)

        let cLabel = NSTextField(labelWithString: "Custom intervention message shown when trying to leave full screen:")
        cLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        cLabel.frame = NSRect(x: 14, y: 178, width: 490, height: 18)
        cinemaView.addSubview(cLabel)

        cinemaMsgField = NSTextField(frame: NSRect(x: 14, y: 104, width: 490, height: 68))
        cinemaMsgField.stringValue = WordStore.shared.cinemaModeMessage
        cinemaMsgField.placeholderString = "Custom reminder to stay immersed while watching media..."
        cinemaMsgField.cell?.wraps = true
        cinemaMsgField.cell?.isScrollable = false
        cinemaView.addSubview(cinemaMsgField)

        let saveCBtn = NSButton(title: "Save Message", target: self, action: #selector(saveCinemaMsgClicked))
        saveCBtn.bezelStyle = .rounded
        saveCBtn.frame = NSRect(x: 14, y: 64, width: 120, height: 28)
        cinemaView.addSubview(saveCBtn)

        let previewCBtn = NSButton(title: "Preview Intervention", target: self, action: #selector(previewCinemaMsgClicked))
        previewCBtn.bezelStyle = .rounded
        previewCBtn.frame = NSRect(x: 140, y: 64, width: 155, height: 28)
        cinemaView.addSubview(previewCBtn)

        let cTip = NSTextField(labelWithString: "💡 Tip: You can also quickly toggle Cinema Mode directly from the menu bar (🛡️ -> 🎬 Cinema Mode).")
        cTip.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        cTip.textColor = .secondaryLabelColor
        cTip.frame = NSRect(x: 14, y: 22, width: 490, height: 18)
        cinemaView.addSubview(cTip)

        cinemaTab.view = cinemaView
        tabView.addTabViewItem(cinemaTab)

        // -------------------------------------------------------------
        // Tab 5: Custom Prompts (Enabled & Quit Messages)
        // -------------------------------------------------------------
        let promptsTab = NSTabViewItem(identifier: "PromptsTab")
        promptsTab.label = "💬 Prompts"
        let promptsView = NSView(frame: tabView.contentRect)

        // Section 1: Disable Protection Intervention Message
        let pLabel = NSTextField(labelWithString: "Message shown when attempting to DISABLE Protection:")
        pLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        pLabel.frame = NSRect(x: 14, y: 248, width: 490, height: 18)
        promptsView.addSubview(pLabel)

        disableMsgField = NSTextField(frame: NSRect(x: 14, y: 200, width: 490, height: 44))
        disableMsgField.stringValue = WordStore.shared.disableProtectionMessage
        disableMsgField.placeholderString = "Custom intervention message to discourage disabling protection..."
        disableMsgField.cell?.wraps = true
        disableMsgField.cell?.isScrollable = false
        promptsView.addSubview(disableMsgField)

        let savePBtn = NSButton(title: "Save Message", target: self, action: #selector(saveDisableMsgClicked))
        savePBtn.bezelStyle = .rounded
        savePBtn.frame = NSRect(x: 14, y: 165, width: 120, height: 28)
        promptsView.addSubview(savePBtn)

        let testPBtn = NSButton(title: "Preview Alert", target: self, action: #selector(testDisableMsgClicked))
        testPBtn.bezelStyle = .rounded
        testPBtn.frame = NSRect(x: 140, y: 165, width: 130, height: 28)
        promptsView.addSubview(testPBtn)

        // Divider
        let pDiv = createDivider(frame: NSRect(x: 14, y: 152, width: 490, height: 1))
        promptsView.addSubview(pDiv)

        // Section 2: Quit Attempt Intervention Message
        let qLabel = NSTextField(labelWithString: "Message shown when attempting to Quit Word Blocker:")
        qLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        qLabel.frame = NSRect(x: 14, y: 122, width: 490, height: 18)
        promptsView.addSubview(qLabel)

        quitMsgField = NSTextField(frame: NSRect(x: 14, y: 74, width: 490, height: 44))
        quitMsgField.stringValue = WordStore.shared.quitMessage
        quitMsgField.placeholderString = "Custom intervention message to discourage quitting..."
        quitMsgField.cell?.wraps = true
        quitMsgField.cell?.isScrollable = false
        promptsView.addSubview(quitMsgField)

        let saveQBtn = NSButton(title: "Save Message", target: self, action: #selector(saveQuitMsgClicked))
        saveQBtn.bezelStyle = .rounded
        saveQBtn.frame = NSRect(x: 14, y: 38, width: 120, height: 28)
        promptsView.addSubview(saveQBtn)

        let testQBtn = NSButton(title: "Preview Quit Alert", target: self, action: #selector(testQuitMsgClicked))
        testQBtn.bezelStyle = .rounded
        testQBtn.frame = NSRect(x: 140, y: 38, width: 140, height: 28)
        promptsView.addSubview(testQBtn)

        promptsTab.view = promptsView
        tabView.addTabViewItem(promptsTab)

        contentView.addSubview(tabView)

        currentY -= 20

        // Divider
        let div2 = createDivider(frame: NSRect(x: 24, y: currentY, width: 532, height: 1))
        contentView.addSubview(div2)

        currentY -= 48

        // Interactive Test Field
        let testLabel = NSTextField(labelWithString: "🧪 Test Area (type 'blockme' to trigger note, or test variations):")
        testLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        testLabel.textColor = .secondaryLabelColor
        testLabel.frame = NSRect(x: 24, y: currentY + 22, width: 530, height: 18)
        contentView.addSubview(testLabel)

        testField = NSTextField(frame: NSRect(x: 24, y: currentY - 6, width: 532, height: 26))
        testField.placeholderString = "Try typing 'blockme' (shows note!), 'b444aad', or 'badger'..."
        contentView.addSubview(testField)

        updatePermissionStatus()

        // Observers
        WordStore.shared.onWordsChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.blockedTableView?.reloadData()
            }
        }

        WordStore.shared.onExceptionsChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.exceptionsTableView?.reloadData()
            }
        }

        WordStore.shared.onWebsitesChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.websitesTableView?.reloadData()
            }
        }

        WordStore.shared.onCinemaModeChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.cinemaEnableCheckbox?.state = WordStore.shared.isCinemaModeEnabled ? .on : .off
                self?.cinemaMsgField?.stringValue = WordStore.shared.cinemaModeMessage
            }
        }

        PermissionsManager.shared.onPermissionStatusChanged = { [weak self] granted in
            DispatchQueue.main.async {
                self?.updatePermissionStatus()
                if granted && !EventTapManager.shared.isTapActive {
                    EventTapManager.shared.start()
                }
            }
        }
    }

    private func createDivider(frame: NSRect) -> NSBox {
        let box = NSBox(frame: frame)
        box.boxType = .separator
        return box
    }

    public func updatePermissionStatus() {
        let granted = PermissionsManager.shared.isAccessibilityGranted()
        if granted {
            permissionBanner.stringValue = "✅ Accessibility Permission Active"
            permissionBanner.textColor = .systemGreen
            permissionButton.isHidden = true
            permissionHintLabel.isHidden = true
        } else {
            permissionBanner.stringValue = "⚠️ Accessibility Permission Missing"
            permissionBanner.textColor = .systemOrange
            permissionButton.isHidden = false
            permissionHintLabel.isHidden = false
        }
    }

    // MARK: - Search Filtering Logic

    private func filteredWords() -> [String] {
        let allWords = WordStore.shared.getWords()
        guard !currentBlockedSearch.isEmpty else { return allWords }
        return allWords.filter { word in
            let note = WordStore.shared.getNote(for: word)?.lowercased() ?? ""
            return word.contains(currentBlockedSearch) || note.contains(currentBlockedSearch)
        }
    }

    private func filteredExceptions() -> [String] {
        let allExceptions = WordStore.shared.getExceptions()
        guard !currentExSearch.isEmpty else { return allExceptions }
        return allExceptions.filter { $0.contains(currentExSearch) }
    }

    private func filteredWebsites() -> [String] {
        let allWebsites = WordStore.shared.getWebsites()
        guard !currentWebSearch.isEmpty else { return allWebsites }
        return allWebsites.filter { domain in
            let note = WordStore.shared.getWebsiteNote(for: domain)?.lowercased() ?? ""
            return domain.contains(currentWebSearch) || note.contains(currentWebSearch)
        }
    }

    @objc private func blockedSearchChanged(_ sender: NSSearchField) {
        currentBlockedSearch = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        blockedTableView.reloadData()
    }

    @objc private func exSearchChanged(_ sender: NSSearchField) {
        currentExSearch = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        exceptionsTableView.reloadData()
    }

    @objc private func webSearchChanged(_ sender: NSSearchField) {
        currentWebSearch = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        websitesTableView.reloadData()
    }

    // MARK: - Actions

    @objc private func permissionButtonClicked() {
        _ = PermissionsManager.shared.promptForAccessibility()
        PermissionsManager.shared.openSystemSettingsAccessibility()
    }

    @objc private func enableToggled(_ sender: NSButton) {
        if sender.state == .off {
            // User is attempting to disable protection!
            MenuBarController.shared.confirmAndDisable { confirmed in
                if !confirmed {
                    // User cancelled, keep checkbox checked
                    sender.state = .on
                }
            }
        } else {
            // Enable silently without sending any pop-up message
            WordStore.shared.isEnabled = true
        }
    }

    @objc private func soundToggled(_ sender: NSButton) {
        WordStore.shared.playAlertSound = (sender.state == .on)
    }

    @objc private func popupNoteToggled(_ sender: NSButton) {
        WordStore.shared.showPopupNotes = (sender.state == .on)
    }

    @objc private func fuzzyToggled(_ sender: NSButton) {
        WordStore.shared.isFuzzyEnabled = (sender.state == .on)
    }

    // Blocked Words & Notes
    @objc private func addWordClicked() {
        let word = newWordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = newNoteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }

        _ = WordStore.shared.addWord(word, note: note.isEmpty ? nil : note)
        if !note.isEmpty {
            WordStore.shared.setNote(for: word, note: note)
        }
        newWordField.stringValue = ""
        newNoteField.stringValue = ""
        blockedTableView.reloadData()
    }

    @objc private func removeWordClicked() {
        let selectedRow = blockedTableView.selectedRow
        let words = filteredWords()
        guard selectedRow >= 0 && selectedRow < words.count else { return }
        let wordToRemove = words[selectedRow]
        WordStore.shared.removeWord(wordToRemove)
        newWordField.stringValue = ""
        newNoteField.stringValue = ""
        blockedTableView.reloadData()
    }

    // Exceptions
    @objc private func addExceptionClicked() {
        let word = newExceptionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        if WordStore.shared.addException(word) {
            newExceptionField.stringValue = ""
            exceptionsTableView.reloadData()
        }
    }

    @objc private func removeExceptionClicked() {
        let selectedRow = exceptionsTableView.selectedRow
        let exceptions = filteredExceptions()
        guard selectedRow >= 0 && selectedRow < exceptions.count else { return }
        let exToRemove = exceptions[selectedRow]
        WordStore.shared.removeException(exToRemove)
        exceptionsTableView.reloadData()
    }

    // Blocked Websites & Notes
    @objc private func addWebsiteClicked() {
        let domain = newDomainField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = newWebNoteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else { return }

        _ = WordStore.shared.addWebsite(domain, note: note.isEmpty ? nil : note)
        if !note.isEmpty {
            WordStore.shared.setWebsiteNote(for: domain, note: note)
        }
        newDomainField.stringValue = ""
        newWebNoteField.stringValue = ""
        websitesTableView.reloadData()
    }

    @objc private func removeWebsiteClicked() {
        let selectedRow = websitesTableView.selectedRow
        let websites = filteredWebsites()
        guard selectedRow >= 0 && selectedRow < websites.count else { return }
        let domainToRemove = websites[selectedRow]
        WordStore.shared.removeWebsite(domainToRemove)
        newDomainField.stringValue = ""
        newWebNoteField.stringValue = ""
        websitesTableView.reloadData()
    }

    @objc private func gateToggled(_ sender: NSButton) {
        WordStore.shared.requireAllowToEnter = (sender.state == .on)
    }

    @objc private func closeTabsToggled(_ sender: NSButton) {
        WordStore.shared.closeBlockedTabs = (sender.state == .on)
    }

    @objc private func webNoteToggled(_ sender: NSButton) {
        WordStore.shared.showWebsiteNotes = (sender.state == .on)
    }

    // Cinema Mode Handlers
    @objc private func cinemaEnableToggled(_ sender: NSButton) {
        WordStore.shared.isCinemaModeEnabled = (sender.state == .on)
    }

    @objc private func saveCinemaMsgClicked() {
        let msg = cinemaMsgField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !msg.isEmpty {
            WordStore.shared.cinemaModeMessage = msg
        }
    }

    @objc private func previewCinemaMsgClicked() {
        saveCinemaMsgClicked()
        InterventionModalController.shared.showCinemaMode(
            note: WordStore.shared.cinemaModeMessage,
            onStay: {},
            onExit: {}
        )
    }

    // Custom Prompts Handlers
    @objc private func saveDisableMsgClicked() {
        let msg = disableMsgField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !msg.isEmpty {
            WordStore.shared.disableProtectionMessage = msg
        }
    }

    @objc private func testDisableMsgClicked() {
        saveDisableMsgClicked()
        InterventionModalController.shared.showDisableProtection(
            message: WordStore.shared.disableProtectionMessage,
            onKeepOn: {},
            onDisable: {}
        )
    }

    @objc private func saveQuitMsgClicked() {
        let msg = quitMsgField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !msg.isEmpty {
            WordStore.shared.quitMessage = msg
        }
    }

    @objc private func testQuitMsgClicked() {
        saveQuitMsgClicked()
        InterventionModalController.shared.showQuitApp(
            message: WordStore.shared.quitMessage,
            onStay: {},
            onQuit: {}
        )
    }

    // MARK: - NSTableViewDataSource & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == blockedTableView {
            return filteredWords().count
        } else if tableView == exceptionsTableView {
            return filteredExceptions().count
        } else {
            return filteredWebsites().count
        }
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }
        let row = tv.selectedRow

        if tv == blockedTableView {
            let words = filteredWords()
            if row >= 0 && row < words.count {
                let word = words[row]
                newWordField.stringValue = word
                newNoteField.stringValue = WordStore.shared.getNote(for: word) ?? ""
            }
        } else if tv == websitesTableView {
            let websites = filteredWebsites()
            if row >= 0 && row < websites.count {
                let domain = websites[row]
                newDomainField.stringValue = domain
                newWebNoteField.stringValue = WordStore.shared.getWebsiteNote(for: domain) ?? ""
            }
        }
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == blockedTableView {
            let words = filteredWords()
            guard row >= 0 && row < words.count else { return nil }
            let word = words[row]

            let isWordCol = (tableColumn?.identifier.rawValue == "WordColumn")
            let cellId = NSUserInterfaceItemIdentifier(isWordCol ? "WordColCell" : "NoteColCell")
            var textField = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTextField

            if textField == nil {
                textField = NSTextField(labelWithString: "")
                textField?.identifier = cellId
                textField?.font = NSFont.systemFont(ofSize: 12)
            }

            if isWordCol {
                textField?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
                textField?.textColor = .labelColor
                textField?.stringValue = word
            } else {
                if let note = WordStore.shared.getNote(for: word), !note.isEmpty {
                    textField?.textColor = .labelColor
                    textField?.stringValue = note
                } else {
                    textField?.textColor = .tertiaryLabelColor
                    textField?.stringValue = "— (no note assigned)"
                }
            }
            return textField
        } else if tableView == exceptionsTableView {
            let exceptions = filteredExceptions()
            guard row >= 0 && row < exceptions.count else { return nil }

            let cellId = NSUserInterfaceItemIdentifier("ExceptionCell")
            var textField = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTextField
            if textField == nil {
                textField = NSTextField(labelWithString: "")
                textField?.identifier = cellId
                textField?.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            }
            textField?.stringValue = exceptions[row]
            return textField
        } else {
            let websites = filteredWebsites()
            guard row >= 0 && row < websites.count else { return nil }
            let domain = websites[row]

            let isDomainCol = (tableColumn?.identifier.rawValue == "DomainColumn")
            let cellId = NSUserInterfaceItemIdentifier(isDomainCol ? "DomainColCell" : "WebNoteColCell")
            var textField = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTextField

            if textField == nil {
                textField = NSTextField(labelWithString: "")
                textField?.identifier = cellId
                textField?.font = NSFont.systemFont(ofSize: 12)
            }

            if isDomainCol {
                textField?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
                textField?.textColor = .labelColor
                textField?.stringValue = domain
            } else {
                if let note = WordStore.shared.getWebsiteNote(for: domain), !note.isEmpty {
                    textField?.textColor = .labelColor
                    textField?.stringValue = note
                } else {
                    textField?.textColor = .tertiaryLabelColor
                    textField?.stringValue = "— (no note assigned)"
                }
            }
            return textField
        }
    }
}
