//
//  KeychainWalletRecoveryCoordinator.swift
//  DashWallet
//
//  Post-reinstall "Wallets found on this device" prompt. SDK Keychain entries
//  survive app reinstall, so this coordinator inventories every stored seed
//  before allowing onboarding to keep them or explicitly delete all of them.
//

import Foundation
import OSLog
import UIKit

@objc(DWWalletDeleteAllConfirmationCoordinator)
final class WalletDeleteAllConfirmationCoordinator: NSObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "wallet-delete-all-confirmation")

    /// Presents the lock-screen delete-all confirmation after first obtaining
    /// a complete, strict inventory. An unreadable or empty inventory never
    /// produces a destructive action.
    @objc(presentFrom:cancelHandler:deleteAllHandler:)
    static func present(
        from host: UIViewController,
        cancelHandler: @escaping () -> Void,
        deleteAllHandler: @escaping () -> Void
    ) {
        do {
            let walletCount = try SwiftDashSDKHost.distinctStoredWalletCount()
            guard walletCount > 0 else {
                presentEmptyInventory(from: host, completion: cancelHandler)
                return
            }
            present(
                from: host,
                walletCount: walletCount,
                cancelHandler: cancelHandler,
                deleteAllHandler: deleteAllHandler)
        } catch {
            logger.error(
                "failed to inventory wallets for delete-all confirmation: \(String(describing: error), privacy: .public)")
            presentReadFailure(
                from: host,
                cancelHandler: cancelHandler,
                retryHandler: {
                    present(
                        from: host,
                        cancelHandler: cancelHandler,
                        deleteAllHandler: deleteAllHandler)
                })
        }
    }

    static func present(
        from host: UIViewController,
        walletCount: Int,
        cancelHandler: @escaping () -> Void,
        deleteAllHandler: @escaping () -> Void
    ) {
        precondition(walletCount > 0)

        let title: String
        let message: String
        let destructiveTitle: String
        if walletCount == 1 {
            title = NSLocalizedString("Delete Wallet?", comment: "")
            message = NSLocalizedString(
                "This permanently removes the wallet, private keys, and recovery phrase from this device. This cannot be undone.",
                comment: "")
            destructiveTitle = NSLocalizedString("Delete", comment: "")
        } else {
            title = NSLocalizedString("Delete All Wallets?", comment: "")
            message = String(
                format: NSLocalizedString(
                    "This will erase all %ld wallets stored on this device. They can only be restored with their recovery phrases. Deleting them from this device cannot be undone.",
                    comment: ""),
                walletCount)
            destructiveTitle = NSLocalizedString("Delete All", comment: "")
        }

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Cancel", comment: ""),
                style: .cancel,
                handler: { _ in cancelHandler() }))
        alert.addAction(
            UIAlertAction(
                title: destructiveTitle,
                style: .destructive,
                handler: { _ in deleteAllHandler() }))
        host.present(alert, animated: true)
    }

    private static func presentReadFailure(
        from host: UIViewController,
        cancelHandler: @escaping () -> Void,
        retryHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: NSLocalizedString("Couldn’t Read Wallets", comment: ""),
            message: NSLocalizedString(
                "The wallets stored on this device could not be verified. Nothing was deleted. Please try again.",
                comment: ""),
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Cancel", comment: ""),
                style: .cancel,
                handler: { _ in cancelHandler() }))
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Retry", comment: ""),
                style: .default,
                handler: { _ in retryHandler() }))
        host.present(alert, animated: true)
    }

    private static func presentEmptyInventory(
        from host: UIViewController,
        completion: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: NSLocalizedString("No Wallets Found", comment: ""),
            message: NSLocalizedString("No stored wallets were found. Nothing was deleted.", comment: ""),
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("OK", comment: ""),
                style: .default,
                handler: { _ in completion() }))
        host.present(alert, animated: true)
    }
}

@objc(DWKeychainWalletRecoveryCoordinator)
final class KeychainWalletRecoveryCoordinator: NSObject {

    /// `true` = keep the stored wallets (or none exist), `false` = the user
    /// explicitly confirmed Delete All.
    @objc(presentReinstallKeepOrDeleteChoiceFrom:completion:)
    static func presentReinstallKeepOrDeleteChoice(
        from host: UIViewController,
        completion: @escaping (Bool) -> Void
    ) {
        do {
            let walletCount = try SwiftDashSDKHost.distinctStoredWalletCount()
            guard walletCount > 0 else {
                completion(true)
                return
            }
            presentPrimaryAlert(
                from: host,
                walletCount: walletCount,
                completion: completion)
        } catch {
            presentInventoryReadFailure(from: host, completion: completion)
        }
    }

    private static func presentPrimaryAlert(
        from host: UIViewController,
        walletCount: Int,
        completion: @escaping (Bool) -> Void
    ) {
        let title: String
        let message: String
        let deleteTitle: String
        let keepTitle: String
        if walletCount == 1 {
            title = NSLocalizedString("Wallet found on this device", comment: "")
            message = NSLocalizedString(
                "A wallet from a previous installation is still stored on this device. Keep using it, or delete it and start fresh? Make sure your recovery phrase is backed up before deleting.",
                comment: "")
            deleteTitle = NSLocalizedString("Delete", comment: "")
            keepTitle = NSLocalizedString("Keep Wallet", comment: "")
        } else {
            title = String(
                format: NSLocalizedString("%ld wallets found on this device", comment: ""),
                walletCount)
            message = String(
                format: NSLocalizedString(
                    "%ld wallets from a previous installation are stored on this device. Delete All removes every wallet. Back up every recovery phrase before deleting.",
                    comment: ""),
                walletCount)
            deleteTitle = NSLocalizedString("Delete All", comment: "")
            keepTitle = NSLocalizedString("Keep Wallets", comment: "")
        }

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert)

        alert.addAction(
            UIAlertAction(
                title: deleteTitle,
                style: .destructive,
                handler: { _ in
                    WalletDeleteAllConfirmationCoordinator.present(
                        from: host,
                        walletCount: walletCount,
                        cancelHandler: {
                            presentPrimaryAlert(
                                from: host,
                                walletCount: walletCount,
                                completion: completion)
                        },
                        deleteAllHandler: { completion(false) })
                }))

        alert.addAction(
            UIAlertAction(
                title: keepTitle,
                style: .default,
                handler: { _ in
                    completion(true)
                }))

        host.present(alert, animated: true)
    }

    private static func presentInventoryReadFailure(
        from host: UIViewController,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: NSLocalizedString("Couldn’t Read Wallets", comment: ""),
            message: NSLocalizedString(
                "The wallets stored on this device could not be verified. Nothing was deleted. Please try again.",
                comment: ""),
            preferredStyle: .alert)

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Keep Wallets", comment: ""),
                style: .cancel,
                handler: { _ in completion(true) }))

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Retry", comment: ""),
                style: .default,
                handler: { _ in
                    presentReinstallKeepOrDeleteChoice(
                        from: host,
                        completion: completion)
                }))

        host.present(alert, animated: true)
    }
}
