//
//  InvitationEntry.swift
//  DashWallet
//
//  The one way an invitation gets in: an opened link (root controller) or a
//  scanned invitation QR (Join DashPay sheet). Both store it and leave the
//  rest to the Home card; nothing is previewed or typed.
//

import UIKit

@objc(DWInvitationEntry)
@MainActor
final class InvitationEntry: NSObject {

    /// Store an opened link. Returns whether Home should be brought forward
    /// to show the card. Dialogs for a link that was not stored are presented
    /// on `presenter`; with no presenter (no wallet yet) nothing is shown.
    @objc
    @discardableResult
    static func receive(_ url: URL, presenter: UIViewController?) -> Bool {
        handle(PendingInvitationStore.shared.receive(url), presenter: presenter)
    }

    /// Move an invitation opened before the wallet existed under the new
    /// wallet.
    @objc
    static func walletSetupDidFinish() {
        PendingInvitationStore.shared.bindUnboundToCurrentWallet()
    }

    /// Present the invitation QR scanner; a scanned invitation goes through
    /// the same store as an opened link.
    static func presentScanner(from presenter: UIViewController, onStored: @escaping () -> Void) {
        let scanner = GenericQRScannerController()
        scanner.modalPresentationStyle = .fullScreen
        scanner.onCancel = { [weak scanner] in
            scanner?.dismiss(animated: true)
        }
        scanner.onQRCodeScanned = { [weak scanner, weak presenter] value in
            guard let scanner else { return }
            // One code per scan: the camera keeps reporting while the
            // dismissal animates.
            scanner.onQRCodeScanned = nil
            scanner.dismiss(animated: true) {
                let outcome = PendingInvitationStore.shared.receive(value)
                if handle(outcome, presenter: presenter) {
                    onStored()
                }
            }
        }
        presenter.present(scanner, animated: true)
    }

    /// Present the dialog an outcome needs; true when the invitation is (or
    /// already was) stored.
    private static func handle(_ outcome: PendingInvitationStore.ReceiveOutcome,
                               presenter: UIViewController?) -> Bool {
        let dialog: UIViewController?
        switch outcome {
        case .stored, .duplicate:
            return true
        case .busy:
            dialog = InvitationOutcomeDialogs.busy()
        case .notAnInvitation:
            dialog = InvitationOutcomeDialogs.notAnInvitation()
        case .alreadyHasIdentity:
            dialog = InvitationOutcomeDialogs.alreadyHasIdentity()
        }
        if let dialog, let presenter {
            topmost(from: presenter).present(dialog, animated: true)
        }
        return false
    }

    private static func topmost(from controller: UIViewController) -> UIViewController {
        var top = controller
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
