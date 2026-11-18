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

    /// Whether the loaded wallet reads the invitation's voucher as
    /// malformed. Unknown before the wallet is loaded, and then left to
    /// Home's own check.
    static func isMalformedInvitation(_ url: URL) -> Bool {
        #if DASHPAY
        guard let uri = DWInvitationLinkNormalizer.normalize(url.absoluteString),
              let preview = DWInvitationService.shared.preview(for: uri) else { return false }
        return !preview.structurallyValid
        #else
        return false
        #endif
    }

    /// Whether Add Contact can send from this wallet: it needs a DashPay
    /// identity.
    static func hasDashPayIdentity() -> Bool {
        #if DASHPAY
        DWCurrentUserIdentityInfo.shared.identityId != nil
        #else
        false
        #endif
    }

    static func route(_ result: QRScanResult, from presenter: UIViewController?) {
        guard !isWalletLocked() else { return }
        switch result {
        case .payment(let input):
            routePayment(input, from: presenter)

        #if DASHPAY
        case .dashPayUser(let link):
            guard let presenter, hasDashPayIdentity() else { return }
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
    nonisolated static func requiresSendScreen(_ input: DWPaymentInput) -> Bool {
        guard let parsed = input.parsedURI else { return false }
        return parsed.requiresSendScreenRouting && parsed.address != nil
    }

    /// Present the Send screen for a payment scanned in another flow — the
    /// same chrome and layout as `DWBasePayViewController
    /// routeScannedBech32Address:`. Like `dispatchPaymentInput`, a verified
    /// merchant request and a Core destination go to the classic processor
    /// whole, amount in duffs; only a Platform or Shielded destination fills
    /// the form and opens on the From picker.
    static func routePayment(_ input: DWPaymentInput, from presenter: UIViewController?) {
        guard let presenter else { return }

        let controller = SendScreenViewController()
        let navigationController = BaseNavigationController(rootViewController: controller)
        navigationController.isNavigationBarHidden = true
        navigationController.modalPresentationStyle = .fullScreen

        if input.bip70Confirmation != nil || !requiresSendScreen(input) {
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

/// The UIKit controller a SwiftUI screen lives in, so a flow the screen's
/// scanner hands a result to is presented from that screen rather than
/// from whatever the app root shows.
final class QRScanPresenterAnchor {
    fileprivate(set) weak var controller: UIViewController?
}

extension View {
    func qrScanPresenterAnchor(_ anchor: QRScanPresenterAnchor) -> some View {
        background(QRScanPresenterAnchorView(anchor: anchor).frame(width: 0, height: 0))
    }
}

private struct QRScanPresenterAnchorView: UIViewControllerRepresentable {
    let anchor: QRScanPresenterAnchor

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        anchor.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
