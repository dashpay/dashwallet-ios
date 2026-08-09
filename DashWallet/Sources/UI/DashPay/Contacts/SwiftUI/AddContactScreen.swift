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

struct AddContactScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query: String

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
    @State private var previewTarget: DpnsSearchResult? = nil
    @State private var errorMessage: String? = nil
    /// Username of the recipient of a just-sent request — drives the
    /// centered success card (nil = hidden).
    @State private var sentToUsername: String?
    @State private var showScanner = false
    @State private var showMyQR = false
    /// A scanned user QR is being verified against Platform (DPNS
    /// lookup + identity id match) — drives the blocking spinner.
    @State private var isVerifyingScan = false

    @ObservedObject private var service = SwiftDashSDKContactsService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    ContactsSearchField(
                        placeholder: NSLocalizedString("Search by username", comment: "DashPay Contacts"),
                        text: $query,
                        height: 52)
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                    qrButtonsRow
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                    resultsList
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
            .sheet(item: $previewTarget) { target in
                AddContactPreviewSheet(
                    result: target,
                    collision: collision(for: target),
                    contact: service.contactItem(for: target.identityId),
                    onSend: { send(to: target) },
                    onAccept: { accept(target) })
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
        ScrollView {
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
                        .onTapGesture { previewTarget = result }
                        .onAppear { checkEligibilityIfNeeded(result) }
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 16)
        }
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

    private func collision(for result: DpnsSearchResult) -> Collision {
        if let ownId = DWCurrentUserIdentityInfo.shared.identityId,
           ownId == result.identityId {
            return .isSelf
        }
        if service.contacts.contains(where: { $0.contactIdentityId == result.identityId }) {
            return .established
        }
        if service.outgoingRequests.contains(where: { $0.contactIdentityId == result.identityId }) {
            return .alreadyRequested
        }
        if service.incomingRequests.contains(where: { $0.contactIdentityId == result.identityId }) {
            return .theyAskedUs
        }
        if eligibilityById[result.identityId] == false {
            return .missingDashPayKeys
        }
        return .none
    }

    @ViewBuilder
    private func resultRow(_ result: DpnsSearchResult) -> some View {
        let state = collision(for: result)
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
                    previewTarget = result
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
                AcceptPillButton { accept(result) }
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
    /// is an exact-username DPNS search whose result must carry the
    /// scanned identity id — the sheet then renders a Platform-backed
    /// `DpnsSearchResult`, never the QR's own unproven claim.
    private func handleScannedCode(_ value: String) {
        showScanner = false
        guard let link = DashPayUserLink.parse(value) else {
            errorMessage = NSLocalizedString("This isn't a DashPay user QR code.", comment: "DashPay Contacts: scanned QR is a payment/invitation/foreign code")
            return
        }
        // Mirror the scanned name into the search field so the results
        // list behind the confirmation sheet shows the same user.
        query = link.username
        isVerifyingScan = true
        Task {
            defer { isVerifyingScan = false }
            do {
                let matches = try await service.searchUsernames(prefix: link.username)
                guard let match = matches.first(where: {
                    $0.identityId == link.identityId
                        && $0.fullName.withoutDashSuffix.lowercased() == link.username.lowercased()
                }) else {
                    errorMessage = String(
                        format: NSLocalizedString("%@ couldn't be verified on the Dash network. The QR code may be outdated.", comment: "DashPay Contacts: scanned username doesn't resolve to the scanned identity"),
                        link.username)
                    return
                }
                checkEligibilityIfNeeded(match)
                previewTarget = match
            } catch {
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

    /// Resolve whether one result can receive a contact request (DIP-15
    /// needs the recipient's DashPay encryption + decryption keys), the
    /// first time its row scrolls into view. Marks pre-DashPay
    /// identities so the user sees "Can't receive contact requests"
    /// instead of hitting the PIN gate and a network error. One query
    /// per identity, deduped via `eligibilityInFlight`.
    private func checkEligibilityIfNeeded(_ result: DpnsSearchResult) {
        let id = result.identityId
        guard eligibilityById[id] == nil, !eligibilityInFlight.contains(id) else { return }
        eligibilityInFlight.insert(id)
        Task {
            defer { eligibilityInFlight.remove(id) }
            let checked = await service.contactRequestEligibility(for: [id])
            eligibilityById.merge(checked) { _, new in new }
        }
    }

    // MARK: Actions

    private func send(to target: DpnsSearchResult) {
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

    private func accept(_ target: DpnsSearchResult) {
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
    let result: DpnsSearchResult
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
                    if username != title {
                        Text(username)
                            .font(.system(size: 14))
                            .foregroundColor(.dash.secondaryText)
                    }
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
                dismiss()
            }
        case .theyAskedUs:
            primaryButton(NSLocalizedString("Accept", comment: "DashPay Contacts"), color: .dashGreen) {
                onAccept()
                dismiss()
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
