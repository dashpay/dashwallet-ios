//
//  SwiftDashSDKWalletProvider.swift
//  DashWallet
//
//  Derives an HDWallet from the mnemonic stored in WalletStorage (keychain)
//  and caches it in memory. All consumers read from here instead of querying
//  SwiftData directly — the HDWallet is never persisted to disk.
//
//  Thread-safe: first caller triggers derivation (~300-500ms), subsequent
//  callers get the cached result instantly. Concurrent callers block until
//  derivation completes.
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

    /// Cached wallet — set once after derivation, cleared on invalidate().
    private var cachedWallet: HDWallet?

    /// Serializes first-access derivation. NSLock is reentrant-safe and
    /// works from any thread including DispatchQueue.
    private let lock = NSLock()

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Returns the cached HDWallet, deriving it from the mnemonic on first call.
    ///
    /// Thread-safe. If multiple threads call simultaneously, one derives and
    /// the others block until derivation completes (~300-500ms first time,
    /// instant after).
    ///
    /// Throws if the mnemonic is not yet stored (fresh install before
    /// onboarding) or if derivation fails.
    func getWallet() throws -> HDWallet {
        lock.lock()
        defer { lock.unlock() }

        if let wallet = cachedWallet {
            return wallet
        }

        let wallet = try deriveWallet()
        cachedWallet = wallet
        return wallet
    }

    /// Clears the cached wallet. Called by the wiper on wallet reset and
    /// by the migrator/creator after storing a new mnemonic so the next
    /// `getWallet()` call re-derives from the updated keychain.
    @objc func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cachedWallet = nil
        Self.logger.info("🔑 WALLETPROV :: cache invalidated")
    }

    // MARK: - Derivation

    /// Derives an HDWallet from the mnemonic in WalletStorage.
    /// Runs ~300-500ms (PBKDF2 + FFI key derivation). Called at most
    /// once per app session (or after invalidate).
    private func deriveWallet() throws -> HDWallet {
        let storage = WalletStorage()
        let mnemonic: String
        do {
            mnemonic = try storage.retrieveMnemonic()
        } catch {
            Self.logger.error("🔑 WALLETPROV :: retrieveMnemonic failed: \(String(describing: error), privacy: .public)")
            throw ProviderError.mnemonicNotAvailable
        }

        guard !mnemonic.isEmpty else {
            Self.logger.error("🔑 WALLETPROV :: mnemonic is empty")
            throw ProviderError.mnemonicNotAvailable
        }

        // Determine network from DWEnvironment (DashSync's chain config).
        let isMainnet = DWEnvironment.sharedInstance().currentChain.isMainnet
        let sdkNetwork: KeyWalletNetwork = isMainnet ? .mainnet : .testnet
        let appNetwork: AppNetwork = isMainnet ? .mainnet : .testnet

        Self.logger.info("🔑 WALLETPROV :: deriving wallet on \(String(describing: sdkNetwork), privacy: .public)")

        // Standalone WalletManager — owns its own FFI handle, freed by ARC
        // when this function returns.
        let walletManager = try WalletManager(network: sdkNetwork)

        let addResult = try walletManager.addWalletAndSerialize(
            mnemonic: mnemonic,
            passphrase: nil,
            birthHeight: isMainnet ? 730_000 : 0,
            accountOptions: .default,
            downgradeToPublicKeyWallet: false,
            allowExternalSigning: false)

        // Construct in-memory HDWallet — never inserted into a ModelContext.
        let wallet = HDWallet(
            walletId: addResult.walletId,
            serializedWalletBytes: addResult.serializedWallet,
            label: "Derived wallet",
            network: appNetwork,
            isWatchOnly: false,
            isImported: false)

        Self.logger.info("🔑 WALLETPROV :: wallet derived OK, walletId=\(addResult.walletId.count, privacy: .public) bytes, serialized=\(addResult.serializedWallet.count, privacy: .public) bytes")

        return wallet
    }

    // MARK: - Errors

    enum ProviderError: LocalizedError {
        case mnemonicNotAvailable

        var errorDescription: String? {
            switch self {
            case .mnemonicNotAvailable:
                return "Wallet mnemonic not available — wallet not yet created or has been wiped"
            }
        }
    }
}
