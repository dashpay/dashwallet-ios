//
//  ContactActivityCard.swift
//  DashWallet
//
//  Payment history with one contact, as a card for ContactSheet.
//

import SwiftDashSDK
import SwiftUI
import DashUIKit

/// The third card in ``ContactSheet``, under the profile and any incoming
/// request. Styled to match them exactly, so the sheet reads as one surface.
///
/// Only payments that flowed through the DashPay contact channel appear here:
/// a send straight to an address is not retained against the contact, so this
/// is not the full history of money moved between the two people.
struct ContactActivityCard: View {
    @StateObject private var viewModel: ContactActivityViewModel
    /// Opens one payment's transaction. Nil leaves every row inert.
    private let onSelect: ((Transaction) -> Void)?
    @State private var showFilterDialog = false

    /// Default `nil` rather than a fresh view model: default arguments are
    /// evaluated off the main actor and `ContactActivityViewModel` is
    /// `@MainActor`. `StateObject`'s autoclosure defers construction to view
    /// installation. Previews pass one in.
    init(
        contactIdentityId: Data,
        viewModel: ContactActivityViewModel? = nil,
        onSelect: ((Transaction) -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: viewModel
                ?? ContactActivityViewModel(contactIdentityId: contactIdentityId))
        self.onSelect = onSelect
    }

    var body: some View {
        Group {
            // Keyed on "has any payments", not on the filtered groups: a
            // filter that matches nothing must leave the card — and with it
            // the control that would undo the filter — on screen.
            if viewModel.hasAnyActivity {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 0) {
                        Text(NSLocalizedString("Activity", comment: "DashPay Contacts"))
                            .dashFont(.subheadMedium)
                            .foregroundStyle(Color.dash.primaryText)

                        Spacer()

                        TransactionFilterButton { showFilterDialog = true }
                    }

                    if viewModel.groups.isEmpty {
                        filteredOutMessage
                    } else {
                        VStack(spacing: 20) {
                            ForEach(viewModel.groups) { group in
                                VStack(spacing: 4) {
                                    dayHeader(group)

                                    ForEach(group.elements) { entry in
                                        switch entry {
                                        case let .payment(payment):
                                            ContactActivityRow(
                                                payment: payment,
                                                // Only a payment whose transaction is in this
                                                // wallet can be opened — a send whose H1 was lost,
                                                // or a receive not yet synced, has nothing behind
                                                // the tap.
                                                onTap: transactionTap(for: payment)
                                            )

                                        case let .event(event):
                                            ContactActivityEventRow(event: event)
                                        }
                                    }
                                }
                                .modifier(DashUIKit.MenuViewModifier())
                            }
                        }
                    }
                }
                .onAppear { viewModel.onAppear() }
                .sheet(isPresented: $showFilterDialog) { filterDialog }
            } else {
                EmptyView()
            }
        }
    }

    /// The home list's filter, minus the rows a contact payment can never
    /// be: it is always a plain send or receive, never a gift card, a reward
    /// or a shielded transfer.
    @ViewBuilder
    private var filterDialog: some View {
        let dialog = TransactionFilterDialog(
            selectedFilters: $viewModel.selectedFilters,
            showRewards: false,
            showMasternode: false,
            showGiftCard: false,
            showShielded: false)

        if #available(iOS 16.0, *) {
            dialog.presentationDetents([.height(TransactionFilterDialog.height(
                showRewards: false,
                showMasternode: false,
                showGiftCard: false,
                showShielded: false))])
        } else {
            dialog
        }
    }

    private var filteredOutMessage: some View {
        Text(NSLocalizedString("No payments match this filter.", comment: "DashPay Contacts"))
            .dashFont(.footnote)
            .foregroundStyle(Color.dash.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    /// Date on the left, weekday on the right — the home transaction list's
    /// section header, minus its own background: here it sits inside the card
    /// rather than forming the top of one.
    private func dayHeader(_ group: ContactActivityViewModel.DayGroup) -> some View {
        HStack {
            Text(group.id)
                .dashFont(.footnoteMedium)
                .foregroundStyle(Color.dash.primaryText)

            Spacer()

            Text(DWDateFormatter.sharedInstance.dayOfWeek(from: group.date))
                .dashFont(.footnote)
                .foregroundStyle(Color.dash.tertiaryText)
        }
        // Matches the horizontal padding TransactionView applies inside each
        // row, so the heading lines up with the text below it.
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func transactionTap(for payment: SwiftDashSDKContactsService.ContactPayment) -> (() -> Void)? {
        guard let onSelect, let tx = viewModel.resolvedByTxid[payment.id] else { return nil }
        return { onSelect(tx) }
    }
}

#if DEBUG

/// Shown on the sheet's own background so the card's fill is visible, which
/// is how it appears inside ``ContactSheet``.
private struct ContactActivityCardHost: View {
    let viewModel: ContactActivityViewModel

    var body: some View {
        ContactActivityCard(contactIdentityId: Data(), viewModel: viewModel)
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.dash.primaryBackground)
    }
}

/// The full history: the request that started it at the bottom, payments
/// since, several days — the case the day headings exist for.
#Preview("Payments and requests") {
    ContactActivityCardHost(viewModel: .preview(
        payments: [
            .preview(memo: "Lunch"),
            .preview(txid: "a0", amountDuffs: 12_500_000, direction: .received),
            .preview(txid: "a1", amountDuffs: 4_000_000, direction: .received, daysAgo: 1),
            .preview(txid: "b2", amountDuffs: 250_000_000, daysAgo: 12),
        ],
        events: [
            .preview(kind: .requestSent, daysAgo: 30),
            .preview(kind: .theyAccepted, daysAgo: 29),
        ]))
}

/// A brand-new contact: the request is the whole history, which is why the
/// card exists before any money has moved.
#Preview("Requests only") {
    ContactActivityCardHost(viewModel: .preview(events: [
        .preview(kind: .requestReceived, daysAgo: 2),
        .preview(kind: .weAccepted, daysAgo: 1),
    ]))
}

/// Nothing known at all — the card renders nothing, so the sheet ends at the
/// profile.
#Preview("No activity") {
    ContactActivityCardHost(viewModel: .preview())
}

#Preview("One payment") {
    ContactActivityCardHost(viewModel: .preview(payments: [
        .preview(amountDuffs: 100_000, direction: .received, fiatString: nil),
    ]))
}

#endif
