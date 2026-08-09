//
//  ContactRow.swift
//  DashWallet
//
//  One row for both contact lists — the ones already mine and the ones
//  found on the network.
//

import SwiftDashSDK
import SwiftUI
import DashUIKit

/// A person, however we know them. The layout is fixed; only the trailing
/// control differs, and it is passed in as ``Accessory`` rather than derived
/// from a model — that is what let the row split in two before, once for
/// `ContactItem` and once for a search hit.
struct ContactRow: View {
    enum Accessory {
        /// A request waiting on us: accept, or dismiss it.
        case acceptIgnore(isProcessing: Bool, onAccept: () -> Void, onIgnore: () -> Void)
        /// Someone we could ask.
        case request(onTap: () -> Void)
        /// Already asked — the same button, spent.
        case requested
        /// They asked us, seen from the network list.
        case accept(onTap: () -> Void)
        /// A send or accept is in flight.
        case sending
        /// We don't yet know whether this identity can be asked. Blank rather
        /// than a guess: the button would otherwise have to change meaning
        /// once the answer arrives.
        case checkingEligibility
        /// Already mutual.
        case established
        /// Pre-DashPay identity: cannot receive contact requests.
        case unavailable
        case none
    }

    let title: String
    /// Second line: the username when the title is a display name or alias,
    /// or the reason this row cannot be actioned.
    let secondary: String?
    let avatarURL: String?
    let identitySeed: Data
    let accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            ContactAvatarView(
                title: title,
                avatarURL: avatarURL,
                identitySeed: identitySeed
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .dashFont(.subheadMedium)
                    .foregroundStyle(Color.dash.primaryText)

                if let secondary {
                    Text(secondary)
                        .dashFont(.footnote)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }
            .padding(.leading, 6)

            Spacer()

            trailing
        }
        .padding(10)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var trailing: some View {
        switch accessory {
        case let .acceptIgnore(isProcessing, onAccept, onIgnore):
            DashUIKit.DashButton(
                text: NSLocalizedString("Accept", comment: "DashPay Contacts"),
                isLoading: isProcessing,
                size: .extraSmall,
                style: .filledBlue,
                action: onAccept)

            if !isProcessing {
                Button(action: onIgnore) {
                    XmarkIcon(size: 9, color: Color.dash.primaryText)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(NSLocalizedString("Close", comment: "DashPay Contacts"))
            }
        case let .request(onTap):
            DashUIKit.DashButton(
                text: NSLocalizedString("Request", comment: "DashPay Contacts"),
                isEnabled: true,
                size: .small,
                style: .strokeGray,
                action: onTap)
        case .requested:
            DashUIKit.DashButton(
                text: NSLocalizedString("Requested", comment: "DashPay Contacts"),
                isEnabled: false,
                size: .small,
                style: .strokeGray)
        case let .accept(onTap):
            DashUIKit.DashButton(
                text: NSLocalizedString("Accept", comment: "DashPay Contacts"),
                size: .extraSmall,
                style: .filledBlue,
                action: onTap)
        case .sending:
            SwiftUI.ProgressView()
        case .checkingEligibility:
            EmptyView()
        case .established:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color.dash.green)
        case .unavailable:
            Image(systemName: "lock.slash")
                .foregroundColor(.dash.tertiaryText)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - From a contact we already have

extension ContactRow {
    init(
        item: ContactItem,
        isProcessing: Bool = false,
        onAccept: (() -> Void)? = nil,
        onIgnore: (() -> Void)? = nil
    ) {
        self.title = item.displayTitle
        // The username is worth a second line only when the first one is
        // something else — a profile display name or the owner's alias.
        self.secondary = {
            guard let username = item.username?.withoutDashSuffix,
                  !username.isEmpty,
                  username != item.displayTitle else { return nil }
            return username
        }()
        self.avatarURL = item.avatarURL
        self.identitySeed = item.contactIdentityId
        self.accessory = switch item.relationship {
        case .incoming:
            .acceptIgnore(
                isProcessing: isProcessing,
                onAccept: { onAccept?() },
                onIgnore: { onIgnore?() })
        case .outgoing: .requested
        case .established: .none
        }
    }
}

// MARK: - From a network search hit

extension ContactRow {
    init(
        result: DpnsSearchResult,
        state: AddContactViewModel.Collision,
        isSending: Bool,
        /// The eligibility query for this identity hasn't answered yet.
        isCheckingEligibility: Bool = false,
        onRequest: @escaping () -> Void,
        onAccept: @escaping () -> Void
    ) {
        self.title = result.fullName.withoutDashSuffix
        self.secondary = state.hintText
        self.avatarURL = nil
        self.identitySeed = result.identityId
        if isSending {
            self.accessory = .sending
        } else if isCheckingEligibility, state == .none {
            // Only the plain case waits: an existing relationship already
            // decides the row, whatever the key query goes on to say.
            self.accessory = .checkingEligibility
        } else {
            self.accessory = switch state {
            case .none: .request(onTap: onRequest)
            case .alreadyRequested: .requested
            case .theyAskedUs: .accept(onTap: onAccept)
            case .established: .established
            case .missingDashPayKeys: .unavailable
            case .isSelf: .none
            }
        }
    }
}

extension AddContactViewModel.Collision {
    /// The second line explaining why this hit is not a plain "add".
    var hintText: String? {
        switch self {
        case .none: nil
        case .established: NSLocalizedString("Already a contact", comment: "DashPay Contacts")
        case .alreadyRequested: NSLocalizedString("Contact Request Pending", comment: "DashPay Contacts")
        case .theyAskedUs: NSLocalizedString("Sent you a request", comment: "DashPay Contacts")
        case .isSelf: NSLocalizedString("This is you", comment: "DashPay Contacts")
        case .missingDashPayKeys: NSLocalizedString("Can't receive contact requests", comment: "DashPay Contacts")
        }
    }
}

#if DEBUG

/// Every state both lists can render, in one place — the trailing control is
/// the only thing that differs.
#Preview {
    VStack(spacing: 2) {
        ContactRow(item: .preview(title: "briantest63a"))
        ContactRow(
            item: .preview(title: "s22test63b", relationship: .incoming),
            onAccept: {}, onIgnore: {})
        ContactRow(
            item: .preview(title: "Upsilon2", relationship: .incoming),
            isProcessing: true)
        ContactRow(item: .preview(title: "Delta", relationship: .outgoing))
    }
    .modifier(DashUIKit.MenuViewModifier())
    .padding()
    .background(Color.dash.primaryBackground)
}

#endif
