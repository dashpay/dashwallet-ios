//
//  QRScanResultRouter.swift
//  DashWallet
//
//  Takes a finished scan whose payload belongs to another flow to that
//  flow: payment → Send screen prefilled, contact QR → add-contact
//  verification, invitation → stored through InvitationEntry like an
//  opened link, with Home's Join DashPay card brought forward.
//

import SwiftUI
import UIKit

@MainActor
enum QRScanResultRouter {

    /// Route from wherever the user currently is; used by SwiftUI call
    /// sites that have no view controller at hand. SwiftUI sheet
    /// dismissal has no completion callback, so the presentation is
    /// deferred a beat to let the scanner sheet finish tearing down.
    static func route(_ result: QRScanResult) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            route(result, from: appRootController?.topController())
        }
    }

    private static var appRootController: UIViewController? {
        UIApplication.shared.delegate?.window??.rootViewController
    }

    /// Whether the wallet is behind its lock screen. Every scanner reads it
    /// before letting a scan leave its flow, and `route` refuses outright
    /// while it holds: a screen opened from the lock screen (Scan to Pay →
    /// Send) has its own scanner, and nothing it scans may navigate the
    /// app behind the lock.
    static func isWalletLocked() -> Bool {
        WalletLifecycleOverlayPresenter.shared.lockScreenVisible
    }

    static func route(_ result: QRScanResult, from presenter: UIViewController?) {
        guard !isWalletLocked() else { return }
        switch result {
        case .payment(let input):
            routePayment(input, from: presenter)

        #if DASHPAY
        case .dashPayUser(let link):
            guard let presenter else { return }
            let hosting = UIHostingController(rootView: AddContactScreen(scannedLink: link))
            presenter.topController().present(hosting, animated: true)

        case .invitation(let url):
            // The same entry an opened invitation link takes: store it for
            // this wallet and bring Home, where its card is, forward.
            if InvitationEntry.receive(url, presenter: presenter) {
                mainTabbar()?.showHomeForInvitation()
            }
        #endif

        case .text:
            break
        }
    }

    /// Whether a payment input has to open the Send screen: a bech32m
    /// Platform or Shielded destination can't ride the classic payment
    /// processor. The same rule `DWBasePayViewController
    /// didScanPaymentInput:` applies to its own scans.
    static func requiresSendScreen(_ input: DWPaymentInput) -> Bool {
        guard let parsed = input.parsedURI else { return false }
        return parsed.requiresSendScreenRouting && parsed.address != nil
    }

    /// Present the Send screen for a payment scanned in another flow — the
    /// same chrome and layout as `DWBasePayViewController
    /// routeScannedBech32Address:`. A verified merchant request goes to the
    /// classic processor whole (its outputs and acknowledgment metadata are
    /// the merchant's); anything else fills the form like a scan made on the
    /// Send screen, amount included, and opens on the From picker. The amount
    /// rides the shared view model to the amount step, which hands it to the
    /// classic processor for a Core → Core send.
    static func routePayment(_ input: DWPaymentInput, from presenter: UIViewController?) {
        guard let presenter else { return }

        let controller = SendScreenViewController()
        let navigationController = BaseNavigationController(rootViewController: controller)
        navigationController.isNavigationBarHidden = true
        navigationController.modalPresentationStyle = .fullScreen

        if input.bip70Confirmation != nil {
            // Wait for a visible anchor before presenting the confirmation.
            presenter.topController().present(navigationController, animated: true) {
                controller.processPaymentInput(input)
            }
            return
        }

        guard SendViewModel.scannedAddress(in: input) != nil else { return }
        controller.prefill(scannedInput: input)
        // An address that did not decode keeps the address step: it is the
        // screen that says so.
        if controller.hasResolvedDestination {
            navigationController.setViewControllers([controller, controller.makeSourceStep()], animated: false)
        }
        presenter.topController().present(navigationController, animated: true)
    }

    #if DASHPAY
    /// The app's tab controller, searched down from the window's root
    /// through children and presentations alike. Walking up from the
    /// presenter misses it whenever the scan came from a sheet presented
    /// by a root-level container, and following only the presented branch
    /// misses it whenever that container is presenting a modal.
    private static func mainTabbar() -> MainTabbarController? {
        appRootController?.dw_firstTabBarController() as? MainTabbarController
    }
    #endif
}
