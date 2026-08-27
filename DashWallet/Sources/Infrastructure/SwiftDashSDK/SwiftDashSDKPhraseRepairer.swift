//
//  SwiftDashSDKPhraseRepairer.swift
//  DashWallet
//
//  Pure-Swift port of DashSync's BIP-39 phrase-repair engine
//  (`DSBIP39Mnemonic findPotentialWordsOfMnemonicForPassphrase:…` /
//  `findLastPotentialWordsOfMnemonicForPassphrase:…`,
//  DSBIP39Mnemonic.m:436–589), composed from SwiftDashSDK primitives:
//  `Mnemonic.wordList` (candidate enumeration), `Mnemonic.validate`
//  (BIP-39 checksum), `Mnemonic.toSeed` + `key_wallet_derive_address_from_seed`
//  (candidate → first BIP-44 mainnet address), plus `InsightClient`
//  (on-chain address-existence) and `DamerauLevenshtein` (typo backup).
//
//  Algorithm (single missing/incorrect word of a 12-word phrase):
//  enumerate the 2048 words of the best-fitting language, keep the ~128
//  whose insertion yields a checksum-valid phrase, derive each candidate
//  wallet's first address (m/44'/5'/0'/0/0, account 0, MAINNET hardcoded
//  — parity with DashSync), then ask Insight which address actually has
//  transaction history. A confirmed word returns confidence 0 (Max);
//  otherwise, for the incorrect-word entry point only, fall back to
//  Damerau-Levenshtein distance < 3 suggestions (confidence = distance,
//  lower is better). Two missing words recurse per outer candidate.
//
//  Sanctioned deviations from DashSync (see DASHSYNC_MIGRATION.md):
//   1. Word counts ∉ {10, 11} (after replacement removal) complete with {}
//      instead of silently never calling completion (stuck-UI quirk).
//   2. Best-fit language spans all 10 SDK languages with a deterministic
//      rawValue tie-break (DashSync: 7 languages, dict-order tie).
//   3. `Mnemonic.validate` auto-detects language — a superset of
//      DashSync's per-language decode; extra candidates are Insight-gated.
//   4. Two-missing concurrency is 4 (DashSync: CPU−1) — gentler on Insight.
//   5. Distance backup ranks ALL checksum-valid words, not only those whose
//      seed derivation succeeded. Identical for English; for non-English
//      phrases the current key-wallet FFI (`mnemonic_to_seed`) is
//      English-hardcoded, so derivation fails and on-chain confirmation is
//      unavailable — the distance backup still works there.
//   6. A stopped scan still completes (with whatever was accumulated):
//      keeps the stop-flag box's lifetime airtight; the VC has already
//      dismissed itself on cancel, so the extra completion is invisible.
//
//  Stop-flag lifetime: DashSync handed the VC a pointer to a STACK bool
//  that the VC writes via a deferred main-queue block — a latent
//  use-after-return. Here the pointer is heap memory owned by
//  `CancellationBox`, retained by the completion closure; progress ticks
//  run on the main queue, and the completion closure is enqueued after the
//  last tick, so FIFO ordering guarantees every deferred VC write lands
//  before the box can be released.
//
//  Never logs phrase material — counts and durations only.
//

import Foundation
import OSLog
import SwiftDashSDK

// MARK: - Obj-C facade

@objc(DWSwiftDashSDKPhraseRepairer)
final class SwiftDashSDKPhraseRepairer: NSObject {

    /// Replaces `DSBIP39RecoveryWordConfidence_Max` (== 0; lower is
    /// better — distance-backup suggestions carry their edit distance).
    @objc static let maxConfidence: UInt = 0

