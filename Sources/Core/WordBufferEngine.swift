import Foundation

/// Maintains a synchronized character buffer of recent keystrokes and tests against the blocklist,
/// supporting standard typing, obfuscated variations, and custom pop-up notes.
public final class WordBufferEngine {
    public static let shared = WordBufferEngine()

    private let lock = NSLock()
    private var rawBuffer: [Character] = []
    private let maxBufferLength = 120

    private init() {}

    /// Appends typed characters, inspects for blocked words or variations, and returns deletion details and note if matched.
    public func processInput(_ text: String) -> (matchedWord: String, deleteCount: Int, note: String?)? {
        lock.lock()
        defer { lock.unlock() }

        guard !text.isEmpty else { return nil }

        for char in text {
            rawBuffer.append(char)
        }

        // Prevent memory growth by keeping a sliding window
        if rawBuffer.count > maxBufferLength {
            let overflow = rawBuffer.count - maxBufferLength
            rawBuffer.removeFirst(overflow)
        }

        // Test if the buffer contains or ends with any blocked word or variation
        if let match = WordStore.shared.matchBlocked(in: rawBuffer) {
            // Reset buffer after detection so subsequent keystrokes start fresh
            rawBuffer.removeAll(keepingCapacity: true)
            return (matchedWord: match.matchedWord, deleteCount: match.deleteCount, note: match.note)
        }

        return nil
    }

    /// Handles user pressing Backspace / Delete
    public func handleBackspace() {
        lock.lock()
        defer { lock.unlock() }

        if !rawBuffer.isEmpty {
            rawBuffer.removeLast()
        }
    }

    /// Clears the active buffer (e.g. on Enter, Escape, mouse click, cursor navigation)
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        rawBuffer.removeAll(keepingCapacity: true)
    }

    /// Returns current buffer snapshot for debugging / status display
    public var currentBuffer: String {
        lock.lock()
        defer { lock.unlock() }
        return String(rawBuffer)
    }
}
