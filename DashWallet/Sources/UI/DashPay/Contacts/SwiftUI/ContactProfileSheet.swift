//
//  ContactProfileSheet.swift
//  DashWallet
//
//  Other-user profile sheet (migration Row #18 phase 5) — SDK-side
//  replacement for the DashSync `DWUserProfileViewController`.
//  Visual design mirrors the Android dash-wallet contact profile
//  (contact_request_view.xml + profile_activity_header_row.xml):
//  gray screen, avatar header, full-width Dash-Blue Pay button,
//  green Accept / tertiary Ignore pair for incoming requests,
//  white card sections for contact settings and payment history.
//

import SwiftUI
import DashUIKit

struct ContactProfileSheet: View {
    @State private var contact: ContactItem

    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    @State private var showingPaySheet = false
    /// Set once the profile has asked to close: a contacts change during the
    /// Pay sheet's exit and that sheet's onDismiss can both ask.
    @State private var isClosing = false

    // Owner-private contact meta, editable for established contacts.
    // Seeded from the immutable snapshot in onAppear; saved through
    // the service (SDK EstablishedContact setters + flushPersist).
    @State private var aliasText = ""
    @State private var noteText = ""
    @State private var isHidden = false
    @State private var payments: [SwiftDashSDKContactsService.ContactPayment] = []
    /// Payment txid (display hex) → the resolved wallet `Transaction`,
    /// for the rows whose on-chain tx exists in this wallet's store.
    /// A payment absent here (H1 loss, or a received tx not yet synced)
    /// renders as a non-tappable row instead of a broken tx-detail push.
    @State private var resolvedByTxid: [String: Transaction] = [:]
    /// Tapped payment's txid (display hex, Hashable) — drives the
    /// tx-detail push via the NavigationStack-native
    /// `navigationDestination(item:)`. The resolved `Transaction` is
    /// looked up from `resolvedByTxid` in the destination builder
    /// (`Transaction` itself isn't `Hashable`).
    @State private var selectedPaymentId: String? = nil
    /// Transient confirmation shown at the bottom of the sheet — a saved edit
    /// or a copied identity id. One slot, so a second message replaces the
    /// first instead of stacking.
    @State private var toastMessage: String? = nil
    /// Contact settings (alias / note) are part of what the sheet is for, so
    /// they open with it; tapping the header still folds them away. They were
    /// collapsed by default, which left an alias the user had already written
    /// invisible on the one screen that shows everything about the contact.
    @State private var showContactSettings = true

    private let service = SwiftDashSDKContactsService.shared

