//
//  SwiftDashSDKContactsService.swift
//  DashWallet
//
//  App-side boundary for the DashPay contacts subsystem (migration
//  Row #18) — the SwiftDashSDK replacement for the DashSync trio
//  `DWDashPayContactsUpdater` (fetch) / `DWDashPayContactsActions`
//  (accept-decline) / Core Data FRC data sources (reads).
//
//  Read model: the SDK's DashPay background sync (started by
//  `PlatformAddressSyncCoordinator`) persists contact-request and
//  contact-profile rows to SwiftData via the Rust persister callback.
//  This service materializes those rows into `[ContactItem]`
//  snapshots — classification: a (owner, contact) pair with BOTH
//  direction rows is established, a single incoming row is a pending
//  incoming request, a single outgoing row is a pending outgoing
//  request. Reads re-run on `NSManagedObjectContextDidSave` (SwiftData
//  posts it under the hood — same mechanism `HomeViewModel` uses for
//  the tx list), debounced, and publish via `@Published` + the typed
//  `contactsDidChangeNotification`.
//
//  Write model: `sendContactRequest` / `acceptContactRequest` follow
//  the exact `DWProfileUpdateCoordinator` sequence — PIN/biometric
//  gate via `DWIdentityAuthorizer`, then `KeychainSigner` into the
//  `ManagedPlatformWallet` call. `ignoreSender` is a local-only mute
//  (no signer, no auth — parity with the legacy decline, which never
//  performed an on-chain action either).
//
//  Singleton justification (per the architecture guardrails): one
//  SwiftData/SDK-backed source of truth consumed by multiple screens
//  (contacts list, add-contact search, notifications badge, user
//  profile) — same shape as `SwiftDashSDKWalletState` and
//  `DWCurrentUserIdentityInfo`. A protocol seam is deliberately
//  deferred until a second implementation (mock/tests) exists; the
//  unit-test target is currently broken repo-wide.
//
//  dashpay target only.
//

import Combine
import CoreData
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@MainActor
final class SwiftDashSDKContactsService: ObservableObject {

    static let shared = SwiftDashSDKContactsService()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.contacts-service")

    /// Posted after every published-snapshot rebuild. New typed name —
    /// consumers migrate here from the legacy
    /// `DWDashPayContactsDidUpdateNotification` as their surfaces are
    /// rewritten (Row #18 phases 2–5).
    static let contactsDidChangeNotification =
        Notification.Name("DWSwiftDashSDKContactsDidChangeNotification")

    // MARK: - Published read model

    /// Established (mutual) contacts, sorted by display title.
    @Published private(set) var contacts: [ContactItem] = []

    /// Pending incoming requests (they asked us), newest first.
    @Published private(set) var incomingRequests: [ContactItem] = []

    /// Pending outgoing requests (we asked them), newest first.
    @Published private(set) var outgoingRequests: [ContactItem] = []

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case noWallet
        case noModelContainer
        case noIdentity
        case authCancelled
        case authFailed
        case requestNotFound
        case sdk(Error)

