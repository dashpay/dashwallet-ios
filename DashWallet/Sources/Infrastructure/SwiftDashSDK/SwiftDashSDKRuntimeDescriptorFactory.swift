//
//  SwiftDashSDKRuntimeDescriptorFactory.swift
//  DashWallet
//
//  Builds SwiftDashSDK runtime wallet descriptors from mnemonic material.
//  Used during create/import/migration and for one-time descriptor bootstrap
//  when the app switches to a supported network that already has a wallet
//  but does not yet have a runtime descriptor.
//

import Foundation
import OSLog
import SwiftDashSDK

final class SwiftDashSDKRuntimeDescriptorFactory {
    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.runtime-descriptor-factory")

    func makeDescriptor(
        mnemonic: String,
        network: AppNetwork,
        isImported: Bool
    ) throws -> SwiftDashSDKRuntimeWalletStore.Descriptor {
        guard !mnemonic.isEmpty, Mnemonic.validate(mnemonic) else {
            throw FactoryError.invalidMnemonic
        }

        let sdkNetwork: KeyWalletNetwork
        let birthHeight: UInt32
        switch network {
        case .mainnet:
            sdkNetwork = .mainnet
            birthHeight = 730_000
        case .testnet:
            sdkNetwork = .testnet
            birthHeight = 0
        case .devnet, .regtest:
            throw FactoryError.unsupportedNetwork(network)
        }

        let walletManager = try WalletManager(network: sdkNetwork)
        let addResult = try walletManager.addWalletAndSerialize(
            mnemonic: mnemonic,
            passphrase: nil,
            birthHeight: birthHeight,
            accountOptions: .default,
            downgradeToPublicKeyWallet: false,
            allowExternalSigning: false)

        do {
            try walletManager.ensurePlatformPaymentAccount(walletId: addResult.walletId)
        } catch {
            Self.logger.warning("ensurePlatformPaymentAccount failed (non-fatal): \(String(describing: error), privacy: .public)")
        }

        return SwiftDashSDKRuntimeWalletStore.Descriptor(
            walletId: addResult.walletId,
            serializedWalletBytes: addResult.serializedWallet,
            network: network,
            isImported: isImported)
    }

    enum FactoryError: LocalizedError {
        case invalidMnemonic
        case unsupportedNetwork(AppNetwork)

        var errorDescription: String? {
            switch self {
            case .invalidMnemonic:
                return "Runtime descriptor factory received an invalid mnemonic"
            case .unsupportedNetwork(let network):
                return "Runtime descriptor factory does not support \(network.rawValue)"
            }
        }
    }
}
