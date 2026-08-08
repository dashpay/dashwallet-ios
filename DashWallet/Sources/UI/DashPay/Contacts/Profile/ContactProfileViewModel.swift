//
//  ContactProfileViewModel.swift
//  DashWallet
//
//  Contact profile state: the live contact row, its owner-private
//  alias/note/hidden metadata, and the payment history between us.
//

import Combine
import SwiftUI

@MainActor
final class ContactProfileViewModel: ObservableObject {

    /// The contact as currently known. Replaced whenever the contacts
    /// snapshot changes, so an accept elsewhere turns this profile from
    /// "incoming request" into an established contact in place.
    @Published private(set) var contact: ContactItem
    @Published private(set) var isProcessing = false
    @Published var errorMessage: String? = nil

    // Owner-private metadata, edited in the sheet.
    @Published var aliasText = ""
    @Published var noteText = ""
    @Published private(set) var isHidden = false
    @Published private(set) var metaSavedToast = false

    @Published private(set) var payments: [SwiftDashSDKContactsService.ContactPayment] = []
    /// Payment id → the wallet transaction it resolved to, for the
    /// tx-detail push. Absent when the transaction isn't in the wallet.
    @Published private(set) var resolvedByTxid: [String: Transaction] = [:]

    /// Set when the profile should close: the action completed, or the row
    /// disappeared underneath us. The view owns `dismiss`, so it watches this.
    @Published private(set) var shouldDismiss = false

    // MARK: - Dependencies

    /// `nil` only in previews — the contacts service does real work in its
    /// initializer and must not be woken by a canvas.
    private let service: SwiftDashSDKContactsService?
    private var cancellables: Set<AnyCancellable> = []

    init(contact: ContactItem, service: SwiftDashSDKContactsService? = .shared) {
        self.contact = contact
        self.service = service
        guard service != nil else { return }
        NotificationCenter.default
            .publisher(for: SwiftDashSDKContactsService.contactsDidChangeNotification)
            .sink { [weak self] _ in self?.contactsDidChange() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func onAppear() {
        aliasText = contact.alias ?? ""
        noteText = contact.note ?? ""
        isHidden = contact.isHidden
        guard let service, contact.relationship == .established else { return }
        // Pull the Rust-side history into SwiftData first — the projection
        // is app-driven (no persister push).
        service.refreshPaymentsProjection()
        loadPayments()
    }

    private func contactsDidChange() {
        guard let service else { return }
        guard let latestContact = service.contactItem(for: contact.contactIdentityId) else {
            // The request was removed (ignored) or the active wallet
            // changed. Do not leave an actionable stale profile open.
            shouldDismiss = true
            return
        }

        let becameEstablished =
            contact.relationship != .established &&
            latestContact.relationship == .established
        contact = latestContact

        if latestContact.relationship == .established {
            if becameEstablished {
                service.refreshPaymentsProjection()
            }
            loadPayments()
        }
    }

    private func loadPayments() {
        guard let service else { return }
        let rows = service.payments(with: contact.contactIdentityId)
        var resolved: [String: Transaction] = [:]
        for payment in rows {
            if let wire = payment.txidWire,
               let tx = SwiftDashSDKWalletSource.fetch(txid: wire) {
                resolved[payment.id] = tx
            }
        }
        payments = rows
        resolvedByTxid = resolved
    }

    // MARK: - Request actions

    func accept() {
        guard let service else { return }
        run { try await service.acceptContactRequest(from: self.contact.contactIdentityId) }
    }

    func ignore() {
        guard let service else { return }
        run { try await service.ignoreSender(self.contact.contactIdentityId) }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                try await operation()
                shouldDismiss = true
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // User backed out of the PIN prompt.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Owner-private metadata

    var metaChanged: Bool {
        aliasText != (contact.alias ?? "") || noteText != (contact.note ?? "")
    }

    func saveMeta() {
        guard let service else { return }
        Task {
            do {
                // Combined write — the contactInfo document carries
                // alias + note + hidden together, so every save sends the
                // sheet's full current state.
                try await service.setContactMeta(
                    alias: aliasText.trimmingCharacters(in: .whitespaces),
                    note: noteText.trimmingCharacters(in: .whitespaces),
                    hidden: isHidden,
                    for: contact.contactIdentityId)
                withAnimation { metaSavedToast = true }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation { metaSavedToast = false }
            } catch {
                errorMessage = Self.errorMessageIfNotCancelled(error)
            }
        }
    }

    func toggleHidden() {
        guard let service else { return }
        Task {
            do {
                try await service.setContactMeta(
                    alias: aliasText.trimmingCharacters(in: .whitespaces),
                    note: noteText.trimmingCharacters(in: .whitespaces),
                    hidden: !isHidden,
                    for: contact.contactIdentityId)
                isHidden.toggle()
            } catch {
                errorMessage = Self.errorMessageIfNotCancelled(error)
            }
        }
    }

    /// A cancelled PIN/biometric prompt is a user action, not an error —
    /// stay silent instead of popping the error alert.
    private static func errorMessageIfNotCancelled(_ error: Error) -> String? {
        if case SwiftDashSDKContactsService.ServiceError.authCancelled = error {
            return nil
        }
        return error.localizedDescription
    }

    // MARK: - Formatting

    static func dashString(duffs: UInt64) -> String {
        let dash = Decimal(duffs) / Decimal(100_000_000)
        return "\(dash)"
    }
}

#if DEBUG

extension ContactProfileViewModel {
    /// Preview seed: no contacts service, so nothing syncs and every action
    /// is a no-op. `payments` can be supplied but `resolvedByTxid` stays
    /// empty — a wallet transaction cannot be fabricated app-side.
    static func preview(
        contact: ContactItem = .preview(title: "briantest63a"),
        payments: [SwiftDashSDKContactsService.ContactPayment] = []
    ) -> ContactProfileViewModel {
        let model = ContactProfileViewModel(contact: contact, service: nil)
        model.aliasText = contact.alias ?? ""
        model.noteText = contact.note ?? ""
        model.isHidden = contact.isHidden
        model.payments = payments
        return model
    }
}

#endif
