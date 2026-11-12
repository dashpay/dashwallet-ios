//
//  ShieldedReceiveAddressSource.swift
//  DashWallet
//

import Foundation
import SwiftDashSDK

/// The outcome of one Receive session's shielded address request.
enum ShieldedReceiveAddress: Equatable {
    /// A fresh address at a random diversifier index, Bech32m-encoded for the
    /// running network.
    case fresh(String)
    /// The default shielded address, used only when a fresh one could not be
    /// derived. Shown only with the linkability warning (AC-07).
    case fallback(String)
    /// The shielded wallet is not ready yet (not bound, or no network
    /// running); Receive shows the «starting» placeholder and Copy and Share
    /// stay disabled. Receive asks again when shielded sync starts running,
    /// and on the next session.
    case notReady
    /// Neither a fresh nor the default address could be produced; Receive
    /// shows a placeholder and Copy and Share stay disabled.
    case unavailable
}

/// Produces the shielded address for one Receive session.
protocol ShieldedReceiveAddressSource {
    func receiveAddress(walletId: Data) async -> ShieldedReceiveAddress
}

/// The SwiftDashSDK-backed source. The SDK calls and the running network are
/// injected so the mapping is testable without the SDK; the defaults read
/// `SwiftDashSDKHost.shared`. `PlatformWalletManager` is main-actor isolated,
/// so the SDK calls run on the main actor.
struct SDKShieldedReceiveAddressSource: ShieldedReceiveAddressSource {
    typealias AddressCall = @MainActor (Data) throws -> Data?

    let freshAddress: AddressCall
    let defaultAddress: AddressCall
    /// `nil` when no network is running.
    let isMainnet: @MainActor () -> Bool?

    init(
        freshAddress: @escaping AddressCall = { walletId in
            guard let manager = SwiftDashSDKHost.shared.manager else { return nil }
            return try manager.shieldedFreshAddress(walletId: walletId)
        },
        defaultAddress: @escaping AddressCall = { walletId in
            guard let manager = SwiftDashSDKHost.shared.manager else { return nil }
            return try manager.shieldedDefaultAddress(walletId: walletId)
        },
        isMainnet: @escaping @MainActor () -> Bool? = {
            SwiftDashSDKHost.shared.runningNetwork.map { $0 == .mainnet }
        }
    ) {
        self.freshAddress = freshAddress
        self.defaultAddress = defaultAddress
        self.isMainnet = isMainnet
    }

    func receiveAddress(walletId: Data) async -> ShieldedReceiveAddress {
        await MainActor.run {
            guard let mainnet = isMainnet() else { return .notReady }
            do {
                guard let raw = try freshAddress(walletId) else { return .notReady }
                return Self.encode(raw: raw, mainnet: mainnet).map(ShieldedReceiveAddress.fresh) ?? .unavailable
            } catch {
                let summary = WalletSendService.logSummary(of: error)
                DWLogger.log("shielded receive: fresh address failed, trying default: \(summary)")
            }
            do {
                guard let raw = try defaultAddress(walletId) else { return .unavailable }
                return Self.encode(raw: raw, mainnet: mainnet).map(ShieldedReceiveAddress.fallback) ?? .unavailable
            } catch {
                DWLogger.log("shielded receive: default address failed: \(WalletSendService.logSummary(of: error))")
                return .unavailable
            }
        }
    }

    /// DIP-0018 display form: HRP `dash`/`tdash`, payload = 0x10 type byte +
    /// the 43 raw Orchard address bytes. `nil` when the bytes can't be encoded.
    static func encode(raw: Data, mainnet: Bool) -> String? {
        Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: mainnet), data: Data([0x10]) + raw)
    }
}
