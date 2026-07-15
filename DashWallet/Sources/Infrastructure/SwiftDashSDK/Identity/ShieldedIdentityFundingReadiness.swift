//
//  ShieldedIdentityFundingReadiness.swift
//  DashWallet
//
//  Single source of truth for "can this wallet fund a DashPay identity
//  from its shielded balance right now?". Read by the Join DashPay
//  banner, the get-ready interstitial, and the Create Username funding
//  picker so all three surfaces agree on the same answer.
//
//  Three gates, priority-ordered (the returned state is the FIRST
//  unmet gate):
//
//  1. Funding — unspent shielded notes must cover the Type-20 exit
//     denomination. `IdentityCreateFromShieldedPool` spends a fixed
//     denomination from the consensus set {0.1, 0.3, 0.5, 1.0} DASH
//     (`shielded_identity_create_denominations`, rs-platform-version);
//     the metered fee is taken FROM the denomination and any excess
//     spent value returns to the pool as change, so the gate is simply
//     `unspent >= denomination`.
//
//  2. Maturity — an app-side privacy policy, not a protocol rule: the
//     notes funding the identity must have rested in the pool for
//     `maturityWindow` so the shielded deposit and the (public)
//     identity creation are separated in time. Computed from
//     `PersistentShieldedNote.createdAt` (first-observed time). For
//     restored wallets old notes are re-observed as new, which makes
//     the gate conservative (over-waits) — the safe direction for a
//     privacy timer.
//
//  3. Pool size — client-side mirror of the consensus rule
//     `minimum_pool_notes_for_outgoing = 250` (rs-platform-version):
//     Drive rejects outgoing shielded transitions, including Type-20
//     identity creation, while the pool holds fewer than 250 notes.
//     The count is latched from the shielded sync's tree-progress
//     signal (`PlatformWalletManager.currentShieldedTreeTotal` — the
//     on-chain note count fetched at the start of each pass; nil
//     between passes). An UNKNOWN count does not block: the server
//     enforces the real rule and the registration coordinator surfaces
//     its `InsufficientPoolNotesError` message as the backstop.
//
//  Singleton rationale (guardrail #4): the pool-count latch must
//  outlive any one screen (the sync signal is nil between passes), and
//  the three consuming surfaces must observe one shared recomputation
//  stream — per-screen instances would each re-derive and could
//  disagree mid-countdown.
//

import Combine
import Foundation
import SwiftData
import SwiftDashSDK

@MainActor
final class ShieldedIdentityFundingReadiness: ObservableObject {

    static let shared = ShieldedIdentityFundingReadiness()

    // MARK: - Policy constants

    /// Consensus minimum pool size for outgoing shielded transitions
    /// (`minimum_pool_notes_for_outgoing`). Mirrored here only to show
    /// progress before submit; Drive enforces the real rule.
    static let minimumPoolNotes: UInt64 = 250

    /// Smallest consensus exit denomination — 0.1 DASH in credits.
    /// Funds a standard (uncontested) username registration; the new
    /// identity starts at denomination − metered fee, comfortably above
    /// the 0.03 DASH the transparent funding paths provision.
    static let standardDenominationCredits: UInt64 = 10_000_000_000

    /// Exit denomination for contested usernames — 0.3 DASH in credits,
    /// the smallest consensus denomination covering
    /// `DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME` (0.25 DASH).
    static let contestedDenominationCredits: UInt64 = 30_000_000_000

    /// How long shielded notes must rest before funding an identity.
    /// DEBUG builds shorten the window so the maturing → ready flip is
    /// testable in one QA session; release policy is 3 hours.
    #if DEBUG
    static let maturityWindow: TimeInterval = 10 * 60
    #else
    static let maturityWindow: TimeInterval = 3 * 60 * 60
    #endif

    static func requiredCredits(forContestedName contested: Bool) -> UInt64 {
        contested ? contestedDenominationCredits : standardDenominationCredits
    }

    // MARK: - State

    enum State: Equatable {
        /// Unspent shielded notes don't cover the denomination.
        case needsFunding(shortfallCredits: UInt64)
        /// Funded, but the covering notes are younger than
        /// `maturityWindow`. `readyAt` is when the oldest sufficient
        /// subset matures.
        case maturing(readyAt: Date)
        /// The on-chain pool is below the consensus minimum; Drive
        /// would reject the transition. Only reported when the count
        /// is actually known.
        case poolTooSmall(current: UInt64)
        case ready
    }

    struct Snapshot: Equatable {
        let state: State
        let requiredCredits: UInt64
        /// Unspent credits old enough to spend under the maturity policy.
        let matureCredits: UInt64
        /// All unspent credits (mature + still-maturing).
        let unspentCredits: UInt64
        /// Last known on-chain pool note count; nil until a shielded
        /// sync pass has reported one.
        let poolNoteCount: UInt64?
    }

    /// Readiness for a standard (uncontested) registration — the value
    /// the banner and interstitial display. Contested requirements are
    /// evaluated on demand via `evaluate(requiredCredits:)`.
    /// nil while the SDK host has no hydrated wallet.
    @Published private(set) var standardSnapshot: Snapshot?

