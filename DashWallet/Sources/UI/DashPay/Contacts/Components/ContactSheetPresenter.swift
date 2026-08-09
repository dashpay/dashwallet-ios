//
//  ContactSheetPresenter.swift
//  DashWallet
//
//  Presents ContactSheet, and the sheets it can raise, for one person.
//

import SwiftDashSDK
import SwiftUI

/// Who the sheet was opened for. The two lists hand over different models —
/// a contact we hold, or a name found on the network — and this is the only
/// place that difference survives; one sheet is presented either way.
enum ContactTarget: Identifiable {
    case contact(ContactItem)
    case searchHit(DpnsSearchResult)

    var id: Data {
        switch self {
        case let .contact(contact): contact.contactIdentityId
        case let .searchHit(result): result.identityId
        }
    }
}

/// Hosts ``ContactSheet`` and feeds it from whichever model the target
/// carries. Shared by the contacts list and the notifications feed so a
/// person opens the same way from both.
///
/// The pay and transaction-detail sheets are raised from here rather than
/// from the presenting screen: a sheet presented by a view that is itself
/// covered by a sheet never appears.
struct ContactSheetPresenter: View {
    let target: ContactTarget
    @ObservedObject var viewModel: ContactsViewModel
    @State private var showingPay = false
    /// A payment from the activity list, opened for its details.
    @State private var selectedTx: TransactionListDataItem? = nil

    var body: some View {
        sheet
            .sheet(isPresented: $showingPay) {
                if let contact = payee {
                    PayContactSheet(contact: contact)
                }
            }
            // The home list's own detail sheet, so a payment opens the same
            // screen whether it was reached from there or from a contact.
            .sheet(item: $selectedTx) { item in
                TransactionDetailsSheet(item: item)
            }
    }

    /// `.tx` carries optional row metadata for the home list's icons and
    /// titles; the detail destination ignores it, so nothing is lost by not
    /// resolving a provider here.
    private func showDetails(_ tx: Transaction) {
        selectedTx = .tx(tx, nil)
    }

    @ViewBuilder
    private var sheet: some View {
        switch target {
        case let .contact(contact):
            ContactSheet(
                contact: contact,
                isSending: viewModel.processingIds.contains(contact.contactIdentityId),
                onPay: { showingPay = true },
                onAccept: { viewModel.accept(contact) },
                onIgnore: { viewModel.ignore(contact) },
                onSelectTransaction: showDetails)

        case let .searchHit(result):
            ContactSheet(
                result: result,
                collision: viewModel.search.collision(for: result),
                contact: viewModel.search.contactItem(for: result.identityId),
                isSending: viewModel.search.sendingIds.contains(result.identityId),
                // A hit we already hold can be paid like any contact; a
                // stranger has no xpub to pay to, so the button is omitted.
                onPay: payee == nil ? nil : { showingPay = true },
                onSendRequest: { viewModel.search.send(to: result) },
                onAccept: { viewModel.search.accept(result) },
                onIgnore: { viewModel.search.ignore(result) },
                onSelectTransaction: showDetails)
        }
    }

    /// The contact record behind this target, which paying needs and a search
    /// hit only has once the request has been accepted.
    private var payee: ContactItem? {
        switch target {
        case let .contact(contact): contact
        case let .searchHit(result): viewModel.search.contactItem(for: result.identityId)
        }
    }
}

