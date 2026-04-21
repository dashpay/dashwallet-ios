//
//  PlatformSendExecutor.swift
//  DashWallet
//
//  Executes a Platform credit transfer via
//  `sdk.addresses.transferFunds(inputs:outputs:feeFromInputIndex:)`. The
//  first cut surfaces a clear TODO boundary around key derivation:
//  `transferFunds` needs a 32-byte secp256k1 private key per input, which
//  must be derived from the app mnemonic and the DIP-17 derivation path
//  stored on the funding `PersistentPlatformAddress`. Wiring that derivation
//  is a separate task; for now the executor throws a precise, actionable
//  error so the UI reflects the state honestly.
//

import Foundation
import OSLog
import SwiftDashSDK

@MainActor
final class PlatformSendExecutor {
    static let shared = PlatformSendExecutor()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.platform-send-executor")

    enum SendError: LocalizedError {
        case coordinatorNotReady
        case noFundedAddress
        case keyDerivationNotImplemented

        var errorDescription: String? {
            switch self {
            case .coordinatorNotReady:
                return "Platform sync is not running. Open Tools → Platform Sync Status to start it."
            case .noFundedAddress:
                return "No funded Platform address. Fund one of the derived addresses first."
            case .keyDerivationNotImplemented:
                return "Platform send is wired end-to-end except for address key derivation; coming next."
            }
        }
    }

    private init() {}

    func transfer(destination: String, amount: UInt64) async throws {
        let coordinator = PlatformAddressSyncCoordinator.shared
        guard coordinator.isRunning else {
            throw SendError.coordinatorNotReady
        }

        let fundedSource = coordinator.derivedAddresses
            .filter { $0.balance >= amount }
            .max(by: { $0.balance < $1.balance })

        guard fundedSource != nil else {
            throw SendError.noFundedAddress
        }

        Self.logger.info("🛰️ PLATFORM-SEND :: PIN unlock succeeded; key derivation not implemented yet")
        throw SendError.keyDerivationNotImplemented
    }
}
