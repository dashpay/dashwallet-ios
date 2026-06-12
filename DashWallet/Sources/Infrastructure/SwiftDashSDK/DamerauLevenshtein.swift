//
//  DamerauLevenshtein.swift
//  DashWallet
//
//  Edit-distance backup for the phrase-repair engine — replaces the
//  MDCDamerauLevenshteinDistance pod DashSync used
//  (`mdc_damerauLevenshteinDistanceTo:`). When no candidate word's first
//  BIP-44 address has on-chain history, the engine falls back to suggesting
//  wordlist words within distance < 3 of the user's typo.
//
//  This is the optimal-string-alignment (OSA) variant: insert, delete,
//  substitute, and adjacent transposition, with each substring edited at
//  most once. OSA and full Damerau-Levenshtein only diverge on contrived
//  multi-edit transposition chains, which is immaterial at a < 3 threshold
//  on ≤ 8-character BIP-39 words.
//

import Foundation

enum DamerauLevenshtein {

    /// OSA edit distance between `a` and `b` (Character-based, so grapheme
    /// clusters in non-Latin wordlists count as single symbols).
    static func distance(_ a: String, _ b: String) -> Int {
        let s = Array(a)
        let t = Array(b)

        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }

        // Rolling three-row DP: prevPrev (i-2), prev (i-1), current (i).
        var prevPrev = [Int](repeating: 0, count: t.count + 1)
        var prev = Array(0...t.count)
        var current = [Int](repeating: 0, count: t.count + 1)

        for i in 1...s.count {
            current[0] = i
            for j in 1...t.count {
                let substitutionCost = (s[i - 1] == t[j - 1]) ? 0 : 1
                var best = Swift.min(
                    prev[j] + 1, // deletion
                    current[j - 1] + 1, // insertion
                    prev[j - 1] + substitutionCost // substitution
                )
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    best = Swift.min(best, prevPrev[j - 2] + 1) // transposition
                }
                current[j] = best
            }
            (prevPrev, prev, current) = (prev, current, prevPrev)
        }

        // After the final swap the answer lives in `prev`.
        return prev[t.count]
    }
}
