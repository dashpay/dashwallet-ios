//
//  SendToContactScreen.swift
//  DashWallet
//
//  "Send to username", step one: pick an established DashPay contact. Step
//  two is the ordinary `ExternalSendAmountScreen` — the picker sets the
//  contact on a `SendViewModel` and pushes it, so a contact is a destination
//  of the standard send flow rather than a parallel screen of its own.
//

#if DASHPAY

import DashUIKit
import SwiftUI

struct SendToContactPickerScreen: View {
    @ObservedObject var viewModel: SendToContactPickerViewModel
    /// Pop back to the payments landing.
    var onBack: () -> Void
    /// A contact was chosen → push the amount step.
    var onSelect: (ContactItem) -> Void

    @State private var showingAddContact = false

    var body: some View {
        VStack(spacing: 0) {
            SendToContactHeader(onBack: onBack)

            if viewModel.hasNoContacts {
                emptyState
            } else {
                list
            }
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .sheet(isPresented: $showingAddContact) {
            AddContactScreen(initialQuery: "")
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ContactsSearchField(
                    placeholder: NSLocalizedString("Search Contacts", comment: "DashPay Contacts"),
                    text: $viewModel.searchText)
                    .padding(.horizontal, 15)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if viewModel.visibleContacts.isEmpty {
                    noMatchesNote
                } else {
                    ForEach(viewModel.visibleContacts) { item in
                        contactRow(item)
                    }
                }

                Spacer(minLength: 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// A contact whose DIP-15 payment channel is permanently broken is listed
    /// but not selectable: every send on it would fail, and the flag only
    /// clears when the CONTACT sends a fresh request. Dropping the row instead
    /// would read as the person having disappeared from the wallet.
    private func contactRow(_ item: ContactItem) -> some View {
        ContactsCard {
            VStack(alignment: .leading, spacing: 0) {
                ContactRow(item: item)
                if item.paymentChannelBroken {
                    // Same sentence the amount step shows if the flag arrives
                    // after a contact is already open.
                    Text(SendViewModel.contactPaymentsUnavailableMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.dashGolden)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 17)
                        .padding(.bottom, 12)
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 3)
        .opacity(item.paymentChannelBroken ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !item.paymentChannelBroken else { return }
            onSelect(item)
        }
        // A stack with a tap gesture is invisible to VoiceOver: it needs the
        // button trait and one combined label. A broken payment channel loses
        // the trait along with the tap it already refuses.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.paymentChannelBroken ? [] : .isButton)
    }

    private var noMatchesNote: some View {
        Text(String.localizedStringWithFormat(
            NSLocalizedString("No contacts match “%@”", comment: "DashPay: contact picker search found nothing"),
            viewModel.trimmedSearchText))
            .font(.system(size: 14))
            .foregroundColor(.dash.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
    }

    // MARK: - Empty state

    /// No established contacts at all. Paying a username needs a mutual
    /// friendship, so the only useful action here is finding someone to ask.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 72, weight: .light))
                .foregroundColor(.dash.blue)
                .padding(.bottom, 12)
            Text(NSLocalizedString("No contacts yet", comment: "DashPay: contact picker empty state headline"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.dash.primaryText)
            Text(NSLocalizedString(
                "Add someone as a contact and you can pay them by username instead of an address.",
                comment: "DashPay: contact picker empty state body"))
                .font(.system(size: 16))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            Button {
                showingAddContact = true
            } label: {
                Label(
                    NSLocalizedString("Search for a User", comment: "DashPay Contacts"),
                    systemImage: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.dash.blue))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.top, 18)
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Shared chrome

/// Back-chevron + "Send" title. The design system's bar rather than the UIKit
/// one, so the glyph and its ring are the `navigationbar-*` assets — the same
/// chrome the address-send steps draw.
private struct SendToContactHeader: View {
    var onBack: () -> Void

    var body: some View {
        DashUIKit.NavigationBar(
            leading: {
                DashUIKit.NavigationBarElement.back.button(action: onBack)
            },
            central: {
                Text(NSLocalizedString("Send", comment: ""))
                    .dashFont(.subheadMedium)
                    .foregroundColor(Color.dash.primaryText)
            })
    }
}

#endif
