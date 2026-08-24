//
//  SwiftDashSDKWalletState.swift
//  DashWallet
//
//  Singleton owner of wallet-side @Published state from SwiftDashSDK.
//  Distinct from SwiftDashSDKSPVCoordinator (which owns chain sync state)
//  because wallet state and chain sync are different concerns even though
//  the FFI couples their event delivery.
//
//  Currently holds wallet balance only (function #5 of the DashSync
//  migration). Transaction history is read directly from SwiftData
//  (`PersistentTransaction` rows written by Rust's persister callback);
//  future migrations may add addresses (#1), identities (#16) etc. as
//  those land. The SPV coordinator's WalletEventsHandler forwards FFI
//  events here; this class owns the @Published Combine surface that
//  BalanceModel and friends subscribe to.
//
//  Hard invariants:
//    1. NEVER throws or crashes from public methods.
//    2. All @Published mutations are marshalled to the main queue so
//       SwiftUI/Combine consumers see updates on the right thread.
//    3. Lifecycle is independent of the SPV coordinator — this class
//       persists across coordinator stop/start cycles. The coordinator
//       seeds/clears it explicitly on import/wipe, not implicitly on
//       SPVClient lifecycle.
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

// MARK: - WalletBalance

/// Wallet balance snapshot. Defined locally rather than re-exporting
/// SwiftDashSDK's `KeyWalletTypes.Balance` because that struct references
/// an internal `FFIBalance` type, which makes it unusable as a `public`
/// property type from this module. The four fields map directly to
/// `SPVWalletEventsHandler.onBalanceUpdated`'s callback parameters.
public struct WalletBalance: Equatable, Sendable {
    public let confirmed: UInt64
    public let unconfirmed: UInt64
    public let immature: UInt64
    public let locked: UInt64

    public init(confirmed: UInt64 = 0, unconfirmed: UInt64 = 0, immature: UInt64 = 0, locked: UInt64 = 0) {
        self.confirmed = confirmed
        self.unconfirmed = unconfirmed
        self.immature = immature
        self.locked = locked
    }

    // The four fields are DISJOINT buckets. `key-wallet`'s
    // `ManagedCoreFundsAccount::update_balance` sorts every UTXO with a single
    // if / else-if chain — locked first, then immature, then
    // confirmed-or-InstantSend-locked-or-trusted, else unconfirmed — so a UTXO
    // contributes to exactly one of them.
    //
    // In particular `locked` is NOT the InstantSend-locked part of `confirmed`:
    // IS-locked funds land in `confirmed`, while `locked` is a separate
    // reserved bucket (`Utxo.is_locked`, intended for CoinJoin-style coin
    // locking). Nothing in production sets that flag today, so it reads 0 —
    // which is why the earlier arithmetic could be wrong here without anyone
    // noticing.

    /// Total user-visible balance — every bucket, matching
    /// `WalletCoreBalance::total()`.
    public var total: UInt64 { confirmed + unconfirmed + immature + locked }

    /// Spendable balance — `confirmed` only.
    ///
    /// Deliberately NOT `WalletCoreBalance::spendable()` (confirmed +
    /// unconfirmed). What gates a real send is the transaction builder's coin
    /// selection, and that is the stricter set: `Utxo::is_spendable`'s own doc
    /// tells callers that want "the spendable balance bucket or conservative
    /// coin selection" to check `is_confirmed || is_instantlocked` — which is
    /// what the `confirmed` bucket already holds (plus trusted change).
    /// Reporting untrusted 0-conf here would offer the user money that coin
    /// selection then refuses, failing the send with "Insufficient funds".
    ///
    /// `locked` is absent from the sum rather than subtracted: the buckets are
    /// disjoint, so it never overlapped `confirmed` to begin with.
    public var spendable: UInt64 { confirmed }

