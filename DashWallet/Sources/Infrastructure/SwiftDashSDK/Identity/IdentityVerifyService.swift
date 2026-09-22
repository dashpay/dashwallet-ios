//
//  Created by Claude
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import OSLog
import SwiftDashSDK
import SwiftData

/// Publishes the proof-of-identity link a contested-name requester posts for
/// masternode owners to check before they vote.
///
/// The link lives on Platform as an `identityVerify` document in the
/// `identity-verify` contract — the same document Android writes through
/// dashj's `IdentityVerify.createForDashDomain` (kotlin-platform:
/// `dpp/.../wallet/IdentityVerify.kt`), so a link posted from either wallet is
/// read by the same voters. Fields: `normalizedLabel`,
/// `normalizedParentDomainName` and `url`.
///
/// Whoever asks for the vote is the one who signs it: the document is written
/// by the requester's own identity, PIN-gated like every other state
/// transition this app sends.
@MainActor
final class IdentityVerifyService {
    private static let logger = Logger(subsystem: "org.dash.wallet", category: "identity-verify")

    enum ServiceError: LocalizedError {
        case noIdentity
        case unsupportedNetwork
        case invalidURL
        case lookupFailed
        case authCancelled
        case authFailed

        var errorDescription: String? {
            switch self {
            case .noIdentity:
                return NSLocalizedString("This wallet has no Platform identity yet.", comment: "Usernames")
            case .unsupportedNetwork:
                return NSLocalizedString("Identity verification is not available on this network.", comment: "Usernames")
            case .invalidURL:
                return NSLocalizedString("Enter a link starting with http:// or https://", comment: "Usernames")
            case .lookupFailed:
                return NSLocalizedString("Could not check whether a link was already published. Try again.", comment: "Usernames")
            case .authCancelled:
                return nil
            case .authFailed:
                return NSLocalizedString("Authentication failed.", comment: "Usernames")
            }
        }
    }

    /// `identity-verify` contract ids, from the registry both wallets share
    /// (kotlin-platform `Platform.kt`, `apps["identity-verify"]`). Devnets have
    /// no deployment, so the feature reports itself unavailable there rather
    /// than writing to a contract that does not exist — the same stance the
    /// DashConnect key-exchange contract takes on mainnet.
    private static let contractIdByNetwork: [WalletEnvironment.NetworkKind: String] = [
        .mainnet: "EVKMFboB3QBUa9Jo7PP5bsLyohzUz8zvw5c2gJs1SfcX",
        .testnet: "Bhptm3yBDhLkRNt7ofjpwaBHhMUKjDrQoPufKzQaxmpK",
    ]
    private static let documentType = "identityVerify"
    /// DPNS's only parent domain — the same constant dashj calls
    /// `Names.DEFAULT_PARENT_DOMAIN`.
    private static let parentDomain = "dash"

    private let authorizer = DWIdentityAuthorizer()

    static let shared = IdentityVerifyService()

    /// Whether this network has a contract to publish to at all. Surfaces as
    /// a hidden entry rather than a button that fails on submit.
    var isAvailable: Bool {
        Self.contractIdByNetwork[WalletEnvironment.networkKind] != nil
    }

    /// The link already published for `label`, or nil when there is none.
    ///
    /// Read from Platform rather than from a local note: the document is the
    /// thing voters see, and a link published from another install of the same
    /// wallet counts.
    /// The link published for `label` by a *specific* identity — a rival
    /// contender's proof of identity, which is what a voter is weighing when
    /// they open that contender.
    ///
    /// Same query as `publishedURL(forLabel:)` (the contract's
    /// `uniqueUsernameIndex` is the only field this document can be found by),
    /// but it fetches the whole set for the label and picks the owner asked
    /// for, since a contested label has one document per contender.
    func publishedURL(forLabel label: String, ownedBy identityIdBase58: String) async throws -> URL? {
        let contractId = try requireContractIdBase58()
        guard let sdk = SwiftDashSDKHost.shared.sdk else { throw ServiceError.noIdentity }

        let normalized = try normalizedLabel(label, sdk: sdk)
        let whereClause = """
        [["normalizedLabel","==","\(normalized)"]]
        """

        // Paged rather than capped: the label is the only field this document
        // can be found by, so every contender's document comes back in one
        // list. A fixed limit would answer "no link published" for a contender
        // who simply sat past the end of the first page.
        let documents = try await allDocuments(
            matching: whereClause, contractId: contractId, sdk: sdk)
        let theirs = documents.first { Self.isOwned(byBase58: identityIdBase58, document: $0) }
        guard let urlString = theirs?["url"] as? String else { return nil }
        return URL(string: urlString)
    }

