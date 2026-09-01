//
//  QRScanResultRouter.swift
//  DashWallet
//
//  Takes a finished scan whose payload belongs to another flow to that
//  flow: payment → Send screen prefilled, contact QR → add-contact
//  verification, invitation → the claim deeplink path (with its
//  wallet/identity/sync gating in HomeViewController).
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

    static func route(_ result: QRScanResult, from presenter: UIViewController?) {
        switch result {
        case .payment(let input):
            routePayment(input, from: presenter)

        #if DASHPAY
        case .dashPayUser(let link):
            guard let presenter else { return }
            let hosting = UIHostingController(rootView: AddContactScreen(scannedLink: link))
            presenter.topController().present(hosting, animated: true)

        case .invitation(let url):
            // The tab controller's deeplink path reuses the invitation
            // gating (existing identity, sync progress) in
            // HomeViewController.handleDeeplink.
            mainTabbar(near: presenter)?.handleDeeplink(url, definedUsername: nil)
        #endif

        case .text:
            break
        }
    }

    /// Present the Send screen prefilled — same chrome as
    /// `DWBasePayViewController routeScannedBech32Address:`. Only
    /// address-carrying intents are routable here; the scanner never
    /// offers a redirect for BIP70-only payloads.
    private static func routePayment(_ input: DWPaymentInput, from presenter: UIViewController?) {
        guard let presenter,
              let parsed = input.parsedURI,
              let address = parsed.address else { return }

        let controller = SendScreenViewController()
        controller.prefill(address: address, amountDuffs: parsed.amount)
        let navigationController = BaseNavigationController(rootViewController: controller)
        navigationController.isNavigationBarHidden = true
        navigationController.modalPresentationStyle = .fullScreen
        presenter.topController().present(navigationController, animated: true)
    }

    #if DASHPAY
    private static func mainTabbar(near presenter: UIViewController?) -> MainTabbarController? {
        var current = presenter
        while let controller = current {
            if let tabbar = controller as? MainTabbarController {
                return tabbar
            }
            if let tabbar = controller.tabBarController as? MainTabbarController {
                return tabbar
            }
            current = controller.presentingViewController ?? controller.parent
        }
        // SwiftUI sheets can be presented from a detached hierarchy;
        // fall back to the app's root.
        var candidate = appRootController
        while let controller = candidate {
            if let tabbar = controller as? MainTabbarController {
                return tabbar
            }
            candidate = controller.presentedViewController ?? controller.children.first
        }
        return nil
    }
    #endif
}