    /// Port of `findPotentialWordsOfMnemonicForPassphrase:replacementString:
    /// progressUpdate:completion:` — suggests replacements for the word(s)
    /// equal to `replacementString` in a 12-word phrase. Blocks are invoked
    /// on the main queue; write `*stop = YES` inside `progressUpdate` to
    /// cancel (observed on the next tick, like DashSync).
    @objc(findPotentialWordsOfMnemonicForPassphrase:replacementString:progressUpdate:completion:)
    static func findPotentialWords(passphrase: String,
                                   replacementString: String,
                                   progressUpdate: @escaping (Float, UnsafeMutablePointer<ObjCBool>) -> Void,
                                   completion: @escaping ([String: NSNumber]) -> Void) {
        run(progressUpdate: progressUpdate, completion: completion) { dependencies, progress in
            await PhraseRepairEngine.findPotentialWords(passphrase: passphrase,
                                                        replacement: replacementString,
                                                        language: nil,
                                                        useDistanceAsBackup: true,
                                                        dependencies: dependencies,
                                                        progress: progress)
        }
    }

    /// Port of `findLastPotentialWordsOfMnemonicForPassphrase:progressUpdate:
    /// completion:` — finds the 1–2 missing trailing words of a 10/11-word
    /// input. On-chain confirmation only (no distance backup), like DashSync.
    @objc(findLastPotentialWordsOfMnemonicForPassphrase:progressUpdate:completion:)
    static func findLastPotentialWords(passphrase: String,
                                       progressUpdate: @escaping (Float, UnsafeMutablePointer<ObjCBool>) -> Void,
                                       completion: @escaping ([String: NSNumber]) -> Void) {
        run(progressUpdate: progressUpdate, completion: completion) { dependencies, progress in
            await PhraseRepairEngine.findLastPotentialWords(passphrase: passphrase,
                                                            dependencies: dependencies,
                                                            progress: progress)
        }
    }

    // MARK: Plumbing

    private static let logger = Logger(subsystem: "org.dashfoundation.dashwallet",
                                       category: "swift-sdk-migration.phrase-repair")

    /// Heap home for the `BOOL *stop` out-pointer handed to the VC's
    /// progress block. Deallocated only when the last closure holding the
    /// box is released — after completion has run on the main queue.
    private final class CancellationBox: @unchecked Sendable {
        let pointer: UnsafeMutablePointer<ObjCBool>

        init() {
            pointer = .allocate(capacity: 1)
            pointer.initialize(to: false)
        }

        deinit {
            pointer.deinitialize(count: 1)
            pointer.deallocate()
        }
    }

    private static func run(progressUpdate: @escaping (Float, UnsafeMutablePointer<ObjCBool>) -> Void,
                            completion: @escaping ([String: NSNumber]) -> Void,
                            work: @escaping (PhraseRepairEngine.Dependencies,
                                             @escaping PhraseRepairEngine.ProgressTick) async -> [String: UInt]) {
        let box = CancellationBox()

        // Each tick: deliver progress to the VC on main, then report back
        // whether a (previous tick's deferred) cancel write has landed.
        let progress: PhraseRepairEngine.ProgressTick = { value in
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    progressUpdate(value, box.pointer)
                    continuation.resume(returning: box.pointer.pointee.boolValue)
                }
            }
        }

        Task.detached(priority: .utility) {
            let started = Date()
            let result = await work(.default, progress)
            let elapsed = Date().timeIntervalSince(started)
            logger.info("🔧 PHRASE-REPAIR :: finished with \(result.count) suggestion(s) in \(String(format: "%.1f", elapsed))s")
            DispatchQueue.main.async {
                completion(result.mapValues { NSNumber(value: $0) })
                // Strong capture keeps the stop pointer alive past every
                // deferred VC write enqueued by earlier progress ticks.
                _ = box
            }
        }
    }
}

// MARK: - Engine

enum PhraseRepairEngine {

    /// Returns `true` to stop the scan (cancellation), like DashSync's
    /// `bool *stop` out-parameter.
    typealias ProgressTick = (Float) async -> Bool

