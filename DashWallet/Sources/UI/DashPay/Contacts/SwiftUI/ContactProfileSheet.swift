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
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
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
            .sheet(isPresented: $showingPaySheet) {
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
                    // changed. Do not leave an actionable stale profile open.
                    dismiss()
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
                dismiss()
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // User backed out of the PIN prompt.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - PayContactSheet

/// Minimal pay-to-contact amount sheet (Row #18 phase 6). The Pay
/// button is the explicit user confirmation; tapping it runs the
/// spend-auth gate and then the single-shot SDK payment (which
/// derives the contact's DIP-15 receive address Rust-side, then
/// builds + signs + broadcasts). The network fee is charged by the
/// SDK on top of the entered amount — the cap below uses
/// `maxSendable` (spendable minus a conservative fee reserve) so the
/// fee can't push the send over the balance.
struct PayContactSheet: View {
    let contact: ContactItem

    @Environment(\.dismiss) private var dismiss
    @StateObject private var walletState = SwiftDashSDKWalletState.shared
    @State private var amountText = ""
    @State private var isSending = false
    @State private var sentTxid: Data? = nil
    /// Exact network fee (duffs) of the broadcast transaction.
    @State private var sentFeeDuffs: UInt64? = nil
    /// Duffs actually broadcast, captured at send time.
    ///
    /// The confirmation must state what was paid, not what was typed. Echoing
    /// `amountText` back made any gap between the two — a locale separator, a
    /// stray character, precision the parser drops — render as a truthful-looking
    /// "sent" line for an amount that never left the wallet.
    @State private var sentAmountDuffs: UInt64?
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let txid = sentTxid {
                    success(txid: txid)
                } else {
                    form
                }
            }
            .padding(24)
            .navigationTitle(String(
                format: NSLocalizedString("Pay %@", comment: "DashPay Contacts"),
                contact.displayTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString(sentTxid == nil ? "Cancel" : "Done", comment: "")) {
                        dismiss()
                    }
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
        }
        // The sheet carries its own keypad now, so it needs the room the
        // system keyboard used to occupy.
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var form: some View {
        // The shared amount surface every other send screen uses, over the
        // app's own keypad. A raw `TextField` + `.decimalPad` accepted whatever
        // the system keyboard allowed — a bare separator, a locale comma, more
        // precision than DASH has — and left validation to the parser, so the
        // typed text and the amount actually sent could disagree.
        EnterAmountView(
            primaryAmount: amountText.isEmpty ? "0" : amountText,
            secondaryAmount: fiatAmountText,
            primaryCurrency: .dash,
            secondaryCurrency: .fiat(App.fiatCurrency),
            isPrimarySelected: true,
            isCurrencySelectorHidden: true,
            onMax: { amountText = Self.dashString(duffs: maxSendable) }
        )
        .padding(.top, 12)

        Text(String(
            format: NSLocalizedString("Available: %@ DASH", comment: "DashPay Contacts"),
            Self.dashString(duffs: maxSendable)))
            .font(.system(size: 13))
            .foregroundColor(.dash.secondaryText)

        Text(NSLocalizedString("A network fee will be added on top of the amount.", comment: "DashPay Contacts"))
            .font(.system(size: 12))
            .foregroundColor(.dash.tertiaryText)

        NumericKeyboardView(
            value: $amountText,
            showDecimalSeparator: true,
            actionButtonText: NSLocalizedString("Pay", comment: "DashPay Contacts"),
            actionEnabled: parsedDuffs != nil,
            inProgress: isSending,
            actionHandler: { pay() }
        )
        .padding(.top, 8)
    }

    /// Fiat equivalent of what is typed, for the secondary line. Empty while
    /// the amount is unparseable or rates have not arrived.
    private var fiatAmountText: String {
        guard let duffs = parsedDuffs else { return "" }
        let dash = Decimal(duffs) / Decimal(100_000_000)
        return CurrencyExchanger.shared.fiatAmountString(for: dash)
    }

    private func success(txid: Data) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.dashGreen)
            Text(NSLocalizedString("Payment Sent", comment: "DashPay Contacts"))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.dash.primaryText)
            Text(String(
                format: NSLocalizedString("%@ DASH sent to %@", comment: "DashPay Contacts"),
                sentAmountDuffs.map { Self.dashString(duffs: $0) } ?? amountText,
                contact.displayTitle))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
            if let fee = sentFeeDuffs {
                Text(String(
                    format: NSLocalizedString("Network fee: %@ DASH", comment: "DashPay Contacts"),
                    Self.dashString(duffs: fee)))
                    .font(.system(size: 12))
                    .foregroundColor(.dash.tertiaryText)
            }
        }
        .padding(.top, 24)
    }

    // MARK: Amounts

    private var maxSendable: UInt64 {
        walletState.feeAwareMaxSendable()
    }

    /// Entered DASH amount in duffs, or nil when unparseable, zero,
    /// or above the sendable cap. The cap check runs in `Decimal`
    /// space BEFORE the `UInt64` conversion — `NSDecimalNumber`'s
    /// `uint64Value` wraps modulo 2^64, so an overflowing input
    /// (e.g. 2^64 + 1 duffs) would otherwise alias to a tiny value
    /// that passes the range check and sends the wrong amount.
    private var parsedDuffs: UInt64? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let dash = Decimal(string: normalized), dash > 0 else { return nil }
        let duffsDecimal = dash * Decimal(100_000_000)
        guard duffsDecimal <= Decimal(maxSendable) else { return nil }
        let duffs = NSDecimalNumber(decimal: duffsDecimal).uint64Value
        guard duffs > 0 else { return nil }
        return duffs
    }

    private static func dashString(duffs: UInt64) -> String {
        let dash = Decimal(duffs) / Decimal(100_000_000)
        return "\(dash)"
    }

    // MARK: Pay

    private func pay() {
        guard let duffs = parsedDuffs, !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let (txid, feeDuffs) = try await WalletSendService.shared.sendToContact(
                    contactIdentityId: contact.contactIdentityId,
                    amount: duffs)
                sentTxid = txid
                sentFeeDuffs = feeDuffs
                sentAmountDuffs = duffs
                // Project the freshly recorded Sent entry to SwiftData
                // right away — the entry lives only in Rust memory
                // until a projection runs, and an app kill before one
                // would lose it permanently (the SDK cannot re-derive
                // sent history; learned the hard way 2026-07-08).
                SwiftDashSDKContactsService.shared.refreshPaymentsProjection()
            } catch {
                let nsError = error as NSError
                if !WalletSendService.isAuthenticationCancelledError(nsError) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
