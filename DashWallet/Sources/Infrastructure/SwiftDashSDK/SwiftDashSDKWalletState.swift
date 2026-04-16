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
//  migration). Will grow to hold transactions (#6), addresses (#1),
//  identities (#16) etc. as those migrations land. The SPV coordinator's
//  WalletEventsHandler forwards FFI events here; this class owns the
//  @Published Combine surface that BalanceModel and friends subscribe to.
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

    /// Latest wallet transaction list from SwiftDashSDK. `nil` until either
    /// `seedTransactions(walletManager:walletId:)` succeeds or the first
    /// `applyTransactions(_:)` call arrives. Updated on the main queue.
    @Published public private(set) var transactions: [WalletTransaction]? = nil

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
            self?.balance = snapshot
            NotificationCenter.default.post(
                name: SwiftDashSDKWalletState.balanceDidChangeNotification,
                object: nil)
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
            NotificationCenter.default.post(
                name: SwiftDashSDKWalletState.balanceDidChangeNotification,
                object: nil)
        }
    }

    /// Clears balance and transaction state synchronously on the main queue.
    /// Runtime transitions use this so a restart cannot race with stale
    /// published wallet data lingering after a network switch.
    public func clearAllState() {
        let clearBlock = { [weak self] in
            Self.logger.info("💰 WALLET :: clearing all wallet state")
            self?.balance = nil
            self?.transactions = nil
            NotificationCenter.default.post(
                name: SwiftDashSDKWalletState.balanceDidChangeNotification,
                object: nil)
            NotificationCenter.default.post(
                name: SwiftDashSDKWalletState.transactionsDidChangeNotification,
                object: nil)
        }

        if Thread.isMainThread {
            clearBlock()
        } else {
            DispatchQueue.main.sync(execute: clearBlock)
        }
    }

    // MARK: - Transactions

    /// Notification posted on the main queue whenever the published
    /// `transactions` changes. Swift consumers should subscribe to
    /// `$transactions` directly.
    @objc public static let transactionsDidChangeNotification =
        NSNotification.Name("DWSwiftDashSDKWalletStateTransactionsDidChange")

    @objc public static var currentTransactionCount: Int {
        return shared.transactions?.count ?? 0
    }

    /// Called from `SwiftDashSDKSPVCoordinator.WalletEventsHandler.onTransactionReceived`
    /// after a re-fetch of all transactions. Marshals to the main queue.
    public func applyTransactions(_ snapshot: [WalletTransaction]) {
        DispatchQueue.main.async { [weak self] in
            Self.logger.info("📜 TXLIST :: applying \(snapshot.count, privacy: .public) transactions")
            self?.transactions = snapshot
            NotificationCenter.default.post(
                name: SwiftDashSDKWalletState.transactionsDidChangeNotification,
                object: nil)
        }
    }

    /// Called from `SwiftDashSDKSPVCoordinator.performStart` after
    /// `walletManager.importWallet` succeeds. Seeds the initial tx list
    /// from the FFI's in-memory state (populated from cached chain data
    /// on cold launch). On first launch the list starts empty and fills
    /// progressively as SPV replays blocks.
    ///
    /// Non-fatal — if the FFI call fails, live updates eventually catch up.
    public func seedTransactions(walletManager: WalletManager, walletId: Data) {
        do {
            let account = try walletManager.getManagedAccount(
                walletId: walletId, accountIndex: 0, accountType: .standardBIP44)
            let txs = account.getTransactions()
            Self.logger.info("📜 TXLIST :: initial transactions seed: count=\(txs.count, privacy: .public)")
            applyTransactions(txs)
        } catch {
            Self.logger.warning("📜 TXLIST :: initial transactions seed failed (non-fatal): \(String(describing: error), privacy: .public)")
        }
    }

    /// Called from `SwiftDashSDKWalletWiper.performWipe` after the wallet
    /// state has been deleted. Clears the cached tx list.
    public func clearTransactions() {
        DispatchQueue.main.async { [weak self] in
            Self.logger.info("📜 TXLIST :: clearing transactions")
            self?.transactions = nil
            NotificationCenter.default.post(
                name: SwiftDashSDKWalletState.transactionsDidChangeNotification,
                object: nil)
        }
    }
}
