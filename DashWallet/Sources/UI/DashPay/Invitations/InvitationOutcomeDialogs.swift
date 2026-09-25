//
//  InvitationOutcomeDialogs.swift
//  DashWallet
//
//  The dialogs that end a DashPay invitation — Android's `InviteHandler`
//  dialogs and `InviteAlreadyClaimedDialog`. Each is shown once; the
//  invitation is already forgotten by the time it appears.
//

import DashUIKit
import SwiftUI
import UIKit

enum InvitationOutcomeDialogs {

    /// The dialog for an outcome that ended the invitation, or nil when the
    /// outcome needs none.
    @MainActor
    static func controller(for outcome: InvitationValidation) -> UIViewController? {
        switch outcome {
        case .invalid(_, let inviter):
            return invalid(inviter: inviter)
        case .alreadyHasIdentity:
            return alreadyHasIdentity()
        case .alreadyRequestedUsername:
            return alert(
                title: NSLocalizedString("Username already requested", comment: "DashPay Invitations"),
                message: NSLocalizedString("You cannot claim this invite since you have already requested a Dash username", comment: "DashPay Invitations"))
        case .alreadyClaimed(let inviter):
            return alreadyClaimed(inviter: inviter)
        case .valid, .undetermined:
            return nil
        }
    }

    @MainActor
    static func invalid(inviter: InvitationInviter) -> UIViewController {
        alert(
            title: NSLocalizedString("Invalid Invitation", comment: "DashPay Invitations"),
            message: String.localizedStringWithFormat(
                NSLocalizedString("Your invitation from %@ is not valid", comment: ""),
                senderName(inviter)))
    }

    @MainActor
    static func alreadyHasIdentity() -> UIViewController {
        alert(
            title: NSLocalizedString("Username already found", comment: ""),
            message: NSLocalizedString("You cannot claim this invite since you already have a Dash username", comment: ""))
    }

    /// A second invitation arrived while one is pending; the new one is dropped.
    @MainActor
    static func busy() -> UIViewController {
        alert(
            title: NSLocalizedString("Invitation Error", comment: "DashPay Invitations"),
            message: NSLocalizedString("DashPay is currently processing an invite.", comment: "DashPay Invitations"))
    }

    /// A valid invitation that could not be saved on this device.
    @MainActor
    static func storageFailed() -> UIViewController {
        alert(
            title: NSLocalizedString("Invitation Error", comment: "DashPay Invitations"),
            message: NSLocalizedString("The invitation couldn't be saved on this device. Open the link again to retry.", comment: "DashPay Invitations"))
    }

    /// The opened link or scanned code is not an invitation.
    @MainActor
    static func notAnInvitation() -> UIViewController {
        alert(
            title: NSLocalizedString("Invalid Invitation", comment: "DashPay Invitations"),
            message: NSLocalizedString("This is not a valid invitation link", comment: ""))
    }

    @MainActor
    static func alreadyClaimed(inviter: InvitationInviter) -> UIViewController {
        let host = UIHostingController(rootView: InvitationAlreadyClaimedDialog(inviter: inviter))
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = .clear
        return host
    }

    /// Display name, then username; "DashPay" when the link named nobody,
    /// so the sentence still reads.
    static func senderName(_ inviter: InvitationInviter) -> String {
        inviter.bestName ?? "DashPay"
    }

    @MainActor
    private static func alert(title: String, message: String) -> UIViewController {
        DPAlertViewController(
            icon: UIImage(named: "icon_invitation_error")!,
            title: title,
            description: message)
    }
}

/// Android's `InviteAlreadyClaimedDialog`: the inviter in a red "error"
/// frame, no title, the sender named in bold, OK.
///
/// The frame shows the initials placeholder, never the link's `avatar-url`:
/// that URL is whatever the link's author put there, unauthenticated, and
/// fetching it would tell a tracking server when the recipient opened the
/// link.
struct InvitationAlreadyClaimedDialog: View {
    let inviter: InvitationInviter
    @Environment(\.dismiss) private var dismiss

    private var message: AttributedString {
        let name = InvitationOutcomeDialogs.senderName(inviter)
        let format = NSLocalizedString("Your invitation from %@ has been already claimed", comment: "")
        let parts = format.components(separatedBy: "%@")
        guard parts.count == 2 else {
            return AttributedString(String(format: format, name))
        }
        var bold = AttributedString(name)
        bold.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString(parts[0]) + bold + AttributedString(parts[1])
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack(alignment: .bottomTrailing) {
                    ContactAvatarView(
                        title: inviter.bestName ?? "",
                        avatarURL: nil,
                        identitySeed: Data((inviter.username ?? "").utf8),
                        size: 72)
                        .overlay(Circle().stroke(Color.dash.red, lineWidth: 3))

                    Image("icon_invitation_error")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }

                Text(message)
                    .dashFont(.body)
                    .foregroundColor(Color.dash.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                DashUIKit.DashButton(
                    text: NSLocalizedString("OK", comment: ""),
                    fillsWidth: true,
                    size: .medium,
                    style: .filledBlue,
                    action: { dismiss() })
            }
            .padding(24)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 40)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(NSLocalizedString("Invitation already claimed", comment: ""))
        }
    }
}
