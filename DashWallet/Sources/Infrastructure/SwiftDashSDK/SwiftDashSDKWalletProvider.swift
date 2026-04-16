//
//  SwiftDashSDKWalletProvider.swift
//  DashWallet
//
//  Restores a detached HDWallet from the app-owned runtime wallet descriptor
//  in Keychain and caches it in memory. All consumers read from here instead
//  of reconstructing the wallet from mnemonic on demand.
//
//  Thread-safe: first caller restores the descriptor-backed wallet,
//  subsequent callers get the cached result instantly. Concurrent callers
//  block until restoration completes.
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKWalletProvider)
final class SwiftDashSDKWalletProvider: NSObject {

    // MARK: - Singleton

    static let shared = SwiftDashSDKWalletProvider()

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-provider")

    // MARK: - State

    /// Cached wallet — set once after restoration, cleared on invalidate().
    private var cachedWallet: HDWallet?
    private let runtimeWalletStore = SwiftDashSDKRuntimeWalletStore()

    /// Serializes first-access restoration. NSLock is reentrant-safe and
    /// works from any thread including DispatchQueue.
    private let lock = NSLock()

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Returns the cached HDWallet for `network`, restoring it from the
    /// runtime descriptor on first call.
    ///
    /// Thread-safe. If multiple threads call simultaneously, one restores and
    /// the others block until restoration completes.
    ///
    /// Throws if the runtime descriptor is not yet stored for that network
    /// (fresh install / no wallet on that chain) or if restoration fails.
    func getWallet(for network: AppNetwork) throws -> HDWallet {
        lock.lock()
        defer { lock.unlock() }

        if let wallet = cachedWallet, wallet.network == network {
            return wallet
        }
        if let wallet = cachedWallet, wallet.network != network {
            Self.logger.error("🔑 WALLETPROV :: cached wallet network mismatch")
            cachedWallet = nil
        }

        let wallet = try restoreWallet(expectedNetwork: network)
        cachedWallet = wallet
        return wallet
    }

    /// Clears the cached wallet. Called by the wiper on wallet reset and
    /// by the runtime after storing a new runtime descriptor so the next
    /// `getWallet(for:)` call re-restores from the updated keychain.
    @objc func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cachedWallet = nil
        Self.logger.info("🔑 WALLETPROV :: cache invalidated")
    }

    // MARK: - Restoration

    /// Restores an HDWallet from the runtime descriptor in Keychain.
    /// Called at most
    /// once per app session (or after invalidate).
    private func restoreWallet(expectedNetwork: AppNetwork) throws -> HDWallet {
        let descriptor: SwiftDashSDKRuntimeWalletStore.Descriptor
        do {
            descriptor = try runtimeWalletStore.retrieve(for: expectedNetwork)
        } catch SwiftDashSDKRuntimeWalletStore.RuntimeWalletStoreError.descriptorNotFound {
            Self.logger.error("🔑 WALLETPROV :: runtime descriptor not found for \(expectedNetwork.rawValue, privacy: .public)")
            throw ProviderError.runtimeDescriptorNotAvailable(network: expectedNetwork)
        } catch {
            Self.logger.error("🔑 WALLETPROV :: runtime descriptor read failed: \(String(describing: error), privacy: .public)")
            throw ProviderError.runtimeDescriptorInvalid(network: expectedNetwork)
        }

        guard !descriptor.walletId.isEmpty, !descriptor.serializedWalletBytes.isEmpty else {
            Self.logger.error("🔑 WALLETPROV :: runtime descriptor is empty")
            throw ProviderError.runtimeDescriptorInvalid(network: expectedNetwork)
        }

        guard descriptor.network == expectedNetwork else {
            Self.logger.error("🔑 WALLETPROV :: runtime descriptor network mismatch")
            throw ProviderError.networkMismatch(expected: expectedNetwork, actual: descriptor.network)
        }

        let wallet = HDWallet(
            walletId: descriptor.walletId,
            serializedWalletBytes: descriptor.serializedWalletBytes,
            label: descriptor.isImported ? "Imported wallet" : "Created wallet",
            network: descriptor.network,
            isWatchOnly: false,
            isImported: descriptor.isImported)

        Self.logger.info("🔑 WALLETPROV :: runtime wallet restored")

        return wallet
    }

    // MARK: - Errors

    enum ProviderError: LocalizedError {
        case runtimeDescriptorNotAvailable(network: AppNetwork)
        case runtimeDescriptorInvalid(network: AppNetwork)
        case networkMismatch(expected: AppNetwork, actual: AppNetwork)

        var errorDescription: String? {
            switch self {
            case .runtimeDescriptorNotAvailable(let network):
                return "Runtime wallet descriptor not available for \(network.rawValue)"
            case .runtimeDescriptorInvalid(let network):
                return "Runtime wallet descriptor is invalid for \(network.rawValue)"
            case .networkMismatch(let expected, let actual):
                return "Runtime wallet descriptor network mismatch: expected \(expected.rawValue), got \(actual.rawValue)"
            }
        }
    }
}