    func publishedURL(forLabel label: String) async throws -> URL? {
        let (_, _, identityId) = try requireContext()
        let contractId = try requireContractIdBase58()
        guard let sdk = SwiftDashSDKHost.shared.sdk else { throw ServiceError.noIdentity }

        let normalized = try normalizedLabel(label, sdk: sdk)
        // Label only, and the owner checked below.
        //
        // A `$ownerId` clause here matched nothing, silently: the FFI turns a
        // JSON string value into `Value::Text`
        // (`rs-sdk-ffi/document/queries/search.rs`, `json_to_platform_value`)
        // and never into an `Identifier`, so comparing it against the stored
        // owner identifier can never be true. The query was accepted and came
        // back empty, which is indistinguishable from "no link published" —
        // the screen showed nothing for a document that was on Platform.
        //
        // `normalizedLabel` is the contract's own `uniqueUsernameIndex`, so it
        // is the one field this document can be found by.
        let whereClause = """
        [["normalizedLabel","==","\(normalized)"]]
        """

        // Paged, for the same reason the contender lookup is: the label is the
        // only searchable field, so a contested name returns one document per
        // contender. Asking for a single row let a rival's document occupy it
        // and reported our own published link as "none" — and `publish()`
        // checks idempotency through this method, so it would then write a
        // second document the contract refuses.
        let documents = try await allDocuments(
            matching: whereClause, contractId: contractId, sdk: sdk)
        // Whose link it is has to be checked here, now that the query no
        // longer filters by owner. A contested label can have a rival
        // contender, and their proof of identity is not ours to show.
        let ours = documents.first { Self.isOwned(by: identityId, document: $0) }
        if ours == nil, !documents.isEmpty {
            // Error level so it persists in the unified log: the only way to
            // tell "nobody published one" from "we could not recognise the
            // owner field" after the fact.
            Self.logger.error(
                "🔗 IDENT-VERIFY :: \(documents.count, privacy: .public) document(s) for \(normalized, privacy: .public), none owned by this identity")
        }
        // The document's own `url` field, not a locally remembered one.
        guard let urlString = ours?["url"] as? String else { return nil }
        return URL(string: urlString)
    }

