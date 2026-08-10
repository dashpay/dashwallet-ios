//
//  UsernameMarketplaceService.swift
//  DashWallet
//
//  DPNS username marketplace over the wallet-level SDK surface that
//  landed with platform #4348 (`DpnsMarketplace.swift`): typed search
//  with sale state, locally persisted my-names rows (including retained
//  sold/transferred departures), per-name trade history from the
//  Document History contract, and orchestrated trade operations with
//  typed errors — `notForSale`, `priceChanged` (a purchase never
//  executes at a price the user didn't confirm; consensus is the
//  backstop), `insufficientIdentityCredits`, and
//  `contestedNameNotTradable`.
//
//  This layer adds only what belongs to the app: the PIN/biometric gate
//  before anything is signed, resolution of the wallet's main identity,
//  friendlier wording for the errors users act on, and the contested
//  guard for direct registration (the trade ops are typed by the SDK).
//
//  dashpay target only.
//

import Foundation
import OSLog
import SwiftDashSDK
import SwiftData

// MARK: - Identifiable projections for SwiftUI

extension DpnsMarketplaceName: Identifiable {
    public var id: Data { documentId }

    var priceDuffs: UInt64? { priceCredits.map { $0 / 1_000 } }
    var isForSale: Bool { priceCredits != nil }

    func isOwned(by identityId: Data?) -> Bool {
        guard let identityId else { return false }
        return ownerId == identityId
    }
}

extension DpnsNameStateRow: Identifiable {
    public var id: Data { documentId }

    var priceDuffs: UInt64? { priceCredits.map { $0 / 1_000 } }
    var isForSale: Bool {
        guard case .owned = status else { return false }
        return priceCredits != nil
    }
}

// MARK: - UsernameMarketplaceService

/// Stateless facade over the SDK marketplace surface. Instantiated per
/// view model (it holds only an authorizer); deliberately NOT a
/// singleton.
@MainActor
struct UsernameMarketplaceService {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.username-marketplace")

    enum ServiceError: LocalizedError {
        case noIdentity
        case contestedName
        case invalidRecipient
        case invalidPrice
        case authCancelled
        case authFailed

        var errorDescription: String? {
            switch self {
            case .noIdentity:
                return NSLocalizedString("No DashPay identity is registered", comment: "DashPay")
            case .contestedName:
                return NSLocalizedString("Short names are decided by a network vote — use Request Username instead.", comment: "Username marketplace")
            case .invalidRecipient:
                return NSLocalizedString("The recipient identity couldn't be resolved.", comment: "Username marketplace")
            case .invalidPrice:
                return NSLocalizedString("This price is too high to list.", comment: "Username marketplace: listing price exceeds the representable maximum")
            case .authCancelled:
                return NSLocalizedString("Authentication cancelled", comment: "DashPay")
            case .authFailed:
                return NSLocalizedString("Authentication failed", comment: "DashPay")
            }
        }
    }

    private let authorizer = DWIdentityAuthorizer()

    // MARK: Reads

    /// Prefix search with live sale state — one network query.
    func search(prefix: String, limit: UInt32 = 25) async throws -> [DpnsMarketplaceName] {
        guard let wallet = SwiftDashSDKHost.shared.wallet else { return [] }
        return try await wallet.searchDpnsMarketplace(prefix: prefix, limit: limit)
    }

    /// The document-history system contract (platform #4348,
    /// `document_history_contract::ID_BYTES`). Every `setDocumentPrice`
    /// also writes a `priceUpdate` row here, indexed by
    /// `[dataContractId, $createdAt]` — the queryable listing trail the
    /// DPNS contract itself lacks ($price is not indexable). Browse
    /// walks it newest-first, so its cost scales with LISTING EVENTS,
    /// not with the size of the namespace.
    private static let documentHistoryContractId = "6voHRaoiPcfmMhbqCA9dixH98xcgPQ9UEcuaXjpVu3LD"

    /// One DPNS trade event from the history trail — a `priceUpdate`
    /// (listing / re-price) or a `purchase`. The event's own price and
    /// time are historical FACTS and safe to show as such; only claims
    /// about the PRESENT ("for sale now") require the live document.
    struct MarketplaceEvent {
        let dpnsDocumentIdBase58: String
        let priceCredits: UInt64
        let createdAtMs: UInt64
        /// Purchase events only: buyer (`$ownerId`) and seller, base58.
        let buyerIdBase58: String?
        let sellerIdBase58: String?
    }