        var errorDescription: String? {
            switch self {
            case .noWallet:
                return NSLocalizedString("Wallet is not ready", comment: "DashPay")
            case .noModelContainer:
                return NSLocalizedString("Storage is not configured", comment: "DashPay")
            case .noIdentity:
                return NSLocalizedString("No DashPay identity is registered", comment: "DashPay")
            case .authCancelled:
                return NSLocalizedString("Authentication cancelled", comment: "DashPay")
            case .authFailed:
                return NSLocalizedString("Authentication failed", comment: "DashPay")
            case .requestNotFound:
                return NSLocalizedString("Contact request not found", comment: "DashPay")
            case .sdk(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    // MARK: - Private state

    private let authorizer = DWIdentityAuthorizer()
    private var saveObserverCancellable: AnyCancellable?
    private var activeWalletCancellable: AnyCancellable?

    /// Last run of the payments projection (see
    /// `refreshPaymentsProjection`). Throttles the piggyback call in
    /// `refresh()` so the projection's own SwiftData save can't loop
    /// it through the save-observer.
    private var lastPaymentsProjection: Date = .distantPast

    private init() {
        // SwiftData posts NSManagedObjectContextDidSave under the hood;
        // the Rust persister saves contact rows off the main context, so
        // debounce bursts (a sync pass upserts request + profile rows
        // back-to-back) into one snapshot rebuild.
        saveObserverCancellable = NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
        // The ownerId (current identity id) changes with the active wallet, so
        // a runtime wallet switch invalidates every published snapshot. Rebuild
        // against the new wallet's ownerId. `refresh` reads the ownerId from
        // `DWCurrentUserIdentityInfo`, whose cache the same notification also
        // invalidates — but NotificationCenter delivery order between the two
        // observers isn't guaranteed, so force the identity snapshot fresh here
        // (idempotent revision bump) before reading it.
        activeWalletCancellable = NotificationCenter.default
            .publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DWCurrentUserIdentityInfo.shared.refreshFromSDK()
                self?.refresh()
            }
        refresh()
    }

    // MARK: - Reads

    /// Rebuild the published snapshots from SwiftData. Cheap enough to
    /// call eagerly; also runs automatically on every (debounced)
    /// SwiftData save.
    func refresh() {
        // Seed / update the txid → DashPay-payment overlay alongside every
        // snapshot rebuild (service init covers the launch case, where the
        // home tx list renders before the first contacts sync pass).
        DashPayPaymentTxLookup.shared.refresh()
        guard let ownerId = DWCurrentUserIdentityInfo.shared.identityId,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            // No identity (or storage not up yet) — an empty contact
            // list is the true state, not an error.
            if !contacts.isEmpty || !incomingRequests.isEmpty || !outgoingRequests.isEmpty {
                contacts = []
                incomingRequests = []
                outgoingRequests = []
                NotificationCenter.default.post(name: Self.contactsDidChangeNotification, object: nil)
            }
            return
        }

        let context = modelContainer.mainContext

        let requestRows: [PersistentDashpayContactRequest]
        let profileRows: [PersistentDashpayContactProfile]
        do {
            requestRows = try context.fetch(FetchDescriptor<PersistentDashpayContactRequest>(
                predicate: PersistentDashpayContactRequest.predicate(ownerIdentityId: ownerId)))
            profileRows = try context.fetch(FetchDescriptor<PersistentDashpayContactProfile>(
                predicate: PersistentDashpayContactProfile.predicate(ownerIdentityId: ownerId)))
        } catch {
            Self.logger.error("👥 CONTACTS :: SwiftData fetch failed: \(String(describing: error), privacy: .public)")
            return
        }

        let profilesByContact = Dictionary(
            profileRows.map { ($0.contactIdentityId, $0) },
            uniquingKeysWith: { first, _ in first })

        // Group request rows into (contact → directions present).
        var rowsByContact: [Data: [PersistentDashpayContactRequest]] = [:]
        for row in requestRows {
            rowsByContact[row.contactIdentityId, default: []].append(row)
        }

        var established: [ContactItem] = []
        var incoming: [ContactItem] = []
        var outgoing: [ContactItem] = []

        for (contactId, rows) in rowsByContact {
            let hasIncoming = rows.contains { !$0.isOutgoing }
            let hasOutgoing = rows.contains { $0.isOutgoing }
            let relationship: ContactRelationship
            if hasIncoming && hasOutgoing {
                relationship = .established
            } else if hasIncoming {
                relationship = .incoming
            } else {
                relationship = .outgoing
            }

            let profile = profilesByContact[contactId]
            let newestMillis = rows.map(\.createdAtMillis).max() ?? 0
            let incomingMillis = rows.filter { !$0.isOutgoing }.map(\.createdAtMillis).max()
            let outgoingMillis = rows.filter { $0.isOutgoing }.map(\.createdAtMillis).max()
            let item = ContactItem(
                contactIdentityId: contactId,
                relationship: relationship,
                username: usernameHint(for: contactId),
                profileDisplayName: profile?.displayName,
                // Owner-private contact meta lives on the request rows
                // (the persister mirrors EstablishedContact state onto
                // both directions; take the first non-nil).
                alias: rows.compactMap(\.contactAlias).first(where: { !$0.isEmpty }),
                note: rows.compactMap(\.contactNote).first(where: { !$0.isEmpty }),
                isHidden: rows.contains(where: \.contactHidden),
                avatarURL: profile?.avatarUrl,
                publicMessage: profile?.publicMessage,
                createdAt: Date(timeIntervalSince1970: TimeInterval(newestMillis) / 1000),
                incomingCreatedAt: incomingMillis.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
                outgoingCreatedAt: outgoingMillis.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) })

            switch relationship {
            case .established: established.append(item)
            case .incoming: incoming.append(item)
            case .outgoing: outgoing.append(item)
            }
        }

        contacts = established.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
        incomingRequests = incoming.sorted { $0.createdAt > $1.createdAt }
        outgoingRequests = outgoing.sorted { $0.createdAt > $1.createdAt }

