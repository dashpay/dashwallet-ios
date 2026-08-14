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
import SwiftDashSDK
import UIKit

@objc(DWWalletDeleteAllConfirmationCoordinator)
final class WalletDeleteAllConfirmationCoordinator: NSObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "wallet-delete-all-confirmation")

    /// Presents the lock-screen warning before the support-assisted wipe flow.
    /// A readable inventory produces exact count-aware copy. If inventory is
    /// empty or unreadable, the user may still continue with a generic warning,
    /// but deletion remains gated by the support acknowledgement phrase.
    @objc(presentFrom:cancelHandler:deleteAllHandler:)
    static func present(
        from host: UIViewController,
        cancelHandler: @escaping () -> Void,
        deleteAllHandler: @escaping () -> Void
    ) {
        do {
            let walletCount = try SwiftDashSDKHost.distinctStoredWalletCount()
            guard walletCount > 0 else {
                presentWithoutVerifiedCount(
                    from: host,
                    cancelHandler: cancelHandler,
                    continueHandler: deleteAllHandler)
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
            presentWithoutVerifiedCount(
                from: host,
                cancelHandler: cancelHandler,
                continueHandler: deleteAllHandler)
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

    private static func presentWithoutVerifiedCount(
        from host: UIViewController,
        cancelHandler: @escaping () -> Void,
        continueHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: NSLocalizedString("Delete All Wallets?", comment: ""),
            message: NSLocalizedString(
                "The number of wallets stored on this device could not be verified. Continuing requires a confirmation phrase provided by Dash Support before any wallet is deleted.",
                comment: ""),
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Cancel", comment: ""),
                style: .cancel,
                handler: { _ in cancelHandler() }))
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Continue", comment: ""),
                style: .destructive,
                handler: { _ in continueHandler() }))
        host.present(alert, animated: true)
    }
}

@objc(DWKeychainWalletRecoveryCoordinator)
final class KeychainWalletRecoveryCoordinator: NSObject {

    /// `true` = keep the stored wallets (or none exist), `false` = continue to
    /// the support-phrase gate. This coordinator never deletes wallets itself.
    @objc(presentReinstallKeepOrDeleteChoiceFrom:completion:)
    static func presentReinstallKeepOrDeleteChoice(
        from host: UIViewController,
        completion: @escaping (Bool) -> Void
    ) {
        do {
            let entries = try SwiftDashSDKHost.strictlyPersistedMnemonics()
            let walletCount = SwiftDashSDKHost.distinctWalletCount(in: entries)
            guard walletCount > 0 else {
                completion(true)
                return
            }
            let storedNetworks = try SwiftDashSDKHost.persistedSDKWalletNetworks(in: entries)
            presentPrimaryAlert(
                from: host,
                walletCount: walletCount,
                storedNetworks: storedNetworks,
                completion: completion)
        } catch {
            presentInventoryReadFailure(from: host, completion: completion)
        }
    }

    private static func presentPrimaryAlert(
        from host: UIViewController,
        walletCount: Int,
        storedNetworks: Set<Network>,
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
                                storedNetworks: storedNetworks,
                                completion: completion)
                        },
                        deleteAllHandler: { completion(false) })
                }))

        alert.addAction(
            UIAlertAction(
                title: keepTitle,
                style: .default,
                handler: { _ in
                    keepWallets(
                        storedNetworks: storedNetworks,
                        completion: completion)
                }))

        host.present(alert, animated: true)
    }

    private static func keepWallets(
        storedNetworks: Set<Network>,
        completion: @escaping (Bool) -> Void
    ) {
        guard storedNetworks.count == 1, let network = storedNetworks.first else {
            completion(true)
            return
        }

        Task { @MainActor in
            let kind: WalletEnvironment.NetworkKind = network == .mainnet ? .mainnet : .testnet
            _ = WalletEnvironment.switchToNetwork(kind)
            completion(true)
        }
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
