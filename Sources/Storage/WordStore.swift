import Foundation

/// Manages persistence, state, and multi-stage matching for blocked words, custom pop-up notes, and exceptions.
public final class WordStore {
    public static let shared = WordStore()

    private let defaults = UserDefaults.standard
    private let blockedWordsKey = "WordBlocker.BlockedWords"
    private let wordNotesKey = "WordBlocker.WordNotes"
    private let showPopupNotesKey = "WordBlocker.ShowPopupNotes"
    private let exceptionsKey = "WordBlocker.ExceptionWords"
    private let blockedWebsitesKey = "WordBlocker.BlockedWebsites"
    private let websiteNotesKey = "WordBlocker.WebsiteNotes"
    private let showWebsiteNotesKey = "WordBlocker.ShowWebsiteNotes"
    private let closeBlockedTabsKey = "WordBlocker.CloseBlockedTabs"
    private let requireAllowToEnterKey = "WordBlocker.RequireAllowToEnter"
    private let cinemaModeEnabledKey = "WordBlocker.CinemaModeEnabled"
    private let cinemaModeMessageKey = "WordBlocker.CinemaModeMessage"
    private let isEnabledKey = "WordBlocker.IsEnabled"
    private let playAlertSoundKey = "WordBlocker.PlayAlertSound"
    private let isFuzzyEnabledKey = "WordBlocker.IsFuzzyEnabled"

    private let lock = NSLock()
    private var wordsSet: Set<String> = []
    private var sortedWordsCache: [String] = []
    private var notesMap: [String: String] = [:]

    private var exceptionsSet: Set<String> = []
    private var sortedExceptionsCache: [String] = []

    private var websitesSet: Set<String> = []
    private var sortedWebsitesCache: [String] = []
    private var websiteNotesMap: [String: String] = [:]
    private var temporaryAllowedUntil: [String: Date] = [:]

    public var onWordsChanged: (() -> Void)?
    public var onExceptionsChanged: (() -> Void)?
    public var onWebsitesChanged: (() -> Void)?
    public var onCinemaModeChanged: (() -> Void)?
    public var onStateChanged: (() -> Void)?

    private init() {
        loadSettings()
    }

