//
//  KeychainWalletRecoveryCoordinator.swift
//  DashWallet
//
//  Post-reinstall "Wallet found on this device" prompt. DashSync's keychain
//  entries survive app reinstall, so the moment onboarding ends
//  `chain.hasAWallet == YES` and the wallet would auto-recover silently —
//  this coordinator gates that transition behind a Keep/Delete choice, with
//  a destructive-action confirm on Delete.
//

import Foundation
import UIKit

@objc(DWKeychainWalletRecoveryCoordinator)
final class KeychainWalletRecoveryCoordinator: NSObject {

    /// `true` = keep the existing wallet, `false` = user confirmed delete.
    @objc(presentReinstallKeepOrDeleteChoiceFrom:completion:)
    static func presentReinstallKeepOrDeleteChoice(
        from host: UIViewController,
        completion: @escaping (Bool) -> Void
    ) {
        presentPrimaryAlert(from: host, completion: completion)
    }

    private static func presentPrimaryAlert(
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
                    presentDeleteConfirm(from: host, completion: completion)
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

    private static func presentDeleteConfirm(
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
                    presentPrimaryAlert(from: host, completion: completion)
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
}
