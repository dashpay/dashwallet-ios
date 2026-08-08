//
//  AddContactPreviewSheet.swift
//  DashWallet
//
//  Confirmation sheet shown for a candidate contact before the request is sent.
//

import SwiftDashSDK
import SwiftUI
import DashUIKit

struct AddContactPreviewSheet: View {
    let result: DpnsSearchResult
    let collision: AddContactScreen.Collision
    /// The already-materialized contact row when this identity is known
    /// (established / incoming / outgoing); nil for a true stranger.
    let contact: ContactItem?
    let onSend: () -> Void
    let onAccept: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var username: String { result.fullName.withoutDashSuffix }
    private var title: String { contact?.displayTitle ?? username }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                VStack(spacing: 12) {
                    ContactAvatarView(
                        title: title,
                        avatarURL: contact?.avatarURL,
                        identitySeed: result.identityId,
                        size: 88)
                        .padding(.top, 28)
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.dash.primaryText)
                    if username != title {
                        Text(username)
                            .font(.system(size: 14))
                            .foregroundColor(.dash.secondaryText)
                    }
                    if let message = contact?.publicMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundColor(.dash.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 2)
                    }
                    Text(rationale)
                        .font(.system(size: 14))
                        .foregroundColor(.dash.tertiaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 4)
                    Spacer()
                    cta
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Close", comment: "")) { dismiss() }
                        .foregroundColor(.dash.blue)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// State-appropriate framing copy — the persuasive "pay directly by
    /// username, keep a shared history" line the legacy send-request
    /// cell showed, adapted per collision state.
    private var rationale: String {
        switch collision {
        case .none, .alreadyRequested:
            return String(
                format: NSLocalizedString("Add %@ as a contact to pay them directly by username and keep a shared history of your payments.", comment: "DashPay Contacts"),
                username)
        case .theyAskedUs:
            return String(
                format: NSLocalizedString("%@ wants to connect. Accept to pay each other directly by username.", comment: "DashPay Contacts"),
                username)
        case .established:
            return NSLocalizedString("You're already connected — you can pay each other directly by username.", comment: "DashPay Contacts")
        case .isSelf:
            return NSLocalizedString("This is your own identity.", comment: "DashPay Contacts")
        case .missingDashPayKeys:
            return NSLocalizedString("This user hasn't set up the keys needed to receive contact requests yet.", comment: "DashPay Contacts")
        }
    }

    @ViewBuilder
    private var cta: some View {
        switch collision {
        case .none:
            primaryButton(NSLocalizedString("Send Contact Request", comment: "DashPay Contacts"), color: .dash.blue) {
                onSend()
                dismiss()
            }
        case .theyAskedUs:
            primaryButton(NSLocalizedString("Accept", comment: "DashPay Contacts"), color: .dashGreen) {
                onAccept()
                dismiss()
            }
        case .alreadyRequested:
            statusLabel(NSLocalizedString("Contact Request Pending", comment: "DashPay Contacts"), systemImage: "hourglass", color: .dashGolden)
        case .established:
            statusLabel(NSLocalizedString("Already a contact", comment: "DashPay Contacts"), systemImage: "checkmark.circle.fill", color: .dashGreen)
        case .isSelf:
            EmptyView()
        case .missingDashPayKeys:
            statusLabel(NSLocalizedString("Can't receive contact requests", comment: "DashPay Contacts"), systemImage: "lock.slash", color: .dash.tertiaryText)
        }
    }

    private func primaryButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.dash.whiteText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
        }
        .buttonStyle(.plain)
    }

    private func statusLabel(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title).font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }
}