    init(contact: ContactItem) {
        _contact = State(initialValue: contact)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        // Sibling of `header` rather than part of it: the
                        // header's tap toggles the contact-settings card, and
                        // this row's tap copies.
                        ContactIdentityIdView(
                            identityId: contact.contactIdentityId,
                            onCopy: { showToast(NSLocalizedString("Copied", comment: "")) })
                        if let message = contact.publicMessage, !message.isEmpty {
                            Text(message)
                                .font(.system(size: 14))
                                .foregroundColor(.dash.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        actions
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedPaymentId) { paymentId in
                // Reuse the standard tx-detail screen. The SwiftUI
                // NavigationStack supplies the back button (nav bar left
                // visible), so we don't drive TXDetailVCWrapper's own
                // programmatic pop.
                if let tx = resolvedByTxid[paymentId] {
                    TXDetailVCWrapper(tx: tx, navigateBack: .constant(false))
                        .navigationTitle(NSLocalizedString("Transaction", comment: "DashPay Contacts"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "")) { closeProfile() }
                        .foregroundColor(.dash.blue)
                }
            }
            .alert(
                NSLocalizedString("Error", comment: ""),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } })
            ) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingPaySheet, onDismiss: {
                // A contact that vanished while Pay was open (see below) closes
                // the profile now that nothing is in flight on top of it.
                if service.contactItem(for: contact.contactIdentityId) == nil {
                    closeProfile()
                }
            }) {
                PayContactSheet(contact: contact)
            }
            .onAppear {
                aliasText = contact.alias ?? ""
                noteText = contact.note ?? ""
                isHidden = contact.isHidden
                if contact.relationship == .established {
                    // Pull the Rust-side history into SwiftData first —
                    // the projection is app-driven (no persister push).
                    service.refreshPaymentsProjection()
                    loadPayments()
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: SwiftDashSDKContactsService.contactsDidChangeNotification)
            ) { _ in
                guard let latestContact = service.contactItem(
                    for: contact.contactIdentityId)
                else {
                    // The request was removed (ignored) or the active wallet
                    // changed. Do not leave an actionable stale profile open —
                    // but not from under Pay: closing the profile would take a
                    // payment in flight, and its outcome, with it. Pay disables
                    // its own Send for the vanished contact, and its onDismiss
                    // closes the profile once it is gone.
                    if !showingPaySheet { closeProfile() }
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
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ContactAvatarView(
                title: contact.displayTitle,
                avatarURL: contact.avatarURL,
                identitySeed: contact.contactIdentityId,
                size: 88)
            Text(contact.displayTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.dash.primaryText)
            // Shown even when it matches the title above. The title can be an
            // owner-set alias or a profile display name, and both are free
            // text — so "the name I gave them" and "the name they registered"
            // looking identical is itself information, and hiding the username
            // then left the user unable to tell which one they were reading.
            if let username = contact.username?.withoutDashSuffix, !username.isEmpty {
                Text(username)
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
            }
            if contact.relationship == .established {
                // Disclosure hint: tapping the header toggles the
                // Contact settings card below.
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.dash.tertiaryText)
                    .rotationEffect(.degrees(showContactSettings ? 180 : 0))
                    .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard contact.relationship == .established else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showContactSettings.toggle()
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch contact.relationship {
        case .incoming:
            // Android "contact request received" pane: caption title +
            // green Accept / tertiary Ignore pair (120×39, radius 8).
            VStack(spacing: 14) {
                Text(String(
                    format: NSLocalizedString("%@ has requested to be your contact", comment: "DashPay Contacts"),
                    contact.displayTitle))
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                    .multilineTextAlignment(.center)
                if isProcessing {
                    SwiftUI.ProgressView()
                } else {
                    HStack(spacing: 10) {
                        Button {
                            run { try await service.acceptContactRequest(from: contact.contactIdentityId) }
                        } label: {
                            Text(NSLocalizedString("Accept", comment: "DashPay Contacts"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.dash.whiteText)
                                .frame(width: 120, height: 39)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.dashGreen))
                        }
                        .buttonStyle(.plain)

                        Button {
                            run { try await service.ignoreSender(contact.contactIdentityId) }
                        } label: {
                            Text(NSLocalizedString("Ignore", comment: "DashPay Contacts"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.dash.primaryText)
                                .frame(width: 120, height: 39)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.dash.gray300Alpha10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 32)
        case .outgoing:
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 12))
                Text(NSLocalizedString("Contact Request Pending", comment: "DashPay Contacts"))
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.dashGolden)
        case .established:
            VStack(spacing: 20) {
                // Contact settings unfold from under the header when
                // the user taps the contact's name/avatar. zIndex(-1)
                // keeps the card BEHIND its siblings while the move
                // transition runs — without it the inserted view is
                // rendered on top and slides over the Pay button.
                if showContactSettings {
                    metaSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(-1)
                }

                // Being established means the contact requests are
                // mutual; it does NOT mean we can pay. Paying needs the
                // DIP-15 external account built from the counterparty's
                // encrypted xpub, and when the SDK has permanently
                // failed to build it, every Pay tap ends in a failure
                // the user can do nothing about. Say so instead.
                if contact.paymentChannelBroken {
                    paymentChannelBrokenNotice
                } else {
                    // Android Button.Primary.Blue: full-width filled pay CTA.
                    Button {
                        showingPaySheet = true
                    } label: {
                        Label(
                            NSLocalizedString("Pay", comment: "DashPay Contacts"),
                            systemImage: "arrow.up.circle.fill")
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
                }

                paymentsSection

                Button {
                    toggleHidden()
                } label: {
                    Label(
                        isHidden
                            ? NSLocalizedString("Unhide Contact", comment: "DashPay Contacts")
                            : NSLocalizedString("Hide Contact", comment: "DashPay Contacts"),
                        systemImage: isHidden ? "eye" : "eye.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dash.gray300Alpha10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 15)
            }
        }
    }

    // MARK: Owner-private meta (alias / note) — "Contact settings" card

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("Contact settings", comment: "DashPay Contacts"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.dash.primaryText)
            Text(NSLocalizedString("Only visible to you", comment: "DashPay Contacts"))
                .font(.system(size: 12))
                .foregroundColor(.dash.tertiaryText)
            TextField(
                NSLocalizedString("Alias", comment: "DashPay Contacts"),
                text: $aliasText)
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.dash.primaryBackground))
                .onSubmit { saveMeta() }
            TextField(
                NSLocalizedString("Note", comment: "DashPay Contacts"),
                text: $noteText,
                axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.dash.primaryBackground))
                .onSubmit { saveMeta() }
            if metaChanged {
                Button {
                    saveMeta()
                } label: {
                    Text(NSLocalizedString("Save", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.dash.blue)
                        .frame(height: 30)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dash.blue.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.dash.secondaryBackground))
        .padding(.horizontal, 15)
    }

    /// Close the profile once, however many paths ask; see `isClosing`.
    private func closeProfile() {
        guard !isClosing else { return }
        isClosing = true
        dismiss()
    }

    /// Show a confirmation and clear it after a beat. `@MainActor` because it
    /// mutates published sheet state from callers on both the main actor and a
    /// view's tap handler.
    @MainActor
    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            // A later toast may have replaced this one; only retract our own.
            if toastMessage == message {
                withAnimation { toastMessage = nil }
            }
        }
    }

    private var metaChanged: Bool {
        aliasText != (contact.alias ?? "") || noteText != (contact.note ?? "")
    }

    private func saveMeta() {
        Task { @MainActor in
            do {
                // Combined write — the contactInfo document carries
                // alias + note + hidden together, so every save sends the
                // sheet's full current state.
                try await service.setContactMeta(
                    alias: aliasText.trimmingCharacters(in: .whitespaces),
                    note: noteText.trimmingCharacters(in: .whitespaces),
                    hidden: isHidden,
                    for: contact.contactIdentityId)
                showToast(NSLocalizedString("Saved", comment: ""))
            } catch {
                errorMessage = errorMessageIfNotCancelled(error)
            }
        }
    }

    private func toggleHidden() {
        Task { @MainActor in
            do {
                try await service.setContactMeta(
                    alias: aliasText.trimmingCharacters(in: .whitespaces),
                    note: noteText.trimmingCharacters(in: .whitespaces),
                    hidden: !isHidden,
                    for: contact.contactIdentityId)
                isHidden.toggle()
            } catch {
                errorMessage = errorMessageIfNotCancelled(error)
            }
        }
    }

    /// A cancelled PIN/biometric prompt is a user action, not an error —
    /// stay silent instead of popping the error alert.
    private func errorMessageIfNotCancelled(_ error: Error) -> String? {
        if case SwiftDashSDKContactsService.ServiceError.authCancelled = error {
            return nil
        }
        return error.localizedDescription
    }

    /// Shown in place of the Pay CTA when the contact's payment
    /// channel is permanently broken.
    ///
    /// Deliberately actionable rather than an error: the flag only
    /// clears when the CONTACT sends a fresh request, so telling the
    /// user what to ask for is the only thing that can fix it. A
    /// disabled-looking button with no explanation would leave them
    /// tapping and reading a Rust diagnostic instead.
    private var paymentChannelBrokenNotice: some View {
        VStack(spacing: 6) {
            Label(
                NSLocalizedString("Payments unavailable", comment: "DashPay Contacts"),
                systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dashGolden)
            Text(NSLocalizedString(
                "This contact's payment details couldn't be set up. Ask them to send you a new contact request.",
                comment: "DashPay Contacts"))
                .font(.system(size: 13))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.dash.secondaryBackground))
        .padding(.horizontal, 32)
    }

    // MARK: Payments between us — history card

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Activity", comment: "DashPay Contacts"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.dash.primaryText)
            // Legacy profile's info tooltip, inlined: only payments
            // that flowed through the DashPay contact channel appear
            // here — direct-to-address sends are not retained.
            Text(NSLocalizedString("Payments made directly to an address aren't retained here.", comment: "DashPay Contacts"))
                .font(.system(size: 12))
                .foregroundColor(.dash.tertiaryText)
            if activityEntries.isEmpty {
                Text(NSLocalizedString("No payments with this contact yet", comment: "DashPay Contacts"))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                    .padding(.top, 2)
            } else {
                ForEach(activityEntries) { entry in
                    switch entry {
                    case .payment(let payment):
                        paymentRow(payment)
                    case .request(let request):
                        requestRow(request)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.dash.secondaryBackground))
        .padding(.horizontal, 15)
    }

    // MARK: - Activity

    /// A moment in the history with this contact. Payments are only part of it:
    /// before the first one there is still the request that opened the channel,
    /// and a profile that showed nothing until money moved read as empty for a
    /// contact the user had just added.
    private enum ActivityEntry: Identifiable {
        case payment(SwiftDashSDKContactsService.ContactPayment)
        case request(RequestEvent)

        var date: Date {
            switch self {
            case .payment(let payment): payment.date
            case .request(let request): request.date
            }
        }

        var id: String {
            switch self {
            case .payment(let payment): "payment-\(payment.id)"
            case .request(let request): "request-\(request.id)"
            }
        }
    }

    /// A contact-request milestone, derived from the pair's own timestamps
    /// rather than a feed: `incomingCreatedAt` / `outgoingCreatedAt` are the two
    /// halves of a DashPay friendship, so the earlier is the request and — once
    /// established — the later is the reply that completed it.
    private struct RequestEvent: Identifiable {
        enum Kind {
            case theyAsked
            case weAsked
            case theyAccepted
            case weAccepted
        }

        let kind: Kind
        let date: Date
        var id: String { "\(kind)-\(date.timeIntervalSince1970)" }
    }

    private var requestEvents: [RequestEvent] {
        let incoming = contact.incomingCreatedAt
        let outgoing = contact.outgoingCreatedAt

        switch (incoming, outgoing) {
        case let (incoming?, outgoing?):
            // Both halves exist, so this pair is established. The older row is
            // the original ask; the newer one is the acceptance, and which side
            // accepted follows from which row is newer.
            return incoming <= outgoing
                ? [RequestEvent(kind: .theyAsked, date: incoming),
                   RequestEvent(kind: .weAccepted, date: outgoing)]
                : [RequestEvent(kind: .weAsked, date: outgoing),
                   RequestEvent(kind: .theyAccepted, date: incoming)]
        case let (incoming?, nil):
            return [RequestEvent(kind: .theyAsked, date: incoming)]
        case let (nil, outgoing?):
            return [RequestEvent(kind: .weAsked, date: outgoing)]
        case (nil, nil):
            return []
        }
    }

    private var activityEntries: [ActivityEntry] {
        let entries = payments.map { ActivityEntry.payment($0) }
            + requestEvents.map { ActivityEntry.request($0) }
        return entries.sorted { $0.date > $1.date }
    }

    /// Wording matches the notifications screen key-for-key so the same event
    /// reads the same in both places and shares one translation.
    private func requestText(_ event: RequestEvent) -> String {
        switch event.kind {
        case .theyAsked:
            String(
                format: NSLocalizedString("%@ has sent you a contact request", comment: "DashPay Notifications"),
                contact.displayTitle)
        case .weAsked:
            String(
                format: NSLocalizedString("You sent a contact request to %@", comment: "DashPay Notifications"),
                contact.displayTitle)
        case .theyAccepted:
            String(
                format: NSLocalizedString("%@ accepted your contact request", comment: "DashPay Notifications"),
                contact.displayTitle)
        case .weAccepted:
            String(
                format: NSLocalizedString("You added %@ as a contact", comment: "DashPay Notifications"),
                contact.displayTitle)
        }
    }

    private func requestRow(_ event: RequestEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .foregroundColor(.dash.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(requestText(event))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.activityDateFormatter.string(from: event.date))
                    .font(.system(size: 11))
                    .foregroundColor(.dash.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private static let activityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// One payment row. Tappable → the standard tx-detail screen when
    /// the on-chain transaction resolves in this wallet's store; a plain
    /// row otherwise (H1-lost sends, or a received tx not yet synced).
    @ViewBuilder
    private func paymentRow(_ payment: SwiftDashSDKContactsService.ContactPayment) -> some View {
        let resolvedTx = resolvedByTxid[payment.id]
        HStack(spacing: 10) {
            Image(systemName: payment.direction == .sent
                ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(payment.direction == .sent ? .dash.blue : .dashGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(payment.direction == .sent ? "-" : "+")\(Self.dashString(duffs: payment.amountDuffs)) DASH")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.dash.primaryText)
                if let fiat = payment.fiatString {
                    Text(fiat)
                        .font(.system(size: 12))
                        .foregroundColor(.dash.secondaryText)
                }
                if let memo = payment.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.system(size: 12))
                        .foregroundColor(.dash.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(payment.date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 12))
                .foregroundColor(.dash.tertiaryText)
            if resolvedTx != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.dash.tertiaryText)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if resolvedTx != nil { selectedPaymentId = payment.id }
        }
    }

    /// Fetch the payment history and resolve each row's on-chain tx
    /// (main-thread SwiftData reads; a handful of rows, <10ms each).
    private func loadPayments() {
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

    private static func dashString(duffs: UInt64) -> String {
        let dash = Decimal(duffs) / Decimal(100_000_000)
        return "\(dash)"
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                try await operation()
                closeProfile()
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // User backed out of the PIN prompt.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - PayContactSheet

/// Pay-to-contact from the contact profile. The amount step is the Send
/// tab's own `ExternalSendAmountScreen` on a `SendViewModel` opened on this
/// contact — the screen "Send to username" ends on — so the amount entry and
/// the review are shared. A sheet of its own had drifted: it took DASH only,
/// while its fiat line looked tappable and did nothing.
///
/// From the shared screen this gets the DASH/fiat switch, the pre-send
/// review, the fee-aware cap, the sync gate and the per-contact lock after a
/// broadcast with an unknown outcome. The outcome is still this sheet's own:
/// the Send tab ends on the UIKit send-success screen, which this sheet,
/// presented from SwiftUI and UIKit hosts alike, does not reach.
struct PayContactSheet: View {
    /// The snapshot the sheet opened on. The view model keeps the current one
    /// (`contactRecipient`), and that is the one the sheet shows.
    let contact: ContactItem

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SendViewModel
    @State private var sent: SendViewModel.SentContactPayment?

    init(contact: ContactItem) {
        self.contact = contact
        // Built inside the autoclosure, so a re-render of the profile does not
        // construct (and subscribe) a view model only to drop it.
        _viewModel = StateObject(wrappedValue: {
            let viewModel = SendViewModel()
            viewModel.setContactRecipient(contact)
            return viewModel
        }())
    }

    var body: some View {
        Group {
            if let sent {
                success(sent)
            } else {
                ExternalSendAmountScreen(
                    viewModel: viewModel,
                    onBack: { dismiss() },
                    onContinueCore: { _, _ in
                        assertionFailure("A contact payment reached the Core → Core route")
                    },
                    onContinueContact: { send() },
                    onSendCompleted: {
                        assertionFailure("A contact payment reached SendConfirmSheet")
                    })
            }
        }
        // The amount step carries its own keypad, so it needs the full height.
        .presentationDetents([.large])
        // Swiping the sheet away mid-broadcast would hide the outcome — the
        // success, or the "don't send it again" notice of an unknown one.
        .interactiveDismissDisabled(viewModel.isSendingToContact)
    }

    private func success(_ payment: SendViewModel.SentContactPayment) -> some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.dashGreen)
                Text(NSLocalizedString("Payment Sent", comment: "DashPay Contacts"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                Text(String(
                    format: NSLocalizedString("%@ DASH sent to %@", comment: "DashPay Contacts"),
                    payment.amountDuffs.formattedDashAmountWithoutCurrencySymbol,
                    recipientTitle))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                Text(String(
                    format: NSLocalizedString("Network fee: %@ DASH", comment: "DashPay Contacts"),
                    payment.feeDuffs.formattedDashAmountWithoutCurrencySymbol))
                    .font(.system(size: 12))
                    .foregroundColor(.dash.tertiaryText)
                Spacer(minLength: 0)
            }
            .padding(24)
            .padding(.top, 24)
            .navigationTitle(String(
                format: NSLocalizedString("Pay %@", comment: "DashPay Contacts"),
                recipientTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                        .foregroundColor(.dash.blue)
                }
            }
        }
    }

    private var recipientTitle: String {
        (viewModel.contactRecipient ?? contact).displayTitle
    }

    // MARK: Pay

    /// `sendToContact` runs the spend-auth gate and the SDK's single-shot
    /// build + sign + broadcast, projects the new Sent entry to SwiftData,
    /// and keeps any failure on the view model, where the amount step shows
    /// it inline. A cancelled PIN prompt returns nil and leaves no error.
    private func send() {
        Task {
            sent = await viewModel.sendToContact()
        }
    }
}