    /// Seam for unit tests; `.default` wires the real Insight client and
    /// the SwiftDashSDK/FFI derivation chain.
    struct Dependencies {
        var insight: InsightAddressQuerying
        /// Checksum-valid candidate phrase → first BIP-44 external address
        /// (account 0, mainnet). `nil` when derivation fails — today that
        /// means a non-English phrase (the FFI's `mnemonic_to_seed` is
        /// English-hardcoded); such candidates skip on-chain confirmation.
        var deriveFirstAddress: (String) -> String?

        static let `default` = Dependencies(insight: InsightClient(),
                                            deriveFirstAddress: PhraseRepairEngine.defaultDeriveFirstAddress)
    }

    /// DashSync iterated word-by-word; reporting every 10 keeps the same
    /// granularity (`DSBIP39Mnemonic.m:531`).
    private static let progressStride = 10

    /// Two-missing-words fan-out width (deviation 4 — DashSync used CPU−1;
    /// each probe can issue an Insight POST, so stay polite).
    private static let twoMissingConcurrency = 4

    /// Distance-backup cutoff, exclusive (`DSBIP39Mnemonic.m:572`).
    private static let maxBackupDistance = 3

    // Per-language wordlists, fetched once from the SDK. Arrays preserve
    // BIP-39 order for enumeration; sets serve membership counting.
    // Deliberate small duplication of the private caches in
    // DWRecoverModel+Mnemonic.swift (different lifetime/owner).
    private static let wordLists: [MnemonicLanguage: [String]] = {
        var lists: [MnemonicLanguage: [String]] = [:]
        for language in MnemonicLanguage.allCases {
            lists[language] = Mnemonic.wordList(language: language)
        }
        return lists
    }()

    private static let wordSets: [MnemonicLanguage: Set<String>] =
        wordLists.mapValues(Set.init)

    // MARK: Entry points

    /// Port of `findPotentialWordsOfMnemonicForPassphrase:replacementString:
    /// inLanguage:useDistanceAsBackup:…` (DSBIP39Mnemonic.m:461).
    static func findPotentialWords(passphrase: String,
                                   replacement: String,
                                   language: MnemonicLanguage?,
                                   useDistanceAsBackup: Bool,
                                   dependencies: Dependencies,
                                   progress: @escaping ProgressTick) async -> [String: UInt] {
        let normalized = Mnemonic.normalizePhrase(passphrase)
        let allWords = normalized.split(separator: " ").map(String.init)

        // Strip every occurrence of the replacement marker, remembering
        // where they sat (DashSync iterated back-to-front; order-equivalent).
        var remaining: [String] = []
        var replacementIndexes: [Int] = []
        for (index, word) in allWords.enumerated() {
            if word == replacement {
                replacementIndexes.append(index)
            } else {
                remaining.append(word)
            }
        }

        guard let firstIndex = replacementIndexes.first,
              let lastIndex = replacementIndexes.last else {
            return [:] // no marker present — nothing to repair
        }

        let checkLanguage = language ?? bestFittingLanguage(for: remaining)

        switch remaining.count {
        case 11:
            return await findSingleMissingWord(remaining: remaining,
                                               insertIndex: firstIndex,
                                               language: checkLanguage,
                                               replacement: replacement,
                                               useDistanceAsBackup: useDistanceAsBackup,
                                               dependencies: dependencies,
                                               progress: progress)
        case 10:
            return await findTwoMissingWords(remaining: remaining,
                                             firstIndex: firstIndex,
                                             lastIndex: lastIndex,
                                             language: checkLanguage,
                                             replacement: replacement,
                                             dependencies: dependencies,
                                             progress: progress)
        default:
            // Deviation 1: DashSync silently never completed here.
            return [:]
        }
    }

