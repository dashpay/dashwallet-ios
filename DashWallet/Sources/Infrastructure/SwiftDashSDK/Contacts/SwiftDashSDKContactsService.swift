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
                // The persister mirrors the flag onto both direction
                // rows, so either carrying it means the channel is
                // broken.
                paymentChannelBroken: rows.contains(where: \.paymentChannelBroken),
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

        backfillMissingUsernames(established + incoming + outgoing)

        // Keep the payment-history rows flowing without any screen
        // open: the projection is app-pulled (see
        // refreshPaymentsProjection), so ride the snapshot refresh at
        // most once a minute.
        if Date().timeIntervalSince(lastPaymentsProjection) > 60 {
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
            // No identity yet: nothing was pulled, so leave the piggyback
            // throttle unarmed. Arming it here spent the launch's first
            // window on a call that returned immediately — the identity
            // typically lands seconds later, and the next chance to project
            // its payments was then a minute away.
            return
        }
        lastPaymentsProjection = Date()
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

    /// Injected by `NotificationsBootstrap` — the same static-injection
    /// seam shape as `CrowdNode.notificationProducer`, because this
    /// singleton is created before the notifications graph exists and must
    /// not depend on the module directly. Fired by every
    /// `markNotificationsViewed`, so the notifications module can clear
    /// the tray's dashpay thread and its store seen-state whenever the
    /// bell screen was viewed. `nil` until the graph is built (and in
    /// builds without it): viewing then only advances the marker.
    static var notificationsViewedHandler: (() -> Void)?

    /// Contact events newer than the last time the user viewed the
    /// notifications screen: pending incoming and outgoing requests plus
    /// established-contact events — every row the notifications screen
    /// renders. Read-state lives in the same
    /// `DWGlobalOptions.mostRecentViewedNotificationDate` slot the
    /// legacy `DWNotificationsModel` used, so upgrade installs don't
    /// re-badge everything the user already saw.
    var unreadNotificationCount: Int {
        DashPayNotificationsReadState.unreadCount(
            incoming: incomingRequests,
            outgoing: outgoingRequests,
            contacts: contacts,
            lastViewed: DWGlobalOptions.sharedInstance().mostRecentViewedNotificationDate)
    }

    /// Advance the read-state marker over every rendered event list —
    /// incoming, outgoing, established — to the newest event currently
    /// shown (mirrors the legacy model, which tracked the max displayed
    /// item date rather than `Date()` — future-dated events stay unread;
    /// the marker never moves backward, so re-firing on multiple exit
    /// paths is harmless). Reposts the change notification so the bell
    /// badge re-renders, and always fires `notificationsViewedHandler` —
    /// stale delivered dashpay notifications must clear whenever the
    /// screen was viewed, whether or not the marker could advance.
    func markNotificationsViewed() {
        defer { Self.notificationsViewedHandler?() }
        let options = DWGlobalOptions.sharedInstance()
        guard let advanced = DashPayNotificationsReadState.advancedMarker(
            incoming: incomingRequests,
            outgoing: outgoingRequests,
            contacts: contacts,
            lastViewed: options.mostRecentViewedNotificationDate) else { return }
        options.mostRecentViewedNotificationDate = advanced
        NotificationCenter.default.post(name: Self.contactsDidChangeNotification, object: nil)
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

        // UI actions can arrive from a SwiftUI row that was rendered for an
        // older relationship snapshot. Treat them as idempotent no-ops once
        // the request has already moved to established/outgoing.
        guard incomingRequests.contains(where: {
            $0.contactIdentityId == senderId
        }) else {
            Self.logger.info(
                "👥 CONTACTS :: ignored stale accept — sender is no longer pending incoming")
            refresh()
            return
        }

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

        // Never let an obsolete incoming row mute an established contact.
        // Besides avoiding a misleading action, this preserves the invariant
        // that ignored senders have no outgoing request from us.
        guard incomingRequests.contains(where: {
            $0.contactIdentityId == senderId
        }) else {
            Self.logger.info(
                "👥 CONTACTS :: ignored stale ignore — sender is no longer pending incoming")
            refresh()
            return
        }

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

    /// Exact DPNS resolution on Platform: the identity id currently
    /// owning `username` ("alice" or "alice.dash"), or nil when the
    /// name is unregistered. Unlike `searchUsernames` this is not a
    /// capped prefix page, so it's the right primitive for verifying a
    /// scanned QR's username↔identity claim.
    func resolveUsername(_ username: String) async throws -> Data? {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw ServiceError.noWallet
        }
        do {
            return try await wallet.resolveDpnsName(username)
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
                counterpartyIdentityId: contactId))
        let rows = (try? modelContainer.mainContext.fetch(descriptor)) ?? []

        // When the payment happened, from the transaction itself.
        //
        // `PersistentDashpayPayment.createdAt` is row bookkeeping — its own
        // model says "not payment dates" — and it only looked like the payment
        // date because a live send writes the row as it happens. A payment
        // reconstructed after a restore is written today, so every recovered
        // row rendered with today's date while the tx-detail screen, which
        // reads the transaction, showed the real one.
        var blockTimeByTxid: [Data: UInt32] = [:]
        if let transactions = try? modelContainer.mainContext.fetch(
            FetchDescriptor<PersistentTransaction>()) {
            for tx in transactions where tx.blockTimestamp > 0 {
                blockTimeByTxid[tx.txid] = tx.blockTimestamp
            }
        }

        return rows.map { row in
            let dash = Decimal(row.amountDuffs) / Decimal(100_000_000)
            // `PersistentDashpayPayment.txid` is display-order hex; the
            // transaction table is keyed by the wire-order bytes.
            let wireTxid = Data(hex: row.txid).map { Data($0.reversed()) }
            // Unconfirmed (or not-yet-synced) transactions have no block time;
            // the row's own timestamp is the best available answer there, and
            // for a live send it is the right one.
            let date = wireTxid
                .flatMap { blockTimeByTxid[$0] }
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
                ?? row.createdAt
            return ContactPayment(
                txid: row.txid,
                amountDuffs: row.amountDuffs,
                direction: row.direction,
                memo: row.memo,
                date: date,
                // Current-rate conversion (parity with the legacy
                // profile, which showed the live fiat equivalent, not a
                // historical one). Returns a "Fetching rates…" string
                // rather than throwing when rates aren't up yet.
                fiatString: row.amountDuffs > 0
                    ? CurrencyExchanger.shared.fiatAmountString(for: dash)
                    : nil)
        }
        // Sort on the payment date, not the row's insert order: reconstructed
        // rows are all written within the same second, so insert order says
        // nothing about which payment came first.
        .sorted { $0.date > $1.date }
    }

    /// Write the owner-private contact metadata (alias / note / hidden)
    /// for an established contact. One combined write: the SDK's
    /// `setDashPayContactInfo` updates the wallet manager's REAL contact
    /// state, persists it (feeds the SwiftData mirror the contacts list
    /// and payment rows read), and publishes the self-encrypted DIP-15
    /// `contactInfo` document to Platform — the "remote wins" convergence
    /// that makes the alias roam across devices.
    ///
    /// The publish signs a Platform document with the identity key, so
    /// this is PIN/biometric-gated like every other document write.
    /// Empty strings clear their field. Returns the publish outcome —
    /// local state is saved even when the document publish was deferred
    /// (DIP-15 defers until ≥ 2 established contacts) or skipped
    /// (watch-only identity).
    ///
    /// Replaces the deprecated `EstablishedContact.setAlias/setNote/hide`
    /// path, which mutated a detached FFI handle clone — nothing it wrote
    /// ever reached wallet state, disk, or Platform (platform PR #4140).
    @discardableResult
    func setContactMeta(
        alias: String?,
        note: String?,
        hidden: Bool,
        for contactId: Data
    ) async throws -> ManagedPlatformWallet.ContactInfoPublishOutcome {
        let (wallet, modelContainer, ownerId) = try requireContext()

        try await authorize()

        let signer = KeychainSigner(modelContainer: modelContainer)
        let outcome: ManagedPlatformWallet.ContactInfoPublishOutcome
        do {
            outcome = try await wallet.setDashPayContactInfo(
                identityId: ownerId,
                contactId: contactId,
                alias: alias?.isEmpty == false ? alias : nil,
                note: note?.isEmpty == false ? note : nil,
                hidden: hidden,
                signer: signer)
        } catch {
            Self.logger.error("👥 CONTACTS :: contact-meta write failed: \(String(describing: error), privacy: .public)")
            throw ServiceError.sdk(error)
        }
        Self.logger.info("👥 CONTACTS :: contact meta saved — outcome \(String(describing: outcome), privacy: .public)")
        refresh()
        return outcome
    }

    // MARK: - Contact-request eligibility

    /// Check whether identities can receive a DashPay contact request:
    /// an enabled ECDSA_SECP256K1 DECRYPTION key (preferred by the SDK)
    /// or ENCRYPTION key (the supported mobile-cohort fallback).
    /// Deliberately NO contract-bounds requirement; a contract-keys
    /// query false-negatives identities whose compatible keys aren't
    /// contract-bound. Identities with neither compatible key fail the
    /// SDK's recipient-key selector, so checking up front lets the UI
    /// explain the state before the PIN gate.
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
                if let eligible = DWDashPayIdentityKeys.recipientEligibility(from: usable) {
                    result[id] = eligible
                }
            } catch {
                Self.logger.error("👥 CONTACTS :: key eligibility query failed for \(base58, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        return result
    }

    /// Contacts whose reverse lookup is already running, so a `refresh()`
    /// triggered by one completing does not restart the others.
    private var usernameBackfillInFlight: Set<Data> = []

    /// Resolve the DPNS label for every contact that has none yet.
    ///
    /// `username` is otherwise only populated at add time (from the username
    /// search) or by the list view's `.onAppear` on the incoming and outgoing
    /// sections. Established contacts had neither: `ContactsScreen`'s "My
    /// Contacts" section never called `resolveUsernameIfNeeded`, and a restored
    /// wallet has no add-time hint because the add happened on the previous
    /// install. `ContactItem.displayTitle` then fell through to its last
    /// resort and rendered the contact as `89fd6ddb…` permanently (BUG-27).
    ///
    /// Doing it here rather than in the view fixes every surface at once — the
    /// list, the profile sheet opened straight from a payment, and the
    /// notifications screen — and does not depend on which row happened to
    /// scroll into view.
    ///
    /// Cost is bounded: `resolveUsername` returns the cached hint without a
    /// network call once resolved, so this is one lookup per contact per
    /// install, and contacts that already have a name are skipped entirely.
    private func backfillMissingUsernames(_ items: [ContactItem]) {
        let targets = items
            .filter { $0.username == nil }
            .map(\.contactIdentityId)
            .filter { !usernameBackfillInFlight.contains($0) }
        guard !targets.isEmpty else { return }

        usernameBackfillInFlight.formUnion(targets)
        Task { @MainActor [weak self] in
            defer { self?.usernameBackfillInFlight.subtract(targets) }
            for contactId in targets {
                _ = await self?.resolveUsername(for: contactId)
            }
        }
    }

    /// Reverse DPNS lookup (identity → label) for any contact we know only by
    /// identity id — incoming-request senders, and established contacts whose
    /// add-time hint is gone (a restored wallet). On success the label is
    /// cached in the hint store, so the next `refresh()` renders it without
    /// another network hop.
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

    /// How many of the DIP-15 contact-request keys (an enabled ECDSA
    /// ENCRYPTION and DECRYPTION key — required on BOTH sides of the ECDH;
    /// without them, other users' clients find no recipient key and can't
    /// send requests to this identity) the wallet's main identity is
    /// missing: 0 (fully enabled), 1, or 2. Drives the Contacts tab's
    /// "Enable DashPay" affordance and its fee estimate. Local-store read
    /// only — `enableDashPay()` re-checks Platform's authoritative key set
    /// before broadcasting anything.
    func missingDashPayKeyCount() -> Int {
        guard let modelContainer = SwiftDashSDKHost.shared.modelContainer,
              let ownerId = DWCurrentUserIdentityInfo.shared.identityId else {
            return 0
        }
        var descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { $0.identityId == ownerId })
        descriptor.fetchLimit = 1
        guard let identity = (try? modelContainer.mainContext.fetch(descriptor))?.first else {
            return 0
        }
        func hasEnabledECDSAKey(purposeRaw: String) -> Bool {
            identity.publicKeys.contains { key in
                key.purpose == purposeRaw
                    && key.keyTypeEnum == .ecdsaSecp256k1
                    && !key.isDisabled
            }
        }
        var missing = 0
        if !hasEnabledECDSAKey(purposeRaw: String(KeyPurpose.encryption.rawValue)) { missing += 1 }
        if !hasEnabledECDSAKey(purposeRaw: String(KeyPurpose.decryption.rawValue)) { missing += 1 }
        return missing
    }

    /// Identity ids whose DIP-15 pair Platform has confirmed enabled this
    /// session. Platform never silently removes keys (they can only be
    /// explicitly disabled), so one confirmation spares a network query on
    /// every subsequent tab load.
    private var platformConfirmedDashPayIdentities: Set<Data> = []

    /// Authoritative Platform-side count of the missing DIP-15 keys for
    /// `ownerId`. The local SwiftData key rows lag when the pair was added
    /// from another device — `missingDashPayKeyCount()` alone would keep
    /// showing the "Enable DashPay" intro for an identity that is already
    /// enabled. Takes the identity explicitly so a caller can bind the
    /// result to the identity it captured before awaiting (a wallet switch
    /// mid-flight must not apply one identity's answer to another).
    /// Returns nil when the query can't run (no SDK / network error);
    /// callers keep the local answer then.
    func missingDashPayKeyCountOnPlatform(identityId ownerId: Data) async -> Int? {
        guard let sdk = SwiftDashSDKHost.shared.sdk else {
            return nil
        }
        if platformConfirmedDashPayIdentities.contains(ownerId) { return 0 }
        do {
            let keysById = try await sdk.identityGetKeys(identityId: ownerId.toBase58String())
            let missing = DWIdentityKeyUpgrader.missingDashPayPurposes(inPlatformKeysById: keysById).count
            if missing == 0 {
                platformConfirmedDashPayIdentities.insert(ownerId)
            }
            return missing
        } catch {
            Self.logger.error("👥 CONTACTS :: platform DashPay-key re-check failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Estimated network fee for the enable-DashPay IdentityUpdate, in
    /// duffs (1 duff = 1000 credits): the platform fee schedule's
    /// `identity_update` minimum (100,000 credits) plus
    /// `identity_key_in_creation_cost` (6,500,000 credits) per added key —
    /// rs-platform-version `state_transition_min_fees` v1. The actual fee
    /// is computed at execution and deducted from the identity's credit
    /// balance; the confirm sheet labels this as an estimate.
    static func enableDashPayEstimatedFeeDuffs(missingKeyCount: Int) -> UInt64 {
        (100_000 + UInt64(max(missingKeyCount, 1)) * 6_500_000) / 1000
    }

    /// PIN-gated "Enable DashPay": one IdentityUpdate adding whichever of
    /// the ENCRYPTION/DECRYPTION pair the identity is missing on Platform
    /// (`DWIdentityKeyUpgrader` — the same lazy repair the contact actions
    /// run). No-op returning false when Platform already has both keys.
    func enableDashPay() async throws -> Bool {
        let (wallet, modelContainer, ownerId) = try requireContext()
        try await authorize()
        let upgraded = try await ensureOwnDashPayKeys(
            wallet: wallet,
            ownerId: ownerId,
            modelContainer: modelContainer)
        Self.logger.info("👥 CONTACTS :: enable DashPay finished (broadcast=\(upgraded, privacy: .public))")
        return upgraded
    }

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

    /// Lazily repair an incomplete identity before a contact action.
    /// New registrations include the full DashPay key pair, but the
    /// fallback remains for earlier/development identities because
    /// both `sendContactRequest` and the reciprocal request inside
    /// `acceptContactRequest` need our own enabled ECDSA ENCRYPTION
    /// key for DIP-15 ECDH. No-op once both keys exist; called after
    /// the PIN gate so any IdentityUpdate is covered by the same user
    /// approval as the contact action it unblocks. Returns true when
    /// an IdentityUpdate was broadcast (the explicit Enable DashPay
    /// flow surfaces this; the contact actions ignore it).
    @discardableResult
    private func ensureOwnDashPayKeys(
        wallet: ManagedPlatformWallet,
        ownerId: Data,
        modelContainer: ModelContainer
    ) async throws -> Bool {
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
            return upgraded
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

    /// Key prefix shared by every hint of the current (owner, network) pair.
    /// Resolved once per batch so a caller reading many contacts does not
    /// re-read the identity snapshot per contact.
    private static func hintKeyPrefix() -> String? {
        guard let ownerId = DWCurrentUserIdentityInfo.shared.identityId,
              let network = SwiftDashSDKHost.shared.runningNetwork else {
            return nil
        }
        let ownerHex = ownerId.map { String(format: "%02x", $0) }.joined()
        return "dw.contacts.dpnsHint.\(network.rawValue).\(ownerHex)."
    }

    private static func hintKey(for contactId: Data) -> String? {
        guard let prefix = hintKeyPrefix() else { return nil }
        return prefix + contactId.map { String(format: "%02x", $0) }.joined()
    }

    /// DPNS labels for `contactIds`, keyed by contact identity id.
    ///
    /// `static` on purpose. `DashPayPaymentTxLookup` needs the same labels the
    /// contacts snapshot uses, but it must not reach `SwiftDashSDKContactsService`
    /// **`.shared`** to get them: `init()` ends in `refresh()`, which calls
    /// `DashPayPaymentTxLookup.shared.refresh()`, so touching `.shared` from
    /// there re-enters the singleton's own `swift_once` and traps
    /// (`EXC_BREAKPOINT` reported on the `static let shared` line). Nothing
    /// here reads instance state, so there is no reason to route through it.
    static func usernameHints(for contactIds: some Sequence<Data>) -> [Data: String] {
        guard let prefix = hintKeyPrefix() else { return [:] }
        var out: [Data: String] = [:]
        for contactId in contactIds where out[contactId] == nil {
            let key = prefix + contactId.map { String(format: "%02x", $0) }.joined()
            if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
                out[contactId] = value
            }
        }
        return out
    }

    private func usernameHint(for contactId: Data) -> String? {
        guard let key = Self.hintKey(for: contactId) else { return nil }
        let value = UserDefaults.standard.string(forKey: key)
        return (value?.isEmpty == false) ? value : nil
    }

    private func setUsernameHint(_ label: String, for contactId: Data) {
        guard let key = Self.hintKey(for: contactId) else { return }
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

    struct PaymentInfo: Sendable, Equatable {
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
        /// Counterparty's DPNS label, when one has been resolved. Most
        /// contacts have no `dashpay.profile.displayName`, so without this
        /// step the row had no name at all and rendered as "?" — while the
        /// contacts list, which does consult DPNS, showed the username.
        let counterpartyUsername: String?

        /// Row-title name: alias first (owner's own label for the contact),
        /// then the profile display name, then the DPNS label — the first
        /// three steps of `ContactItem.displayTitle`. It deliberately stops
        /// there: `displayTitle`'s truncated-identity last resort is right for
        /// a contact row that must render something, but a transaction row
        /// falls back to its own generic title, which beats "Sent to 89fd6ddb…".
        var titleName: String? {
            counterpartyAlias ?? counterpartyName ?? counterpartyUsername
        }
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
            // DPNS labels, resolved in one batch — see `usernameHints`, which
            // is static precisely so this cannot touch the contacts service
            // singleton while that singleton is still initializing.
            let usernameByContactId = SwiftDashSDKContactsService.usernameHints(
                for: rows.lazy.filter { $0.amountDuffs > 0 }.map(\.counterpartyIdentityId))
            var map: [String: PaymentInfo] = [:]
            for row in rows where row.amountDuffs > 0 {
                let profile = profileByContactId[row.counterpartyIdentityId]
                map[row.txid.lowercased()] = PaymentInfo(
                    amountDuffs: row.amountDuffs,
                    isOutgoing: row.direction == .sent,
                    counterpartyIdentityId: row.counterpartyIdentityId,
                    counterpartyName: profile?.name?.isEmpty == false ? profile?.name : nil,
                    counterpartyAlias: aliasByContactId[row.counterpartyIdentityId],
                    counterpartyAvatarURL: profile?.avatarURL?.isEmpty == false ? profile?.avatarURL : nil,
                    counterpartyUsername: usernameByContactId[row.counterpartyIdentityId]?
                        .withoutDashSuffix)
            }
            store(map)
        } catch {
            // Keep the previous snapshot on a transient fetch failure.
        }
    }

    /// Swap the snapshot in, and say so when it actually changed.
    ///
    /// The signal matters because nothing else carries it. The payment rows
    /// behind this snapshot are written by an app-pulled projection, not by
    /// the SDK persister, and they live in entities the transaction feed's
    /// SwiftData-save filter ignores — so a feed already on screen kept
    /// rendering rows with dash-spv's misread direction and no contact name
    /// for the rest of the session. That was the whole of "DashPay
    /// transactions only come back after a resync": the data was correct in
    /// this cache, and nobody asked it again.
    ///
    /// Gated on a real change: the projection re-runs on a timer, and an
    /// unconditional post would rebuild the whole history list every pass.
    private func store(_ map: [String: PaymentInfo]) {
        lock.lock()
        let changed = infoByTxid != map
        infoByTxid = map
        lock.unlock()

        guard changed else { return }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}

extension DashPayPaymentTxLookup {
    /// Posted when the txid → DashPay-payment snapshot gained, lost, or
    /// altered an entry. Consumers re-read `info(forTxidHex:)`.
    static let didChangeNotification =
        Notification.Name("DWDashPayPaymentTxLookupDidChange")
}