    /// Newest-first page of DPNS listing / re-price events. `beforeMs`
    /// is the pagination cursor (previous page's last `createdAtMs`).
    func recentPriceChanges(beforeMs: UInt64?, limit: UInt32 = 25) async throws -> [MarketplaceEvent] {
        try await eventsPage(documentType: "priceUpdate", beforeMs: beforeMs, limit: limit)
    }

    /// Newest-first page of DPNS purchase events, with price paid and
    /// both counterparties.
    func recentPurchases(beforeMs: UInt64?, limit: UInt32 = 25) async throws -> [MarketplaceEvent] {
        try await eventsPage(documentType: "purchase", beforeMs: beforeMs, limit: limit)
    }

    private func eventsPage(documentType: String, beforeMs: UInt64?, limit: UInt32) async throws -> [MarketplaceEvent] {
        guard let sdk = SwiftDashSDKHost.shared.sdk else { return [] }
        var conditions = "[[\"dataContractId\",\"==\",\"\(DPNSVotePoll.contractId)\"]"
        if let beforeMs {
            conditions += ",[\"$createdAt\",\"<\",\(beforeMs)]"
        }
        conditions += "]"
        let result = try await sdk.documentList(
            dataContractId: Self.documentHistoryContractId,
            documentType: documentType,
            whereClause: conditions,
            // Order-by tuples here are [field, ascending-bool] — the FFI
            // rejects "asc"/"desc" strings. false = newest first.
            orderByClause: "[[\"$createdAt\",false]]",
            limit: limit)
        let docs: [[String: Any]]
        if let array = result["documents"] as? [[String: Any]] {
            docs = array
        } else if let array = result["items"] as? [[String: Any]] {
            docs = array
        } else {
            docs = result.values.compactMap { $0 as? [String: Any] }
        }
        return docs.compactMap { doc in
            guard let raw = doc["documentId"] as? String,
                  let documentId = Self.identifier32(raw),
                  let price = (doc["price"] as? NSNumber)?.uint64Value,
                  let createdAt = (doc["$createdAt"] as? NSNumber)?.uint64Value else { return nil }
            let buyer = (doc["$ownerId"] as? String).flatMap(Self.identifier32)
            let seller = (doc["sellerId"] as? String).flatMap(Self.identifier32)
            return MarketplaceEvent(
                dpnsDocumentIdBase58: documentId.toBase58String(),
                priceCredits: price,
                createdAtMs: createdAt,
                buyerIdBase58: documentType == "purchase" ? buyer?.toBase58String() : nil,
                sellerIdBase58: documentType == "purchase" ? seller?.toBase58String() : nil)
        }
    }

    /// Identifier-typed CUSTOM properties serialize as base64 in this
    /// query path's JSON, while SYSTEM fields ($id, $ownerId) are base58.
    /// Accept either, but only an exact 32-byte identifier — anything
    /// else is nil, never a guess.
    private static func identifier32(_ string: String) -> Data? {
        if let data = Data(base64Encoded: string), data.count == 32 {
            return data
        }
        if let data = Data.identifier(fromBase58: string), data.count == 32 {
            return data
        }
        return nil
    }

    /// The name behind an event's domain document: its label plus its
    /// live marketplace state. nil when the document is gone entirely;
    /// `live` nil when the name currently resolves to no queryable
    /// state. Only `live` may claim anything about the PRESENT — the
    /// event's own price/time are already history.
    struct EventName {
        let label: String
        let live: DpnsMarketplaceName?
    }

    func eventName(forDomainDocumentId documentIdBase58: String) async throws -> EventName? {
        guard let sdk = SwiftDashSDKHost.shared.sdk,
              let wallet = SwiftDashSDKHost.shared.wallet else { return nil }
        let doc: [String: Any]
        do {
            doc = try await sdk.documentGet(
                dataContractId: DPNSVotePoll.contractId,
                documentType: DPNSVotePoll.documentTypeName,
                documentId: documentIdBase58)
        } catch {
            // Gone documents are an expected outcome for old events.
            return nil
        }
        guard let label = (doc["label"] as? String) ?? (doc["normalizedLabel"] as? String) else {
            return nil
        }
        return EventName(
            label: label,
            live: try await wallet.dpnsMarketplaceNameState(name: label))
    }