    /// Conservative fee headroom reserved on top of a fixed-amount send so a
    /// "Max"/affordability value stays sendable. Approximate — Core has no
    /// pre-build fee-estimate FFI yet (the send path settles the exact fee via
    /// `adjustAmountDownwards`); sized for a realistic multi-input InstantSend
    /// (10 × DashSync `TX_FEE_PER_INPUT` of 10_000 = 100_000 duffs ≈ 0.001 DASH).
    public static let sendFeeReserveDuffs: UInt64 = 100_000

    /// Fee-aware max single-tx output — the SwiftDashSDK replacement for
    /// DashSync `DSAccount.maxOutputAmount`: spendable minus a reserved fee,
    /// floored at 0. Mirrors the shielded `creditsMinusFeeReserve` pattern.
    public var maxSendable: UInt64 { spendable > Self.sendFeeReserveDuffs ? spendable - Self.sendFeeReserveDuffs : 0 }
}

// MARK: - SwiftDashSDKWalletState

@objc(DWSwiftDashSDKWalletState)
public final class SwiftDashSDKWalletState: NSObject, ObservableObject {

    public static let shared = SwiftDashSDKWalletState()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-state")

    /// Latest wallet balance from SwiftDashSDK. `nil` until either
    /// `seedInitialBalance(walletManager:walletId:)` succeeds or the
    /// first `applyBalance(_:)` call arrives. Updated on the main queue.
    @Published public private(set) var balance: WalletBalance? = nil

    /// Fee-aware "Max" / all-funds amount for a core send: spendable minus a
    /// reserve sized from the account's real UTXO count
    /// (`SwiftDashSDKTransactionSender.maxSendFeeReserveDuffs`), floored at 0.
    /// Prefer this over `WalletBalance.maxSendable` (flat 100k reserve) at every
    /// core-send "Max" call site so the sent amount tracks the real fee instead
    /// of stranding ~0.001 DASH as change.
    public func feeAwareMaxSendable() -> UInt64 {
        let spendable = balance?.spendable ?? 0
        let reserve = SwiftDashSDKTransactionSender.maxSendFeeReserveDuffs()
        return spendable > reserve ? spendable - reserve : 0
    }

    /// Total DIP-17 Platform Payment credit balance across every
    /// PlatformPayment account (`accountType == 14`) for the active
    /// wallet. Reported in credits (1e11 credits per DASH). Refreshed
    /// in lockstep with `balance` updates — every Core-balance event
    /// is treated as a hint that BLAST sync has progressed and a
    /// platform-address re-tally may be worthwhile. The tally itself
    /// runs on a background `ModelContext` and is throttled to ~1
    /// run/second (`refreshPlatformPaymentCredits`), so this property
    /// updates asynchronously shortly after a refresh is requested.
    ///
    /// Consumed by `CreateUsernameViewModel` to gate the
    /// SwiftDashSDK identity-registration flow's funding-source
    /// picker: when this is ≥ the required cost in credits, the
    /// Platform Payment funding path becomes selectable as an
    /// alternative to spending Core UTXOs.
    @Published public private(set) var platformPaymentCredits: UInt64 = 0

    /// `platformPaymentCredits` re-expressed in duffs (credits / 1000),
    /// for parity with the duff-denominated `DWDP_MIN_BALANCE_*`
    /// constants the username form validates against.
    public var platformPaymentCreditsAsDuffs: UInt64 {
        platformPaymentCredits / 1000
    }

    /// Spendable balance (in duffs) sitting in the wallet's CoinJoin
    /// account(s) — the "mixed coins" left stranded once CoinJoin support is
    /// dropped. Refreshed in lockstep with `balance` from
    /// `SwiftDashSDKCoinJoinBalanceReader`. This is the single source of
    /// truth for the post-migration "move your mixed coins" surfaces (the
    /// one-time Home popup and the conditional Settings row), both of which
    /// gate their visibility on `> dust`. Bound here — NOT to the legacy
    /// DashSync `CoinJoinService`, which is being removed.
    @Published public private(set) var coinJoinBalanceDuffs: UInt64 = 0

