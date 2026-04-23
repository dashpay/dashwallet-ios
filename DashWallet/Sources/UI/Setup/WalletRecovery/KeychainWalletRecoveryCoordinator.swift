//
//  KeychainWalletRecoveryCoordinator.swift
//  DashWallet
//
//  Drives the "Recover Wallet?" prompt shown on the Setup screen when the
//  keychain contains a mnemonic left over from a previous install but the
//  app has no wallet data yet. Mirrors the SwiftExampleApp flow at
//  `ContentView.swift:115-273` in platform/packages/swift-sdk.
//

import Foundation
import LocalAuthentication
import OSLog
import UIKit

@objc(DWKeychainWalletRecoveryCoordinator)
final class KeychainWalletRecoveryCoordinator: NSObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.keychain-wallet-recovery")

    // MARK: - Detection

    @objc(hasOrphanMnemonic)
    static func hasOrphanMnemonic() -> Bool {
        guard let phrase = SwiftDashSDKMnemonicReader.readMnemonic() else {
            return false
        }
        return !phrase.isEmpty
    }

    // MARK: - Flow entry

    /// Presents the "Recover Wallet?" alert on `host`. Completion fires on the
    /// main queue exactly once — with a non-empty mnemonic on Authorize-success
    /// or `nil` when the user dismissed, cancelled the biometric prompt, or
    /// deleted the stored mnemonic.
    @objc(presentRecoveryFlowFrom:completion:)
    static func presentRecoveryFlow(
        from host: UIViewController,
        completion: @escaping (String?) -> Void
    ) {
        presentPrimaryAlert(from: host, completion: completion)
    }

    /// Presents the post-reinstall "Wallet found on this device" prompt on
    /// `host`. Used by `DWInitialViewController` after the Welcome carousel
    /// when DashSync's keychain entries survived the reinstall — the wallet
    /// is fully usable, so the user only needs to choose between keeping it
    /// or wiping it clean before landing on the app root. Completion fires
    /// on the main queue exactly once: `true` = keep, `false` = delete.
    @objc(presentReinstallKeepOrDeleteChoiceFrom:completion:)
    static func presentReinstallKeepOrDeleteChoice(
        from host: UIViewController,
        completion: @escaping (Bool) -> Void
    ) {
        presentReinstallPrimaryAlert(from: host, completion: completion)
    }

    // MARK: - Alert sequencing

    private static func presentPrimaryAlert(
        from host: UIViewController,
        completion: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(
            title: NSLocalizedString("Recover Wallet?", comment: ""),
            message: NSLocalizedString(
                "A wallet mnemonic is stored on this device, but no wallet data was found. Authorize to re-derive the wallet's public keys from the stored mnemonic.",
                comment: ""),
            preferredStyle: .alert)

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("No", comment: ""),
                style: .cancel,
                handler: { _ in
                    presentKeepPrompt(from: host, completion: completion)
                }))

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Authorize", comment: ""),
                style: .default,
                handler: { _ in
                    authorizeAndRecover(from: host, completion: completion)
                }))

        host.present(alert, animated: true)
    }

    private static func presentKeepPrompt(
        from host: UIViewController,
        completion: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(
            title: NSLocalizedString("Keep this Wallet?", comment: ""),
            message: NSLocalizedString(
                "Recreate will re-derive the wallet from the stored mnemonic. Delete will permanently remove the mnemonic from this device.",
                comment: ""),
            preferredStyle: .alert)

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Recreate", comment: ""),
                style: .default,
                handler: { _ in
                    presentPrimaryAlert(from: host, completion: completion)
                }))

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Delete", comment: ""),
                style: .destructive,
                handler: { _ in
                    _ = SwiftDashSDKMnemonicReader.deleteStoredMnemonic()
                    completion(nil)
                }))

        host.present(alert, animated: true)
    }

    // MARK: - Reinstall Keep/Delete sequencing

    private static func presentReinstallPrimaryAlert(
        from host: UIViewController,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: NSLocalizedString("Wallet found on this device", comment: ""),
            message: NSLocalizedString(
                "A wallet from a previous installation is still stored on this device. Keep using it, or delete it and start fresh? Make sure your recovery phrase is backed up before deleting.",
                comment: ""),
            preferredStyle: .alert)

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Delete", comment: ""),
                style: .destructive,
                handler: { _ in
                    presentReinstallDeleteConfirm(from: host, completion: completion)
                }))

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Keep Wallet", comment: ""),
                style: .default,
                handler: { _ in
                    completion(true)
                }))

        host.present(alert, animated: true)
    }

    private static func presentReinstallDeleteConfirm(
        from host: UIViewController,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: NSLocalizedString("Delete Wallet?", comment: ""),
            message: NSLocalizedString(
                "This permanently removes the wallet, private keys, and recovery phrase from this device. This cannot be undone.",
                comment: ""),
            preferredStyle: .alert)

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Cancel", comment: ""),
                style: .cancel,
                handler: { _ in
                    presentReinstallPrimaryAlert(from: host, completion: completion)
                }))

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Delete", comment: ""),
                style: .destructive,
                handler: { _ in
                    completion(false)
                }))

        host.present(alert, animated: true)
    }

    // MARK: - Authorize + mnemonic fetch

    private static func authorizeAndRecover(
        from host: UIViewController,
        completion: @escaping (String?) -> Void
    ) {
        let context = LAContext()
        context.localizedCancelTitle = NSLocalizedString("Cancel", comment: "")

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            logger.warning(
                "🔐 RECOVERY :: device owner auth unavailable: \(String(describing: policyError), privacy: .public)")
            presentKeepPrompt(from: host, completion: completion)
            return
        }

        let reason = NSLocalizedString(
            "Re-derive your wallet from the stored recovery phrase.",
            comment: "")
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { authorized, error in
            DispatchQueue.main.async {
                guard authorized else {
                    logger.info("🔐 RECOVERY :: auth declined: \(String(describing: error), privacy: .public)")
                    completion(nil)
                    return
                }
                guard let phrase = SwiftDashSDKMnemonicReader.readMnemonic(), !phrase.isEmpty else {
                    logger.error("🔐 RECOVERY :: auth succeeded but mnemonic read returned nil")
                    completion(nil)
                    return
                }
                completion(phrase)
            }
        }
    }
}
