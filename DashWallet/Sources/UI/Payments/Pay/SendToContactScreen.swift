//
//  SendToContactScreen.swift
//  DashWallet
//
//  "Send to username", split across two pushed steps. Step one
//  (`SendToContactPickerScreen`) picks an established DashPay contact; step
//  two (`SendToContactAmountScreen`) takes the amount and spends through
//  `WalletSendService.sendToContact`, which derives the contact's DIP-15
//  receive address Rust-side and broadcasts atomically.
//

#if DASHPAY

import DashUIKit
import SwiftUI

// MARK: - Step 1: contact picker

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
                    Text(NSLocalizedString(
                        "Payments unavailable — ask them to send you a new contact request.",
                        comment: "DashPay: contact whose payment channel could not be built"))
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

// MARK: - Step 2: amount

struct SendToContactAmountScreen: View {
    @ObservedObject var viewModel: SendToContactAmountViewModel
    /// Pop back to the contact picker.
    var onBack: () -> Void
    /// Send tapped — the host runs the spend and presents the success screen.
    var onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SendToContactHeader(onBack: onBack)

            ScrollView {
                VStack(spacing: 14) {
                    contactSummary
                        .padding(.top, 12)

                    sourceCard

                    amountRow
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                    if let message = viewModel.amountValidationMessage {
                        TransferAmountValidationNote(message: message)
                            .padding(.horizontal, 20)
                    }

                    if let message = viewModel.errorMessage {
                        TransferAmountValidationNote(message: message)
                            .padding(.horizontal, 20)
                    }

                    if viewModel.isBlockedBySync {
                        SyncGateNote()
                            .padding(.horizontal, 20)
                    }

                    feeNote
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            keyboardSection
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - Recipient

    /// Who is being paid, read-only. Tapping goes back to the picker, which is
    /// where a different contact is chosen.
    private var contactSummary: some View {
        let contact = viewModel.contact
        return Button(action: onBack) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("To", comment: ""))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
                HStack(spacing: 10) {
                    ContactAvatarView(
                        title: contact.displayTitle,
                        avatarURL: contact.avatarURL,
                        identitySeed: contact.contactIdentityId)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color.dash.primaryText)
                            .lineLimit(1)
                        if let username = contact.username?.withoutDashSuffix,
                           !username.isEmpty,
                           username != contact.displayTitle {
                            Text(username)
                                .font(.system(size: 12))
                                .foregroundColor(Color.dash.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.dash.secondaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.dash.secondaryBackground)
                .cornerRadius(10)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - Source

    /// The funding balance, fixed rather than picked. A contact payment is
    /// derived and signed Rust-side from the transparent account, so there is
    /// no other balance that could pay it.
    private var sourceCard: some View {
        TransferSourceRow(
            iconSystemName: "d.circle.fill",
            caption: NSLocalizedString("From", comment: ""),
            title: viewModel.sourceTitle,
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(viewModel.coreBalanceFormatted),
            selected: false,
            showsRadio: false,
            action: {})
            .padding(.horizontal, 20)
    }

    // MARK: - Amount

    private var amountRow: some View {
        EnterAmountView(
            primaryAmount: viewModel.dashAmountText,
            secondaryAmount: viewModel.fiatAmountText,
            primaryCurrency: .dash,
            secondaryCurrency: .fiat(viewModel.fiatCurrencyCode),
            isPrimarySelected: viewModel.isDashInputSelected,
            currencyCodes: viewModel.amountCurrencyCodes,
            selectedCurrencyCode: viewModel.selectedAmountCurrencyCode,
            onMax: { viewModel.fillMax() },
            onSwap: { viewModel.toggleUnit() },
            onCurrencyTap: { viewModel.toggleUnit() },
            onSelectInputType: { viewModel.selectCurrency($0) }
        )
    }

    /// The SDK charges the network fee on top of the entered amount, so the
    /// wallet is debited slightly more than the figure above.
    private var feeNote: some View {
        Text(NSLocalizedString(
            "A network fee will be added on top of the amount.",
            comment: "DashPay Contacts"))
            .font(.system(size: 12))
            .foregroundColor(Color.dash.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }

    // MARK: - Keyboard

    private var keyboardSection: some View {
        HardwareNumericKeyboardView(
            value: keypadBinding,
            showDecimalSeparator: true,
            actionButtonText: NSLocalizedString("Send", comment: ""),
            actionEnabled: viewModel.canSend,
            inProgress: viewModel.isSending,
            actionHandler: onSend
        )
    }

    private var keypadBinding: Binding<String> {
        Binding(
            get: { viewModel.keypadText },
            set: { viewModel.keypadText = $0 })
    }
}

// MARK: - Shared chrome

/// Back-chevron + "Send" title, shared by both steps. The design system's bar
/// rather than the UIKit one, so the glyph and its ring are the
/// `navigationbar-*` assets — same chrome as the address-send steps.
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