    // MARK: - Obj-C bridge

    /// Notification posted on the main queue whenever the published
    /// `balance` changes (including clears). Obj-C consumers that can't
    /// subscribe to the `@Published` Combine pipeline should observe
    /// this notification and read `currentTotalBalance`. Swift consumers
    /// should subscribe to `$balance` directly.
    @objc public static let balanceDidChangeNotification =
        NSNotification.Name("DWSwiftDashSDKWalletStateBalanceDidChange")

    /// Notification posted on the main queue AFTER the active wallet is
    /// switched at runtime (`SwiftDashSDKWalletRuntime.switchWallet`) — the
    /// host has bound the new wallet and its balance state has been seeded.
    /// Consumers that cache per-wallet state keyed off the host's active
    /// wallet (identity snapshot, DashPay contacts, tx list, DashPay tab
    /// gating) observe this to invalidate and reload for the new wallet.
    ///
    /// A distinct name (guardrail #5): it is NOT a re-emission of any DashSync
    /// `DS*` name nor of `balanceDidChangeNotification` — a balance change and
    /// an active-wallet change are different events, and the switch drives the
    /// balance notification separately (via `clearAllState` + the SPV re-seed).
    @objc public static let activeWalletDidChangeNotification =
        NSNotification.Name("DWSwiftDashSDKWalletStateActiveWalletDidChange")

    /// Obj-C-friendly accessor for the current total balance in satoshis.
    /// Returns 0 when no balance is published yet (e.g. before SPV first
    /// emits a balance event for an imported wallet, or after `clearBalance`).
    @objc public static var currentTotalBalance: UInt64 {
        return shared.balance?.total ?? 0
    }

    private override init() {
        super.init()
    }

    // MARK: - Apply (called from SPV event handler)

