//
//  SwiftDashSDKReceiveAddressReader.swift
//  DashWallet
//
//  Receive-address adapter — SwiftDashSDK is the sole authoritative source.
//
//  Returns the next unused BIP44 external receive address for the wallet
//  bound to `SwiftDashSDKHost.shared`. The "next unused" decision is made
//  by Rust inside `core_wallet_next_receive_address`, which consults the
//  managed wallet's used-set. The used-set is populated by Core SPV block
//  processing and persisted across launches in
//  `Documents/SwiftDashSDK/Platform/<network>/`.
//
//  Cold-launch behavior:
//   - Warm launch with cached SPV state: returns the correct next-unused
//     address immediately (used-set hydrated from disk during host start).
//   - First launch post-migration / after wipe: SPV data dir is fresh, the
//     used-set starts empty, the FFI returns address index 0. As SPV
//     replays blocks, the used-set advances and the next read picks up the
//     new lowest-unused index.
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

    /// Returns the next unused BIP44 external receive address on the primary
    /// account (index 0). Returns nil when the host hasn't bound a wallet
    /// yet or the FFI call fails. Never throws.
    ///
    /// The `chain` argument is preserved on the public surface for legacy
    /// `@objc` callers; the underlying lookup goes through
    /// `SwiftDashSDKHost.shared` which is already bound to the active
    /// network at the time `start(network:)` ran.
    @objc(receiveAddressOnChain:)
    static func receiveAddress(on chain: DSChain) -> String? {
        _ = chain
        if Thread.isMainThread {
            return MainActor.assumeIsolated { readOnMain() }
        }
        var result: String?
        DispatchQueue.main.sync {
            result = MainActor.assumeIsolated { readOnMain() }
        }
        return result
    }

    @MainActor
    private static func readOnMain() -> String? {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            Self.logger.warning("📬 RECVADDR :: host has no wallet yet")
            return nil
        }
        do {
            return try wallet.coreWallet().nextReceiveAddress(accountIndex: 0)
        } catch {
            Self.logger.warning(
                "📬 RECVADDR :: nextReceiveAddress failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
