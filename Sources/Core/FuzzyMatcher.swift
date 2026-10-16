import Foundation

/// Fast string matching engine supporting exact canonical matches, collapsed matches,
/// and Damerau-Levenshtein edit distance for typo and transposition resilience.
public final class FuzzyMatcher {
    public static let shared = FuzzyMatcher()

    private init() {}

    /// Computes the Damerau-Levenshtein distance between two strings
    /// (insertions, deletions, substitutions, and adjacent transpositions).
    public func damerauLevenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        // Distance matrix (m+1) x (n+1)
        var d = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { d[i][0] = i }
        for j in 0...n { d[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = (a[i - 1] == b[j - 1]) ? 0 : 1

                var minVal = min(
                    d[i - 1][j] + 1,       // deletion
                    d[i][j - 1] + 1,       // insertion
                    d[i - 1][j - 1] + cost // substitution
                )

                // Transposition
                if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                    minVal = min(minVal, d[i - 2][j - 2] + cost)
                }

                d[i][j] = minVal
            }
        }

        return d[m][n]
    }

    /// Evaluates candidate tokens against a target word.
    /// Returns true if any candidate matches the target word under exact, collapsed, or fuzzy rules.
    public func matches(candidates: [TracedToken], targetWord: String, allowFuzzyEditDistance: Bool = true) -> TracedToken? {
        let (targetCanon, targetCollapsed) = ObfuscationNormalizer.shared.canonicalizeTargetWord(targetWord)

        for candidate in candidates {
            let candidateText = candidate.text

            // 1. Exact Canonical Match (e.g. "bad" == "bad", or leet "b4d" -> "bad")
            if candidateText == targetCanon {
                return candidate
            }

            // 2. Collapsed Match (e.g. "b444aad" -> collapsed "bad" == target "bad")
            if candidateText == targetCollapsed {
                return candidate
            }

            // 3. Damerau-Levenshtein Fuzzy Match (for typos, transpositions)
            if allowFuzzyEditDistance {
                let maxAllowedDistance = allowedDistanceForLength(targetCanon.count)
                if maxAllowedDistance > 0 {
                    let dist = damerauLevenshteinDistance(candidateText, targetCanon)
                    if dist <= maxAllowedDistance {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    /// Determines the maximum allowed edit distance based on word length to minimize false positives.
    public func allowedDistanceForLength(_ length: Int) -> Int {
        if length <= 4 {
            return 0 // For short words (e.g. "bad"), distance must be 0 to avoid false positives
        } else if length <= 7 {
            return 1 // Medium words (e.g. "secret", "blocked") allow 1 edit/transposition
        } else {
            return 2 // Long words (e.g. "forbidden", "password") allow 2 edits
        }
    }
}
