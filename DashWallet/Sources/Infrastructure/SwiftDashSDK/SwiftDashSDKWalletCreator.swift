//
//  SwiftDashSDKWalletCreator.swift
//  DashWallet
//
//  Creates or imports a SwiftDashSDK wallet from explicit inputs
//  (mnemonic + PIN + network). Used during onboarding (fresh-install
//  wallet creation, via `createWallet`) and during the recover-wallet
//  flow (importing an existing wallet from a recovery phrase, via
//  `importWallet`) to make the SwiftDashSDK side exist alongside the
//  DashSync side from day one. Runtime restoration is keyed off an
//  app-owned Keychain descriptor, not a persisted SwiftData wallet record.
//
//  This file is intentionally decoupled from DashSync — it does not import
//  DashSync, does not know DashSync's keychain layout, and does not read
//  any DashSync state. All inputs come from the caller. The upgrade-time
//  migration concern lives separately in SwiftDashSDKKeyMigrator.swift.
//

import Foundation
import OSLog
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

    /// Create a fresh SwiftDashSDK wallet from a just-generated mnemonic and PIN.
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
            performCreate(
                mnemonic: mnemonic,
                pin: pin,
                network: network,
                isImported: false,
                label: "Created wallet")
        }
    }

    /// Import a SwiftDashSDK wallet from an existing mnemonic (e.g., from
    /// the recover-wallet flow).
    ///
    /// Same threading and error semantics as `createWallet`: dispatched to a
    /// background queue, idempotent, never throws, never crashes.
    ///
    /// - Parameters:
    ///   - mnemonic: BIP39 phrase from the user-provided recovery phrase.
    ///   - pin: User's plaintext PIN, used to encrypt the seed in WalletStorage.
    ///   - network: 0 = mainnet, 1 = testnet. Devnet/regtest are unsupported.
    @objc(importWalletWithMnemonic:pin:network:)
    static func importWallet(mnemonic: String, pin: String, network: Network) {
        DispatchQueue.global(qos: .userInitiated).async {
            performCreate(
                mnemonic: mnemonic,
                pin: pin,
                network: network,
                isImported: true,
                label: "Imported wallet")
        }
    }

    // MARK: - Background creation body

    /// The actual creation body. Runs on a background `DispatchQueue` —
    /// uses the lowest-level public SwiftDashSDK API surface (standalone
    /// `WalletManager` and `WalletStorage`)
    /// so it has no `@MainActor` requirements. Mirrors the migrator's
    /// `performMigration` body, but takes its inputs as parameters instead
    /// of reading them from DashSync's keychain.
    ///
    /// Shared between `createWallet` (fresh-install) and `importWallet`
    /// (recover-from-recovery-phrase). The two callers differ only in the
    /// `isImported` and `label` values they pass for the runtime descriptor.
    private static func performCreate(
        mnemonic: String,
        pin: String,
        network: Network,
        isImported: Bool,
        label: String
    ) {
        let sdkNetwork: KeyWalletNetwork = (network == .mainnet) ? .mainnet : .testnet
        let appNetwork: AppNetwork       = (network == .mainnet) ? .mainnet : .testnet

        guard !mnemonic.isEmpty else {
            logger.error("\(label, privacy: .public): empty mnemonic — refusing")
            return
        }
        guard !pin.isEmpty else {
            logger.error("\(label, privacy: .public): empty PIN — refusing")
            return
        }
        guard Mnemonic.validate(mnemonic) else {
            logger.error("\(label, privacy: .public): mnemonic failed BIP39 validation — refusing")
            return
        }

        do {
            // Determinism + length sanity check (matches migrator).
            let seed = try Mnemonic.toSeed(mnemonic: mnemonic)
            guard seed.count == 64 else {
                logger.error("\(label, privacy: .public): seed length invalid: \(seed.count, privacy: .public)")
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

            // Encrypt and store the seed via WalletStorage. Already idempotent
            // because storeSeed deletes existing items before adding new ones
            // (WalletStorage.swift:41).
            let storage = WalletStorage()
            _ = try storage.storeSeed(seed, pin: pin)

            // Round-trip verify before storing the runtime descriptor. If
            // verify fails, roll back the seed write.
            let readBack = try storage.retrieveSeed(pin: pin)
            guard readBack == seed else {
                logger.error("\(label, privacy: .public): round-trip seed mismatch — rolling back")
                try? storage.deleteSeed()
                return
            }

            try storage.storeMnemonic(mnemonic)
            let storedMnemonic = try storage.retrieveMnemonic()
            guard storedMnemonic == mnemonic else {
                logger.error("\(label, privacy: .public): mnemonic round-trip mismatch — rolling back")
                throw CreateError.mnemonicRoundTripMismatch
            }
            logger.info("stored mnemonic in WalletStorage")

            let runtimeWalletStore = SwiftDashSDKRuntimeWalletStore()
            let descriptor = SwiftDashSDKRuntimeWalletStore.Descriptor(
                walletId: addResult.walletId,
                serializedWalletBytes: addResult.serializedWallet,
                network: appNetwork,
                isImported: isImported)
            try runtimeWalletStore.store(descriptor)
            let storedDescriptor = try runtimeWalletStore.retrieve()
            guard storedDescriptor == descriptor else {
                logger.error("\(label, privacy: .public): runtime descriptor round-trip mismatch — rolling back")
                throw CreateError.runtimeDescriptorRoundTripMismatch
            }

            // Invalidate the wallet provider so the next getWallet() call
            // restores from the newly-stored runtime descriptor.
            SwiftDashSDKWalletProvider.shared.invalidate()

            logger.info("\(label, privacy: .public) completed on \(String(describing: sdkNetwork), privacy: .public)")

            // Wake the SPV coordinator now that the runtime descriptor is in keychain.
            SwiftDashSDKSPVCoordinator.startIfReady()
        } catch {
            logger.error("\(label, privacy: .public) threw: \(String(describing: error), privacy: .public)")
            // Best-effort: leave SwiftDashSDK side clean if anything was partially written.
            try? WalletStorage().deleteSeed()
            try? WalletStorage().deleteMnemonic()
            try? SwiftDashSDKRuntimeWalletStore().delete()
        }
    }

    private enum CreateError: LocalizedError {
        case mnemonicRoundTripMismatch
        case runtimeDescriptorRoundTripMismatch
    }
}