        Self.logger.info("👥 CONTACTS :: snapshot rebuilt — \(established.count, privacy: .public) established, \(incoming.count, privacy: .public) incoming, \(outgoing.count, privacy: .public) outgoing")
        NotificationCenter.default.post(name: Self.contactsDidChangeNotification, object: nil)

        // Keep the payment-history rows flowing without any screen
        // open: the projection is app-pulled (see
        // refreshPaymentsProjection), so ride the snapshot refresh at
        // most once a minute.
        if Date().timeIntervalSince(lastPaymentsProjection) > 60 {
            lastPaymentsProjection = Date()
            refreshPaymentsProjection()
        }
    }

    /// Project the Rust-side DashPay payment history into SwiftData.
    ///
    /// The SDK persister deliberately does NOT push payment rows —
    /// `PersistentDashpayPayment` is populated only by this app-pulled
    /// projection (`PlatformWalletManager.refreshDashPayPayments`:
    /// one FFI read of `managed_identity_get_dashpay_payments` + one
    /// upsert pass). Discovered 2026-07-08: dashwallet never called
    /// it, so payments recorded in Rust (send-time entries AND
    /// reconcile-derived received entries) never reached the store —
    /// the profile sheet showed "No payments" while the example app
    /// (which calls it) showed the same channel's history fine.
    func refreshPaymentsProjection() {
        guard let manager = SwiftDashSDKHost.shared.manager,
              let wallet = SwiftDashSDKHost.shared.wallet,
              let ownerId = DWCurrentUserIdentityInfo.shared.identityId else {
            return
        }
        do {
            let payments = try manager.refreshDashPayPayments(
                walletId: wallet.walletId,
                identityId: ownerId)
            Self.logger.info("👥 CONTACTS :: payments projection — \(payments.count, privacy: .public) row(s)")
        } catch {
            Self.logger.error("👥 CONTACTS :: payments projection failed: \(String(describing: error), privacy: .public)")
        }
        // The projection may have upserted payment rows; keep the tx-list
        // classification overlay in step.
        DashPayPaymentTxLookup.shared.refresh()
    }

    // MARK: - Notifications read-state (bell badge)

    /// Contact events newer than the last time the user viewed the
    /// notifications screen: pending incoming requests plus
    /// established-contact events. Read-state lives in the same
    /// `DWGlobalOptions.mostRecentViewedNotificationDate` slot the
    /// legacy `DWNotificationsModel` used, so upgrade installs don't
    /// re-badge everything the user already saw.
    var unreadNotificationCount: Int {
        let lastViewed = DWGlobalOptions.sharedInstance().mostRecentViewedNotificationDate ?? .distantPast
        let unreadIncoming = incomingRequests.filter { $0.createdAt > lastViewed }.count
        let unreadEstablished = contacts.filter { $0.createdAt > lastViewed }.count
        return unreadIncoming + unreadEstablished
    }

    /// Advance the read-state marker to the newest event currently
    /// shown (mirrors the legacy model, which tracked the max
    /// displayed item date rather than `Date()` — future-dated
    /// events stay unread). Reposts the change notification so the
    /// bell badge re-renders.
    func markNotificationsViewed() {
        guard let newest = (incomingRequests + contacts).map(\.createdAt).max() else { return }
        let options = DWGlobalOptions.sharedInstance()
        if (options.mostRecentViewedNotificationDate ?? .distantPast) < newest {
            options.mostRecentViewedNotificationDate = newest
            NotificationCenter.default.post(name: Self.contactsDidChangeNotification, object: nil)
        }
    }

    /// On-demand sync pass (pull-to-refresh). The background loop
    /// already runs every 15s; this shortens the wait after a
    /// user-visible action. Errors are logged, not thrown — the
    /// background loop retries anyway.
    func syncNow() async {
        guard let manager = SwiftDashSDKHost.shared.manager else { return }
        do {
            let summary = try await manager.dashPaySyncNow()
            Self.logger.info("👥 CONTACTS :: syncNow — \(summary.success, privacy: .public) ok, \(summary.errors, privacy: .public) failed")
        } catch {
            Self.logger.error("👥 CONTACTS :: syncNow failed: \(String(describing: error), privacy: .public)")
        }
        // A pass may have recorded new payment entries Rust-side;
        // pull them into SwiftData so the profile sheet sees them.
        refreshPaymentsProjection()
    }

    // MARK: - Actions

    /// Send a contact request. PIN/biometric-gated (broadcasts a
    /// Platform document). `usernameHint` is the DPNS label the user
    /// picked in search — stored locally so the pending-outgoing row
    /// can render a name before the profile cache syncs.
    func sendContactRequest(to recipientId: Data, usernameHint: String?) async throws {
        let (wallet, modelContainer, ownerId) = try requireContext()

        try await authorize()
        try await ensureOwnDashPayKeys(wallet: wallet, ownerId: ownerId, modelContainer: modelContainer)

        let signer = KeychainSigner(modelContainer: modelContainer)
        do {
            _ = try await wallet.sendContactRequest(
                senderIdentityId: ownerId,
                recipientIdentityId: recipientId,
                accountLabel: nil,
                autoAcceptProof: nil,
                signer: signer)
        } catch {
            Self.logger.error("👥 CONTACTS :: sendContactRequest failed: \(String(describing: error), privacy: .public)")
            throw ServiceError.sdk(error)
        }

        if let usernameHint, !usernameHint.isEmpty {
            setUsernameHint(usernameHint, for: recipientId)
        }
        Self.logger.info("👥 CONTACTS :: request sent to \(recipientId.prefix(4).map { String(format: "%02x", $0) }.joined(), privacy: .public)…")

        // Land the new outgoing row in SwiftData without waiting for
        // the next background pass.
        Task { await self.syncNow() }
    }

    /// Accept a pending incoming request (broadcasts the reciprocal
    /// request — PIN/biometric-gated). The SDK registers the external
    /// contact account on establish, which is what later makes
    /// `sendDashPayPayment` to this contact possible.
    func acceptContactRequest(from senderId: Data) async throws {
        let (wallet, modelContainer, ownerId) = try requireContext()

        // Resolve the live ContactRequest handle from the SDK's
        // in-memory state. That state is PER-SESSION — the SwiftData row
        // the UI acted on may have been persisted by an earlier session's
        // sync, so a miss here doesn't mean the request is gone: run a
        // DashPay sync pass to repopulate the in-memory list and look
        // again. Only a miss after a fresh pass is a genuinely
        // revoked/consumed request.
        let request: ContactRequest
        do {
            if let incoming = try incomingRequestHandle(wallet: wallet, ownerId: ownerId, senderId: senderId) {
                request = incoming
            } else {
                Self.logger.info("👥 CONTACTS :: incoming request not in memory — resyncing before accept")
                await syncNow()
                guard let retried = try incomingRequestHandle(wallet: wallet, ownerId: ownerId, senderId: senderId) else {
                    throw ServiceError.requestNotFound
                }
                request = retried
            }
        } catch let error as ServiceError {
            throw error
        } catch {
            Self.logger.error("👥 CONTACTS :: incoming-request lookup failed: \(String(describing: error), privacy: .public)")
            throw ServiceError.sdk(error)
        }

        try await authorize()
        try await ensureOwnDashPayKeys(wallet: wallet, ownerId: ownerId, modelContainer: modelContainer)

        let signer = KeychainSigner(modelContainer: modelContainer)
        do {
            _ = try await wallet.acceptContactRequest(request, signer: signer)
        } catch {
            Self.logger.error("👥 CONTACTS :: acceptContactRequest failed: \(String(describing: error), privacy: .public)")
            throw ServiceError.sdk(error)
        }
        Self.logger.info("👥 CONTACTS :: accepted request from \(senderId.prefix(4).map { String(format: "%02x", $0) }.joined(), privacy: .public)…")

        Task { await self.syncNow() }
    }

    /// One in-memory lookup of a pending incoming request — split out so
    /// the accept path can retry it after a resync.
    private func incomingRequestHandle(
        wallet: ManagedPlatformWallet,
        ownerId: Data,
        senderId: Data
    ) throws -> ContactRequest? {
        let identity = try wallet.managedIdentity(identityId: ownerId)
        return try identity.getIncomingContactRequest(senderId: senderId)
    }

    /// Local-only mute: drops the sender's pending request and
    /// suppresses future ones from the sync list. No on-chain
    /// artifact, so no auth gate — parity with the legacy decline
    /// (which was a stub that never acted at all). Reversible SDK-side
    /// via `unignoreContactSender`.
    func ignoreSender(_ senderId: Data) async throws {
        let (wallet, _, ownerId) = try requireContext()
        do {
            try await wallet.ignoreContactSender(
                ourIdentityId: ownerId,
                contactIdentityId: senderId)
        } catch {
            Self.logger.error("👥 CONTACTS :: ignoreContactSender failed: \(String(describing: error), privacy: .public)")
            throw ServiceError.sdk(error)
        }
        Self.logger.info("👥 CONTACTS :: ignored sender \(senderId.prefix(4).map { String(format: "%02x", $0) }.joined(), privacy: .public)…")

        Task { await self.syncNow() }
    }

    /// DPNS prefix search for the add-contact flow. Thin passthrough;
    /// each result pairs a label with the 32-byte identity ID that
    /// `sendContactRequest(to:)` takes.
    ///
    /// `limit == 0` (the default) defers to the SDK's own cap — 100
    /// rows, the same page size the legacy `DWUserSearchModel` fetched.
    /// Eligibility is checked lazily per visible row (see
    /// `contactRequestEligibility`), so a large result set doesn't fan
    /// out a key query for every hit up front.
    func searchUsernames(prefix: String, limit: UInt32 = 0) async throws -> [DpnsSearchResult] {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw ServiceError.noWallet
        }
        do {
            return try await wallet.searchDpnsNames(prefix: prefix, limit: limit)
        } catch {
            throw ServiceError.sdk(error)
        }
    }

    /// Look up an already-materialized `ContactItem` for `identityId`
    /// across the established / incoming / outgoing snapshots. Used by
    /// the add-contact preview to show a contact's real profile fields
    /// when we already hold them; returns nil for a true stranger (no
    /// on-chain profile fetch exists in the SDK — reads are cache-only).
    func contactItem(for identityId: Data) -> ContactItem? {
        contacts.first { $0.contactIdentityId == identityId }
            ?? incomingRequests.first { $0.contactIdentityId == identityId }
            ?? outgoingRequests.first { $0.contactIdentityId == identityId }
    }

    // MARK: - Contact meta (alias / note / hidden)

    /// One row of the payments-between-us history for a contact,
    /// read from the SwiftData rows the DashPay sync reconciles.
    struct ContactPayment: Identifiable {
        /// Display-order (RPC) txid hex — the Rust `dashpay_payments`
        /// map key, produced by `dashcore::Txid::to_string()`.
        let txid: String
        let amountDuffs: UInt64
        let direction: DashPayPaymentDirection
        let memo: String?
        let date: Date
        /// Current-rate fiat equivalent of `amountDuffs`, formatted for
        /// display (e.g. "$0.35"). Nil only when the amount is zero.
        let fiatString: String?
        var id: String { txid }

        /// Wire-order txid (the byte reverse of the display-order hex
        /// key) — the form `SwiftDashSDKWalletSource.fetch(txid:)` and
        /// `TxDetailModel(txidWire:)` expect, matching
        /// `PersistentTransaction.txid`. Nil when the hex won't parse.
        var txidWire: Data? {
            guard let display = Data(hex: txid) else { return nil }
            return Data(display.reversed())
        }
    }

    /// DashPay payment history with one contact, newest first.
    func payments(with contactId: Data) -> [ContactPayment] {
        guard let ownerId = DWCurrentUserIdentityInfo.shared.identityId,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            return []
        }
        let descriptor = FetchDescriptor<PersistentDashpayPayment>(
            predicate: PersistentDashpayPayment.predicate(
                ownerIdentityId: ownerId,
                counterpartyIdentityId: contactId),
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let rows = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
        return rows.map { row in
            let dash = Decimal(row.amountDuffs) / Decimal(100_000_000)
            return ContactPayment(
                txid: row.txid,
                amountDuffs: row.amountDuffs,
                direction: row.direction,
                memo: row.memo,
                date: row.createdAt,
                // Current-rate conversion (parity with the legacy
                // profile, which showed the live fiat equivalent, not a
                // historical one). Returns a "Fetching rates…" string
                // rather than throwing when rates aren't up yet.
                fiatString: row.amountDuffs > 0
                    ? CurrencyExchanger.shared.fiatAmountString(for: dash)
                    : nil)
        }
    }

    /// Set / clear the owner-private alias on an established contact.
    /// Local-only state (no on-chain artifact, no auth gate); durably
    /// persisted via `flushPersist`.
    func setAlias(_ alias: String?, for contactId: Data) async throws {
        try await mutateEstablishedContact(contactId) { contact in
            if let alias, !alias.isEmpty {
                try contact.setAlias(alias)
            } else {
                try contact.clearAlias()
            }
        }
    }

    /// Set / clear the owner-private note on an established contact.
    func setNote(_ note: String?, for contactId: Data) async throws {
        try await mutateEstablishedContact(contactId) { contact in
            if let note, !note.isEmpty {
                try contact.setNote(note)
            } else {
                try contact.clearNote()
            }
        }
    }

    /// Hide / unhide an established contact (moves it to the Hidden
    /// section of the contacts list).
    func setHidden(_ hidden: Bool, for contactId: Data) async throws {
        try await mutateEstablishedContact(contactId) { contact in
            hidden ? try contact.hide() : try contact.unhide()
        }
    }

    /// One in-memory lookup of an established contact — split out so the
    /// mutation path can retry it after a resync.
    private func establishedContactHandle(
        wallet: ManagedPlatformWallet,
        ownerId: Data,
        contactId: Data
    ) throws -> EstablishedContact? {
        let identity = try wallet.managedIdentity(identityId: ownerId)
        return try identity.getEstablishedContact(contactId: contactId)
    }

    private func mutateEstablishedContact(
        _ contactId: Data,
        _ mutate: (EstablishedContact) throws -> Void
    ) async throws {
        let (wallet, _, ownerId) = try requireContext()
        do {
            // The SDK's in-memory contact state is PER-SESSION while the
            // rows the UI acted on persist across sessions — same trap as
            // `acceptContactRequest`. A miss doesn't mean the contact is
            // gone: resync and look again before failing (setting an alias
            // right after launch used to die here with the bogus
            // "Contact request not found").
            let contact: EstablishedContact
            if let live = try establishedContactHandle(wallet: wallet, ownerId: ownerId, contactId: contactId) {
                contact = live
            } else {
                Self.logger.info("👥 CONTACTS :: established contact not in memory — resyncing before mutation")
                await syncNow()
                guard let retried = try establishedContactHandle(wallet: wallet, ownerId: ownerId, contactId: contactId) else {
                    throw ServiceError.requestNotFound
                }
                contact = retried
            }
            try mutate(contact)
            // Durability: the setters mutate in-memory Rust state; the
            // flush lands the change in SwiftData via the persister,
            // which also triggers the debounced snapshot refresh.
            try wallet.flushPersist()
        } catch let error as ServiceError {
            throw error
        } catch {
            Self.logger.error("👥 CONTACTS :: contact-meta mutation failed: \(String(describing: error), privacy: .public)")
            throw ServiceError.sdk(error)
        }
        refresh()
    }

    // MARK: - Contact-request eligibility

    /// Check whether identities can participate in DashPay contact
    /// requests: an enabled ECDSA_SECP256K1 key with purpose
    /// ENCRYPTION *and* one with purpose DECRYPTION. The ENCRYPTION
    /// predicate mirrors the SDK send path verbatim
    /// (`rs-platform-wallet/…/contact_requests.rs`: `purpose ==
    /// ENCRYPTION && key_type == ECDSA_SECP256K1 &&
    /// disabled_at.is_none()`, over the identity's plain public keys —
    /// deliberately NO contract-bounds requirement; a contract-keys
    /// query false-negatives identities whose DashPay keys aren't
    /// contract-bound). DECRYPTION is additionally required so the
    /// recipient can actually open incoming requests. Identities
    /// registered before DashPay keys existed fail `sendContactRequest`
    /// with "Identity has no enabled ECDSA_SECP256K1 encryption key" —
    /// checking up front lets the add-contact UI mark them instead of
    /// letting the user hit the PIN gate and a network error.
    ///
    /// Returns eligibility per requested id; an id whose key query
    /// fails is omitted — callers treat absent as "unknown" and leave
    /// the row actionable (the send path still surfaces the real
    /// error if the identity turns out ineligible).
    func contactRequestEligibility(for identityIds: [Data]) async -> [Data: Bool] {
        guard let sdk = SwiftDashSDKHost.shared.sdk else { return [:] }
        var result: [Data: Bool] = [:]
        // Dedupe: DPNS search returns one row per LABEL, so an identity
        // owning several matching names appears multiple times.
        for id in Set(identityIds) {
            let base58 = id.toBase58String()
            do {
                // keyId → IdentityPublicKey JSON (dpp serde: camelCase,
                // `purpose`/`type` as serde_repr numbers, `disabledAt`
                // absent when the key is enabled), or null for a
                // requested-but-missing key id.
                let keys = try await sdk.identityGetKeys(identityId: base58)
                let usable = keys.values.compactMap { $0 as? [String: Any] }
                func hasEnabledECDSAKey(purpose: Int) -> Bool {
                    usable.contains { key in
                        (key["purpose"] as? Int) == purpose
                            && (key["type"] as? Int) == 0  // ECDSA_SECP256K1
                            && (key["disabledAt"] == nil || key["disabledAt"] is NSNull)
                    }
                }
                result[id] = hasEnabledECDSAKey(purpose: 1)  // ENCRYPTION
                    && hasEnabledECDSAKey(purpose: 2)        // DECRYPTION
            } catch {
                Self.logger.error("👥 CONTACTS :: key eligibility query failed for \(base58, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        return result
    }

    /// Reverse DPNS lookup (identity → label) for incoming-request
    /// senders, where we only learn the identity ID from the synced
    /// row. On success the label is cached in the hint store, so the
    /// next `refresh()` renders it without another network hop.
    func resolveUsername(for contactId: Data) async -> String? {
        if let cached = usernameHint(for: contactId) {
            return cached
        }
        guard let sdk = SwiftDashSDKHost.shared.sdk else { return nil }
        let base58 = contactId.toBase58String()
        do {
            let usernames = try await sdk.dpnsGetUsername(identityId: base58, limit: 1)
            guard let label = usernames.first?["label"] as? String, !label.isEmpty else {
                return nil
            }
            setUsernameHint(label, for: contactId)
            refresh()
            return label
        } catch {
            Self.logger.error("👥 CONTACTS :: dpnsGetUsername failed for \(base58, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Internals

    private func requireContext() throws -> (ManagedPlatformWallet, ModelContainer, Data) {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw ServiceError.noWallet
        }
        guard let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            throw ServiceError.noModelContainer
        }
        guard let ownerId = DWCurrentUserIdentityInfo.shared.identityId else {
            throw ServiceError.noIdentity
        }
        return (wallet, modelContainer, ownerId)
    }

    /// Lazily bring the current identity up to the DashPay key set
    /// before its first contact action: dashwallet's registration
    /// derives AUTHENTICATION keys only, and both `sendContactRequest`
    /// and the reciprocal request inside `acceptContactRequest` need
    /// our own enabled ECDSA ENCRYPTION key for the DIP-15 ECDH.
    /// No-op once the keys exist; called after the PIN gate so the
    /// IdentityUpdate broadcast is covered by the same user approval
    /// as the contact action it unblocks.
    private func ensureOwnDashPayKeys(
        wallet: ManagedPlatformWallet,
        ownerId: Data,
        modelContainer: ModelContainer
    ) async throws {
        guard let sdk = SwiftDashSDKHost.shared.sdk,
              let network = SwiftDashSDKHost.shared.runningNetwork else {
            throw ServiceError.noWallet
        }
        do {
            let upgraded = try await DWIdentityKeyUpgrader.ensureDashPayKeys(
                wallet: wallet,
                ownerId: ownerId,
                modelContainer: modelContainer,
                sdk: sdk,
                network: network)
            if upgraded {
                Self.logger.info("👥 CONTACTS :: identity upgraded with DashPay keys before contact action")
            }
        } catch {
            Self.logger.error("👥 CONTACTS :: DashPay key upgrade failed: \(String(describing: error), privacy: .public)")
            throw ServiceError.sdk(error)
        }
    }

    /// PIN / biometric prompt via the shared authorizer (same gate the
    /// registration and profile coordinators use), with the authorizer's
    /// errors translated so callers don't import its symbols.
    private func authorize() async throws {
        do {
            try await authorizer.authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            throw ServiceError.authCancelled
        } catch {
            throw ServiceError.authFailed
        }
    }

    // MARK: - DPNS-label hint store

    // Device-local map (network, owner, contact) → DPNS label,
    // captured at add time or by `resolveUsername`. Modeled on
    // SwiftExampleApp's `DashPayContactMetaStore` DPNS-hint store; the
    // label is display metadata, not wallet state, so UserDefaults is
    // the honest backing.

    private func hintKey(for contactId: Data) -> String? {
        guard let ownerId = DWCurrentUserIdentityInfo.shared.identityId,
              let network = SwiftDashSDKHost.shared.runningNetwork else {
            return nil
        }
        let ownerHex = ownerId.map { String(format: "%02x", $0) }.joined()
        let contactHex = contactId.map { String(format: "%02x", $0) }.joined()
        return "dw.contacts.dpnsHint.\(network.rawValue).\(ownerHex).\(contactHex)"
    }

    private func usernameHint(for contactId: Data) -> String? {
        guard let key = hintKey(for: contactId) else { return nil }
        let value = UserDefaults.standard.string(forKey: key)
        return (value?.isEmpty == false) ? value : nil
    }

    private func setUsernameHint(_ label: String, for contactId: Data) {
        guard let key = hintKey(for: contactId) else { return }
        UserDefaults.standard.set(label, forKey: key)
    }
}

// MARK: - Obj-C badge bridge

/// Thin Obj-C facade for the one legacy consumer of the notifications
/// badge count: `DWDashPayModel.unreadNotificationsCount` (KVO-observed
/// by the home header). Falls away when `DWDashPayModel` is retired.
@objc(DWContactsNotificationsBridge)
@MainActor
final class ContactsNotificationsBridge: NSObject {
    @objc static var unreadCount: UInt {
        UInt(SwiftDashSDKContactsService.shared.unreadNotificationCount)
    }
}

// MARK: - DashPay payment tx lookup

/// Thread-safe txid → DashPay-payment snapshot, mirrored from
/// `PersistentDashpayPayment` — the same overlay shape as
/// `ShieldedTxLookup`. The home transaction list uses it to classify
/// DIP-15 contact payments: dash-spv's net-change view misreads an
/// outgoing contact payment as an incoming +amount (the jointly-derived
/// payment address is watched by our wallet, while the spent inputs
/// aren't attributed), so the payment record written by the Rust
/// payment history — which knows the true direction and amount — wins.
///
/// Keys are display-order txid hex, lowercased (the `PersistentDashpayPayment.txid`
/// convention, which matches explorer txids and `Transaction`'s
/// reversed `txHashData`).
final class DashPayPaymentTxLookup {
    static let shared = DashPayPaymentTxLookup()

    struct PaymentInfo: Sendable {
        let amountDuffs: UInt64
        /// True when the wallet's identity SENT this payment.
        let isOutgoing: Bool
        let counterpartyIdentityId: Data
        /// Counterparty's DashPay profile display name, when the profile
        /// cache has one — drives the "Sent to <name>" row title.
        let counterpartyName: String?
        /// Owner-set alias for the counterparty, when one exists — wins
        /// over `counterpartyName` in the row title (the profile name then
        /// moves to the gray details line).
        let counterpartyAlias: String?
        /// Counterparty's avatar URL, when their profile carries one.
        let counterpartyAvatarURL: String?

        /// Row-title name: alias first (owner's own label for the contact),
        /// then the profile display name. Matches `ContactItem.displayTitle`.
        var titleName: String? { counterpartyAlias ?? counterpartyName }
    }

    private let lock = NSLock()
    private var infoByTxid: [String: PaymentInfo] = [:]

    private init() {}

    /// Snapshot entry for a txid (display-order hex), or nil when the tx
    /// is not a recorded DashPay payment. Thread-safe; touches no SwiftData.
    func info(forTxidHex txidHex: String) -> PaymentInfo? {
        let key = txidHex.lowercased()
        lock.lock()
        defer { lock.unlock() }
        return infoByTxid[key]
    }

    /// Rebuild the snapshot from the active container's payment rows.
    /// Main actor: reads the SwiftData `mainContext`. A nil container
    /// clears the snapshot; a transient fetch error keeps the previous one.
    @MainActor
    func refresh() {
        guard let container = SwiftDashSDKHost.shared.modelContainer else {
            store([:])
            return
        }
        do {
            let rows = try container.mainContext.fetch(FetchDescriptor<PersistentDashpayPayment>())
            // Join the counterparty's cached DashPay profile for the row
            // title/avatar. Tiny tables; fetch-all and index in Swift.
            let profiles = try container.mainContext.fetch(FetchDescriptor<PersistentDashpayContactProfile>())
            var profileByContactId: [Data: (name: String?, avatarURL: String?)] = [:]
            for profile in profiles {
                profileByContactId[profile.contactIdentityId] = (profile.displayName, profile.avatarUrl)
            }
            // Owner-set aliases ride on the contact-request rows (either
            // direction of the pair may carry it — same read the contacts
            // snapshot uses).
            let requests = try container.mainContext.fetch(FetchDescriptor<PersistentDashpayContactRequest>())
            var aliasByContactId: [Data: String] = [:]
            for request in requests {
                if let alias = request.contactAlias, !alias.isEmpty {
                    aliasByContactId[request.contactIdentityId] = alias
                }
            }
            var map: [String: PaymentInfo] = [:]
            for row in rows where row.amountDuffs > 0 {
                let profile = profileByContactId[row.counterpartyIdentityId]
                map[row.txid.lowercased()] = PaymentInfo(
                    amountDuffs: row.amountDuffs,
                    isOutgoing: row.direction == .sent,
                    counterpartyIdentityId: row.counterpartyIdentityId,
                    counterpartyName: profile?.name?.isEmpty == false ? profile?.name : nil,
                    counterpartyAlias: aliasByContactId[row.counterpartyIdentityId],
                    counterpartyAvatarURL: profile?.avatarURL?.isEmpty == false ? profile?.avatarURL : nil)
            }
            store(map)
        } catch {
            // Keep the previous snapshot on a transient fetch failure.
        }
    }

    private func store(_ map: [String: PaymentInfo]) {
        lock.lock()
        infoByTxid = map
        lock.unlock()
    }
}