    /// Called from `SwiftDashSDKSPVCoordinator.WalletEventsHandler.onBalanceUpdated`
    /// on every relevant block / mempool tx / InstantSend confirmation.
    /// Marshals to the main queue so SwiftUI/Combine consumers receive
    /// updates on the right thread.
    public func applyBalance(_ snapshot: WalletBalance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.balance = snapshot
            // Both refresh methods are @MainActor (they read
            // MainActor-isolated `SwiftDashSDKHost.shared` state).
            // We're already on the main queue here, so
            // `assumeIsolated` is the synchronous, zero-hop way to
            // satisfy the isolation requirement. The credits refresh
            // only schedules a throttled background tally, so this
            // stays cheap even during sync-burst balance events.
            MainActor.assumeIsolated {
                self.refreshPlatformPaymentCredits()
                self.refreshCoinJoinBalance()
            }
            NotificationCenter.default.post(
                name: SwiftDashSDKWalletState.balanceDidChangeNotification,
                object: nil)
        }
    }

    /// Non-nil while a Platform-credit tally (plus its 1 s cool-down)
    /// is in flight. Requests arriving during that window flip
    /// `platformCreditsRerunRequested` instead of spawning another
    /// fetch, and replay as a single trailing tally when the window
    /// closes — so sync-burst balance events (one every ~0.5 s) cost
    /// at most one SwiftData round trip per second and the final
    /// event's state is always applied.
    @MainActor private var platformCreditsTallyTask: Task<Void, Never>?
    @MainActor private var platformCreditsRerunRequested = false

    /// Request a re-tally of the Platform Payment credit balance from
    /// SwiftData. Idempotent — safe to call from any MainActor
    /// consumer that wants a fresh snapshot (e.g.
    /// `CreateUsernameViewModel.observeBalance` on view-model init,
    /// before the next Core-balance hook fires). No-op when the wallet
    /// handle or model container isn't ready.
    ///
    /// Asynchronous: the fetch + sum runs on a background
    /// `ModelContext` and publishes into `platformPaymentCredits` on
    /// the MainActor when it lands — this method returns before the
    /// value updates, so consumers observe `$platformPaymentCredits`
    /// rather than reading it on return. Keeping the SQLite work
    /// off-main matters because the tally can block on the WAL write
    /// lock while the background sync persister is committing (every
    /// ~0.5 s during sync), which used to stall the main thread.
    ///
    /// `@MainActor` is required because the function reads
    /// `SwiftDashSDKHost.shared.wallet/.modelContainer`, both
    /// MainActor-isolated. The non-MainActor entry points on this
    /// class (`applyBalance`, `clearBalance`, `clearAllState`)
    /// dispatch through their existing `DispatchQueue.main.async` and
    /// call this via `MainActor.assumeIsolated`.
    @MainActor
    public func refreshPlatformPaymentCredits() {
        if platformCreditsTallyTask != nil {
            platformCreditsRerunRequested = true
            return
        }
        platformCreditsTallyTask = Task { @MainActor [weak self] in
            await self?.tallyPlatformPaymentCredits()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            // On cancellation `cancelPlatformCreditsTally` already
            // reset the throttle state (and may have been replaced by
            // a newer task) — don't clobber it.
            guard let self, !Task.isCancelled else { return }
            let rerun = self.platformCreditsRerunRequested
            self.platformCreditsRerunRequested = false
            self.platformCreditsTallyTask = nil
            if rerun {
                self.refreshPlatformPaymentCredits()
            }
        }
    }

    /// One Platform-credit tally: fetch the wallet's
    /// `PersistentPlatformAddress` balances on a background context,
    /// then publish the sum. Only `refreshPlatformPaymentCredits`
    /// calls this (inside `platformCreditsTallyTask`), so
    /// `Task.isCancelled` reflects a wipe/switch cancellation from
    /// `cancelPlatformCreditsTally` and gates the publish.
    @MainActor
    private func tallyPlatformPaymentCredits() async {
        guard
            let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
            let container = SwiftDashSDKHost.shared.modelContainer
        else {
            if platformPaymentCredits != 0 {
                platformPaymentCredits = 0
            }
            return
        }

        // Fetch the address rows directly — one indexed SQLite
        // statement via the denormalized `walletId` column — instead
        // of traversing `PersistentAccount.platformAddresses`, which
        // faults every row through its own `performAndWait` fetch.
        // Platform addresses exist only under PlatformPayment
        // accounts (`accountType == 14`), so the wallet-scoped
        // address set equals the account-scoped tally. The persister
        // keeps `balance` upserted by BLAST sync, so fetch + sum is
        // sufficient; no live FFI call needed.
        let total: UInt64? = await Task.detached(priority: .utility) {
            let descriptor = FetchDescriptor<PersistentPlatformAddress>(
                predicate: PersistentPlatformAddress.predicate(walletId: walletId))
            do {
                let context = ModelContext(container)
                return try context.fetch(descriptor).reduce(UInt64(0)) { $0 + $1.balance }
            } catch {
                Self.logger.warning("💰 WALLET :: platformPaymentCredits fetch failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }.value

        guard let total, !Task.isCancelled else { return }
        if platformPaymentCredits != total {
            platformPaymentCredits = total
            Self.logger.info("💰 WALLET :: platformPaymentCredits=\(total, privacy: .public) credits")
        }
    }

    /// Drop any in-flight tally so it cannot publish a stale total
    /// after the clear paths reset `platformPaymentCredits` to 0
    /// (wipe-then-recover, network switch).
    @MainActor
    private func cancelPlatformCreditsTally() {
        platformCreditsTallyTask?.cancel()
        platformCreditsTallyTask = nil
        platformCreditsRerunRequested = false
    }

    /// Re-tally the CoinJoin-account spendable balance via
    /// `SwiftDashSDKCoinJoinBalanceReader` (an in-memory read of the live
    /// per-account balances). Idempotent; safe to call from any MainActor
    /// consumer that needs a fresh snapshot — e.g. the sweep coordinator
    /// forces a refresh right after a successful sweep so the popup/Settings
    /// row self-clear without waiting for the next balance event.
    ///
    /// `@MainActor` for symmetry with `refreshPlatformPaymentCredits`; the
    /// reader detects the main thread and reads synchronously.
    @MainActor
    public func refreshCoinJoinBalance() {
        let duffs = SwiftDashSDKCoinJoinBalanceReader.coinJoinSpendableDuffs()
        if coinJoinBalanceDuffs != duffs {
            coinJoinBalanceDuffs = duffs
            Self.logger.info("💰 WALLET :: coinJoinBalanceDuffs=\(duffs, privacy: .public)")
        }
    }

    // MARK: - Seed (called from coordinator after wallet import)

    /// Called from `SwiftDashSDKSPVCoordinator.performStart` after
    /// `walletManager.importWallet` succeeds. The FFI does not emit an
    /// `onBalanceUpdated` event on `startSync` for a wallet with zero
    /// new activity, so without this seed the home screen would sit on
    /// `nil` until the first relevant tx (potentially hours into a
    /// fresh sync).
    ///
    /// `WalletManager.getWalletBalance` returns only `(confirmed, unconfirmed)`
    /// — the `immature`/`locked` fields aren't exposed by this API surface.
    /// They default to 0 in the seed and are populated properly by the
    /// first live `applyBalance(_:)` call. Mining wallets are unaffected
    /// (we don't support them).
    ///
    /// Non-fatal — if the FFI call fails, live updates eventually catch up.
    public func seedInitialBalance(walletManager: WalletManager, walletId: Data) {
        do {
            let tuple = try walletManager.getWalletBalance(walletId: walletId)
            let initial = WalletBalance(
                confirmed: tuple.confirmed,
                unconfirmed: tuple.unconfirmed,
                immature: 0,
                locked: 0)
            Self.logger.info("💰 WALLET :: initial balance seed: confirmed=\(initial.confirmed, privacy: .public) unconfirmed=\(initial.unconfirmed, privacy: .public) total=\(initial.total, privacy: .public)")
            applyBalance(initial)
        } catch {
            Self.logger.warning("💰 WALLET :: initial balance seed failed (non-fatal): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Clear (called from wallet wiper)

    /// Called from `SwiftDashSDKWalletWiper.performWipe` after the wallet
    /// state has been deleted from keychain-backed storage. Without this, the
    /// published value would keep showing the previous wallet's balance
    /// across a wipe-then-recover or wipe-then-create flow until the new
    /// wallet's first balance event arrives.
    @objc public func clearBalance() {
        DispatchQueue.main.async { [weak self] in
            Self.logger.info("💰 WALLET :: clearing balance")
            self?.balance = nil
            MainActor.assumeIsolated {
                self?.cancelPlatformCreditsTally()
            }
            self?.platformPaymentCredits = 0
            self?.coinJoinBalanceDuffs = 0
            NotificationCenter.default.post(
                name: SwiftDashSDKWalletState.balanceDidChangeNotification,
                object: nil)
        }
    }

    /// Clears wallet state synchronously on the main queue. Runtime
    /// transitions use this so a restart cannot race with stale published
    /// wallet data lingering after a network switch.
    public func clearAllState() {
        let clearBlock = { [weak self] in
            Self.logger.info("💰 WALLET :: clearing all wallet state")
            self?.balance = nil
            MainActor.assumeIsolated {
                self?.cancelPlatformCreditsTally()
            }
            self?.platformPaymentCredits = 0
            self?.coinJoinBalanceDuffs = 0
            NotificationCenter.default.post(
                name: SwiftDashSDKWalletState.balanceDidChangeNotification,
                object: nil)
        }

        if Thread.isMainThread {
            clearBlock()
        } else {
            DispatchQueue.main.sync(execute: clearBlock)
        }
    }
}
