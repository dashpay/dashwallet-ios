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

    /// Total user-visible balance: confirmed + unconfirmed + immature.
    /// `locked` is a subset of `confirmed` (the InstantSend-locked portion
    /// of the confirmed balance) so it is NOT added separately.
    public var total: UInt64 { confirmed + unconfirmed + immature }

    /// Spendable balance: confirmed minus the InstantSend-locked subset.
    public var spendable: UInt64 { confirmed > locked ? confirmed - locked : 0 }
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

    /// Total DIP-17 Platform Payment credit balance across every
    /// PlatformPayment account (`accountType == 14`) for the active
    /// wallet. Reported in credits (1e11 credits per DASH). Refreshed
    /// in lockstep with `balance` updates — every Core-balance event
    /// is treated as a hint that BLAST sync has progressed and a
    /// platform-address re-tally may be worthwhile. Reads from
    /// SwiftData synchronously on the main context; the underlying
    /// table is small (one row per HD-derived platform address) so
    /// this is cheap.
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
            // `refreshPlatformPaymentCredits` is @MainActor (it reads
            // `SwiftDashSDKHost.shared.wallet/.modelContainer`, both
            // MainActor-isolated). We're already on the main queue
            // here, so `assumeIsolated` is the synchronous, zero-hop
            // way to satisfy the isolation requirement.
            MainActor.assumeIsolated {
                self.refreshPlatformPaymentCredits()
                self.refreshCoinJoinBalance()
            }
            NotificationCenter.default.post(
                name: SwiftDashSDKWalletState.balanceDidChangeNotification,
                object: nil)
        }
    }

    /// Re-tally the Platform Payment credit balance from SwiftData.
    /// Idempotent — safe to call from any MainActor consumer that
    /// needs a fresh snapshot (e.g. `CreateUsernameViewModel.observeBalance`
    /// on view-model init, before the next Core-balance hook fires).
    /// No-op when the wallet handle or model container isn't ready.
    ///
    /// `@MainActor` is required because the function reads
    /// `SwiftDashSDKHost.shared.wallet/.modelContainer`, both
    /// MainActor-isolated. The non-MainActor entry points on this
    /// class (`applyBalance`, `clearBalance`, `clearAllState`)
    /// dispatch through their existing `DispatchQueue.main.async` and
    /// call this via `MainActor.assumeIsolated`.
    @MainActor
    public func refreshPlatformPaymentCredits() {
        guard
            let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
            let container = SwiftDashSDKHost.shared.modelContainer
        else {
            if platformPaymentCredits != 0 {
                platformPaymentCredits = 0
            }
            return
        }

        let context = container.mainContext
        // Filter accounts to PlatformPayment (`accountType == 14`) for
        // this wallet — the only account type that carries
        // `platformAddresses`. The persister keeps `balance` upserted
        // by BLAST sync, so a fetch + reduce is sufficient; no live
        // FFI call needed.
        let descriptor = FetchDescriptor<PersistentAccount>(
            predicate: #Predicate { account in
                account.accountType == 14
                    && account.wallet.walletId == walletId
            }
        )
        do {
            let accounts = try context.fetch(descriptor)
            let total = accounts.reduce(UInt64(0)) { acc, account in
                acc + account.platformAddresses.reduce(UInt64(0)) { $0 + $1.balance }
            }
            if platformPaymentCredits != total {
                platformPaymentCredits = total
                Self.logger.info("💰 WALLET :: platformPaymentCredits=\(total, privacy: .public) credits")
            }
        } catch {
            Self.logger.warning("💰 WALLET :: platformPaymentCredits fetch failed: \(String(describing: error), privacy: .public)")
        }
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
