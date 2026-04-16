//
//  SwiftDashSDKReceiveAddressReader.swift
//  DashWallet
//
//  Receive-address adapter — SwiftDashSDK is the sole authoritative source.
//  Function #1 of DASHSYNC_MIGRATION.md.
//
//  Returns the next unused BIP44 external receive address for the wallet
//  registered with the running SPV coordinator. The "next unused" decision
//  is made by Rust inside `managed_wallet_get_next_bip44_receive_address`,
//  which consults the managed_wallet_info's used-set. That used-set is
//  populated by SPV block processing and persisted across launches in
//  `Documents/SwiftDashSDK/SPV/<network>/`.
//
//  Cold-launch behavior:
//   - Warm launch with cached SPV state: returns the correct next-unused
//     address immediately (used-set hydrated from disk during importWallet).
//   - First launch post-migration / after wipe: SPV data dir is fresh, the
//     used-set starts empty, the FFI returns address index 0. As SPV
//     replays blocks, the used-set advances. DWReceiveModel observes
//     `SwiftDashSDKWalletState.transactionsDidChangeNotification` and
//     re-fetches, so the screen catches up automatically.
//
//  Returns nil rather than throwing on failure — call sites already treat
//  nil as "no address yet" (DWReceiveModel clears the QR + cache, Swift
//  callers fall back to "" or fatalError as they did before).
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKReceiveAddressReader)
final class SwiftDashSDKReceiveAddressReader: NSObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.receive-address-reader")

    /// Returns the next unused BIP44 external receive address for the given
    /// chain on the primary account (index 0). Returns nil when the SPV
    /// runtime isn't available, the runtime descriptor is missing, or the
    /// FFI call fails. Never throws.
    @objc(receiveAddressOnChain:)
    static func receiveAddress(on chain: DSChain) -> String? {
        let network = mapNetwork(chain.chainType.tag)
        do {
            let descriptor = try SwiftDashSDKRuntimeWalletStore().retrieve(for: network)
            let walletManager = try SwiftDashSDKSPVCoordinator.shared.getWalletManager()
            return try walletManager.getReceiveAddress(walletId: descriptor.walletId)
        } catch {
            Self.logger.warning("📬 RECVADDR :: receiveAddress(on:) failed for \(network.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Network mapping

    private static func mapNetwork(_ tag: ChainType_Tag) -> AppNetwork {
        switch tag {
        case ChainType_MainNet: return .mainnet
        case ChainType_TestNet: return .testnet
        default:                return .devnet
        }
    }
}