    private func loadSettings() {
        lock.lock()
        defer { lock.unlock() }

        // Load blocked words
        if let saved = defaults.stringArray(forKey: blockedWordsKey) {
            wordsSet = Set(saved.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        } else {
            wordsSet = ["blockme", "badword", "bad"]
            defaults.set(Array(wordsSet), forKey: blockedWordsKey)
        }

        // Load custom pop-up notes
        if let savedNotes = defaults.dictionary(forKey: wordNotesKey) as? [String: String] {
            notesMap = savedNotes
        } else {
            notesMap = [
                "blockme": "Take a breath! You chose to block this word to stay productive.",
                "badword": "Remember your standards. Stay focused on your goals."
            ]
            defaults.set(notesMap, forKey: wordNotesKey)
        }

        // Load exceptions (allowed words that should never be deleted)
        if let savedExceptions = defaults.stringArray(forKey: exceptionsKey) {
            exceptionsSet = Set(savedExceptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        } else {
            exceptionsSet = ["badger", "badge", "password", "compass"]
            defaults.set(Array(exceptionsSet), forKey: exceptionsKey)
        }

        // Load blocked websites
        if let savedWebsites = defaults.stringArray(forKey: blockedWebsitesKey) {
            websitesSet = Set(savedWebsites.map { normalizeWebsiteInput($0) }.filter { !$0.isEmpty })
        } else {
            websitesSet = ["reddit.com", "twitter.com", "x.com", "youtube.com"]
            defaults.set(Array(websitesSet), forKey: blockedWebsitesKey)
        }

        // Load custom website pop-up notes
        if let savedWebNotes = defaults.dictionary(forKey: websiteNotesKey) as? [String: String] {
            websiteNotesMap = savedWebNotes
        } else {
            websiteNotesMap = [
                "reddit.com": "Take a breath! You blocked Reddit to focus on your deep work.",
                "twitter.com": "Remember your goals. Avoid the endless social media feed.",
                "x.com": "Remember your goals. Avoid the endless social media feed.",
                "youtube.com": "Stay focused! Keep your momentum going on current projects."
            ]
            defaults.set(websiteNotesMap, forKey: websiteNotesKey)
        }

        rebuildCache()
    }

    private func rebuildCache() {
        sortedWordsCache = wordsSet.sorted()
        sortedExceptionsCache = exceptionsSet.sorted()
        sortedWebsitesCache = websitesSet.sorted()
    }

    // MARK: - General Settings

    public var isEnabled: Bool {
        get {
            if defaults.object(forKey: isEnabledKey) == nil { return true }
            return defaults.bool(forKey: isEnabledKey)
        }
        set {
            defaults.set(newValue, forKey: isEnabledKey)
            onStateChanged?()
        }
    }

    public var playAlertSound: Bool {
        get {
            if defaults.object(forKey: playAlertSoundKey) == nil { return true }
            return defaults.bool(forKey: playAlertSoundKey)
        }
        set {
            defaults.set(newValue, forKey: playAlertSoundKey)
        }
    }

    public var isFuzzyEnabled: Bool {
        get {
            if defaults.object(forKey: isFuzzyEnabledKey) == nil { return true }
            return defaults.bool(forKey: isFuzzyEnabledKey)
        }
        set {
            defaults.set(newValue, forKey: isFuzzyEnabledKey)
        }
    }

    public var showPopupNotes: Bool {
        get {
            if defaults.object(forKey: showPopupNotesKey) == nil { return true }
            return defaults.bool(forKey: showPopupNotesKey)
        }
        set {
            defaults.set(newValue, forKey: showPopupNotesKey)
        }
    }

    public var showWebsiteNotes: Bool {
        get {
            if defaults.object(forKey: showWebsiteNotesKey) == nil { return true }
            return defaults.bool(forKey: showWebsiteNotesKey)
        }
        set {
            defaults.set(newValue, forKey: showWebsiteNotesKey)
        }
    }

    public var closeBlockedTabs: Bool {
        get {
            if defaults.object(forKey: closeBlockedTabsKey) == nil { return true }
            return defaults.bool(forKey: closeBlockedTabsKey)
        }
        set {
            defaults.set(newValue, forKey: closeBlockedTabsKey)
        }
    }

    public var requireAllowToEnter: Bool {
        get {
            if defaults.object(forKey: requireAllowToEnterKey) == nil { return true }
            return defaults.bool(forKey: requireAllowToEnterKey)
        }
        set {
            defaults.set(newValue, forKey: requireAllowToEnterKey)
        }
    }

    // MARK: - Temporary Access Management

    public func isWebsiteTemporarilyAllowed(_ rawDomain: String) -> Bool {
        let clean = normalizeWebsiteInput(rawDomain)
        lock.lock()
        defer { lock.unlock() }

        // Check exact domain or matching parent domain
        for (domain, expiry) in temporaryAllowedUntil {
            if clean == domain || clean.hasSuffix("." + domain) {
                if Date() < expiry {
                    return true
                } else {
                    temporaryAllowedUntil.removeValue(forKey: domain)
                }
            }
        }
        return false
    }

    public func allowWebsiteTemporarily(_ rawDomain: String, minutes: Int) {
        let clean = normalizeWebsiteInput(rawDomain)
        guard !clean.isEmpty else { return }
        lock.lock()
        temporaryAllowedUntil[clean] = Date().addingTimeInterval(Double(minutes * 60))
        lock.unlock()
    }

    public func clearTemporaryAllowances() {
        lock.lock()
        temporaryAllowedUntil.removeAll()
        lock.unlock()
    }

    // MARK: - Custom Intervention Messages

    private let disableProtectionMsgKey = "WordBlocker.DisableProtectionMessage"
    private let quitMessageKey = "WordBlocker.QuitMessage"

    public var disableProtectionMessage: String {
        get {
            return defaults.string(forKey: disableProtectionMsgKey) ?? "Are you sure you want to disable protection? Stay focused and keep your commitment."
        }
        set {
            defaults.set(newValue, forKey: disableProtectionMsgKey)
        }
    }

    public var quitMessage: String {
        get {
            return defaults.string(forKey: quitMessageKey) ?? "Are you sure you want to quit? Remember your commitment to staying focused."
        }
        set {
            defaults.set(newValue, forKey: quitMessageKey)
        }
    }

    public var isCinemaModeEnabled: Bool {
        get {
            if defaults.object(forKey: cinemaModeEnabledKey) == nil { return false }
            return defaults.bool(forKey: cinemaModeEnabledKey)
        }
        set {
            defaults.set(newValue, forKey: cinemaModeEnabledKey)
            NotificationCenter.default.post(name: Notification.Name("CinemaModeStateChanged"), object: nil)
            onCinemaModeChanged?()
        }
    }

    public var cinemaModeMessage: String {
        get {
            return defaults.string(forKey: cinemaModeMessageKey) ?? "Stay immersed! Remember your commitment to finish what you're watching without multitasking."
        }
        set {
            defaults.set(newValue, forKey: cinemaModeMessageKey)
            onCinemaModeChanged?()
        }
    }

    // MARK: - Blocked Words & Pop-Up Notes Management

    public func getWords() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return sortedWordsCache
    }

    public func getNote(for rawWord: String) -> String? {
        let clean = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        defer { lock.unlock() }
        return notesMap[clean]
    }

    public func setNote(for rawWord: String, note: String) {
        let clean = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return }

        lock.lock()
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNote.isEmpty {
            notesMap.removeValue(forKey: clean)
        } else {
            notesMap[clean] = trimmedNote
        }
        defaults.set(notesMap, forKey: wordNotesKey)
        lock.unlock()

        onWordsChanged?()
    }