    /// Port of `findLastPotentialWordsOfMnemonicForPassphrase:` —
    /// appends one or two "x" markers to the RAW input (DashSync did the
    /// same; `normalizePhrase` re-runs inside the delegate call).
    static func findLastPotentialWords(passphrase: String,
                                       dependencies: Dependencies,
                                       progress: @escaping ProgressTick) async -> [String: UInt] {
        let normalized = Mnemonic.normalizePhrase(passphrase)
        let wordCount = normalized.split(separator: " ").count
        let padded = passphrase + (wordCount == 10 ? " x x" : " x")
        return await findPotentialWords(passphrase: padded,
                                        replacement: "x",
                                        language: nil,
                                        useDistanceAsBackup: false,
                                        dependencies: dependencies,
                                        progress: progress)
    }

    // MARK: Language fit

    /// Port of `bestFittingLanguageForWords:` (DSBIP39Mnemonic.m:142) over
    /// all 10 SDK languages with a deterministic rawValue tie-break
    /// (deviation 2). Empty/no-match input falls back to English.
    static func bestFittingLanguage(for words: [String]) -> MnemonicLanguage {
        var counts: [MnemonicLanguage: Int] = [:]
        for word in words {
            for language in MnemonicLanguage.allCases where wordSets[language]?.contains(word) == true {
                counts[language, default: 0] += 1
            }
        }
        let best = counts.max { lhs, rhs in
            (lhs.value, rhs.key.rawValue) < (rhs.value, lhs.key.rawValue)
        }
        return best?.key ?? .english
    }

    // MARK: Single missing word (count == 11)

    /// Scan result: every checksum-valid candidate word, plus the first
    /// BIP-44 address of those whose seed derivation succeeded.
    struct CandidateScan {
        var checksumValidWords: [String] = []
        var addressToWord: [String: String] = [:]
        var stopped = false
    }

    static func scanCandidates(remaining: [String],
                               insertIndex: Int,
                               language: MnemonicLanguage,
                               dependencies: Dependencies,
                               progress: @escaping ProgressTick) async -> CandidateScan {
        var scan = CandidateScan()
        guard let list = wordLists[language], !list.isEmpty else { return scan }

        for (index, word) in list.enumerated() {
            if index % progressStride == progressStride - 1 {
                if await progress(Float(index) / Float(list.count)) {
                    scan.stopped = true
                    return scan
                }
            }

            var candidate = remaining
            candidate.insert(word, at: insertIndex)
            let phrase = candidate.joined(separator: " ")
            guard Mnemonic.validate(phrase) else { continue }

            scan.checksumValidWords.append(word)
            if let address = dependencies.deriveFirstAddress(phrase) {
                scan.addressToWord[address] = word
            }
        }
        return scan
    }

    static func findSingleMissingWord(remaining: [String],
                                      insertIndex: Int,
                                      language: MnemonicLanguage,
                                      replacement: String,
                                      useDistanceAsBackup: Bool,
                                      dependencies: Dependencies,
                                      progress: @escaping ProgressTick) async -> [String: UInt] {
        let scan = await scanCandidates(remaining: remaining,
                                        insertIndex: insertIndex,
                                        language: language,
                                        dependencies: dependencies,
                                        progress: progress)
        if scan.stopped || scan.checksumValidWords.isEmpty {
            return [:]
        }

        // On-chain confirmation; a network failure means "no matches"
        // (graceful offline degradation, parity with DashSync).
        let existing = (try? await dependencies.insight
            .findExistingAddresses(Array(scan.addressToWord.keys))) ?? []
        var confirmed: [String: UInt] = [:]
        for address in existing {
            if let word = scan.addressToWord[address] {
                confirmed[word] = 0
            }
        }
        if !confirmed.isEmpty {
            return confirmed
        }

        guard useDistanceAsBackup else { return [:] }

        // Deviation 5: rank every checksum-valid word (not only the
        // derivable ones) by edit distance to the user's typo.
        var suggestions: [String: UInt] = [:]
        for word in scan.checksumValidWords {
            let distance = DamerauLevenshtein.distance(replacement, word)
            if distance < maxBackupDistance {
                suggestions[word] = UInt(distance)
            }
        }
        return suggestions
    }

