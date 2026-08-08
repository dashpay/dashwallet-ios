//
//  UsernameMarketplaceService.swift
//  DashWallet
//
//  DPNS username marketplace over the v2 contract's trade surface
//  (`transferable = 1`, `tradeMode = 1` — direct purchase):
//
//  - Reads go through `SDK.documentList` on the two indices the contract
//    actually has: `parentNameAndLabel` (search) and `records.identity`
//    (my names). There is NO `$price` index, so a global "browse
//    everything for sale" query is not possible today — the marketplace
//    is search-driven until the contract grows a price index (tracked in
//    the platform-wallet marketplace task).
//  - Trade actions compose the generic FFI-wired document transitions on
//    `ManagedPlatformWallet`: `setDocumentPrice`, `purchaseDocument`,
//    `transferDocument`. Consensus (verified in rs-drive) removes
//    `$price` on BOTH purchase and transfer, so delisting is a transfer
//    to the owner's own identity. Purchases require the transition price
//    to equal the listed price, so a seller-side price change between
//    view and confirm is rejected on-chain — surfaced here as
//    `.priceChanged`.
//
//  Every action authenticates (PIN/biometric) BEFORE anything is signed
//  or broadcast, and signs with the identity's critical authentication
//  key (id 1) — critical satisfies every document security-level
//  requirement short of master, and master keys cannot sign document
//  transitions.
//
//  dashpay target only.
//

import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

// MARK: - MarketplaceName

/// One DPNS `domain` document projected for the marketplace UI. Every
/// field is read defensively from the document JSON; absent data stays
/// nil rather than defaulting.
struct MarketplaceName: Identifiable, Equatable {
    /// Base58 document id (`$id`) — the handle every trade action needs.
    let documentIdBase58: String
    /// Display label ("Alice"); falls back to the normalized label when
    /// the pretty-cased one is absent.
    let label: String
    let normalizedLabel: String
    /// Base58 `$ownerId` — the identity that owns (and may sell) the name.
    let ownerIdBase58: String
    /// Listed price in credits (`$price`); nil = not for sale.
    let priceCredits: UInt64?
    /// `$createdAt` / `$transferredAt` in ms when the document carries
    /// them — the only trade-history facts readable without the SDK's
    /// revision-history query (in progress).
    let createdAtMs: UInt64?
    let transferredAtMs: UInt64?

    var id: String { documentIdBase58 }
    var isForSale: Bool { priceCredits != nil }
    var priceDuffs: UInt64? { priceCredits.map { $0 / 1_000 } }

