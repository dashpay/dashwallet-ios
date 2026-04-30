//
//  SwiftDashSDKWalletCreator.swift
//  DashWallet
//
//  Creates or imports a SwiftDashSDK wallet from explicit inputs
//  (mnemonic + PIN + network). Used during onboarding (fresh-install
//  wallet creation, via `createWallet`) and during the recover-wallet
//  flow (importing an existing wallet from a recovery phrase, via
//  `importWallet`) to make the SwiftDashSDK side exist alongside the
//  DashSync side from day one. Runtime ownership belongs to
//  `SwiftDashSDKHost`, which creates the ManagedPlatformWallet, persists
//  the SwiftData wallet row, and stores the mnemonic in WalletStorage.
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

    /// Create a fresh SwiftDashSDK wallet from a just-generated mnemonic.
    ///
    /// Dispatched to `DispatchQueue.global(qos: .userInitiated)` and returns
    /// to the caller in microseconds. Validation happens on the background
    /// queue; wallet creation hops to `SwiftDashSDKHost` on the main actor.
    ///
    /// Never throws, never crashes; all errors are swallowed into os.log.
    ///
    /// - Parameters:
    ///   - mnemonic: BIP39 phrase. Caller is responsible for it being valid;
    ///     we re-validate via `Mnemonic.validate` defensively before use.
    ///   - pin: User's plaintext PIN. Retained for Obj-C selector stability;
    ///     SwiftDashSDK key material is now mnemonic-only.
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
    ///   - pin: User's plaintext PIN. Retained for Obj-C selector stability;
    ///     SwiftDashSDK key material is now mnemonic-only.
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

    /// The actual creation body. Runs on a background `DispatchQueue` and
    /// performs cheap validation before invoking `SwiftDashSDKHost` on the
    /// main actor. The host is the only code allowed to create the managed
    /// wallet and persist the mnemonic under the returned wallet id.
    ///
    /// Shared between `createWallet` (fresh-install) and `importWallet`
    /// (recover-from-recovery-phrase). The two callers differ only in the
    /// `isImported` and `label` values they pass for logging.
    private static func performCreate(
        mnemonic: String,
        pin: String,
        network: Network,
        isImported: Bool,
        label: String
    ) {
        let appNetwork: AppNetwork = (network == .mainnet) ? .mainnet : .testnet

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

            let walletId = try createWalletOnHost(
                mnemonic: mnemonic,
                network: appNetwork,
                isImported: isImported)

            let walletPrefix = walletId.prefix(4).map { String(format: "%02x", $0) }.joined()
            logger.info("\(label, privacy: .public) completed on \(appNetwork.rawValue, privacy: .public), wallet=\(walletPrefix, privacy: .public)…")

            // Refresh the app-owned runtime now that wallet material is ready.
            SwiftDashSDKWalletRuntime.handleWalletMaterialChanged()
        } catch {
            logger.error("\(label, privacy: .public) threw: \(String(describing: error), privacy: .public)")
        }
    }

    private static func createWalletOnHost(
        mnemonic: String,
        network: AppNetwork,
        isImported: Bool
    ) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?

        Task { @MainActor in
            result = Result {
                try SwiftDashSDKHost.shared.createOrImportWallet(
                    mnemonic: mnemonic,
                    network: network,
                    isImported: isImported
                ).walletId
            }
            semaphore.signal()
        }

        semaphore.wait()
        guard let result else {
            throw CreateError.hostCreateDidNotReturn
        }
        return try result.get()
    }

    private enum CreateError: LocalizedError {
        case hostCreateDidNotReturn
    }
}
