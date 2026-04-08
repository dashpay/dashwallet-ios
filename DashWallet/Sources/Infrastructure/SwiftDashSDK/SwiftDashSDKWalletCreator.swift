//
//  SwiftDashSDKWalletCreator.swift
//  DashWallet
//
//  Creates a SwiftDashSDK wallet from explicit inputs (mnemonic + PIN + network).
//  Used during onboarding to make the SwiftDashSDK side exist alongside the
//  DashSync side from day one for fresh-install and restored-wallet users.
//
//  This file is intentionally decoupled from DashSync — it does not import
//  DashSync, does not know DashSync's keychain layout, and does not read
//  any DashSync state. All inputs come from the caller. The upgrade-time
//  migration concern lives separately in SwiftDashSDKKeyMigrator.swift.
//

import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@objc(DWSwiftDashSDKWalletCreator)
final class SwiftDashSDKWalletCreator: NSObject {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-creator")

    // MARK: - Network

    /// Network tags exposed to Obj-C as plain integers, mirroring the
    /// `KeyWalletNetwork` cases the migrator uses. Keeps Obj-C call sites
    /// from needing to import SwiftDashSDK.
    @objc(DWSwiftDashSDKNetwork)
    enum Network: Int {
        case mainnet = 0
        case testnet = 1
    }

    // MARK: - Public entry point

    /// Create a SwiftDashSDK wallet from the given mnemonic and PIN.
    ///
    /// Dispatched to `DispatchQueue.global(qos: .userInitiated)` and returns
    /// to the caller in microseconds, mirroring the migrator's pattern. The
    /// actual ~300–500 ms of PBKDF2 + FFI work happens in the background while
    /// the caller's UI continues.
    ///
    /// Never throws, never crashes; all errors are swallowed into os.log.
    ///
    /// - Parameters:
    ///   - mnemonic: BIP39 phrase. Caller is responsible for it being valid;
    ///     we re-validate via `Mnemonic.validate` defensively before use.
    ///   - pin: User's plaintext PIN, used to encrypt the seed in WalletStorage.
    ///   - network: 0 = mainnet, 1 = testnet. Devnet/regtest are unsupported.
    @objc(createWalletWithMnemonic:pin:network:)
    static func createWallet(mnemonic: String, pin: String, network: Network) {
        DispatchQueue.global(qos: .userInitiated).async {
            performCreate(mnemonic: mnemonic, pin: pin, network: network)
        }
    }

    // MARK: - Background creation body

    /// The actual creation body. Runs on a background `DispatchQueue` —
    /// uses the lowest-level public SwiftDashSDK API surface (standalone
    /// `WalletManager`, `WalletStorage`, and direct `HDWallet` construction)
    /// so it has no `@MainActor` requirements. Mirrors the migrator's
    /// `performMigration` body, but takes its inputs as parameters instead
    /// of reading them from DashSync's keychain.
    private static func performCreate(mnemonic: String, pin: String, network: Network) {
        let sdkNetwork: KeyWalletNetwork = (network == .mainnet) ? .mainnet : .testnet
        let appNetwork: AppNetwork       = (network == .mainnet) ? .mainnet : .testnet

        guard !mnemonic.isEmpty else {
            logger.error("createWallet called with empty mnemonic — refusing")
            return
        }
        guard !pin.isEmpty else {
            logger.error("createWallet called with empty PIN — refusing")
            return
        }
        guard Mnemonic.validate(mnemonic) else {
            logger.error("createWallet: mnemonic failed BIP39 validation — refusing")
            return
        }

        do {
            // Determinism + length sanity check (matches migrator).
            let seed = try Mnemonic.toSeed(mnemonic: mnemonic)
            guard seed.count == 64 else {
                logger.error("createWallet: seed length invalid: \(seed.count, privacy: .public)")
                return
            }

            // Standalone WalletManager — public init, owns its own FFI handle,
            // freed by ARC when this function returns.
            let walletManager = try WalletManager(network: sdkNetwork)

            // birthHeight matches the migrator's choice for fresh wallets:
            // 730k for mainnet (a recent checkpoint), 0 elsewhere.
            let addResult = try walletManager.addWalletAndSerialize(
                mnemonic: mnemonic,
                passphrase: nil,
                birthHeight: sdkNetwork == .mainnet ? 730_000 : 0,
                accountOptions: .default,
                downgradeToPublicKeyWallet: false,
                allowExternalSigning: false)

            // Optional platform payment account — non-fatal, matches migrator.
            do {
                try walletManager.ensurePlatformPaymentAccount(walletId: addResult.walletId)
            } catch {
                logger.warning("ensurePlatformPaymentAccount failed (non-fatal): \(String(describing: error), privacy: .public)")
            }

            // Encrypt and store the seed via WalletStorage.
            let storage = WalletStorage()
            _ = try storage.storeSeed(seed, pin: pin)

            // Round-trip verify before persisting the HDWallet record. If
            // verify fails, roll back the seed write.
            let readBack = try storage.retrieveSeed(pin: pin)
            guard readBack == seed else {
                logger.error("createWallet: round-trip seed mismatch — rolling back")
                try? storage.deleteSeed()
                return
            }

            // Persist the HDWallet SwiftData record on a fresh non-main
            // context so this code path doesn't require @MainActor isolation.
            let modelContainer = try ModelContainerHelper.createContainer()
            let context = ModelContext(modelContainer)
            let hdWallet = HDWallet(
                walletId: addResult.walletId,
                serializedWalletBytes: addResult.serializedWallet,
                label: "Created wallet",
                network: appNetwork,
                isWatchOnly: false,
                isImported: false)
            context.insert(hdWallet)
            try context.save()

            logger.info("createWallet: wallet created on \(String(describing: sdkNetwork), privacy: .public)")
        } catch {
            logger.error("createWallet threw: \(String(describing: error), privacy: .public)")
            // Best-effort: leave SwiftDashSDK side clean if anything was partially written.
            try? WalletStorage().deleteSeed()
        }
    }
}
