//
//  SwiftDashSDKWalletCreator.swift
//  DashWallet
//
//  Creates or imports a SwiftDashSDK wallet from explicit inputs
//  (mnemonic + PIN + network). Used during onboarding (fresh-install
//  wallet creation, via `createWallet`) and during the recover-wallet
//  flow (importing an existing wallet from a recovery phrase, via
//  `importWallet`) to make the SwiftDashSDK side exist alongside the
//  DashSync side from day one.
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

    /// Create a fresh SwiftDashSDK wallet from a just-generated mnemonic and PIN.
    ///
    /// Used by the onboarding wallet-creation flow. The resulting `HDWallet`
    /// SwiftData record is marked `isImported: false` with label `"Created wallet"`,
    /// distinguishing it from migrator records (`"Migrated wallet"`) and from
    /// records produced by `importWallet` (`"Imported wallet"`).
    ///
    /// Dispatched to `DispatchQueue.global(qos: .userInitiated)` and returns
    /// to the caller in microseconds, mirroring the migrator's pattern. The
    /// actual ~300–500 ms of PBKDF2 + FFI work happens in the background while
    /// the caller's UI continues.
    ///
    /// Idempotent — safe to call multiple times for the same mnemonic+PIN; the
    /// existence check on `HDWallet.walletId` (which is `@Attribute(.unique)`)
    /// turns the duplicate-call case from a destructive rollback into a no-op.
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
    /// Identical to `createWallet` except the resulting `HDWallet` SwiftData
    /// record is marked `isImported: true` with label `"Imported wallet"`,
    /// matching the convention used by `SwiftDashSDKKeyMigrator` for wallets
    /// it imports from DashSync's keychain at upgrade time (which uses
    /// `"Migrated wallet"` to distinguish further).
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
    /// `WalletManager`, `WalletStorage`, and direct `HDWallet` construction)
    /// so it has no `@MainActor` requirements. Mirrors the migrator's
    /// `performMigration` body, but takes its inputs as parameters instead
    /// of reading them from DashSync's keychain.
    ///
    /// Shared between `createWallet` (fresh-install) and `importWallet`
    /// (recover-from-recovery-phrase). The two callers differ only in the
    /// `isImported` and `label` values they pass for the SwiftData record.
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

            // Round-trip verify before persisting the HDWallet record. If
            // verify fails, roll back the seed write.
            let readBack = try storage.retrieveSeed(pin: pin)
            guard readBack == seed else {
                logger.error("\(label, privacy: .public): round-trip seed mismatch — rolling back")
                try? storage.deleteSeed()
                return
            }

            // Persist the HDWallet SwiftData record on a fresh background
            // `ModelContext` against the shared `ModelContainer` that
            // `SwiftDashSDKContainer.warmUp()` created at app launch. We
            // deliberately do NOT call `ModelContainerHelper.createContainer()`
            // here — the SDK helper fails CloudKit validation on entitled
            // apps; see SwiftDashSDKContainer.swift for the full rationale.
            guard let modelContainer = SwiftDashSDKContainer.modelContainer else {
                logger.error("\(label, privacy: .public): SwiftDashSDKContainer.modelContainer is nil — rolling back seed")
                try? storage.deleteSeed()
                return
            }
            let context = ModelContext(modelContainer)

            // Idempotency: skip insert if a record for this walletId already
            // exists (e.g., wipe-then-restore, repeated calls). The seed write
            // above is already idempotent. `walletId` is `@Attribute(.unique)`
            // on `HDWallet`, so a duplicate insert would throw at save() and
            // fall into the catch block below — which would then `deleteSeed`
            // and destroy valid state. The existence check turns that case
            // into a safe no-op.
            let walletId = addResult.walletId
            let descriptor = FetchDescriptor<HDWallet>(
                predicate: #Predicate { $0.walletId == walletId }
            )
            let existing = try context.fetch(descriptor)

            if existing.isEmpty {
                let hdWallet = HDWallet(
                    walletId: walletId,
                    serializedWalletBytes: addResult.serializedWallet,
                    label: label,
                    network: appNetwork,
                    isWatchOnly: false,
                    isImported: isImported)
                context.insert(hdWallet)
                try context.save()
                logger.info("\(label, privacy: .public) record inserted on \(String(describing: sdkNetwork), privacy: .public)")
            } else {
                logger.info("HDWallet record already exists for walletId, skipping insert (\(label, privacy: .public))")
            }

            // Wake the SPV coordinator now that the wallet exists in SwiftData.
            // On a fresh install / first launch the coordinator was started from
            // AppDelegate but found no HDWallet record and parked itself in
            // .stopped. This call is the only way to get sync going for the
            // onboarding-create and recover-from-seed flows. Idempotent — if
            // the coordinator is already running for some reason, this is a no-op.
            SwiftDashSDKSPVCoordinator.startIfReady()
        } catch {
            logger.error("\(label, privacy: .public) threw: \(String(describing: error), privacy: .public)")
            // Best-effort: leave SwiftDashSDK side clean if anything was partially written.
            try? WalletStorage().deleteSeed()
        }
    }
}