    // MARK: Two missing words (count == 10)

    static func findTwoMissingWords(remaining: [String],
                                    firstIndex: Int,
                                    lastIndex: Int,
                                    language: MnemonicLanguage,
                                    replacement: String,
                                    dependencies: Dependencies,
                                    progress: @escaping ProgressTick) async -> [String: UInt] {
        guard let list = wordLists[language], !list.isEmpty else { return [:] }

        // For each outer candidate W, probe the inner single-missing path on
        // "remaining + W@first + marker@last" (insertion order preserves the
        // original positions, DSBIP39Mnemonic.m:491-492). First W whose probe
        // confirms an inner word on-chain wins; both stop the scan.
        var found: [String: UInt] = [:]
        var completed = 0

        // Typealias keeps `String` in type-resolution context — inside a
        // metatype EXPRESSION like `(String, …).self`, the bare name would
        // resolve to the C enum constant `DashSDKResultDataType.String`
        // re-exported through the DashSDKFFI umbrella.
        typealias Probe = (word: String, inner: [String: UInt])

        await withTaskGroup(of: Probe.self) { group in
            var iterator = list.makeIterator()

            @discardableResult
            func enqueueNext() -> Bool {
                guard let word = iterator.next() else { return false }
                group.addTask {
                    var candidate = remaining
                    candidate.insert(word, at: firstIndex)
                    candidate.insert(replacement, at: lastIndex)
                    let phrase = candidate.joined(separator: " ")
                    // Inner probes report no UI progress; their tick just
                    // surfaces group cancellation (DashSync used a no-op
                    // progress block here too, DSBIP39Mnemonic.m:500).
                    let inner = await findPotentialWords(passphrase: phrase,
                                                         replacement: replacement,
                                                         language: language,
                                                         useDistanceAsBackup: false,
                                                         dependencies: dependencies,
                                                         progress: { _ in Task.isCancelled })
                    return (word, inner)
                }
                return true
            }

            for _ in 0..<twoMissingConcurrency {
                enqueueNext()
            }

            for await (word, inner) in group {
                completed += 1

                if let innerWord = inner.keys.first {
                    found["\(word) \(innerWord)"] = 0
                    group.cancelAll()
                    break
                }
                if await progress(Float(completed) / Float(list.count)) {
                    group.cancelAll()
                    break
                }
                enqueueNext()
            }
        }
        return found
    }

    // MARK: Address derivation (SDK + FFI)

    /// m/44'/5'/0'/0/0 — first external address of account 0, mainnet
    /// (hardcoded, parity with `[DSChain mainnet]` in DSBIP39Mnemonic.m:542).
    private static let firstAddressPath: String? =
        try? KeyDerivation.getBIP44PaymentPath(network: .mainnet,
                                               accountIndex: 0,
                                               isChange: false,
                                               addressIndex: 0)

    /// Checksum-valid phrase → BIP-39 seed (nil passphrase) → address via
    /// the `key_wallet_derive_address_from_seed` C FFI (re-exported through
    /// SwiftDashSDK; result freed with `string_free`, its documented pair).
    /// Returns nil on any failure — notably non-English phrases, which the
    /// FFI's English-hardcoded `mnemonic_to_seed` rejects.
    static func defaultDeriveFirstAddress(phrase: String) -> String? {
        guard let path = firstAddressPath,
              let seed = try? Mnemonic.toSeed(mnemonic: phrase),
              seed.count == 64 else {
            return nil
        }

        var address: String?
        seed.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            path.withCString { cPath in
                guard let cAddress = key_wallet_derive_address_from_seed(base,
                                                                         Network.mainnet.ffiValue,
                                                                         cPath) else { return }
                address = String(cString: cAddress)
                string_free(cAddress)
            }
        }
        return address
    }
}
