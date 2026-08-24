//
//  KeychainWalletRecoveryCoordinator.swift
//  DashWallet
//
//  Post-reinstall "Wallets found on this device" prompt. SDK Keychain entries
//  survive app reinstall, so this coordinator inventories every stored SDK seed
//  before allowing onboarding to keep them or explicitly delete all wallet data.
//

import Foundation
import SwiftDashSDK
import UIKit

@objc(DWWalletDeleteAllConfirmationCoordinator)
final class WalletDeleteAllConfirmationCoordinator: NSObject {
    /// Presents the lock-screen warning before the support-assisted wipe flow.
    /// Copy is intentionally count-free because the destructive operation also
    /// removes legacy DashSync seeds that are not necessarily present in the
    /// SDK inventory. Deletion remains gated by the support acknowledgement.
    @objc(presentFrom:cancelHandler:deleteAllHandler:)
    static func present(
        from host: UIViewController,
        cancelHandler: @escaping () -> Void,
        deleteAllHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: NSLocalizedString("Delete All Wallets?", comment: ""),
            message: NSLocalizedString(
                "This permanently removes all wallets, private keys, and recovery phrases stored by this app on this device. They can only be restored from backups. This cannot be undone.",
                comment: ""),
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Cancel", comment: ""),
                style: .cancel,
                handler: { _ in cancelHandler() }))
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Delete All", comment: ""),
                style: .destructive,
                handler: { _ in deleteAllHandler() }))
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
            guard SwiftDashSDKHost.distinctWalletCount(in: entries) > 0 else {
                completion(true)
                return
            }
            let storedNetworks = try SwiftDashSDKHost.persistedSDKWalletNetworks(in: entries)
            presentPrimaryAlert(
                from: host,
                storedNetworks: storedNetworks,
                completion: completion)
        } catch {
            presentInventoryReadFailure(from: host, completion: completion)
        }
    }

    private static func presentPrimaryAlert(
        from host: UIViewController,
        storedNetworks: Set<Network>,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: NSLocalizedString("Wallets found on this device", comment: ""),
            message: NSLocalizedString(
                "Wallet data from a previous installation is still stored on this device. Keep using these wallets, or delete all wallet data and start fresh? Make sure every recovery phrase is backed up before deleting.",
                comment: ""),
            preferredStyle: .alert)

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Delete All", comment: ""),
                style: .destructive,
                handler: { _ in
                    WalletDeleteAllConfirmationCoordinator.present(
                        from: host,
                        cancelHandler: {
                            presentPrimaryAlert(
                                from: host,
                                storedNetworks: storedNetworks,
                                completion: completion)
                        },
                        deleteAllHandler: { completion(false) })
                }))

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Keep Wallets", comment: ""),
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
