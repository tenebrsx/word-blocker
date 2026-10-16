import Foundation

/// Represents a character with its corresponding original start and end indices in the raw keystroke buffer.
public struct TracedChar: Equatable {
    public let char: Character
    public let rawStartIndex: Int
    public let rawEndIndex: Int

    public init(char: Character, rawStartIndex: Int, rawEndIndex: Int) {
        self.char = char
        self.rawStartIndex = rawStartIndex
        self.rawEndIndex = rawEndIndex
    }
}

/// Represents a normalized token (word) mapped directly to its physical character span in the raw buffer.
public struct TracedToken: Equatable {
    public let text: String
    public let rawStartIndex: Int
    public let rawEndIndex: Int

    public var physicalLength: Int {
        return (rawEndIndex - rawStartIndex) + 1
    }
}

/// Transforms raw keystrokes by resolving leetspeak, homoglyphs, repeated character elongations,
/// and noise characters, while preserving exact raw physical index spans.
public final class ObfuscationNormalizer {
    public static let shared = ObfuscationNormalizer()

    // Canonical leetspeak substitution table (maps lookalikes to base lowercase Latin letters)
    private let leetMap: [Character: Character] = [
        "0": "o",
        "1": "i", "!": "i", "|": "i", "l": "l",
        "3": "e", "€": "e",
        "4": "a", "@": "a", "^": "a",
        "5": "s", "$": "s",
        "7": "t", "+": "t",
        "8": "b",
        "9": "g"
    ]

    // Cyrillic & Greek homoglyphs commonly used to evade Latin filters
    private let homoglyphMap: [Character: Character] = [
        "а": "a", "А": "a", // Cyrillic
        "в": "b", "В": "b",
        "е": "e", "Е": "e",
        "к": "k", "К": "k",
        "м": "m", "М": "m",
        "н": "h", "Н": "h",
        "о": "o", "О": "o",
        "р": "p", "Р": "p",
        "с": "c", "С": "c",
        "т": "t", "Т": "t",
        "у": "y", "У": "y",
        "х": "x", "Х": "x",
        "α": "a", "ο": "o", "ρ": "p" // Greek
    ]

    private init() {}

    /// Canonicalizes a single character (lowercasing, leetspeak, homoglyphs, diacritics).
    public func canonicalizeChar(_ c: Character) -> Character {
        let lower = Character(c.lowercased())

        if let mapped = leetMap[lower] {
            return mapped
        }
        if let mapped = homoglyphMap[lower] {
            return mapped
        }

        // Strip diacritics / accents (e.g. â -> a, é -> e)
        let str = String(lower)
        let transformed = str.folding(options: .diacriticInsensitive, locale: .current)
        return transformed.first ?? lower
    }

    /// Takes raw buffer characters and produces normalized token candidates with origin spans.
    public func normalizeBuffer(_ rawChars: [Character]) -> [TracedToken] {
        guard !rawChars.isEmpty else { return [] }

        // Step 1: Trace and map each character with its raw buffer index
        var mappedChars: [TracedChar] = []
        for (idx, char) in rawChars.enumerated() {
            let canon = canonicalizeChar(char)
            mappedChars.append(TracedChar(char: canon, rawStartIndex: idx, rawEndIndex: idx))
        }

        // Step 2: Separate into tokens by word boundaries (whitespace/delimiters)
        var tokens: [TracedToken] = []
        var currentTokenChars: [TracedChar] = []

        for item in mappedChars {
            if item.char.isWhitespace {
                if !currentTokenChars.isEmpty {
                    tokens.append(contentsOf: createTokenCandidates(from: currentTokenChars))
                    currentTokenChars.removeAll(keepingCapacity: true)
                }
            } else {
                currentTokenChars.append(item)
            }
        }

        if !currentTokenChars.isEmpty {
            tokens.append(contentsOf: createTokenCandidates(from: currentTokenChars))
        }

        return tokens
    }

    /// Generates normalized variants for a sequence of characters within a token:
    /// 1. Standard canonicalized form (with noise stripped like '.', '_', '-')
    /// 2. Run-length folded form (consecutive identical characters collapsed to 1)
    /// 3. Run-length folded form (consecutive identical characters collapsed to at most 2)
    private func createTokenCandidates(from chars: [TracedChar]) -> [TracedToken] {
        guard let first = chars.first, let last = chars.last else { return [] }

        let rawStart = first.rawStartIndex
        let rawEnd = last.rawEndIndex

        // Filter out punctuation noise inside a word (e.g. "b.a.d" -> "bad")
        let nonNoiseChars = chars.filter { $0.char.isLetter || $0.char.isNumber }
        guard !nonNoiseChars.isEmpty else { return [] }

        let nonNoiseText = String(nonNoiseChars.map { $0.char })
        var candidates: [TracedToken] = []

        // Candidate 1: Canonicalized noise-stripped form
        candidates.append(TracedToken(text: nonNoiseText, rawStartIndex: rawStart, rawEndIndex: rawEnd))

        // Candidate 2: Run-length folded to at most 1 (e.g. "b444aad" -> "bad", "w0000000rrrrrd" -> "word")
        var folded1: [Character] = []
        for ch in nonNoiseChars {
            if folded1.isEmpty || folded1.last != ch.char {
                folded1.append(ch.char)
            }
        }
        let folded1Text = String(folded1)
        if folded1Text != nonNoiseText {
            candidates.append(TracedToken(text: folded1Text, rawStartIndex: rawStart, rawEndIndex: rawEnd))
        }

        // Candidate 3: Run-length folded to at most 2 (preserves natural doubles like "cool", "look", "pass")
        var folded2: [Character] = []
        var repeatCount = 0
        for ch in nonNoiseChars {
            if folded2.isEmpty || folded2.last != ch.char {
                folded2.append(ch.char)
                repeatCount = 1
            } else if repeatCount < 2 {
                folded2.append(ch.char)
                repeatCount += 1
            }
        }
        let folded2Text = String(folded2)
        if folded2Text != nonNoiseText && folded2Text != folded1Text {
            candidates.append(TracedToken(text: folded2Text, rawStartIndex: rawStart, rawEndIndex: rawEnd))
        }

        return candidates
    }

    /// Normalizes a target blocked word (stripping diacritics, leet, and folding)
    public func canonicalizeTargetWord(_ word: String) -> (canonical: String, collapsed: String) {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let chars = clean.map { canonicalizeChar($0) }
        let canon = String(chars)

        // Collapsed to 1
        var folded: [Character] = []
        for c in chars {
            if folded.isEmpty || folded.last != c {
                folded.append(c)
            }
        }
        return (canonical: canon, collapsed: String(folded))
    }
}
