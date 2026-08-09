//
//  ContactSettingsViewModel.swift
//  DashWallet
//
//  Owner-private contact metadata: alias, note, hidden.
//

import Combine
import SwiftUI

/// The alias / note / hidden trio for one established contact.
///
/// All three travel together: `setContactMeta` writes a single DIP-15
/// `contactInfo` document carrying the whole set, so every save — including a
/// hide toggle — sends the current value of the other two with it.
@MainActor
final class ContactSettingsViewModel: ObservableObject {

    @Published var aliasText = ""
    @Published var noteText = ""
    @Published private(set) var isHidden = false
    @Published private(set) var isSaving = false
    @Published private(set) var savedToast = false
    @Published var errorMessage: String? = nil

    /// The alias or note differ from what the contact currently holds, so
    /// there is something to save.
    var metaChanged: Bool {
        aliasText != (contact.alias ?? "") || noteText != (contact.note ?? "")
    }

    private var contact: ContactItem
    /// `nil` only in previews. The contacts service does real work in its
    /// initializer and must not be woken by a canvas.
    private let service: SwiftDashSDKContactsService?
    private var cancellables: Set<AnyCancellable> = []

    init(contact: ContactItem, service: SwiftDashSDKContactsService? = .shared) {
        self.contact = contact
        self.service = service
        guard let service else { return }
        // Keep the baseline `metaChanged` compares against in step with the
        // contact itself — an alias edited on another device arrives here as
        // a snapshot change, and without this the Save button would stay lit
        // against a value that is no longer current.
        service.$contacts
            .compactMap { [contactIdentityId = contact.contactIdentityId] contacts in
                contacts.first { $0.contactIdentityId == contactIdentityId }
            }
            .removeDuplicates()
            .sink { [weak self] latest in self?.adopt(latest) }
            .store(in: &cancellables)
    }

    func onAppear() {
        aliasText = contact.alias ?? ""
        noteText = contact.note ?? ""
        isHidden = contact.isHidden
    }

    /// A remote change wins only where the user has not typed: overwriting a
    /// half-finished edit with a synced value would take the text out from
    /// under them mid-sentence.
    private func adopt(_ latest: ContactItem) {
        let hadLocalEdits = metaChanged
        contact = latest
        isHidden = latest.isHidden
        guard !hadLocalEdits else { return }
        aliasText = latest.alias ?? ""
        noteText = latest.note ?? ""
    }

    func save() {
        write(hidden: isHidden) { [weak self] in
            guard let self else { return }
            withAnimation { self.savedToast = true }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation { self.savedToast = false }
        }
    }

    func toggleHidden() {
        let target = !isHidden
        write(hidden: target) { [weak self] in
            self?.isHidden = target
        }
    }

    private func write(hidden: Bool, then finish: @escaping () async -> Void) {
        guard let service, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await service.setContactMeta(
                    alias: aliasText.trimmingCharacters(in: .whitespaces),
                    note: noteText.trimmingCharacters(in: .whitespaces),
                    hidden: hidden,
                    for: contact.contactIdentityId)
                await finish()
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // Backing out of the PIN prompt is a user action, not an
                // error — nothing was written, so say nothing.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if DEBUG

extension ContactSettingsViewModel {
    /// Preview seed: no contacts service, so saving is a no-op.
    static func preview(
        contact: ContactItem = .preview(title: "briantest63a"),
        alias: String = "",
        note: String = "",
        isHidden: Bool = false
    ) -> ContactSettingsViewModel {
        let model = ContactSettingsViewModel(contact: contact, service: nil)
        model.aliasText = alias
        model.noteText = note
        model.isHidden = isHidden
        return model
    }
}

#endif