    /// See gate 3 above. Kept latched (not zeroed between passes).
    @Published private(set) var latchedPoolNoteCount: UInt64?

    private var managerCancellables = Set<AnyCancellable>()
    private var notificationCancellable: AnyCancellable?
    /// Re-evaluation alarm for the next maturing → ready flip.
    private var maturityFlipTask: Task<Void, Never>?

    private init() {
        notificationCancellable = NotificationCenter.default
            .publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // The runtime rebuild may have replaced the manager —
                // re-wire the sync-event subscriptions to the new one.
                self?.wireManagerIfNeeded(rewire: true)
                self?.refresh()
            }
        wireManagerIfNeeded(rewire: false)
        refresh()
    }

    // MARK: - Evaluation

    /// Compute readiness for an arbitrary requirement (contested names
    /// need the 0.3 DASH denomination). Returns nil while the SDK host
    /// has no hydrated wallet or storage.
    func evaluate(requiredCredits: UInt64, now: Date = Date()) -> Snapshot? {
        wireManagerIfNeeded(rewire: false)
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            return nil
        }
        latchPoolCount()

        let walletId = wallet.walletId
        let descriptor = FetchDescriptor<PersistentShieldedNote>(
            predicate: PersistentShieldedNote.unspentPredicate(walletId: walletId),
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        let notes = (try? modelContainer.mainContext.fetch(descriptor)) ?? []

        let unspent = notes.reduce(UInt64(0)) { $0 + $1.value }
        let maturityCutoff = now.addingTimeInterval(-Self.maturityWindow)
        let mature = notes
            .filter { $0.createdAt <= maturityCutoff }
            .reduce(UInt64(0)) { $0 + $1.value }

        let state: State
        if unspent < requiredCredits {
            state = .needsFunding(shortfallCredits: requiredCredits - unspent)
        } else if mature < requiredCredits {
            // Oldest-first accumulation: the covering subset's youngest
            // note decides when the requirement is met.
            var accumulated: UInt64 = 0
            var readyAt = now.addingTimeInterval(Self.maturityWindow)
            for note in notes {
                accumulated += note.value
                if accumulated >= requiredCredits {
                    readyAt = note.createdAt.addingTimeInterval(Self.maturityWindow)
                    break
                }
            }
            state = .maturing(readyAt: readyAt)
        } else if let poolCount = latchedPoolNoteCount, poolCount < Self.minimumPoolNotes {
            state = .poolTooSmall(current: poolCount)
        } else {
            state = .ready
        }

        return Snapshot(
            state: state,
            requiredCredits: requiredCredits,
            matureCredits: mature,
            unspentCredits: unspent,
            poolNoteCount: latchedPoolNoteCount)
    }

    /// Recompute `standardSnapshot` and (re)arm the maturity alarm.
    func refresh() {
        let snapshot = evaluate(requiredCredits: Self.standardDenominationCredits)
        if snapshot != standardSnapshot {
            standardSnapshot = snapshot
        }
        armMaturityFlip(for: snapshot)
    }

    /// Kick a shielded sync pass so the pool count (and any new notes)
    /// arrive promptly — used by screens that display readiness the
    /// moment they appear. No-ops into the SDK's own single-flight
    /// guard when a pass is already running.
    func requestFreshSignals() {
        guard let manager = SwiftDashSDKHost.shared.manager else { return }
        Task {
            try? await manager.syncShieldedNow()
        }
    }

    // MARK: - Wiring

    /// Subscribe to the live `PlatformWalletManager`'s shielded-sync
    /// publishers. The manager can be created after this service (cold
    /// start) and replaced by a runtime rebuild (wallet/network switch),
    /// so wiring is idempotent-with-rewire rather than init-once.
    private func wireManagerIfNeeded(rewire: Bool) {
        if rewire {
            managerCancellables.removeAll()
        }
        guard managerCancellables.isEmpty,
              let manager = SwiftDashSDKHost.shared.manager else { return }

        manager.$lastShieldedSyncEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &managerCancellables)

        manager.$currentShieldedTreeTotal
            .receive(on: RunLoop.main)
            .sink { [weak self] total in
                guard let self else { return }
                if let total, total > 0, total != self.latchedPoolNoteCount {
                    self.latchedPoolNoteCount = total
                    self.refresh()
                }
            }
            .store(in: &managerCancellables)
    }

    /// Pull the current tree-total directly (the publisher only fires
    /// on change, and a pass may already have reported before we wired).
    private func latchPoolCount() {
        if let total = SwiftDashSDKHost.shared.manager?.currentShieldedTreeTotal,
           total > 0, total != latchedPoolNoteCount {
            latchedPoolNoteCount = total
        }
    }

    /// Schedule a one-shot re-evaluation at `readyAt` so `.maturing`
    /// flips to `.ready` without the user leaving and re-entering the
    /// screen. Cancelled/re-armed on every refresh.
    private func armMaturityFlip(for snapshot: Snapshot?) {
        maturityFlipTask?.cancel()
        maturityFlipTask = nil
        guard case .maturing(let readyAt) = snapshot?.state else { return }
        let delay = readyAt.timeIntervalSinceNow
        guard delay > 0 else { return }
        maturityFlipTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((delay + 1) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
