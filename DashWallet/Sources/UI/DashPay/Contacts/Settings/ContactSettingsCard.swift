//
//  ContactSettingsCard.swift
//  DashWallet
//
//  Alias, note and the hide toggle, as a card for ContactSheet.
//

import SwiftUI
import DashUIKit

/// The last card in ``ContactSheet``, for an established contact.
///
/// Everything here is owner-private: it is published as a self-encrypted
/// DIP-15 `contactInfo` document, so it roams to the owner's other devices
/// and is never readable by the contact. Each write is signed with the
/// identity key, which is why saving goes through the PIN gate.
struct ContactSettingsCard: View {
    @StateObject private var viewModel: ContactSettingsViewModel

    /// Default `nil` rather than a fresh view model: default arguments are
    /// evaluated off the main actor and `ContactSettingsViewModel` is
    /// `@MainActor`. `StateObject`'s autoclosure defers construction to view
    /// installation. Previews pass one in.
    init(contact: ContactItem, viewModel: ContactSettingsViewModel? = nil) {
        _viewModel = StateObject(
            wrappedValue: viewModel ?? ContactSettingsViewModel(contact: contact))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(spacing: 10) {
                TextField(
                    NSLocalizedString("Alias", comment: "DashPay Contacts"),
                    text: $viewModel.aliasText)
                    .dashFont(.subhead)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.dash.primaryBackground)
                    .clipShape(.rect(cornerRadius: 10))
                    .onSubmit { viewModel.save() }

                TextField(
                    NSLocalizedString("Note", comment: "DashPay Contacts"),
                    text: $viewModel.noteText,
                    axis: .vertical)
                    .dashFont(.subhead)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Color.dash.primaryBackground)
                    .clipShape(.rect(cornerRadius: 10))
                    .onSubmit { viewModel.save() }
            }

            // Only while there is something to save: an always-present Save
            // button on a form that writes through the PIN gate invites a
            // prompt for no change.
            if viewModel.metaChanged {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Save", comment: ""),
                    isLoading: viewModel.isSaving,
                    fillsWidth: true,
                    size: .medium,
                    style: .filledBlue,
                    action: { viewModel.save() })
            }

            DashUIKit.DashButton(
                text: viewModel.isHidden
                    ? NSLocalizedString("Unhide Contact", comment: "DashPay Contacts")
                    : NSLocalizedString("Hide Contact", comment: "DashPay Contacts"),
                leadingIcon: .system(viewModel.isHidden ? "eye" : "eye.slash"),
                isEnabled: !viewModel.isSaving,
                fillsWidth: true,
                size: .medium,
                style: .tintedGray,
                action: { viewModel.toggleHidden() })
        }
        .padding(20)
        .background(Color.dash.secondaryBackground)
        .clipShape(.rect(cornerRadius: 20))
        .onAppear { viewModel.onAppear() }
        .alert(
            NSLocalizedString("Error", comment: ""),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } })
        ) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Contact settings", comment: "DashPay Contacts"))
                    .dashFont(.subheadMedium)
                    .foregroundStyle(Color.dash.primaryText)

                Text(NSLocalizedString("Only visible to you", comment: "DashPay Contacts"))
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
            }

            Spacer()

            // The hide toggle writes without a Save button of its own, so
            // without this it would confirm nothing.
            if viewModel.savedToast {
                Text(NSLocalizedString("Saved", comment: ""))
                    .dashFont(.footnoteMedium)
                    .foregroundStyle(Color.dash.green)
                    .transition(.opacity)
            }
        }
    }
}

#if DEBUG

private struct ContactSettingsCardHost: View {
    let viewModel: ContactSettingsViewModel

    var body: some View {
        ContactSettingsCard(contact: .preview(title: "briantest63a"), viewModel: viewModel)
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.dash.primaryBackground)
    }
}

#Preview("Empty") {
    ContactSettingsCardHost(viewModel: .preview())
}

/// Saved values, nothing edited — no Save button.
#Preview("Filled") {
    ContactSettingsCardHost(viewModel: .preview(
        contact: ContactItem.preview(title: "briantest63a"),
        alias: "Brian from the meetup",
        note: "Owes me for the taxi. Pays in DASH, always rounds up."))
}

#Preview("Hidden") {
    ContactSettingsCardHost(viewModel: .preview(isHidden: true))
}

#endif