    /// Publishes `url` as the verification link for `label`.
    ///
    /// Idempotent by design, like dashj's `create`: an existing document is
    /// returned instead of writing a second one, because the contract indexes
    /// one document per (owner, label) and a duplicate would be rejected.
    @discardableResult
    func publish(url: URL, forLabel label: String) async throws -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ServiceError.invalidURL
        }

        let (wallet, container, identityId) = try requireContext()
        let contractId = try requireContractIdentifier()
        guard let sdk = SwiftDashSDKHost.shared.sdk else { throw ServiceError.noIdentity }

        if let existing = try await publishedURL(forLabel: label) {
            Self.logger.info("🔗 IDENT-VERIFY :: document already published for \(label, privacy: .public)")
            return existing
        }

        let normalized = try normalizedLabel(label, sdk: sdk)
        try await authorize()

        // Hand-built rather than JSONEncoder'd: the properties are three
        // strings, and the Rust side sanitizes them against the on-chain
        // schema anyway.
        let properties: [String: String] = [
            "normalizedLabel": normalized,
            "normalizedParentDomainName": Self.parentDomain,
            "url": url.absoluteString,
        ]
        let propertiesJSON = String(
            data: try JSONSerialization.data(withJSONObject: properties, options: []),
            encoding: .utf8) ?? "{}"

        _ = try await wallet.createDocument(
            ownerIdentityId: identityId,
            contractId: contractId,
            documentType: Self.documentType,
            propertiesJSON: propertiesJSON,
            signer: KeychainSigner(modelContainer: container))

        Self.logger.info("🔗 IDENT-VERIFY :: published link for \(normalized, privacy: .public)")
        return url
    }

    /// The registration flow's variant: publishes `url` for `label` with an
    /// identity and signer handed in, rather than looked up.
    ///
    /// The contested submission has just created the identity and still holds
    /// an authorized signer, so this costs no second PIN prompt — the same
    /// place Android publishes the document from (`CreateIdentityService`).
    /// Failure is the caller's to treat as non-fatal: the request itself has
    /// already been submitted by then.
    @discardableResult
    func publish(
        url: URL,
        forLabel label: String,
        identityId: Data,
        wallet: ManagedPlatformWallet,
        signer: KeychainSigner
    ) async throws -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ServiceError.invalidURL
        }
        guard let sdk = SwiftDashSDKHost.shared.sdk else { throw ServiceError.noIdentity }

        let contractId = try requireContractIdentifier()
        let normalized = try normalizedLabel(label, sdk: sdk)
        let properties: [String: String] = [
            "normalizedLabel": normalized,
            "normalizedParentDomainName": Self.parentDomain,
            "url": url.absoluteString,
        ]
        let propertiesJSON = String(
            data: try JSONSerialization.data(withJSONObject: properties, options: []),
            encoding: .utf8) ?? "{}"

        _ = try await wallet.createDocument(
            ownerIdentityId: identityId,
            contractId: contractId,
            documentType: Self.documentType,
            propertiesJSON: propertiesJSON,
            signer: signer)

        Self.logger.info("🔗 IDENT-VERIFY :: published link for \(normalized, privacy: .public) (registration flow)")
        return url
    }

    /// Every `identityVerify` document matching `whereClause`, walked page by
    /// page. The contract indexes this document type by `normalizedLabel`
    /// alone, so a contested label returns one row per contender and the
    /// caller — not the query — decides which is theirs.
    ///
    /// The FFI call is blocking under its `async` signature, hence the detach:
    /// awaiting it from this main-actor type would run the round trip on the
    /// main thread.
    private func allDocuments(
        matching whereClause: String,
        contractId: String,
        sdk: SDK
    ) async throws -> [[String: Any]] {
        var collected: [[String: Any]] = []
        var startAfter: String? = nil

        for _ in 0..<Self.maxLookupPages {
            let response: [String: Any]
            do {
                let after = startAfter
                response = try await Task.detached(priority: .userInitiated) {
                    try await sdk.documentList(
                        dataContractId: contractId,
                        documentType: Self.documentType,
                        whereClause: whereClause,
                        limit: Self.lookupPageSize,
                        startAfter: after)
                }.value
            } catch {
                Self.logger.error("🔗 IDENT-VERIFY :: lookup failed: \(String(describing: error), privacy: .public)")
                throw ServiceError.lookupFailed
            }

            guard let page = response["documents"] as? [[String: Any]] else {
                throw ServiceError.lookupFailed
            }
            collected.append(contentsOf: page)

            // A short page is the last one.
            guard page.count == Int(Self.lookupPageSize),
                  let cursor = page.last?["$id"] as? String
            else { return collected }
            startAfter = cursor
        }

        Self.logger.error("🔗 IDENT-VERIFY :: lookup gave up after \(Self.maxLookupPages, privacy: .public) pages")
        return collected
    }

    /// Documents per page when looking a contender's link up, and the number
    /// of pages before the search gives up — a contest with more contenders
    /// than this has bigger problems than a missing link.
    private static let lookupPageSize: UInt32 = 100
    private static let maxLookupPages = 10

    /// Whether `document` belongs to `identityId`.
    ///
    /// `$ownerId` comes back from `document.to_object()` through
    /// `serde_json`, and an identifier can land as base58 text or as raw
    /// bytes depending on how the platform value serializes, so both are
    /// accepted rather than assuming one.
    /// Same check as `isOwned(by:document:)`, for an owner known only by its
    /// base58 spelling — which is how contenders arrive from the vote-state
    /// query.
    private static func isOwned(byBase58 identityId: String, document: [String: Any]) -> Bool {
        guard let owner = document["$ownerId"] else { return false }
        if let text = owner as? String {
            return text == identityId
        }
        if let numbers = owner as? [NSNumber] {
            return Data(numbers.map { $0.uint8Value }).toBase58String() == identityId
        }
        if let bytes = owner as? Data {
            return bytes.toBase58String() == identityId
        }
        return false
    }

    private static func isOwned(by identityId: Data, document: [String: Any]) -> Bool {
        guard let owner = document["$ownerId"] else { return false }
        if let text = owner as? String {
            return text == identityId.toBase58String()
        }
        if let numbers = owner as? [NSNumber] {
            return Data(numbers.map { $0.uint8Value }) == identityId
        }
        if let bytes = owner as? Data {
            return bytes == identityId
        }
        return false
    }

    // MARK: - Plumbing

    private func requireContext() throws -> (ManagedPlatformWallet, ModelContainer, Data) {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let container = SwiftDashSDKHost.shared.modelContainer,
              let identityId = DWCurrentUserIdentityInfo.shared.identityId else {
            throw ServiceError.noIdentity
        }
        return (wallet, container, identityId)
    }

    /// The contract id in base58, for the document queries that address it as
    /// a string.
    private func requireContractIdBase58() throws -> String {
        guard let contractId = Self.contractIdByNetwork[WalletEnvironment.networkKind] else {
            throw ServiceError.unsupportedNetwork
        }
        return contractId
    }

    /// The same id as raw 32 bytes, which is what `createDocument` takes.
    private func requireContractIdentifier() throws -> Data {
        guard let identifier = Data.identifier(fromBase58: try requireContractIdBase58()),
              identifier.count == 32 else {
            throw ServiceError.unsupportedNetwork
        }
        return identifier
    }

    /// Normalization is protocol behavior: it goes through the SDK, never a
    /// Swift copy of the homograph mapping, or the document would be indexed
    /// under a label no voter looks up.
    private func normalizedLabel(_ label: String, sdk: SDK) throws -> String {
        try sdk.dpnsNormalizeLabel(label.trimmingCharacters(in: .whitespacesAndNewlines))
    }

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
