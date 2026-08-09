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
    let collision: AddContactViewModel.Collision
    /// The already-materialized contact row when this identity is known
    /// (established / incoming / outgoing); nil for a true stranger.
    let contact: ContactItem?
    /// A send or accept for this identity is in flight. The sheet stays up
    /// while it runs so the button can show progress, and closes itself when
    /// it finishes — see the `onChange` below.
    var isSending: Bool = false
    let onSend: () -> Void
    let onAccept: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var username: String { result.fullName.withoutDashSuffix }
    private var title: String { contact?.displayTitle ?? username }

    /// Self-sizing: the sheet snaps to whatever this content needs, which
    /// varies — a stranger has no public message and no second name line.
    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            showBackButton: .constant(false),
            background: .dash.primaryBackground
        ) {
            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 20) {
                    ContactPreviewHeader(
                        title: title,
                        username: username,
                        avatarURL: contact?.avatarURL,
                        identitySeed: result.identityId,
                        publicMessage: contact?.publicMessage)

                    DashUIKit.DashButton(
                        text: NSLocalizedString("Send", comment: "DashPay Contacts"),
                        leadingIcon: .custom("dash", bundle: .main), // fix here
                        isLoading: isSending,
                        fillsWidth: true,
                        size: .large,
                        style: .filledBlue
                    ) {
                        // Send money
                    }

                    DashUIKit.DashButton(
                        text: NSLocalizedString("Send request", comment: "DashPay Contacts"),
                        isLoading: isSending,
                        fillsWidth: true,
                        size: .large,
                        style: .filledBlue
                    ) {
                        onSend()
                    }

                    Text(NSLocalizedString("Once johndoe accepts your request you can pay directly to the username", comment: "DashPay Contacts"))
                        .dashFont(.caption1)
                        .foregroundStyle(Color.dash.secondaryText)
                        .padding(.trailing, 40)
                }
                .padding(20)
                .background(Color.dash.secondaryBackground)
                .clipShape(.rect(cornerRadius: 20))


                VStack(alignment: .leading, spacing: 20) {

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("janedoe has sent you contact request", comment: "DashPay Contacts"))
                            .dashFont(.subheadMedium)
                            .foregroundStyle(Color.dash.primaryText)

                        Text(NSLocalizedString("If you don’t want janedoe to be in your contact list you can tap the “Ignore” button. They will not be notified about your decision.", comment: "DashPay Contacts"))
                            .dashFont(.footnote)
                            .foregroundStyle(Color.dash.secondaryText)
                    }

                    HStack(spacing: 20) {
                        DashUIKit.DashButton(
                            text: NSLocalizedString("Ignore", comment: "DashPay Contacts"),
                            isLoading: isSending,
                            fillsWidth: true,
                            size: .large,
                            style: .tintedGray
                        ) {

                        }

                        DashUIKit.DashButton(
                            text: NSLocalizedString("Accept", comment: "DashPay Contacts"),
                            isLoading: isSending,
                            fillsWidth: true,
                            size: .large,
                            style: .filledBlue
                        ) {

                        }
                    }
                }
                .padding(20)
                .background(Color.dash.secondaryBackground)
                .clipShape(.rect(cornerRadius: 20))


            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        // Close once the request the user submitted has landed. Dismissing on
        // tap instead would hide the progress the button is there to show.
        .onChange(of: isSending) { wasSending, nowSending in
            if wasSending && !nowSending { dismiss() }
        }
    }
}

#if DEBUG

/// Presented through `.sheet` rather than rendered flat, so the canvas shows
/// the real thing: the bottom sheet over the screen it is raised from, at the
/// height its content actually needs.
private struct AddContactPreviewSheetHost: View {
    let result: DpnsSearchResult
    let collision: AddContactViewModel.Collision
    var contact: ContactItem? = nil
    var isSending: Bool = false
    @State private var isPresented = true

    var body: some View {
        Color.dash.primaryBackground
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
                AddContactPreviewSheet(
                    result: result,
                    collision: collision,
                    contact: contact,
                    isSending: isSending,
                    onSend: {}, onAccept: {})
            }
    }
}

private func previewResult(_ name: String) -> DpnsSearchResult {
    DpnsSearchResult(identityId: Data(name.utf8), fullName: name)
}

// MARK: Can be actioned

#Preview("Stranger") {
    AddContactPreviewSheetHost(result: previewResult("briantest63a"), collision: .none)
}

#Preview("Stranger — sending") {
    AddContactPreviewSheetHost(
        result: previewResult("briantest63a"), collision: .none, isSending: true)
}

#Preview("They asked us") {
    AddContactPreviewSheetHost(
        result: previewResult("s22test63b"),
        collision: .theyAskedUs,
        contact: .preview(title: "s22test63b", relationship: .incoming))
}

#Preview("They asked us — accepting") {
    AddContactPreviewSheetHost(
        result: previewResult("s22test63b"),
        collision: .theyAskedUs,
        contact: .preview(title: "s22test63b", relationship: .incoming),
        isSending: true)
}

// MARK: Nothing to do

#Preview("Already requested") {
    AddContactPreviewSheetHost(
        result: previewResult("Upsilon2"),
        collision: .alreadyRequested,
        contact: .preview(title: "Upsilon2", relationship: .outgoing))
}

#Preview("Already a contact") {
    AddContactPreviewSheetHost(
        result: previewResult("Delta"),
        collision: .established,
        contact: .preview(title: "Delta"))
}

#Preview("Cannot receive requests") {
    AddContactPreviewSheetHost(
        result: previewResult("olduser42"), collision: .missingDashPayKeys)
}

#Preview("This is you") {
    AddContactPreviewSheetHost(result: previewResult("mywallet7"), collision: .isSelf)
}

// MARK: Longest content — the sheet has to grow for it

#Preview("Display name and message") {
    AddContactPreviewSheetHost(
        result: previewResult("briantest63a"),
        collision: .established,
        contact: ContactItem(
            contactIdentityId: Data("briantest63a".utf8),
            relationship: .established,
            username: "briantest63a",
            profileDisplayName: "Brian",
            alias: nil,
            note: nil,
            isHidden: false,
            avatarURL: nil,
            publicMessage: "Building things on Dash Platform. Ping me about contested names, invitations, or anything DashPay.",
            createdAt: Date(timeIntervalSince1970: 1_685_000_000),
            incomingCreatedAt: Date(timeIntervalSince1970: 1_685_000_000),
            outgoingCreatedAt: Date(timeIntervalSince1970: 1_684_000_000)))
}

#endif
