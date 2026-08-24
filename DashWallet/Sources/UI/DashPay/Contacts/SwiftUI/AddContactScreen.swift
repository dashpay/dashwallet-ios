//
//  AddContactScreen.swift
//  DashWallet
//
//  Add-contact flow (migration Row #18 phase 3): debounced DPNS
//  prefix search via `searchDpnsNames`, collision detection against
//  the local snapshots, DashPay-key eligibility marking, and the
//  PIN-gated send. Visual design mirrors the Android dash-wallet
//  "Add New Contact" screen (activity_search_dashpay_profile_1.xml):
//  centered icon + "Add a New Contact" headline + "Find a User"
//  subtitle, elevated rounded white search field, white card result
//  rows on the gray background.
//
//  QR entry points ("My QR" / "Scan QR" buttons under the search
//  field): scan another user's `dashpay://user` code — verified
//  against Platform before the send-confirmation sheet opens — and
//  show your own (`MyDashPayUserQRSheet`).
//

import SwiftDashSDK
import SwiftUI
import DashUIKit

/// Identity + DPNS full name pair driving the send-confirmation sheet
/// — built from a tapped search row, or from a scan verified via exact
/// DPNS resolution (the SDK's `DpnsSearchResult` is not constructible
/// app-side, and a capped prefix page must not gate a verified scan).
struct ContactCandidate: Identifiable, Equatable {
    let identityId: Data
    let fullName: String
    /// Unique per (name, identity) pair — a contested name shares
    /// `fullName` across contenders.
    var id: String { fullName + "|" + identityId.map { String(format: "%02x", $0) }.joined() }
}

