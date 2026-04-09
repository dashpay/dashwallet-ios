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
    /// records have been deleted from SwiftData. Without this, the
    /// published value would keep showing the previous wallet's balance
    /// across a wipe-then-recover or wipe-then-create flow until the new
    /// wallet's first balance event arrives.
    @objc public func clearBalance() {
        DispatchQueue.main.async { [weak self] in
            Self.logger.info("💰 WALLET :: clearing balance")
            self?.balance = nil
        }
    }
}
