//
//  ContactListEntry.swift
//  DashWallet
//
//  One row's worth of contact-list data.
//

import SwiftUI

/// SwiftUI otherwise reuses a contact row by `ContactItem.id` when the same
/// identity moves between incoming / established / outgoing sections. That
/// can preserve the old row type and its action closures (for example an
/// Accept button rendered inside the Pending section).
struct ContactListEntry: Identifiable {
    enum Section: Hashable {
        case incoming
        case established
        case outgoing
        case hidden
    }

    struct ID: Hashable {
        let section: Section
        let contactIdentityId: Data
    }

    let item: ContactItem
    let id: ID

    init(item: ContactItem, section: Section) {
        self.item = item
        id = ID(
            section: section,
            contactIdentityId: item.contactIdentityId)
    }
}
