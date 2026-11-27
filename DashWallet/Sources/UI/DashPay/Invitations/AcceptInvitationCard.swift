//
//  AcceptInvitationCard.swift
//  DashWallet
//
//  The Home card for a DashPay invitation waiting to be accepted — Android's
//  `accept_invitation_row`: Join DashPay, Hide / Create, and a hint while the
//  invitation cannot be used yet.
//

import DashUIKit
import SwiftUI

struct AcceptInvitationCard: View {
    @ObservedObject var viewModel: PendingInvitationViewModel
    var isSyncing: Bool
    /// The invitation and what its voucher funds.
    var onCreate: (PendingInvitation, UInt64) -> Void
    /// Opens the ordinary registration form, which finishes a paid
    /// registration without the invitation.
    var onFinishRegistration: () -> Void

    private var isCreateEnabled: Bool {
        if case .valid = viewModel.cardState { return !isSyncing }
        return false
    }

    private var isGreyedOut: Bool {
        isSyncing || viewModel.cardState == .syncing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(dash: isGreyedOut
                    ? .custom("menu-send-account-disabled", bundle: .dashUIKit)
                    : .custom("dp_user_generic", bundle: .main))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Join DashPay", comment: ""))
                        .dashFont(.subheadMedium)
                        .foregroundColor(isGreyedOut ? Color.dash.secondaryText : Color.dash.primaryText)
                    Text(String(localized: "Create a username and say goodbye to numerical addresses", comment: "DashPay Invitations"))
                        .dashFont(.footnote)
                        .foregroundColor(isGreyedOut ? Color.dash.tertiaryText : Color.dash.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                DashUIKit.DashButton(
                    text: String(localized: "Hide", comment: ""),
                    fillsWidth: true,
                    size: .small,
                    style: .tintedGray,
                    action: { viewModel.hide() })

                DashUIKit.DashButton(
                    text: String(localized: "Create", comment: "DashPay Invitations"),
                    isEnabled: isCreateEnabled,
                    isLoading: viewModel.cardState == .verifying && !isSyncing,
                    fillsWidth: true,
                    size: .small,
                    style: .filledBlue,
                    action: { viewModel.create(proceed: onCreate) })
            }

            hint
        }
        .padding(10)
        .modifier(MenuViewModifier())
    }

    @ViewBuilder
    private var hint: some View {
        if isSyncing || viewModel.cardState == .syncing {
            hintText(String(localized: "Wait until syncing is finished to create a username", comment: "DashPay Invitations"))
        } else {
            switch viewModel.cardState {
            case .verifying:
                hintText(String(localized: "Verifying invitation", comment: "DashPay Invitations"))
            case .undetermined:
                hintWithRetry(String(localized: "Couldn't verify the invitation. Check your connection and try again.", comment: "DashPay Invitations"))
            case .awaitingChainLock:
                hintWithRetry(String(localized: "The invitation is still confirming on the network. Try again in a few minutes.", comment: "DashPay Invitations"))
            case .pendingPaidRegistration:
                hintWithAction(
                    String(localized: "This wallet has a paid registration that hasn't finished yet. Finish it first; the invitation can't be used for it.", comment: "DashPay Invitations"),
                    action: String(localized: "Finish registration", comment: "DashPay registration recovery"),
                    perform: onFinishRegistration)
            case .ownClaimNotLoaded:
                hintWithRetry(String(localized: """
                    This wallet already claimed this invitation, but its identity isn't loaded. Turn on Advanced mode in Settings, open More › Identities and tap Find identities, then try again.
                    """, comment: "DashPay Invitations"))
            case .syncing, .valid:
                EmptyView()
            }
        }
    }

    private func hintWithRetry(_ text: String) -> some View {
        hintWithAction(text, action: String(localized: "Retry", comment: ""), perform: { viewModel.retry() })
    }

    private func hintWithAction(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            hintText(text)
            DashUIKit.DashButton(
                text: action,
                size: .extraSmall,
                style: .tintedBlue,
                action: perform)
        }
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .dashFont(.caption1)
            .foregroundColor(Color.dash.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }
}