    /// The main identity's tracked names from the wallet's local rows —
    /// no network round-trip. Includes retained `.sold` / `.transferred`
    /// departures so the UI can show what left and to whom.
    func myNames() async throws -> [DpnsNameStateRow] {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let identityId = DWCurrentUserIdentityInfo.shared.identityId else { return [] }
        return try await wallet.myDpnsMarketplaceNames(identityId: identityId)
    }

    /// Authoritative live state of one exact name; nil = unregistered.
    func nameState(_ name: String) async throws -> DpnsMarketplaceName? {
        guard let wallet = SwiftDashSDKHost.shared.wallet else { return nil }
        return try await wallet.dpnsMarketplaceNameState(name: name)
    }

    /// Full trade timeline (registration, listings, purchases with
    /// counterparties, transfers), block-time ascending.
    func history(_ name: String) async throws -> [DpnsNameHistoryEvent] {
        guard let wallet = SwiftDashSDKHost.shared.wallet else { return [] }
        return try await wallet.dpnsNameHistory(name: name)
    }

    /// Pull-to-refresh: one marketplace sync pass (tracked names, added/
    /// departed labels, price changes, seller balance refreshes).
    @discardableResult
    func syncNow() async throws -> DpnsMarketplaceSyncSummary {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw ServiceError.noIdentity
        }
        return try await wallet.syncDpnsMarketplace()
    }

    // MARK: Trade actions (all PIN-gated; SDK errors are typed)

    func setPrice(name: String, priceDuffs: UInt64) async throws {
        let (wallet, container, ownerId) = try requireOwnContext()
        guard priceDuffs <= UInt64.max / 1_000 else {
            throw ServiceError.invalidPrice
        }
        try await authorize()
        _ = try await wallet.setDpnsNamePrice(
            ownerIdentityId: ownerId,
            name: name,
            priceCredits: priceDuffs * 1_000,
            signer: KeychainSigner(modelContainer: container))
        Self.logger.info("🏷️ MARKET :: price set on \(name, privacy: .public)")
    }

    func removeFromSale(name: String) async throws {
        let (wallet, container, ownerId) = try requireOwnContext()
        try await authorize()
        _ = try await wallet.delistDpnsName(
            ownerIdentityId: ownerId,
            name: name,
            signer: KeychainSigner(modelContainer: container))
        Self.logger.info("🏷️ MARKET :: delisted \(name, privacy: .public)")
    }

    func transfer(name: String, toIdentityBase58 recipient: String) async throws {
        let (wallet, container, ownerId) = try requireOwnContext()
        guard let recipientId = Data.identifier(fromBase58: recipient), recipientId.count == 32 else {
            throw ServiceError.invalidRecipient
        }
        try await authorize()
        _ = try await wallet.transferDpnsName(
            ownerIdentityId: ownerId,
            name: name,
            recipientId: recipientId,
            signer: KeychainSigner(modelContainer: container))
        Self.logger.info("🏷️ MARKET :: transferred \(name, privacy: .public)")
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
    }

    /// Buy a listed name at exactly `expectedPriceCredits` — the SDK
    /// pre-flights the listing and the buyer's identity balance, pins the
    /// confirmed price into the transition, and consensus rejects any
    /// seller-side change (typed `.priceChanged`).
    func purchase(name: String, expectedPriceCredits: UInt64) async throws {
        let (wallet, container, buyerId) = try requireOwnContext()
        try await authorize()
        _ = try await wallet.purchaseDpnsName(
            purchaserIdentityId: buyerId,
            name: name,
            expectedPriceCredits: expectedPriceCredits,
            signer: KeychainSigner(modelContainer: container))
        Self.logger.info("🏷️ MARKET :: purchased \(name, privacy: .public) for \(expectedPriceCredits, privacy: .public) credits")
        // The name now points at the buyer's identity; refresh the
        // snapshots the rest of the app renders usernames from.
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
    }

    /// Register a name nobody owns, claimed instantly. Contested-eligible
    /// labels go through `requestContestedName` instead — this path
    /// refuses them rather than silently starting a vote.
    func register(label: String) async throws {
        guard !Self.isContested(label) else {
            throw ServiceError.contestedName
        }
        let (wallet, container, identityId) = try requireOwnContext()
        try await authorize()
        _ = try await wallet.registerDpnsName(
            identityId: identityId,
            name: label,
            signer: KeychainSigner(modelContainer: container))
        Self.logger.info("🏷️ MARKET :: registered \(label, privacy: .public)")
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
    }

    /// Request a contested-eligible name. Same `registerDpnsName`
    /// transition, but the on-chain effect differs: the label enters a
    /// masternode vote (~2 weeks mainnet) instead of being claimed, and
    /// the transition locks the protocol's vote-resolution fund
    /// (`contestedFundCredits`) from the identity balance.
    ///
    /// Mirrors step 3.5 of `DWIdentityRegistrationCoordinator`: the
    /// submission is bookmarked in `DWContestedNameStatusService` so the
    /// not-yet-owned label stays out of every username surface
    /// (`DWCurrentUserIdentityInfo`'s pending filter) and the Home-appear
    /// reconciliation resolves the eventual win/loss. The bookmark store
    /// tracks every in-flight label independently, so any number of
    /// contested requests can run at once — each is its own vote poll
    /// with its own vote-resolution fund.
    ///
    /// Returns the authoritative voting end time when Platform has
    /// already indexed the contest, nil while indexing lags.
    @discardableResult
    func requestContestedName(label: String) async throws -> Date? {
        let (wallet, container, identityId) = try requireOwnContext()
        // Capture the network BEFORE the PIN prompt and FFI awaits — a
        // network switch mid-flight must not scope the bookmark to the
        // newly-selected network (the network-explicit overload exists
        // for exactly this).
        guard let network = WalletEnvironment.network else {
            throw ServiceError.noIdentity
        }
        try await authorize()
        _ = try await wallet.registerDpnsName(
            identityId: identityId,
            name: label,
            signer: KeychainSigner(modelContainer: container))
        Self.logger.info("🏷️ MARKET :: contested request submitted for \(label, privacy: .public)")
        // Bookmark BEFORE the vote-state read — Platform can legitimately
        // return nil until the contest is indexed, and the conservative
        // fallback deadline written here is what reconciliation leans on.
        DWContestedNameStatusService.shared.recordSubmission(label: label, network: network)
        do {
            _ = try await wallet.syncContestedDpnsNames(identityId: identityId)
        } catch {
            Self.logger.warning("🏷️ MARKET :: syncContestedDpnsNames failed: \(String(describing: error), privacy: .public)")
        }
        var endTime: Date?
        if let state = try? await wallet.fetchContestVoteState(identityId: identityId, label: label) {
            endTime = state.endTime
            DWContestedNameStatusService.shared.recordVotingEndTime(state.endTime, label: label, network: network)
        }
        return endTime
    }

    // MARK: Contest reads

    /// Labels this identity is actively contending for, from the SDK's
    /// local cache (resolved contests drop out wholesale on sync).
    func myContestedNames(syncFirst: Bool = false) async -> [String] {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let identityId = DWCurrentUserIdentityInfo.shared.identityId else { return [] }
        if syncFirst {
            _ = try? await wallet.syncContestedDpnsNames(identityId: identityId)
        }
        return (try? wallet.managedIdentity(identityId: identityId).getContestedDpnsNames()) ?? []
    }

    /// Live vote state for a contest this identity is part of. nil while
    /// Platform hasn't indexed the contest, or once it resolved.
    func contestState(label: String) async -> ContestVoteState? {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let identityId = DWCurrentUserIdentityInfo.shared.identityId else { return nil }
        return try? await wallet.fetchContestVoteState(identityId: identityId, label: label)
    }

    /// What an unregistered contested-eligible label looks like on the
    /// network BEFORE we submit. Best-effort: an unavailable query
    /// reports `.unknown` (never a fabricated all-clear) and the
    /// submit-time transition stays the authority.
    enum ContestPrecheck: Equatable {
        /// No contest exists — a request starts a fresh vote.
        case fresh
        /// An active vote already holds this label; a request joins it
        /// as another contender.
        case activeContest(contenders: Int)
        /// A past vote locked the label — nobody can register it.
        case locked
        /// The query failed; state can't be determined.
        case unknown
    }

    func contestPrecheck(label: String) async -> ContestPrecheck {
        guard let sdk = SwiftDashSDKHost.shared.sdk else { return .unknown }
        do {
            let state = try await sdk.dpnsGetContestedVoteState(name: label)
            if state["winner"] is String {
                // "LOCKED" or a winning identity's base58 id. Either way
                // the vote is over and nobody can register the label, so
                // both resolve to locked-for-registration.
                return .locked
            }
            let contenders = (state["contenders"] as? [[String: Any]]) ?? []
            return contenders.isEmpty ? .fresh : .activeContest(contenders: contenders.count)
        } catch {
            // rs-sdk reports "no contest" as an error rather than an
            // empty result; a missing contest is the normal fresh case.
            let text = String(describing: error).lowercased()
            if text.contains("not found") || text.contains("no contest") {
                return .fresh
            }
            Self.logger.info("🏷️ MARKET :: contest precheck unavailable for \(label, privacy: .public): \(String(describing: error), privacy: .public)")
            return .unknown
        }
    }

    // MARK: Helpers

    /// Contested-name eligibility — delegates to the SDK's own
    /// `dash_sdk_dpns_is_contested_username` predicate so the client
    /// can't drift from the network rule.
    static func isContested(_ label: String) -> Bool {
        DWContestedNameStatusService.isContestedLabel(label)
    }

    /// The protocol's contested-document vote-resolution fund: what a
    /// contested request locks from the identity balance on top of the
    /// normal registration fee. Mirrors
    /// `vote_resolution_fund_fees::v1` in rs-platform-version
    /// (20_000_000_000 credits = 0.2 DASH).
    static let contestedFundCredits: UInt64 = 20_000_000_000

    /// Until when NEW contenders may join a contest, derived from its
    /// authoritative voting end time. Mirrors rs-platform-version
    /// `VotingValidationVersions` (v3): contenders may join for
    /// `allow_other_contenders_time` after the FIRST request — mainnet
    /// 1 week of the 2-week poll, testing environments 45 minutes of the
    /// 90-minute poll. In both, joining closes (poll − join window)
    /// before the end: 1 week on mainnet, 45 minutes on testnet.
    static func contenderJoinDeadline(voteEnd: Date) -> Date {
        let closedBeforeEnd: TimeInterval = WalletEnvironment.isMainnet
            ? 7 * 24 * 60 * 60
            : 45 * 60
        return voteEnd.addingTimeInterval(-closedBeforeEnd)
    }

    /// Buyer identity's credit balance from the persisted row — for the
    /// affordability hint; the SDK re-checks authoritatively at purchase.
    static func identityBalanceCredits(identityId: Data, container: ModelContainer) -> UInt64 {
        var descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { $0.identityId == identityId })
        descriptor.fetchLimit = 1
        guard let identity = (try? container.mainContext.fetch(descriptor))?.first else { return 0 }
        return UInt64(bitPattern: identity.balance)
    }

    /// Friendlier wording for the typed SDK failures a user acts on;
    /// everything else keeps the SDK's own description.
    static func userFacingMessage(for error: Error) -> String {
        if let walletError = error as? PlatformWalletError {
            switch walletError {
            case .notForSale:
                return NSLocalizedString("This username is not for sale.", comment: "Username marketplace")
            case .priceChanged:
                return NSLocalizedString("The seller changed the price before your purchase was accepted. Review the new price and try again.", comment: "Username marketplace")
            case let .insufficientIdentityCredits(_, required, available):
                return String.localizedStringWithFormat(
                    NSLocalizedString("Your identity balance can't cover this purchase: %@ DASH needed (including a fee reserve), %@ DASH available. Top up your identity balance and try again.", comment: "Username marketplace"),
                    (required / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol,
                    (available / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol)
            case .contestedNameNotTradable:
                return NSLocalizedString("This name is in an active network vote and can't be traded until the contest ends.", comment: "Username marketplace")
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func requireOwnContext() throws -> (ManagedPlatformWallet, ModelContainer, Data) {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let container = SwiftDashSDKHost.shared.modelContainer,
              let identityId = DWCurrentUserIdentityInfo.shared.identityId else {
            throw ServiceError.noIdentity
        }
        return (wallet, container, identityId)
    }

    /// PIN / biometric prompt with the authorizer's errors translated to
    /// service errors, so a user cancellation stays distinguishable from
    /// a failed marketplace action without callers importing the
    /// authorizer's symbols (same shape as
    /// `SwiftDashSDKContactsService.authorize()`).
    private func authorize() async throws {
        do {
            try await authorizer.authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            throw ServiceError.authCancelled
        } catch {
            throw ServiceError.authFailed
        }
    }
}
