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
import SwiftData
import SwiftDashSDK

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

        var errorDescription: String? {
            switch self {
            case .noIdentity:
                return NSLocalizedString("No DashPay identity is registered", comment: "DashPay")
            case .contestedName:
                return NSLocalizedString("This name is short enough to be contested and must be requested through the username flow, where it goes to a network vote.", comment: "Username marketplace")
            case .invalidRecipient:
                return NSLocalizedString("The recipient identity couldn't be resolved.", comment: "Username marketplace")
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
        try await authorizer.authorize()
        _ = try await wallet.setDpnsNamePrice(
            ownerIdentityId: ownerId,
            name: name,
            priceCredits: priceDuffs * 1_000,
            signer: KeychainSigner(modelContainer: container))
        Self.logger.info("🏷️ MARKET :: price set on \(name, privacy: .public)")
    }

    func removeFromSale(name: String) async throws {
        let (wallet, container, ownerId) = try requireOwnContext()
        try await authorizer.authorize()
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
        try await authorizer.authorize()
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
        try await authorizer.authorize()
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

    /// Register a name nobody owns. Contested-eligible labels must go
    /// through the voting flow instead — this path refuses them rather
    /// than silently starting a vote.
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
            case .insufficientIdentityCredits(_, let required, let available):
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
}
