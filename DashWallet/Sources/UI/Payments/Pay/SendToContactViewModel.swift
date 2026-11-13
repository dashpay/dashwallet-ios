//
//  SendToContactViewModel.swift
//  DashWallet
//
//  View model for the Send tab's "Send to username" contact picker. The
//  amount step that follows it is the ordinary `ExternalSendAmountScreen` on
//  `SendViewModel` — a contact is a destination of the standard send flow,
//  not a flow of its own.
//

#if DASHPAY

import Foundation
import SwiftDashSDK

// MARK: - Picker

/// The contact list behind "Send to username".
///
/// Reads the same snapshot the contacts tab lists under "My Contacts":
/// `SwiftDashSDKContactsService.contacts` holds only ESTABLISHED (mutual)
/// pairs, already sorted by display title. Pending incoming/outgoing
/// requests are separate snapshots and are deliberately not offered here —
/// a DIP-15 payment channel only exists once the friendship is mutual.
@MainActor
final class SendToContactPickerViewModel: ObservableObject {
    @Published private(set) var contacts: [ContactItem] = []
    @Published var searchText: String = ""

    private let service = SwiftDashSDKContactsService.shared

    init() {
        // Direct assign is safe: both objects are main-actor and the service
        // publishes on main — same wiring `ContactsViewModel` uses.
        service.$contacts.assign(to: &$contacts)
    }

    /// Rebuild the service snapshot from SwiftData. The payments stack never
    /// runs the contacts tab's own refresh, so without this the picker would
    /// show whatever the last visit to that tab left behind.
    func refresh() {
        service.refresh()
    }

    /// True when there is not a single established contact — the empty state,
    /// as opposed to a search that matched nothing.
    var hasNoContacts: Bool { contacts.isEmpty }

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// Contacts matching the search text, in the service's display-title
    /// order. Hidden contacts are included: hiding tidies the contacts tab's
    /// list, it does not say the person can no longer be paid.
    var visibleContacts: [ContactItem] {
        let trimmed = trimmedSearchText
        guard !trimmed.isEmpty else { return contacts }
        return contacts.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(trimmed)
                || ($0.username?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }
}

#endif
