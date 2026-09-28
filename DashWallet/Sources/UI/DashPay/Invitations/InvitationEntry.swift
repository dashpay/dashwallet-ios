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

    /// The wallet exists now: an invitation opened before it moves under it
    /// (the store retries that on every reload, so a failure here is not
    /// final).
    @objc
    static func walletSetupDidFinish() {
        PendingInvitationStore.shared.reload()
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
    /// An explanation owed for a link taken while nothing could show it
    /// (locked, onboarding). Holds the outcome only, never the link.
    private static var heldNotice = InvitationReceiptNotice()

    private static func handle(_ outcome: PendingInvitationStore.ReceiveOutcome,
                               presenter: UIViewController?) -> Bool {
        guard let presenter else {
            heldNotice.hold(outcome)
            return InvitationReceiptNotice.isStored(outcome)
        }
        if let dialog = dialog(for: outcome) {
            topmost(from: presenter).present(dialog, animated: true)
        }
        return InvitationReceiptNotice.isStored(outcome)
    }

    /// Show an explanation held while locked or onboarding, if any.
    @objc
    static func presentHeldNotice(from presenter: UIViewController) {
        guard let outcome = heldNotice.take(), let dialog = dialog(for: outcome) else { return }
        topmost(from: presenter).present(dialog, animated: true)
    }

    /// A wipe: nothing received before it is explained after it.
    @objc
    static func discardHeldNotice() {
        heldNotice.discard()
    }

    private static func dialog(for outcome: PendingInvitationStore.ReceiveOutcome) -> UIViewController? {
        switch outcome {
        case .stored, .duplicate, .suspended:
            // Stored: the card is the answer. Suspended: the wipe's own
            // screen is up; the link is simply not taken.
            return nil
        case .busy:
            return InvitationOutcomeDialogs.busy()
        case .notAnInvitation:
            return InvitationOutcomeDialogs.notAnInvitation()
        case .alreadyHasIdentity:
            return InvitationOutcomeDialogs.alreadyHasIdentity()
        case .storageFailed:
            return InvitationOutcomeDialogs.storageFailed()
        }
    }

    private static func topmost(from controller: UIViewController) -> UIViewController {
        var top = controller
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// The explanation owed for an invitation link taken while nothing could
/// present it. Pure, so the decision is unit-testable; holds the outcome
/// only — the link carries the voucher key and is never kept.
struct InvitationReceiptNotice {
    private(set) var outcome: PendingInvitationStore.ReceiveOutcome?

    /// The link ended up stored (or already was): its card is the answer.
    static func isStored(_ outcome: PendingInvitationStore.ReceiveOutcome) -> Bool {
        outcome == .stored || outcome == .duplicate
    }

    /// Whether the outcome needs telling at all.
    static func needsExplanation(_ outcome: PendingInvitationStore.ReceiveOutcome) -> Bool {
        switch outcome {
        case .busy, .notAnInvitation, .alreadyHasIdentity, .storageFailed: return true
        case .stored, .duplicate, .suspended: return false
        }
    }

    /// Keep the latest outcome that needs explaining; a later successful
    /// receipt makes an earlier refusal moot.
    mutating func hold(_ outcome: PendingInvitationStore.ReceiveOutcome) {
        if Self.needsExplanation(outcome) {
            self.outcome = outcome
        } else if Self.isStored(outcome) {
            self.outcome = nil
        }
    }

    mutating func take() -> PendingInvitationStore.ReceiveOutcome? {
        defer { outcome = nil }
        return outcome
    }

    mutating func discard() {
        outcome = nil
    }
}