    func isOwned(by identityId: Data?) -> Bool {
        guard let identityId else { return false }
        return Data.identifier(fromBase58: ownerIdBase58) == identityId
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

    /// DPNS domain documents live under this parent domain.
    private static let parentDomain = "dash"
    private static let documentType = "domain"

    /// Identity key id 1 = the critical authentication key every
    /// registration creates; satisfies the document transitions'
    /// security-level requirements (master keys are not allowed to sign
    /// document transitions).
    private static let signingKeyId: UInt32 = 1

    /// Conservative fee reserve (credits) required ON TOP of the listed
    /// price before a purchase is attempted: the observed document-batch
    /// transition fee is well under 0.0005 DASH; 0.001 DASH keeps a 2x
    /// margin. The actual fee is metered at execution from the buyer
    /// identity's credits.
    static let purchaseFeeReserveCredits: UInt64 = 100_000_000

    enum ServiceError: LocalizedError, Equatable {
        case noIdentity
        case notForSale
        case priceChanged
        case insufficientIdentityCredits(neededCredits: UInt64, availableCredits: UInt64)
        case contestedName
        case invalidRecipient
        case invalidDocument

        var errorDescription: String? {
            switch self {
            case .noIdentity:
                return NSLocalizedString("No DashPay identity is registered", comment: "DashPay")
            case .notForSale:
                return NSLocalizedString("This username is not for sale.", comment: "Username marketplace")
            case .priceChanged:
                return NSLocalizedString("The seller changed the price before your purchase was accepted. Review the new price and try again.", comment: "Username marketplace")
            case .insufficientIdentityCredits(let needed, let available):
                return String.localizedStringWithFormat(
                    NSLocalizedString("Your identity balance can't cover this purchase: %@ DASH needed (including a fee reserve), %@ DASH available. Top up your identity balance and try again.", comment: "Username marketplace"),
                    (needed / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol,
                    (available / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol)
            case .contestedName:
                return NSLocalizedString("This name is short enough to be contested and must be requested through the username flow, where it goes to a network vote.", comment: "Username marketplace")
            case .invalidRecipient:
                return NSLocalizedString("The recipient identity couldn't be resolved.", comment: "Username marketplace")
            case .invalidDocument:
                return NSLocalizedString("This username's record couldn't be read from the network.", comment: "Username marketplace")
            }
        }
    }

    private let authorizer = DWIdentityAuthorizer()

    // MARK: Reads

    /// Prefix search over the `parentNameAndLabel` index — one query
    /// returns the full documents, so sale state and price come with the
    /// results (unlike `searchDpnsNames`, which only returns name +
    /// identity).
    func search(prefix: String, limit: UInt32 = 25) async throws -> [MarketplaceName] {
        guard let sdk = SwiftDashSDKHost.shared.sdk else { return [] }
        let normalized = (try? sdk.dpnsNormalizeLabel(prefix)) ?? prefix.lowercased()
        guard !normalized.isEmpty else { return [] }
        let whereClause = """
        [["normalizedParentDomainName","==","\(Self.parentDomain)"],["normalizedLabel","startsWith","\(normalized)"]]
        """
        let orderBy = "[[\"normalizedLabel\",\"asc\"]]"
        let result = try await sdk.documentList(
            dataContractId: DPNSVotePoll.contractId,
            documentType: Self.documentType,
            whereClause: whereClause,
            orderByClause: orderBy,
            limit: limit)
        return Self.parseDomainDocuments(result)
    }

    /// Every domain document owned by `identityIdBase58`, via the
    /// `records.identity` index.
    func names(ownedBy identityIdBase58: String) async throws -> [MarketplaceName] {
        guard let sdk = SwiftDashSDKHost.shared.sdk else { return [] }
        let whereClause = "[[\"records.identity\",\"==\",\"\(identityIdBase58)\"]]"
        let result = try await sdk.documentList(
            dataContractId: DPNSVotePoll.contractId,
            documentType: Self.documentType,
            whereClause: whereClause,
            limit: 50)
        return Self.parseDomainDocuments(result)
    }

    /// The single domain document for an exact label, or nil when the
    /// name is unregistered. Used to re-read the authoritative sale
    /// state right before a purchase.
    func name(exactLabel: String) async throws -> MarketplaceName? {
        guard let sdk = SwiftDashSDKHost.shared.sdk else { return nil }
        let normalized = (try? sdk.dpnsNormalizeLabel(exactLabel)) ?? exactLabel.lowercased()
        let whereClause = """
        [["normalizedParentDomainName","==","\(Self.parentDomain)"],["normalizedLabel","==","\(normalized)"]]
        """
        let result = try await sdk.documentList(
            dataContractId: DPNSVotePoll.contractId,
            documentType: Self.documentType,
            whereClause: whereClause,
            limit: 1)
        return Self.parseDomainDocuments(result).first
    }

    // MARK: Trade actions (all PIN-gated)

    /// List a name for sale, or change its price. `priceDuffs` is what
    /// the user typed; the document stores credits.
    func setPrice(name: MarketplaceName, priceDuffs: UInt64) async throws {
        let (wallet, container, ownerId) = try requireOwnContext()
        guard name.isOwned(by: ownerId) else { throw ServiceError.invalidDocument }
        guard let documentId = Data.identifier(fromBase58: name.documentIdBase58) else {
            throw ServiceError.invalidDocument
        }
        try await authorizer.authorize()
        _ = try await wallet.setDocumentPrice(
            ownerIdentityId: ownerId,
            contractId: Self.contractIdentifier(),
            documentType: Self.documentType,
            documentId: documentId,
            price: priceDuffs * 1_000,
            signingKeyId: Self.signingKeyId,
            signer: KeychainSigner(modelContainer: container))
        Self.logger.info("🏷️ MARKET :: price set on \(name.normalizedLabel, privacy: .public)")
    }

    /// Remove a name from sale. Consensus clears `$price` on every
    /// transfer (rs-drive `document_transfer_transition_action`), so a
    /// transfer to the owner's own identity delists without changing
    /// ownership — the contract has no dedicated "remove price"
    /// transition (`documentsMutable = false`).
    func removeFromSale(name: MarketplaceName) async throws {
        let (wallet, container, ownerId) = try requireOwnContext()
        guard name.isOwned(by: ownerId) else { throw ServiceError.invalidDocument }
        try await transfer(name: name, toIdentity: ownerId, wallet: wallet, container: container, ownerId: ownerId)
        Self.logger.info("🏷️ MARKET :: delisted \(name.normalizedLabel, privacy: .public) via self-transfer")
    }

    /// Gift/transfer a name to another identity (also clears any listing).
    func transfer(name: MarketplaceName, toIdentityBase58 recipient: String) async throws {
        let (wallet, container, ownerId) = try requireOwnContext()
        guard name.isOwned(by: ownerId) else { throw ServiceError.invalidDocument }
        guard let recipientId = Data.identifier(fromBase58: recipient), recipientId.count == 32 else {
            throw ServiceError.invalidRecipient
        }
        try await transfer(name: name, toIdentity: recipientId, wallet: wallet, container: container, ownerId: ownerId)
    }

    /// Buy a listed name. `expectedPriceCredits` is the price the user
    /// confirmed — the transition pins it, and consensus rejects the
    /// purchase if the seller changed the listing in between (surfaced
    /// as `.priceChanged` after a re-read).
    func purchase(name: MarketplaceName, expectedPriceCredits: UInt64) async throws {
        let (wallet, container, buyerId) = try requireOwnContext()
        guard let documentId = Data.identifier(fromBase58: name.documentIdBase58) else {
            throw ServiceError.invalidDocument
        }
        // Authoritative pre-flight: the listing may have changed or gone
        // since the row rendered.
        guard let current = try await self.name(exactLabel: name.normalizedLabel) else {
            throw ServiceError.invalidDocument
        }
        guard let listedPrice = current.priceCredits else { throw ServiceError.notForSale }
        guard listedPrice == expectedPriceCredits else { throw ServiceError.priceChanged }

        let needed = listedPrice + Self.purchaseFeeReserveCredits
        let available = Self.identityBalanceCredits(identityId: buyerId, container: container)
        guard available >= needed else {
            throw ServiceError.insufficientIdentityCredits(
                neededCredits: needed, availableCredits: available)
        }

        try await authorizer.authorize()
        _ = try await wallet.purchaseDocument(
            purchaserId: buyerId,
            contractId: Self.contractIdentifier(),
            documentType: Self.documentType,
            documentId: documentId,
            price: listedPrice,
            signingKeyId: Self.signingKeyId,
            signer: KeychainSigner(modelContainer: container))
        Self.logger.info("🏷️ MARKET :: purchased \(name.normalizedLabel, privacy: .public) for \(listedPrice, privacy: .public) credits")
        // The name now points at the buyer's identity; refresh the
        // snapshots the rest of the app renders usernames from.
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
    }

    /// Register a name nobody owns. Contested-eligible labels (3–19
    /// characters, letters/digits only per DPNS rules) must go through
    /// the voting flow instead — this path refuses them rather than
    /// silently starting a vote.
    func register(label: String) async throws {
        let (wallet, container, identityId) = try requireOwnContext()
        if let sdk = SwiftDashSDKHost.shared.sdk {
            let normalized = (try? sdk.dpnsNormalizeLabel(label)) ?? label.lowercased()
            if Self.isContestedEligible(normalizedLabel: normalized) {
                throw ServiceError.contestedName
            }
        }
        try await authorizer.authorize()
        _ = try await wallet.registerDpnsName(
            identityId: identityId,
            name: label,
            signer: KeychainSigner(modelContainer: container))
        Self.logger.info("🏷️ MARKET :: registered \(label, privacy: .public)")
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
    }

    // MARK: Helpers

    /// DPNS contested-name eligibility per the platform rules the
    /// username flow enforces: normalized labels of 3–19 characters
    /// consisting only of letters and digits (no hyphen) go to a vote.
    static func isContestedEligible(normalizedLabel: String) -> Bool {
        let length = normalizedLabel.count
        guard (3...19).contains(length) else { return false }
        return normalizedLabel.allSatisfy { $0.isLetter || $0.isNumber }
            && !normalizedLabel.allSatisfy { $0.isNumber }
    }

    /// Buyer identity's credit balance from the persisted row (same
    /// bit-pattern read the identities screen uses).
    static func identityBalanceCredits(identityId: Data, container: ModelContainer) -> UInt64 {
        var descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { $0.identityId == identityId })
        descriptor.fetchLimit = 1
        guard let identity = (try? container.mainContext.fetch(descriptor))?.first else { return 0 }
        return UInt64(bitPattern: identity.balance)
    }

    private func transfer(
        name: MarketplaceName,
        toIdentity recipientId: Data,
        wallet: ManagedPlatformWallet,
        container: ModelContainer,
        ownerId: Data
    ) async throws {
        guard let documentId = Data.identifier(fromBase58: name.documentIdBase58) else {
            throw ServiceError.invalidDocument
        }
        try await authorizer.authorize()
        _ = try await wallet.transferDocument(
            ownerIdentityId: ownerId,
            contractId: Self.contractIdentifier(),
            documentType: Self.documentType,
            documentId: documentId,
            recipientId: recipientId,
            signingKeyId: Self.signingKeyId,
            signer: KeychainSigner(modelContainer: container))
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
    }

    private func requireOwnContext() throws -> (ManagedPlatformWallet, ModelContainer, Data) {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let container = SwiftDashSDKHost.shared.modelContainer,
              let identityId = DWCurrentUserIdentityInfo.shared.identityId else {
            throw ServiceError.noIdentity
        }
        return (wallet, container, identityId)
    }

    private static func contractIdentifier() throws -> Data {
        guard let id = Data.identifier(fromBase58: DPNSVotePoll.contractId) else {
            throw ServiceError.invalidDocument
        }
        return id
    }

    /// Parse `documentList`'s JSON payload into projections. Accepts the
    /// `{"documents": [...]}` envelope or a bare array; anything that
    /// doesn't carry the required identity fields is dropped rather than
    /// guessed at.
    static func parseDomainDocuments(_ payload: [String: Any]) -> [MarketplaceName] {
        let docs: [[String: Any]]
        if let array = payload["documents"] as? [[String: Any]] {
            docs = array
        } else if let array = payload["items"] as? [[String: Any]] {
            docs = array
        } else if payload["$id"] != nil {
            docs = [payload]
        } else {
            docs = payload.values.compactMap { $0 as? [String: Any] }
        }
        return docs.compactMap { doc in
            guard let documentId = doc["$id"] as? String,
                  let ownerId = doc["$ownerId"] as? String else { return nil }
            let normalized = (doc["normalizedLabel"] as? String) ?? ""
            let label = (doc["label"] as? String) ?? normalized
            guard !label.isEmpty else { return nil }
            return MarketplaceName(
                documentIdBase58: documentId,
                label: label,
                normalizedLabel: normalized.isEmpty ? label.lowercased() : normalized,
                ownerIdBase58: ownerId,
                priceCredits: Self.uint64(doc["$price"]),
                createdAtMs: Self.uint64(doc["$createdAt"]),
                transferredAtMs: Self.uint64(doc["$transferredAt"]))
        }
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let string = value as? String, let parsed = UInt64(string) { return parsed }
        return nil
    }
}