    public func addWord(_ rawWord: String, note: String? = nil) -> Bool {
        let clean = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return false }

        lock.lock()
        let inserted = wordsSet.insert(clean).inserted
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            notesMap[clean] = note
            defaults.set(notesMap, forKey: wordNotesKey)
        }

        if inserted {
            rebuildCache()
            defaults.set(Array(wordsSet), forKey: blockedWordsKey)
        }
        lock.unlock()

        if inserted {
            onWordsChanged?()
        }
        return inserted
    }

    public func removeWord(_ rawWord: String) {
        let clean = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        let removed = wordsSet.remove(clean) != nil
        notesMap.removeValue(forKey: clean)
        defaults.set(notesMap, forKey: wordNotesKey)

        if removed {
            rebuildCache()
            defaults.set(Array(wordsSet), forKey: blockedWordsKey)
        }
        lock.unlock()

        if removed {
            onWordsChanged?()
        }
    }

    public func removeWord(at index: Int) {
        lock.lock()
        guard index >= 0 && index < sortedWordsCache.count else {
            lock.unlock()
            return
        }
        let word = sortedWordsCache[index]
        wordsSet.remove(word)
        notesMap.removeValue(forKey: word)
        defaults.set(notesMap, forKey: wordNotesKey)
        rebuildCache()
        defaults.set(Array(wordsSet), forKey: blockedWordsKey)
        lock.unlock()

        onWordsChanged?()
    }

    public func clearAllWords() {
        lock.lock()
        wordsSet.removeAll()
        notesMap.removeAll()
        defaults.set([:], forKey: wordNotesKey)
        rebuildCache()
        defaults.set([], forKey: blockedWordsKey)
        lock.unlock()

        onWordsChanged?()
    }

    // MARK: - Exceptions Management

    public func getExceptions() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return sortedExceptionsCache
    }

    public func addException(_ rawWord: String) -> Bool {
        let clean = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return false }

        lock.lock()
        let inserted = exceptionsSet.insert(clean).inserted
        if inserted {
            rebuildCache()
            defaults.set(Array(exceptionsSet), forKey: exceptionsKey)
        }
        lock.unlock()

        if inserted {
            onExceptionsChanged?()
        }
        return inserted
    }

    public func removeException(_ rawWord: String) {
        let clean = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        let removed = exceptionsSet.remove(clean) != nil
        if removed {
            rebuildCache()
            defaults.set(Array(exceptionsSet), forKey: exceptionsKey)
        }
        lock.unlock()

        if removed {
            onExceptionsChanged?()
        }
    }

    public func removeException(at index: Int) {
        lock.lock()
        guard index >= 0 && index < sortedExceptionsCache.count else {
            lock.unlock()
            return
        }
        let word = sortedExceptionsCache[index]
        exceptionsSet.remove(word)
        rebuildCache()
        defaults.set(Array(exceptionsSet), forKey: exceptionsKey)
        lock.unlock()

        onExceptionsChanged?()
    }

    public func clearAllExceptions() {
        lock.lock()
        exceptionsSet.removeAll()
        rebuildCache()
        defaults.set([], forKey: exceptionsKey)
        lock.unlock()

        onExceptionsChanged?()
    }

    // MARK: - Blocked Websites Management

    public func normalizeWebsiteInput(_ raw: String) -> String {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("https://") {
            clean = String(clean.dropFirst(8))
        } else if clean.hasPrefix("http://") {
            clean = String(clean.dropFirst(7))
        }
        if clean.hasPrefix("www.") {
            clean = String(clean.dropFirst(4))
        }
        while clean.hasSuffix("/") {
            clean = String(clean.dropLast())
        }
        return clean
    }

    public func getWebsites() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return sortedWebsitesCache
    }

    public func getWebsiteNote(for rawDomain: String) -> String? {
        let clean = normalizeWebsiteInput(rawDomain)
        lock.lock()
        defer { lock.unlock() }
        return websiteNotesMap[clean]
    }

    public func setWebsiteNote(for rawDomain: String, note: String) {
        let clean = normalizeWebsiteInput(rawDomain)
        guard !clean.isEmpty else { return }

        lock.lock()
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNote.isEmpty {
            websiteNotesMap.removeValue(forKey: clean)
        } else {
            websiteNotesMap[clean] = trimmedNote
        }
        defaults.set(websiteNotesMap, forKey: websiteNotesKey)
        lock.unlock()

        onWebsitesChanged?()
    }

    public func addWebsite(_ rawDomain: String, note: String? = nil) -> Bool {
        let clean = normalizeWebsiteInput(rawDomain)
        guard !clean.isEmpty else { return false }

        lock.lock()
        let inserted = websitesSet.insert(clean).inserted
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            websiteNotesMap[clean] = note
            defaults.set(websiteNotesMap, forKey: websiteNotesKey)
        }

        if inserted {
            sortedWebsitesCache = websitesSet.sorted()
            defaults.set(Array(websitesSet), forKey: blockedWebsitesKey)
        }
        lock.unlock()

        if inserted {
            onWebsitesChanged?()
        }
        return inserted
    }

    public func removeWebsite(_ rawDomain: String) {
        let clean = normalizeWebsiteInput(rawDomain)
        lock.lock()
        let removed = websitesSet.remove(clean) != nil
        websiteNotesMap.removeValue(forKey: clean)
        defaults.set(websiteNotesMap, forKey: websiteNotesKey)

        if removed {
            sortedWebsitesCache = websitesSet.sorted()
            defaults.set(Array(websitesSet), forKey: blockedWebsitesKey)
        }
        lock.unlock()

        if removed {
            onWebsitesChanged?()
        }
    }

    public func removeWebsite(at index: Int) {
        lock.lock()
        guard index >= 0 && index < sortedWebsitesCache.count else {
            lock.unlock()
            return
        }
        let domain = sortedWebsitesCache[index]
        websitesSet.remove(domain)
        websiteNotesMap.removeValue(forKey: domain)
        defaults.set(websiteNotesMap, forKey: websiteNotesKey)
        sortedWebsitesCache = websitesSet.sorted()
        defaults.set(Array(websitesSet), forKey: blockedWebsitesKey)
        lock.unlock()

        onWebsitesChanged?()
    }

    public func clearAllWebsites() {
        lock.lock()
        websitesSet.removeAll()
        websiteNotesMap.removeAll()
        defaults.set([:], forKey: websiteNotesKey)
        sortedWebsitesCache.removeAll()
        defaults.set([], forKey: blockedWebsitesKey)
        lock.unlock()

        onWebsitesChanged?()
    }

    /// Matches a visited URL or host against the set of blocked websites.
    /// Supports exact hosts, subdomains, and specific URL paths.
    public func matchBlockedWebsite(urlOrHost: String) -> (matchedDomain: String, note: String?)? {
        lock.lock()
        defer { lock.unlock() }

        guard !websitesSet.isEmpty else { return nil }

        let text = urlOrHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Ignore browser internal schemes
        if text.hasPrefix("chrome://") || text.hasPrefix("about:") || text.hasPrefix("edge://") || text.hasPrefix("brave://") || text.hasPrefix("arc://") {
            return nil
        }

        var fullLower = text.lowercased()
        if fullLower.hasPrefix("https://") {
            fullLower = String(fullLower.dropFirst(8))
        } else if fullLower.hasPrefix("http://") {
            fullLower = String(fullLower.dropFirst(7))
        }
        if fullLower.hasPrefix("www.") {
            fullLower = String(fullLower.dropFirst(4))
        }

        // Extract host part (before / or ?)
        let host: String
        if let slashIndex = fullLower.firstIndex(of: "/") {
            host = String(fullLower[..<slashIndex])
        } else if let questionIndex = fullLower.firstIndex(of: "?") {
            host = String(fullLower[..<questionIndex])
        } else {
            host = fullLower
        }

        for domain in sortedWebsitesCache {
            let cleanBlocked = normalizeWebsiteInput(domain)
            if cleanBlocked.contains("/") {
                // Path-based match (e.g. reddit.com/r/all)
                // Match the host (including subdomains like m.youtube.com) and the path prefix.
                let parts = cleanBlocked.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                let blockedHost = String(parts[0])
                let blockedPath = parts.count > 1 ? "/" + String(parts[1]) : "/"
                let pathPart = fullLower.dropFirst(host.count)
                let hostMatches = host == blockedHost || host.hasSuffix("." + blockedHost)
                if hostMatches && (pathPart.hasPrefix(blockedPath) || fullLower.hasPrefix(cleanBlocked)) {
                    return (matchedDomain: domain, note: websiteNotesMap[domain])
                }
            } else {
                // Host / Subdomain match (e.g. reddit.com matches reddit.com and old.reddit.com)
                if host == cleanBlocked || host.hasSuffix("." + cleanBlocked) {
                    return (matchedDomain: domain, note: websiteNotesMap[domain])
                }
            }
        }

        return nil
    }

    // MARK: - Matching Engine with Exceptions Guard & Pop-Up Note Resolution

    /// Tests the raw keystroke buffer against blocked words, strictly honoring exceptions,
    /// and attaches the custom pop-up note if assigned.
    public func matchBlocked(in rawChars: [Character]) -> (matchedWord: String, deleteCount: Int, note: String?)? {
        lock.lock()
        defer { lock.unlock() }

        guard !wordsSet.isEmpty, !rawChars.isEmpty else { return nil }

        let rawString = String(rawChars).lowercased()
        let lastChar = rawChars.last!
        let isAtWordBoundary = lastChar.isWhitespace || lastChar.isPunctuation

        // Extract the current raw word being typed
        let currentRawToken: String = {
            var chars: [Character] = []
            for c in rawChars.reversed() {
                if c.isWhitespace { break }
                chars.append(c)
            }
            return String(chars.reversed()).lowercased()
        }()

        // 1. Guard against Exceptions
        if exceptionsSet.contains(currentRawToken) {
            return nil
        }

        // Defer if token is a prefix of an exception
        if !isAtWordBoundary {
            let isPrefixOfException = exceptionsSet.contains { exception in
                exception.hasPrefix(currentRawToken) && exception != currentRawToken
            }
            if isPrefixOfException {
                return nil
            }
        }

        // 2. Tier 1: Fast direct suffix check
        for word in wordsSet {
            if rawString.hasSuffix(word) {
                if !isAtWordBoundary {
                    let hasExceptionPrefix = exceptionsSet.contains { $0.hasPrefix(word) && $0 != word }
                    if hasExceptionPrefix {
                        continue
                    }
                }
                let note = notesMap[word]
                return (matchedWord: word, deleteCount: word.count, note: note)
            }
        }

        // 3. Tier 2: Obfuscation & Fuzzy variation detection
        if isFuzzyEnabled {
            let tokens = ObfuscationNormalizer.shared.normalizeBuffer(rawChars)
            guard !tokens.isEmpty else { return nil }

            for word in wordsSet {
                for token in tokens.reversed() {
                    if exceptionsSet.contains(token.text) {
                        continue
                    }

                    if token.rawEndIndex >= rawChars.count - 2 {
                        if !isAtWordBoundary {
                            let isPrefixOfException = exceptionsSet.contains { $0.hasPrefix(token.text) && $0 != token.text }
                            if isPrefixOfException {
                                continue
                            }
                        }

                        if let matchedToken = FuzzyMatcher.shared.matches(candidates: [token], targetWord: word, allowFuzzyEditDistance: true) {
                            let deleteCount = rawChars.count - matchedToken.rawStartIndex
                            let note = notesMap[word]
                            return (matchedWord: word, deleteCount: deleteCount, note: note)
                        }
                    }
                }

                // Multi-word phrases
                if word.contains(" ") {
                    let phraseTokens = tokens.filter { $0.rawEndIndex >= rawChars.count - 30 }
                    let combinedText = phraseTokens.map { $0.text }.joined(separator: " ")
                    if combinedText.contains(word) || combinedText.hasSuffix(word) {
                        if !exceptionsSet.contains(combinedText) {
                            if let firstToken = phraseTokens.first {
                                let deleteCount = rawChars.count - firstToken.rawStartIndex
                                let note = notesMap[word]
                                return (matchedWord: word, deleteCount: deleteCount, note: note)
                            }
                        }
                    }
                }
            }
        }

        return nil
    }
}