struct AddContactScreen: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    @State private var query: String

    private enum Layout {
        static let searchFieldHeight: CGFloat = 52
        static let searchHeaderTopPadding: CGFloat = 12
        static let searchHeaderHeight = searchFieldHeight + searchHeaderTopPadding
    }

    private enum ScrollTarget: Hashable {
        case searchField
    }

    /// Contact action selected in the preview. The action is deliberately
    /// deferred until the preview sheet's dismissal completes so the PIN
    /// prompt is never presented from a controller that is disappearing.
    private enum PendingPreviewAction {
        case send(ContactCandidate)
        case accept(ContactCandidate)
    }

    /// `initialQuery` prefills the search (the Contacts tab's network
    /// teaser hands its text over); the search fires on appear so the
    /// results are already loading when the sheet lands.
    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }
    @State private var results: [DpnsSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var sendingIds: Set<Data> = []
    /// identityId → can receive a contact request (has enabled
    /// DashPay ENCRYPTION + DECRYPTION keys). Absent = unknown
    /// (eligibility query unavailable) — row stays actionable and the
    /// send path surfaces the real error.
    @State private var eligibilityById: [Data: Bool] = [:]
    /// identityIds with an in-flight eligibility query — set while the
    /// lazy per-row check runs so a row doesn't fire it twice.
    @State private var eligibilityInFlight: Set<Data> = []
    /// Tapped result shown in the preview sheet (the single
    /// send/accept confirmation surface).
    @State private var previewTarget: ContactCandidate? = nil
    @State private var pendingPreviewAction: PendingPreviewAction? = nil
    @State private var errorMessage: String? = nil
    /// Username of the recipient of a just-sent request — drives the
    /// centered success card (nil = hidden).
    @State private var sentToUsername: String?
    @State private var showScanner = false
    @State private var showMyQR = false
    /// A scanned user QR is being verified against Platform (DPNS
    /// lookup + identity id match) — drives the blocking spinner.
    @State private var isVerifyingScan = false
    /// The in-flight verification. Canceled by the next scan and on
    /// screen dismissal so a stale lookup can never overwrite the
    /// newer one's `previewTarget`/`errorMessage`/spinner state.
    @State private var scanVerifyTask: Task<Void, Never>? = nil

    @ObservedObject private var service = SwiftDashSDKContactsService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                GeometryReader { geometry in
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                header

                                Section {
                                    LazyVStack(spacing: 0) {
                                        qrButtonsRow
                                            .padding(.horizontal, 24)
                                            .padding(.top, 12)
                                        resultsList
                                    }
                                    // Keep the search anchor reachable even before a
                                    // short/empty result set has enough content to scroll.
                                    .frame(
                                        minHeight: max(0, geometry.size.height - Layout.searchHeaderHeight),
                                        alignment: .top)
                                } header: {
                                    ContactsSearchField(
                                        placeholder: NSLocalizedString("Search by username", comment: "DashPay Contacts"),
                                        text: $query,
                                        height: Layout.searchFieldHeight,
                                        focus: $isSearchFocused)
                                        .padding(.horizontal, 24)
                                        .padding(.top, Layout.searchHeaderTopPadding)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.dash.primaryBackground)
                                        .id(ScrollTarget.searchField)
                                        .zIndex(1)
                                }
                            }
                        }
                        .onChange(of: isSearchFocused) { _, focused in
                            guard focused else { return }
                            Task { @MainActor in
                                await Task.yield()
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    scrollProxy.scrollTo(ScrollTarget.searchField, anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                        .foregroundColor(.dash.blue)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                GenericQRScannerView(
                    onQRCodeScanned: { handleScannedCode($0) },
                    onCancel: { showScanner = false })
            }
            .sheet(isPresented: $showMyQR) {
                if let link = myUserLink {
                    MyDashPayUserQRSheet(
                        link: link,
                        displayName: DWCurrentUserIdentityInfo.shared.displayName)
                }
            }
            .onChange(of: query) { _, _ in
                scheduleSearch()
            }
            .onAppear {
                if !trimmedQuery.isEmpty {
                    scheduleSearch()
                }
            }
            .onDisappear {
                scanVerifyTask?.cancel()
                scanVerifyTask = nil
                isVerifyingScan = false
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
            .sheet(
                item: $previewTarget,
                onDismiss: performPendingPreviewAction
            ) { target in
                AddContactPreviewSheet(
                    result: target,
                    collision: collision(identityId: target.identityId),
                    contact: service.contactItem(for: target.identityId),
                    onSend: { queuePreviewAction(.send(target)) },
                    onAccept: { queuePreviewAction(.accept(target)) })
            }
            .overlay {
                if isVerifyingScan {
                    VStack(spacing: 12) {
                        SwiftUI.ProgressView()
                        Text(NSLocalizedString("Verifying user…", comment: "DashPay Contacts: spinner after scanning a user QR code"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.dash.secondaryText)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.dash.secondaryBackground)
                            .shadow(color: Color.dash.shadow, radius: 24, x: 0, y: 8))
                } else if let username = sentToUsername {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.dashGreen)
                        Text(String(
                            format: NSLocalizedString("Contact request sent to %@", comment: "DashPay Contacts: success card after sending a request"),
                            username))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.dash.primaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.dash.secondaryBackground)
                            .shadow(color: Color.dash.shadow, radius: 24, x: 0, y: 8))
                    .padding(.horizontal, 40)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
    }

    /// "My QR" + "Scan QR" side by side under the search field. "My
    /// QR" needs an identity with a DPNS name (the QR encodes both),
    /// so before that "Scan QR" spans the full width alone.
    private var qrButtonsRow: some View {
        HStack(spacing: 10) {
            if myUserLink != nil {
                qrActionButton(
                    NSLocalizedString("My QR", comment: "DashPay Contacts: shows the user's own contact QR code"),
                    systemImage: "qrcode") {
                    showMyQR = true
                }
            }
            qrActionButton(
                NSLocalizedString("Scan QR", comment: ""),
                systemImage: "qrcode.viewfinder") {
                showScanner = true
            }
        }
    }

    private func qrActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.dash.blue)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.dash.blue.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    /// Android search screen header: icon, headline, subtitle.
    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(.dash.blue)
                .padding(.bottom, 14)
            Text(NSLocalizedString("Add a New Contact", comment: "DashPay Contacts"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.dash.primaryText)
            Text(NSLocalizedString("Find a User", comment: "DashPay Contacts"))
                .font(.system(size: 16))
                .foregroundColor(.dash.secondaryText)
        }
        .padding(.top, 28)
    }

    @ViewBuilder
    private var resultsList: some View {
        LazyVStack(spacing: 6) {
            if isSearching {
                SwiftUI.ProgressView()
                    .padding(.top, 32)
            } else if results.isEmpty && trimmedQuery.count >= 2 {
                Text(NSLocalizedString("No usernames found", comment: "DashPay Contacts"))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                    .padding(.top, 32)
            } else if trimmedQuery.count < 2 && !trimmedQuery.isEmpty {
                Text(NSLocalizedString("Type at least 2 characters to search usernames", comment: "DashPay Contacts"))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                    .padding(.top, 32)
            }
            ForEach(results) { result in
                resultRow(result)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.dash.secondaryBackground))
                    .contentShape(Rectangle())
                    .onTapGesture { previewTarget = candidate(result) }
                    .onAppear { checkEligibilityIfNeeded(id: result.identityId) }
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 16)
    }

    // MARK: Rows

    /// Non-private so `AddContactPreviewSheet` can render the
    /// state-appropriate CTA from the same classification.
    enum Collision {
        case none
        case established
        case alreadyRequested
        case theyAskedUs
        case isSelf
        /// Identity lacks the DashPay-contract encryption/decryption
        /// keys a contact request needs (pre-DashPay identities).
        case missingDashPayKeys
    }

    private func collision(identityId: Data) -> Collision {
        if let ownId = DWCurrentUserIdentityInfo.shared.identityId,
           ownId == identityId {
            return .isSelf
        }
        if service.contacts.contains(where: { $0.contactIdentityId == identityId }) {
            return .established
        }
        if service.outgoingRequests.contains(where: { $0.contactIdentityId == identityId }) {
            return .alreadyRequested
        }
        if service.incomingRequests.contains(where: { $0.contactIdentityId == identityId }) {
            return .theyAskedUs
        }
        if eligibilityById[identityId] == false {
            return .missingDashPayKeys
        }
        return .none
    }

    /// The sheet-driving candidate for a tapped search row.
    private func candidate(_ result: DpnsSearchResult) -> ContactCandidate {
        ContactCandidate(identityId: result.identityId, fullName: result.fullName)
    }

    @ViewBuilder
    private func resultRow(_ result: DpnsSearchResult) -> some View {
        let state = collision(identityId: result.identityId)
        HStack(spacing: 10) {
            ContactAvatarView(
                title: result.fullName,
                avatarURL: nil,
                identitySeed: result.identityId)
                .padding(.leading, 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.fullName.withoutDashSuffix)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                if let hint = collisionText(state) {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundColor(state == .alreadyRequested ? .dashGolden : .dash.tertiaryText)
                }
            }
            Spacer()
            trailingControl(result, state: state)
                .padding(.trailing, 12)
        }
        .frame(height: 70)
    }

    private func collisionText(_ state: Collision) -> String? {
        switch state {
        case .none: return nil
        case .established: return NSLocalizedString("Already a contact", comment: "DashPay Contacts")
        case .alreadyRequested: return NSLocalizedString("Contact Request Pending", comment: "DashPay Contacts")
        case .theyAskedUs: return NSLocalizedString("Sent you a request", comment: "DashPay Contacts")
        case .isSelf: return NSLocalizedString("This is you", comment: "DashPay Contacts")
        case .missingDashPayKeys: return NSLocalizedString("Can't receive contact requests", comment: "DashPay Contacts")
        }
    }

    @ViewBuilder
    private func trailingControl(_ result: DpnsSearchResult, state: Collision) -> some View {
        if sendingIds.contains(result.identityId) {
            SwiftUI.ProgressView()
        } else {
            switch state {
            case .none:
                Button {
                    previewTarget = candidate(result)
                } label: {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(.dash.blue)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dash.blue.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Send Contact Request", comment: "DashPay Contacts"))
            case .theyAskedUs:
                AcceptPillButton { accept(candidate(result)) }
            case .established:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.dashGreen)
            case .alreadyRequested:
                Image(systemName: "hourglass")
                    .foregroundColor(.dashGolden)
            case .isSelf:
                EmptyView()
            case .missingDashPayKeys:
                Image(systemName: "lock.slash")
                    .foregroundColor(.dash.tertiaryText)
            }
        }
    }

    // MARK: My QR / scanning

    /// The current user's scannable identity payload — nil until the
    /// identity is registered AND owns a DPNS name (the QR encodes
    /// both, so there is nothing honest to show before that).
    private var myUserLink: DashPayUserLink? {
        guard let identityId = DWCurrentUserIdentityInfo.shared.identityId,
              let username = DWCurrentUserIdentityInfo.shared.username
        else { return nil }
        return DashPayUserLink(identityId: identityId, username: username.withoutDashSuffix)
    }

    /// Scanned QR → parse → verify against Platform → the same
    /// send-confirmation sheet a search result tap opens. Verification
    /// is an exact DPNS resolution (`resolveUsername`) that must return
    /// the scanned identity id — not a capped prefix page that could
    /// miss the identity, and never the QR's own unproven claim. The
    /// search field is left untouched so no second (debounced) lookup
    /// races this one.
    ///
    /// Every UI-state write happens on the main actor after a
    /// cancellation check, and a new scan cancels the previous task
    /// first, so a slow stale lookup can neither clear the newer
    /// scan's spinner nor overwrite its result.
    private func handleScannedCode(_ value: String) {
        showScanner = false
        // A new scan replaces the previous one wholesale — cancel its
        // verification before even parsing, so an invalid code can't
        // leave a stale lookup spinning behind the error alert and
        // popping the prior QR's preview later.
        scanVerifyTask?.cancel()
        scanVerifyTask = nil
        isVerifyingScan = false

        guard let link = DashPayUserLink.parse(value) else {
            errorMessage = NSLocalizedString("This isn't a DashPay user QR code.", comment: "DashPay Contacts: scanned QR is a payment/invitation/foreign code")
            return
        }
        isVerifyingScan = true
        scanVerifyTask = Task {
            defer {
                // A canceled task's replacement owns the spinner now.
                if !Task.isCancelled {
                    isVerifyingScan = false
                }
            }
            do {
                let ownerId = try await service.resolveUsername(link.username)
                guard !Task.isCancelled else { return }
                guard ownerId == link.identityId else {
                    errorMessage = String(
                        format: NSLocalizedString("%@ couldn't be verified on the Dash network. The QR code may be outdated.", comment: "DashPay Contacts: scanned username doesn't resolve to the scanned identity"),
                        link.username)
                    return
                }
                checkEligibilityIfNeeded(id: link.identityId)
                previewTarget = ContactCandidate(
                    identityId: link.identityId,
                    // Search rows carry the ".dash"-suffixed full name;
                    // keep the scan-sourced candidate consistent.
                    fullName: link.username + ".dash")
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Search

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let prefix = trimmedQuery
        guard prefix.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            // Debounce keystrokes; canceled by the next onChange.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                // limit 0 → the SDK's default cap (100), matching the
                // legacy global search's page size. Eligibility is
                // resolved lazily per visible row (below) so a large
                // result set doesn't fan out a key query for every hit.
                let found = try await service.searchUsernames(prefix: prefix)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Resolve whether one identity can receive a contact request
    /// (DIP-15 needs the recipient's DashPay encryption + decryption
    /// keys), the first time its row scrolls into view or its scan is
    /// verified. Marks pre-DashPay identities so the user sees "Can't
    /// receive contact requests" instead of hitting the PIN gate and a
    /// network error. One query per identity, deduped via
    /// `eligibilityInFlight`.
    private func checkEligibilityIfNeeded(id: Data) {
        guard eligibilityById[id] == nil, !eligibilityInFlight.contains(id) else { return }
        eligibilityInFlight.insert(id)
        Task {
            defer { eligibilityInFlight.remove(id) }
            let checked = await service.contactRequestEligibility(for: [id])
            eligibilityById.merge(checked) { _, new in new }
        }
    }

    // MARK: Actions

    /// Closing one modal while presenting the PIN modal from it races
    /// UIKit's presentation hierarchy. Drive dismissal through the owning
    /// binding, then let the sheet's `onDismiss` start authentication only
    /// after the transition has completed.
    private func queuePreviewAction(_ action: PendingPreviewAction) {
        guard pendingPreviewAction == nil else { return }
        isSearchFocused = false
        pendingPreviewAction = action
        previewTarget = nil
    }

    private func performPendingPreviewAction() {
        guard let action = pendingPreviewAction else { return }
        // Consume first so a repeated dismissal callback cannot dispatch the
        // same Platform action twice.
        pendingPreviewAction = nil

        switch action {
        case .send(let target):
            // The background contact sync or eligibility lookup may have
            // changed the relationship while the preview was dismissing.
            switch collision(identityId: target.identityId) {
            case .none:
                send(to: target)
            case .missingDashPayKeys:
                errorMessage = NSLocalizedString(
                    "This user hasn't set up the keys needed to receive contact requests yet.",
                    comment: "DashPay Contacts")
            default:
                return
            }
        case .accept(let target):
            guard case .theyAskedUs = collision(identityId: target.identityId) else { return }
            accept(target)
        }
    }

    private func send(to target: ContactCandidate) {
        guard eligibilityById[target.identityId] != false else { return }
        guard !sendingIds.contains(target.identityId) else { return }
        sendingIds.insert(target.identityId)
        Task {
            defer { sendingIds.remove(target.identityId) }
            do {
                try await service.sendContactRequest(
                    to: target.identityId,
                    usernameHint: target.fullName)
                let username = target.fullName.withoutDashSuffix
                withAnimation { sentToUsername = username }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                // Another send may have replaced the card in the
                // meantime — only this recipient's own timer clears it.
                withAnimation {
                    if sentToUsername == username {
                        sentToUsername = nil
                    }
                }
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // User backed out of the PIN prompt.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func accept(_ target: ContactCandidate) {
        guard !sendingIds.contains(target.identityId) else { return }
        sendingIds.insert(target.identityId)
        Task {
            defer { sendingIds.remove(target.identityId) }
            do {
                try await service.acceptContactRequest(from: target.identityId)
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // User backed out of the PIN prompt.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - AddContactPreviewSheet

/// Preview shown when a search result is tapped — the SDK-side stand-in
/// for the legacy `DWUserProfileViewController` a user reached before
/// sending a request. It confirms who you're adding (avatar, name,
/// username, and — when we already hold it — the contact's profile
/// message) and carries the single send/accept CTA.
///
/// Honest limitation: the SDK exposes no on-chain profile fetch for an
/// arbitrary identity (`getDashPayProfile`/`getContactProfile` read the
/// local cache only), so for a true stranger this shows the DPNS
/// username + placeholder avatar, not a fetched bio. Real profile
/// fields appear once the identity is one of our contacts/requesters
/// (`contact` non-nil). Nothing is fabricated when the data is absent.
struct AddContactPreviewSheet: View {
    let result: ContactCandidate
    let collision: AddContactScreen.Collision
    /// The already-materialized contact row when this identity is known
    /// (established / incoming / outgoing); nil for a true stranger.
    let contact: ContactItem?
    let onSend: () -> Void
    let onAccept: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var username: String { result.fullName.withoutDashSuffix }
    private var title: String { contact?.displayTitle ?? username }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                VStack(spacing: 12) {
                    ContactAvatarView(
                        title: title,
                        avatarURL: contact?.avatarURL,
                        identitySeed: result.identityId,
                        size: 88)
                        .padding(.top, 28)
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.dash.primaryText)
                    // Kept even when it equals the title: the title may be an
                    // alias for an already-known contact, and the registered
                    // username is what the request is actually addressed to.
                    Text(username)
                        .font(.system(size: 14))
                        .foregroundColor(.dash.secondaryText)
                    // Before accepting a request or sending one, the id is the
                    // only field that distinguishes two identities presenting
                    // the same DPNS label.
                    ContactIdentityIdView(identityId: result.identityId)
                        .padding(.top, 2)
                    if let message = contact?.publicMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundColor(.dash.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 2)
                    }
                    Text(rationale)
                        .font(.system(size: 14))
                        .foregroundColor(.dash.tertiaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 4)
                    Spacer()
                    cta
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Close", comment: "")) { dismiss() }
                        .foregroundColor(.dash.blue)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// State-appropriate framing copy — the persuasive "pay directly by
    /// username, keep a shared history" line the legacy send-request
    /// cell showed, adapted per collision state.
    private var rationale: String {
        switch collision {
        case .none, .alreadyRequested:
            return String(
                format: NSLocalizedString("Add %@ as a contact to pay them directly by username and keep a shared history of your payments.", comment: "DashPay Contacts"),
                username)
        case .theyAskedUs:
            return String(
                format: NSLocalizedString("%@ wants to connect. Accept to pay each other directly by username.", comment: "DashPay Contacts"),
                username)
        case .established:
            return NSLocalizedString("You're already connected — you can pay each other directly by username.", comment: "DashPay Contacts")
        case .isSelf:
            return NSLocalizedString("This is your own identity.", comment: "DashPay Contacts")
        case .missingDashPayKeys:
            return NSLocalizedString("This user hasn't set up the keys needed to receive contact requests yet.", comment: "DashPay Contacts")
        }
    }

    @ViewBuilder
    private var cta: some View {
        switch collision {
        case .none:
            primaryButton(NSLocalizedString("Send Contact Request", comment: "DashPay Contacts"), color: .dash.blue) {
                onSend()
            }
        case .theyAskedUs:
            primaryButton(NSLocalizedString("Accept", comment: "DashPay Contacts"), color: .dashGreen) {
                onAccept()
            }
        case .alreadyRequested:
            statusLabel(NSLocalizedString("Contact Request Pending", comment: "DashPay Contacts"), systemImage: "hourglass", color: .dashGolden)
        case .established:
            statusLabel(NSLocalizedString("Already a contact", comment: "DashPay Contacts"), systemImage: "checkmark.circle.fill", color: .dashGreen)
        case .isSelf:
            EmptyView()
        case .missingDashPayKeys:
            statusLabel(NSLocalizedString("Can't receive contact requests", comment: "DashPay Contacts"), systemImage: "lock.slash", color: .dash.tertiaryText)
        }
    }

    private func primaryButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.dash.whiteText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
        }
        .buttonStyle(.plain)
    }

    private func statusLabel(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title).font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }
}

// MARK: - MyDashPayUserQRSheet

/// "My QR" — the counterpart of the scan button: renders the current
/// user's `DashPayUserLink` (identity id + preferred username) as a
/// Dash-branded QR code (`QRCodeGenerator.dashStyledImage`) another
/// Dash Wallet can scan to open the send-request confirmation for
/// this user.
struct MyDashPayUserQRSheet: View {
    let link: DashPayUserLink
    let displayName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                VStack(spacing: 6) {
                    Text(displayName ?? link.username)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.dash.primaryText)
                        .padding(.top, 20)
                    if displayName != nil {
                        Text(link.username)
                            .font(.system(size: 14))
                            .foregroundColor(.dash.secondaryText)
                    }
                    Group {
                        if let qrImage {
                            Image(uiImage: qrImage)
                                .resizable()
                                .scaledToFit()
                        } else {
                            SwiftUI.ProgressView()
                        }
                    }
                    .frame(width: 240, height: 240)
                    .padding(20)
                    // The branded QR draws Dash-blue modules on a
                    // transparent background — keep the card white in
                    // dark mode so camera scanners keep their contrast.
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: Color.dash.shadow, radius: 16, x: 0, y: 4))
                    .padding(.top, 14)
                    Text(NSLocalizedString("Let another Dash Wallet user scan this code to add you as a contact.", comment: "DashPay Contacts: caption under the user's own QR code"))
                        .font(.system(size: 14))
                        .foregroundColor(.dash.tertiaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                        .padding(.top, 14)
                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Close", comment: "")) { dismiss() }
                        .foregroundColor(.dash.blue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if qrImage == nil {
                qrImage = QRCodeGenerator.dashStyledImage(for: link.uriString, size: 240)
            }
        }
    }
}
