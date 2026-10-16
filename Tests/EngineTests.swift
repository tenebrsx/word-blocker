import Foundation

@main
struct TestRunner {
    static func assertTest(_ condition: Bool, _ message: String) {
        if !condition {
            print("❌ FAILED: \(message)")
            exit(1)
        } else {
            print("✅ PASSED: \(message)")
        }
    }

    static func main() {
        print("=== Running Word Blocker Engine, Obfuscation & Exceptions Tests ===")

        let store = WordStore.shared
        store.clearAllWords()
        store.clearAllExceptions()

        _ = store.addWord("bad")
        _ = store.addWord("word")
        _ = store.addWord("secret")
        _ = store.addWord("forbidden")

        _ = store.addException("badger")
        _ = store.addException("badge")
        _ = store.addException("password")
        _ = store.addException("compass")

        store.isFuzzyEnabled = true

        let engine = WordBufferEngine.shared
        engine.reset()

        // -------------------------------------------------------------
        // Test 1: Standard Exact Word Matching
        // -------------------------------------------------------------
        print("\n--- Test 1: Standard Exact Matching ---")
        let exactRes = engine.processInput("word")
        assertTest(exactRes != nil, "Matches exact word 'word'")
        assertTest(exactRes?.matchedWord == "word", "Matched word is 'word'")
        assertTest(exactRes?.deleteCount == 4, "Delete count is 4 for 'word'")

        // -------------------------------------------------------------
        // Test 2: Character Elongation & Leetspeak
        // -------------------------------------------------------------
        print("\n--- Test 2: Character Elongation & Leetspeak ---")
        engine.reset()
        let wordRes = engine.processInput("w0000000rrrrrd")
        assertTest(wordRes != nil, "Detected 'w0000000rrrrrd' as variation of 'word'")
        assertTest(wordRes?.deleteCount == 14, "Physical delete count is 14 for 'w0000000rrrrrd'")

        // -------------------------------------------------------------
        // Test 3: Exception Protection (Allowed Words)
        // -------------------------------------------------------------
        print("\n--- Test 3: Exceptions / Whitelist Protection ---")
        engine.reset()

        // Typing exception word "password" (which contains "pass")
        let exRes1 = engine.processInput("password")
        assertTest(exRes1 == nil, "Exception 'password' was NOT blocked")

        // Typing exception word "badge"
        engine.reset()
        let exRes2 = engine.processInput("badge")
        assertTest(exRes2 == nil, "Exception 'badge' was NOT blocked")

        // Typing exception word "badger" character-by-character
        engine.reset()
        _ = engine.processInput("b")
        _ = engine.processInput("a")
        let badPrefix = engine.processInput("d") // 'bad' is typed, but 'badger' is in exceptions!
        assertTest(badPrefix == nil, "'bad' prefix deferred because 'badger' is an allowed exception")

        _ = engine.processInput("g")
        _ = engine.processInput("e")
        let badgerComplete = engine.processInput("r")
        assertTest(badgerComplete == nil, "Completed exception 'badger' was NOT blocked")

        // Typing 'bad ' followed by a space (so user was NOT typing badger, but actually bad)
        engine.reset()
        _ = engine.processInput("bad")
        let badWithSpace = engine.processInput(" ")
        assertTest(badWithSpace != nil, "'bad ' followed by word boundary IS blocked")

        // -------------------------------------------------------------
        // Test 4: Infix Noise & Punctuation Padding
        // -------------------------------------------------------------
        print("\n--- Test 4: Infix Noise & Punctuation Padding ---")
        engine.reset()
        let noiseRes = engine.processInput("w.o.r.d")
        assertTest(noiseRes != nil, "Detected 'w.o.r.d' as variation of 'word'")
        assertTest(noiseRes?.deleteCount == 7, "Physical delete count is 7 for 'w.o.r.d'")

        // -------------------------------------------------------------
        // Test 5: Typo & Transposition (Fuzzy Distance)
        // -------------------------------------------------------------
        print("\n--- Test 5: Typos & Transpositions ---")
        engine.reset()
        let transRes = engine.processInput("sceret")
        assertTest(transRes != nil, "Detected adjacent transposition 'sceret' for 'secret'")

        // -------------------------------------------------------------
        // Test 7: Pop-Up Notes Management & Resolution
        // -------------------------------------------------------------
        print("\n--- Test 7: Pop-Up Notes Operations ---")
        _ = store.addWord("sloth", note: "Stay disciplined and focus on your goals!")
        assertTest(store.getNote(for: "sloth") == "Stay disciplined and focus on your goals!", "Note saved for 'sloth'")

        engine.reset()
        let noteMatch = engine.processInput("sloth")
        assertTest(noteMatch != nil, "Matched 'sloth'")
        assertTest(noteMatch?.note == "Stay disciplined and focus on your goals!", "Match includes assigned custom note")

        // Update note
        store.setNote(for: "sloth", note: "Updated custom reminder")
        assertTest(store.getNote(for: "sloth") == "Updated custom reminder", "Updated note for 'sloth'")

        // Word without note
        engine.reset()
        let noNoteMatch = engine.processInput("word")
        assertTest(noNoteMatch != nil, "Matched 'word'")
        assertTest(noNoteMatch?.note == nil, "Word without note returns nil note")

        // -------------------------------------------------------------
        // Test 8: Custom Intervention Messages (Disable & Quit)
        // -------------------------------------------------------------
        print("\n--- Test 8: Custom Intervention Messages ---")
        assertTest(!store.disableProtectionMessage.isEmpty, "Disable protection message exists")
        assertTest(!store.quitMessage.isEmpty, "Quit message exists")

        store.disableProtectionMessage = "Custom Disable Warning!"
        assertTest(store.disableProtectionMessage == "Custom Disable Warning!", "Updated disable protection message")

        store.quitMessage = "Custom Quit Warning!"
        assertTest(store.quitMessage == "Custom Quit Warning!", "Updated quit message")

        // -------------------------------------------------------------
        // Test 9: Blocked Websites & Website Notes
        // -------------------------------------------------------------
        print("\n--- Test 9: Blocked Websites & Notes Operations ---")
        store.clearAllWebsites()
        _ = store.addWebsite("reddit.com", note: "Stay off Reddit during work!")
        _ = store.addWebsite("youtube.com/shorts", note: "No shorts allowed!")
        _ = store.addWebsite("https://www.twitter.com/", note: "Avoid Twitter!")

        assertTest(store.getWebsites().contains("reddit.com"), "Added 'reddit.com'")
        assertTest(store.getWebsites().contains("twitter.com"), "Normalized and added 'twitter.com'")
        assertTest(store.getWebsites().contains("youtube.com/shorts"), "Added path-specific website")

        assertTest(store.getWebsiteNote(for: "reddit.com") == "Stay off Reddit during work!", "Website note for 'reddit.com'")
        assertTest(store.getWebsiteNote(for: "twitter.com") == "Avoid Twitter!", "Website note for 'twitter.com'")

        // Matching tests
        let redditMatch1 = store.matchBlockedWebsite(urlOrHost: "https://www.reddit.com/r/swift")
        assertTest(redditMatch1 != nil, "Matched https://www.reddit.com/r/swift")
        assertTest(redditMatch1?.matchedDomain == "reddit.com", "Matched domain is reddit.com")
        assertTest(redditMatch1?.note == "Stay off Reddit during work!", "Matched note is correct")

        let redditSubdomain = store.matchBlockedWebsite(urlOrHost: "https://old.reddit.com")
        assertTest(redditSubdomain != nil, "Matched subdomain old.reddit.com")

        let falseReddit = store.matchBlockedWebsite(urlOrHost: "https://notreddit.com")
        assertTest(falseReddit == nil, "Did not falsely match notreddit.com")

        let falseRedditSuffix = store.matchBlockedWebsite(urlOrHost: "https://reddit.com.otherdomain.org")
        assertTest(falseRedditSuffix == nil, "Did not falsely match other domain with reddit in host prefix")

        let shortsMatch = store.matchBlockedWebsite(urlOrHost: "https://www.youtube.com/shorts/abc123xyz")
        assertTest(shortsMatch != nil, "Matched specific path youtube.com/shorts")

        let nonShortsMatch = store.matchBlockedWebsite(urlOrHost: "https://www.youtube.com/watch?v=123")
        assertTest(nonShortsMatch == nil, "Did not match non-shorts YouTube URL when only shorts is blocked")

        // Removal
        store.removeWebsite("reddit.com")
        assertTest(!store.getWebsites().contains("reddit.com"), "Removed reddit.com")
        assertTest(store.matchBlockedWebsite(urlOrHost: "https://reddit.com") == nil, "Removed domain is no longer matched")

        // -------------------------------------------------------------
        // Test 10: Access Gate & Temporary Allowance
        // -------------------------------------------------------------
        print("\n--- Test 10: Access Gate & Temporary Allowance ---")
        assertTest(store.requireAllowToEnter == true, "Access Gate enabled by default")
        store.clearTemporaryAllowances()

        assertTest(!store.isWebsiteTemporarilyAllowed("twitter.com"), "Twitter not yet allowed")
        store.allowWebsiteTemporarily("twitter.com", minutes: 10)
        assertTest(store.isWebsiteTemporarilyAllowed("twitter.com"), "Twitter is now temporarily allowed for 10 min")
        assertTest(store.isWebsiteTemporarilyAllowed("mobile.twitter.com"), "Subdomain of Twitter is also temporarily allowed")

        store.clearTemporaryAllowances()
        assertTest(!store.isWebsiteTemporarilyAllowed("twitter.com"), "Temporary allowances successfully cleared")

        // -------------------------------------------------------------
        // Test 11: Cinema Mode Configuration & Messages
        // -------------------------------------------------------------
        print("\n--- Test 11: Cinema Mode Configuration & Messages ---")
        assertTest(!store.cinemaModeMessage.isEmpty, "Cinema mode has a default message")

        var cinemaCallbackFired = false
        store.onCinemaModeChanged = {
            cinemaCallbackFired = true
        }

        store.isCinemaModeEnabled = true
        assertTest(store.isCinemaModeEnabled == true, "Cinema mode successfully enabled")
        assertTest(cinemaCallbackFired == true, "Cinema mode callback fired on toggle")

        let customMsg = "Focus on the movie! Do not tab out."
        store.cinemaModeMessage = customMsg
        assertTest(store.cinemaModeMessage == customMsg, "Cinema mode message updated and saved")

        store.isCinemaModeEnabled = false
        assertTest(store.isCinemaModeEnabled == false, "Cinema mode successfully disabled")

        print("\n🎉 ALL TESTS INCLUDING CINEMA MODE PASSED SUCCESSFULLY! 🎉\n")
    }
}
