//
//  PlatformDashConnectDataSource.swift
//  DashWallet
//
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

import Combine
import Foundation
import OSLog
import Security
import SwiftData
import SwiftDashSDK

struct DashConnectAppMetadata: Equatable {
    let name: String
    let url: String
}

enum DashConnectFallbackAppMetadata {
    // Fallback-only branding keyed by the trustworthy contract id, not the spoofable QR label.
    private static let knownApps: [String: DashConnectAppMetadata] = [
        "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F": .init(name: "Yappr", url: "yap.pr")
    ]

    static func resolve(contractId: String, unauthenticatedLabel: String) -> DashConnectAppMetadata {
        if let known = knownApps[contractId] {
            return known
        }

        return DashConnectAppMetadata(
            name: unauthenticatedLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            url: ""
        )
    }
}

/// `Equatable` so tests can assert which failure occurred rather than matching
/// on its message. Matches `DashConnectMockError`, which is already declared
/// the same way; every associated value here is itself `Equatable`, so the
/// conformance is synthesised.
enum DashConnectPlatformError: LocalizedError, Equatable {
    case noWallet
    case noIdentity
    case noModelContainer
    case noSDK
    case unsupportedRuntimeNetwork(Network)
    case unsupportedRequestNetwork(expected: DashConnectNetwork, actual: DashConnectNetwork)
    case authorizationCancelled
    case authorizationFailed
    case randomGenerationFailed(OSStatus)
    case invalidHash160
    case noAuthenticationKey
    case existingDocumentLookupFailed
    case noApprovedConnectionAwaitingKeyRegistration
    case keyRegistrationWrongIdentity
    case keyRegistrationUnexpectedMutation
    case keyRegistrationMismatchedDerivedKey(KeyPurpose)
    case ephemeralKeyGenerationFailed
    case ambiguousKeyRegistrationConnection
    case devnetLoginContractNotConfigured
    case loginContractUnavailable

    var errorDescription: String? {
        switch self {
        case .noWallet:
            return "DashConnect requires an active SwiftDashSDK wallet."
        case .noIdentity:
            return "DashConnect requires a registered Platform identity."
        case .noModelContainer:
            return "DashConnect requires the SwiftData model container."
        case .noSDK:
            return "DashConnect requires the SwiftDashSDK runtime."
        case .unsupportedRuntimeNetwork(let network):
            return "DashConnect cannot publish from this wallet: the app runtime is on \(Self.displayName(for: network)), which does not match the network DashConnect is configured for."
        case let .unsupportedRequestNetwork(expected, actual):
            return "This DashConnect QR is for \(Self.displayName(for: actual)), but this wallet currently supports \(Self.displayName(for: expected)) only."
        case .authorizationCancelled:
            return NSLocalizedString("Authentication cancelled", comment: "DashConnect")
        case .authorizationFailed:
            return NSLocalizedString("Authentication failed", comment: "DashConnect")
        case .randomGenerationFailed(let status):
            return "Failed to generate secure random bytes for DashConnect (\(status))."
        case .invalidHash160:
            return "Failed to compute the app ephemeral public key hash."
        case .noAuthenticationKey:
            return "No enabled AUTHENTICATION ECDSA key is available for this identity."
        case .existingDocumentLookupFailed:
            return "The existing loginKeyResponse document could not be located for replacement."
        case .noApprovedConnectionAwaitingKeyRegistration:
            return "There is no login awaiting key registration — scan the app's login QR first."
        case .keyRegistrationWrongIdentity:
            return "The scanned key-registration transition targets a different identity."
        case .keyRegistrationUnexpectedMutation:
            return "The scanned key-registration transition does more than add the expected login keys."
        case .ephemeralKeyGenerationFailed:
            return "Could not generate an ephemeral DashConnect key."
        case .ambiguousKeyRegistrationConnection:
            return "Could not tell which approved app this login belongs to. Scan the app's QR code again."
        case .keyRegistrationMismatchedDerivedKey(let purpose):
            return "The scanned key-registration transition adds a \(purpose.name) key we did not derive."
        case .devnetLoginContractNotConfigured:
            return NSLocalizedString(
                "The devnet DashConnect contract id is not set or is not a valid identifier. Enter it in Settings → Devnet Settings.",
                comment: "DashConnect")
        case .loginContractUnavailable:
            return "The DashConnect login contract is not available on this network."
        }
    }

    private static func displayName(for network: DashConnectNetwork) -> String {
        switch network {
        case .mainnet:
            return "Mainnet"
        case .testnet:
            return "Testnet"
        case .devnet:
            return "Devnet"
        }
    }

    private static func displayName(for network: Network) -> String {
        switch network {
        case .mainnet:
            return "Mainnet"
        case .testnet:
            return "Testnet"
        case .devnet:
            return "Devnet"
        case .regtest:
            return "Regtest"
        }
    }
}

struct DashConnectLoginKeyResponseDraft: Equatable {
    let properties: [String: AnyHashable]
    let walletEphemeralPublicKey: Data
    let encryptedPayload: Data
}

struct DashConnectKeyRegistrationKey: Equatable {
    let keyId: UInt32
    let keyType: KeyType
    let purpose: KeyPurpose
    let securityLevel: SecurityLevel
    let publicKeyData: Data
    let contractBounds: ContractBounds?
}

struct DashConnectKeyRegistrationTransition: Equatable {
    let identityId: Data
    let addPublicKeys: [DashConnectKeyRegistrationKey]
    let disablePublicKeyIds: [UInt32]
}

/// The two keys a `dash-st:` transition was allowed to add, once every check
/// passed, paired with the app contract id they were derived against.
struct DashConnectKeyRegistrationValidationResult: Equatable {
    let appContractId: Data
    let authenticationKey: DashConnectKeyRegistrationKey
    let encryptionKey: DashConnectKeyRegistrationKey
}

private struct DashConnectKeyRegistrationDerivedMaterial {
    var loginKey: Data
    var authenticationPrivateKey: Data
    let authenticationPublicKeyHash160: Data
    var encryptionPrivateKey: Data
    let encryptionPublicKey: Data
}

protocol DashConnectKeyRegistrationParsing {
    func parse(_ transitionBytes: Data) throws -> DashConnectKeyRegistrationTransition
}

struct PlatformWalletDashConnectKeyRegistrationParser: DashConnectKeyRegistrationParsing {
    private let parseTransition: (Data) throws -> ManagedPlatformWallet.ParsedIdentityUpdateTransition

    init(
        parseTransition: @escaping (Data) throws -> ManagedPlatformWallet.ParsedIdentityUpdateTransition = { bytes in
            try MainActor.assumeIsolated {
                guard let wallet = SwiftDashSDKHost.shared.wallet else {
                    throw DashConnectPlatformError.noWallet
                }
                return try wallet.parseIdentityUpdateTransition(bytes)
            }
        }
    ) {
        self.parseTransition = parseTransition
    }

    func parse(_ transitionBytes: Data) throws -> DashConnectKeyRegistrationTransition {
        let parsed = try parseTransition(transitionBytes)

        return DashConnectKeyRegistrationTransition(
            identityId: parsed.identityId,
            addPublicKeys: parsed.addPublicKeys.map { key in
                DashConnectKeyRegistrationKey(
                    keyId: key.keyId,
                    keyType: key.keyType,
                    purpose: key.purpose,
                    securityLevel: key.securityLevel,
                    publicKeyData: key.pubkeyBytes,
                    contractBounds: key.contractBounds.map {
                        switch $0 {
                        case .singleContract(let id):
                            return .singleContract(id: id)
                        case .singleContractDocumentType(let id, let documentTypeName):
                            return .singleContractDocumentType(
                                id: id,
                                documentTypeName: documentTypeName
                            )
                        }
                    }
                )
            },
            disablePublicKeyIds: parsed.disablePublicKeyIds
        )
    }
}

final class PlatformDashConnectDataSource: DashConnectDataSource {
    struct DocumentSigningKeyCandidate: Equatable {
        let keyId: UInt32
        let purpose: KeyPurpose
        let securityLevel: SecurityLevel
        let keyType: KeyType
        let disabledAt: Int64?
    }

    private struct Context {
        let wallet: ManagedPlatformWallet
        let sdk: SDK
        let modelContainer: ModelContainer
        let network: Network
        let identityId: Data
        let identityIndex: UInt32
        let storedUsername: String?
    }

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "dashconnect.platform-data-source")

    /// The pinned TESTNET `loginKeyResponse` contract id. Compile-time
    /// constant, so the length check can never fire at runtime.
    static let testnetLoginKeyExchangeContractId: Data = {
        guard let data = Data.identifier(fromBase58: "7UaqHGBJBbRLJ4fUWS45cnud8PPUugJWoGTt1SKwHJ2P"),
              data.count == 32 else {
            fatalError("DashConnect loginKeyResponse contract id must be a 32-byte identifier.")
        }
        return data
    }()
    static let loginKeyExchangeDocumentType = "loginKeyResponse"

    private let supportedNetwork: DashConnectNetwork
    private let store: any DashConnectStore
    private let subject: CurrentValueSubject<[DAppConnection], Never>
    private let authorizer: DWIdentityAuthorizer
    private let keyRegistrationParser: any DashConnectKeyRegistrationParsing
    private let now: () -> Date

    /// The DashConnect network matching the app's current network selection —
    /// what the default data source serves. Mainnet maps to `.mainnet` for
    /// completeness, but the real data source is never constructed there
    /// (the feature is unavailable on mainnet; the mock is used instead).
    static func currentEnvironmentNetwork() -> DashConnectNetwork {
        switch WalletEnvironment.networkKind {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        }
    }

    init(
        supportedNetwork: DashConnectNetwork = PlatformDashConnectDataSource.currentEnvironmentNetwork(),
        store: (any DashConnectStore)? = nil,
        authorizer: DWIdentityAuthorizer = DWIdentityAuthorizer(),
        keyRegistrationParser: any DashConnectKeyRegistrationParsing = PlatformWalletDashConnectKeyRegistrationParser(),
        now: @escaping () -> Date = Date.init
    ) {
        assert(
            supportedNetwork == .testnet || supportedNetwork == .devnet,
            "DashConnect Platform publish runs on testnet and devnet only.")
        self.supportedNetwork = supportedNetwork
        self.store = store ?? UserDefaultsDashConnectStore(network: supportedNetwork)
        self.authorizer = authorizer
        self.keyRegistrationParser = keyRegistrationParser
        self.now = now
        self.subject = CurrentValueSubject(self.store.load())
    }

    var connections: AnyPublisher<[DAppConnection], Never> {
        subject.eraseToAnyPublisher()
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if DashConnectUri.isKeyUri(trimmed) {
            let request = try DashConnectUri.parseKeyRequest(trimmed)
            try validateNetwork(request.network)
            return .login(request)
        }

        if DashConnectUri.isStUri(trimmed) {
            let request = try DashConnectUri.parseStRequest(trimmed)
            try validateNetwork(request.network)
            return .keyRegistration(request)
        }

        throw DashConnectMockError.notDashConnectQrCode
    }

    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest {
        let fallback = ConnectionRequest(loginRequest: loginRequest)
        let existingConnection = existingConnection(for: fallback.appContractId)

        guard let context = try? await requireContext() else {
            return ConnectionRequest(
                loginRequest: loginRequest,
                appLabel: fallback.appLabel,
                appUrl: fallback.appUrl,
                walletUsername: nil,
                walletIdentityId: nil,
                existingConnection: existingConnection
            )
        }

        let metadata = await resolveAppMetadata(for: loginRequest, sdk: context.sdk)
        let walletUsername = await resolveWalletUsername(context: context)

        return ConnectionRequest(
            loginRequest: loginRequest,
            appLabel: metadata.name.isEmpty ? fallback.appLabel : metadata.name,
            appUrl: metadata.url,
            walletUsername: walletUsername,
            walletIdentityId: context.identityId.toBase58String(),
            existingConnection: existingConnection
        )
    }

    func approveLogin(_ request: DashKeyRequest) async throws -> DAppConnection {
        Self.logger.info("🔗 DASHCONNECT :: approveLogin started")
        try validateNetwork(request.network)

        let context: Context
        do {
            context = try await requireContext()
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: no context — \(error.localizedDescription, privacy: .public)")
            throw error
        }
        do {
            try await authorize()
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: authorization failed — \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // `deriveIdentityAuthKeyAtSlot` is main-actor isolated in the SDK.
        var chainKey = try await MainActor.run {
            try context.wallet.deriveIdentityAuthKeyAtSlot(
                identityIndex: context.identityIndex,
                keyId: UInt32(LoginKeyDerivation.defaultKeyIndex),
                network: context.network
            ).privateKeyData
        }
        defer { Self.zero(&chainKey) }

        var loginKey = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: context.identityId,
            appContractId: request.contractId
        )
        defer { Self.zero(&loginKey) }

        var walletEphemeralPrivateKey = try Self.generateEphemeralPrivateKey()
        let draft = try Self.buildLoginKeyResponseDraft(
            loginKey: loginKey,
            appContractId: request.contractId,
            appEphemeralPubKey: request.appEphemeralPubKey,
            walletEphemeralPrivateKey: &walletEphemeralPrivateKey
        )

        let signer = KeychainSigner(modelContainer: context.modelContainer)
        let propertiesJSON = try Self.makeJSONObjectString(from: draft.properties)

        // Whether this identity already published a login-key response for this
        // app is a question about state, so it is answered by asking. Matching
        // substrings in the error text instead would break the moment the SDK
        // rewords or localizes a message, and "duplicate" also matches unique-
        // index failures that have nothing to do with this document.
        try await writeLoginKeyResponseDocument(
            context: context,
            appContractId: request.contractId,
            propertiesJSON: propertiesJSON,
            signer: signer
        )

        let preview = await makeConnectionRequest(from: request)
        let connection: DAppConnection
        do {
            var derivedMaterial = try Self.deriveKeyRegistrationMaterial(
                chainKeyPrivateBytes: chainKey,
                identityId: context.identityId,
                appContractId: request.contractId
            )
            defer {
                Self.zero(&derivedMaterial.loginKey)
                Self.zero(&derivedMaterial.authenticationPrivateKey)
                Self.zero(&derivedMaterial.encryptionPrivateKey)
            }

            let currentPublicKeys = try context.wallet
                .managedIdentity(identityId: context.identityId)
                .getPublicKeys()
            // The `dash-st:` registration happens once per (identity, app):
            // after it, the app stops emitting that QR. So the status reflects
            // whether the derived login keys are on the identity, not which
            // step of the flow just ran.
            if Self.hasRegisteredLoginKeys(
                authenticationPublicKeyHash160: derivedMaterial.authenticationPublicKeyHash160,
                encryptionPublicKey: derivedMaterial.encryptionPublicKey,
                currentIdentityPublicKeys: currentPublicKeys
            ) {
                connection = Self.makeConnection(preview: preview, status: .active, updatedAt: now())
            } else {
                connection = Self.makeConnection(preview: preview, status: .approved, updatedAt: now())
            }
        } catch {
            Self.logger.error(
                "🔗 DASHCONNECT :: could not confirm registered login keys after approveLogin — \(error.localizedDescription, privacy: .public)"
            )
            // Conservative fallback: asking for a QR is safer than claiming the
            // registration is already on the identity when we could not verify it.
            connection = Self.makeConnection(preview: preview, status: .approved, updatedAt: now())
        }

        var current = subject.value.filter { $0.id != connection.id }
        current.append(connection)
        persistAndSend(current)
        return connection
    }

    func completeKeyRegistration(_ request: DashStRequest) async throws {
        try validateNetwork(request.network)
        let context = try await requireContext()
        // Chosen approach: (a) deserialize the scanned IdentityUpdateTransition,
        // verify it only adds the exact derived login keys for our identity,
        // then rebuild the equivalent `updateIdentity(...)` call through the SDK.
        //
        // Parsed before the connection is chosen: `DashStRequest` carries no app
        // identifier, but the transition's keys usually do, in their contract
        // bounds. Picking the most recently approved connection instead would
        // derive app B's keys for a QR scanned from app A.
        let transition = try await MainActor.run {
            try keyRegistrationParser.parse(request.transitionBytes)
        }

        let pendingConnection = try pendingApprovedConnectionForKeyRegistration(
            boundContractId: Self.boundAppContractId(in: transition)
        )
        guard let pendingAppContractId = Self.decodeIdentifier(pendingConnection.id) else {
            throw DashConnectPlatformError.noApprovedConnectionAwaitingKeyRegistration
        }

        // `deriveIdentityAuthKeyAtSlot` is main-actor isolated in the SDK.
        var chainKey = try await MainActor.run {
            try context.wallet.deriveIdentityAuthKeyAtSlot(
                identityIndex: context.identityIndex,
                keyId: UInt32(LoginKeyDerivation.defaultKeyIndex),
                network: context.network
            ).privateKeyData
        }
        defer { Self.zero(&chainKey) }

        var derivedMaterial = try Self.deriveKeyRegistrationMaterial(
            chainKeyPrivateBytes: chainKey,
            identityId: context.identityId,
            appContractId: pendingAppContractId
        )
        defer {
            Self.zero(&derivedMaterial.loginKey)
            Self.zero(&derivedMaterial.authenticationPrivateKey)
            Self.zero(&derivedMaterial.encryptionPrivateKey)
        }

        let validated = try Self.validateKeyRegistration(
            transition,
            identityId: context.identityId,
            appContractId: pendingAppContractId,
            derivedMaterial: derivedMaterial
        )

        let currentPublicKeys = try context.wallet
            .managedIdentity(identityId: context.identityId)
            .getPublicKeys()
        let missingKeys = Self.missingKeyRegistrationKeys(
            validated,
            currentIdentityPublicKeys: currentPublicKeys
        )

        guard !missingKeys.isEmpty else {
            persistAndSend(
                subject.value.map { connection in
                    guard connection.id == pendingConnection.id else { return connection }
                    return DAppConnection(
                        id: connection.id,
                        name: connection.name,
                        url: connection.url,
                        status: .active,
                        updatedAt: now()
                    )
                }
            )
            return
        }

        try await authorize()

        let signer = KeychainSigner(modelContainer: context.modelContainer)
        try await signer.withAdditionalSigningKeys([
            (
                publicKey: validated.authenticationKey.publicKeyData,
                privateKey: derivedMaterial.authenticationPrivateKey
            ),
            (
                publicKey: validated.encryptionKey.publicKeyData,
                privateKey: derivedMaterial.encryptionPrivateKey
            ),
        ]) {
            try await context.wallet.updateIdentity(
                identityId: context.identityId,
                addPublicKeys: missingKeys.map(Self.makeManagedIdentityPubkey),
                signer: signer
            )
        }

        persistAndSend(
            subject.value.map { connection in
                guard connection.id == pendingConnection.id else { return connection }
                return DAppConnection(
                    id: connection.id,
                    name: connection.name,
                    url: connection.url,
                    status: .active,
                    updatedAt: now()
                )
            }
        )
    }

    func remove(id: String) async {
        persistAndSend(subject.value.filter { $0.id != id })
    }

    func disconnect(id: String) async {
        let disconnectedAt = now()
        // Local-only: keep the published `loginKeyResponse` document intact.
        // Re-approving the same `dash-key:` QR is enough to return to `.active`
        // once the identity keys are still registered.
        persistAndSend(subject.value.map { connection in
            guard connection.id == id else { return connection }
            return DAppConnection(
                id: connection.id,
                name: connection.name,
                url: connection.url,
                status: .approved,
                updatedAt: disconnectedAt
            )
        })
    }

    static func buildLoginKeyResponseDraft(
        loginKey: Data,
        appContractId: Data,
        appEphemeralPubKey: Data,
        walletEphemeralPrivateKey: inout Data,
        encryptLoginKey: (Data, Data, Data) throws -> Data = { loginKey, walletPriv, appPub in
            try KeyExchangeCrypto.encryptLoginKey(
                loginKey,
                walletEphemeralPriv: walletPriv,
                appEphemeralPub: appPub
            )
        }
    ) throws -> DashConnectLoginKeyResponseDraft {
        defer { zero(&walletEphemeralPrivateKey) }

        let appEphemeralPubKeyHash = try KeyExchangeCrypto.hash160(appEphemeralPubKey)
        guard appEphemeralPubKeyHash.count == 20 else {
            throw DashConnectPlatformError.invalidHash160
        }

        let walletEphemeralPublicKey = try Secp256k1.compressedPublicKey(privateKey: walletEphemeralPrivateKey)
        let encryptedPayload = try encryptLoginKey(loginKey, walletEphemeralPrivateKey, appEphemeralPubKey)

        return DashConnectLoginKeyResponseDraft(
            properties: [
                "contractId": appContractId.toBase58String(),
                "appEphemeralPubKeyHash": appEphemeralPubKeyHash.toHexString(),
                "walletEphemeralPubKey": walletEphemeralPublicKey.toHexString(),
                "encryptedPayload": encryptedPayload.toHexString(),
                "keyIndex": LoginKeyDerivation.defaultKeyIndex,
            ],
            walletEphemeralPublicKey: walletEphemeralPublicKey,
            encryptedPayload: encryptedPayload
        )
    }

    static func validateKeyRegistration(
        _ transition: DashConnectKeyRegistrationTransition,
        chainKeyPrivateBytes: Data,
        identityId: Data,
        appContractId: Data
    ) throws -> DashConnectKeyRegistrationValidationResult {
        var derivedMaterial = try deriveKeyRegistrationMaterial(
            chainKeyPrivateBytes: chainKeyPrivateBytes,
            identityId: identityId,
            appContractId: appContractId
        )
        defer {
            zero(&derivedMaterial.loginKey)
            zero(&derivedMaterial.authenticationPrivateKey)
            zero(&derivedMaterial.encryptionPrivateKey)
        }

        return try validateKeyRegistration(
            transition,
            identityId: identityId,
            appContractId: appContractId,
            derivedMaterial: derivedMaterial
        )
    }

    private static func deriveKeyRegistrationMaterial(
        chainKeyPrivateBytes: Data,
        identityId: Data,
        appContractId: Data
    ) throws -> DashConnectKeyRegistrationDerivedMaterial {
        var loginKey = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKeyPrivateBytes,
            identityId: identityId,
            appContractId: appContractId
        )
        var authenticationPrivateKey = Data()
        var encryptionPrivateKey = Data()

        do {
            authenticationPrivateKey = try KeyExchangeCrypto.deriveAuthPrivateKey(
                loginKey: loginKey,
                identityId: identityId
            )
            let authenticationPublicKey = try Secp256k1.compressedPublicKey(
                privateKey: authenticationPrivateKey
            )
            let authenticationPublicKeyHash160 = try KeyExchangeCrypto.hash160(authenticationPublicKey)

            encryptionPrivateKey = try KeyExchangeCrypto.deriveEncryptionPrivateKey(
                loginKey: loginKey,
                identityId: identityId
            )
            let encryptionPublicKey = try Secp256k1.compressedPublicKey(
                privateKey: encryptionPrivateKey
            )

            return DashConnectKeyRegistrationDerivedMaterial(
                loginKey: loginKey,
                authenticationPrivateKey: authenticationPrivateKey,
                authenticationPublicKeyHash160: authenticationPublicKeyHash160,
                encryptionPrivateKey: encryptionPrivateKey,
                encryptionPublicKey: encryptionPublicKey
            )
        } catch {
            zero(&loginKey)
            zero(&authenticationPrivateKey)
            zero(&encryptionPrivateKey)
            throw error
        }
    }

    private static func validateKeyRegistration(
        _ transition: DashConnectKeyRegistrationTransition,
        identityId: Data,
        appContractId: Data,
        derivedMaterial: DashConnectKeyRegistrationDerivedMaterial
    ) throws -> DashConnectKeyRegistrationValidationResult {
        guard transition.identityId == identityId else {
            throw DashConnectPlatformError.keyRegistrationWrongIdentity
        }
        guard transition.disablePublicKeyIds.isEmpty else {
            throw DashConnectPlatformError.keyRegistrationUnexpectedMutation
        }
        guard transition.addPublicKeys.count == 2 else {
            throw DashConnectPlatformError.keyRegistrationUnexpectedMutation
        }

        var authenticationKey: DashConnectKeyRegistrationKey?
        var encryptionKey: DashConnectKeyRegistrationKey?

        for key in transition.addPublicKeys {
            switch key.purpose {
            case .authentication:
                guard authenticationKey == nil,
                      key.keyType == .ecdsaHash160,
                      key.securityLevel == .high,
                      key.publicKeyData == derivedMaterial.authenticationPublicKeyHash160 else {
                    throw DashConnectPlatformError.keyRegistrationMismatchedDerivedKey(.authentication)
                }
                authenticationKey = key
            case .encryption:
                guard encryptionKey == nil,
                      key.keyType == .ecdsaSecp256k1,
                      key.securityLevel == .medium,
                      key.publicKeyData == derivedMaterial.encryptionPublicKey else {
                    throw DashConnectPlatformError.keyRegistrationMismatchedDerivedKey(.encryption)
                }
                encryptionKey = key
            default:
                throw DashConnectPlatformError.keyRegistrationUnexpectedMutation
            }
        }

        guard let authenticationKey, let encryptionKey else {
            throw DashConnectPlatformError.keyRegistrationUnexpectedMutation
        }

        return DashConnectKeyRegistrationValidationResult(
            appContractId: appContractId,
            authenticationKey: authenticationKey,
            encryptionKey: encryptionKey
        )
    }

    static func hasRegisteredLoginKeys(
        authenticationPublicKeyHash160: Data,
        encryptionPublicKey: Data,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> Bool {
        hasRegisteredAuthenticationKey(
            authenticationPublicKeyHash160: authenticationPublicKeyHash160,
            currentIdentityPublicKeys: currentIdentityPublicKeys
        ) && hasRegisteredEncryptionKey(
            encryptionPublicKey: encryptionPublicKey,
            currentIdentityPublicKeys: currentIdentityPublicKeys
        )
    }

    static func missingKeyRegistrationKeys(
        _ validated: DashConnectKeyRegistrationValidationResult,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> [DashConnectKeyRegistrationKey] {
        let hasAuthenticationKey = hasRegisteredAuthenticationKey(
            authenticationPublicKeyHash160: validated.authenticationKey.publicKeyData,
            currentIdentityPublicKeys: currentIdentityPublicKeys
        )
        let hasEncryptionKey = hasRegisteredEncryptionKey(
            encryptionPublicKey: validated.encryptionKey.publicKeyData,
            currentIdentityPublicKeys: currentIdentityPublicKeys
        )

        var missingKeys: [DashConnectKeyRegistrationKey] = []
        if !hasAuthenticationKey {
            missingKeys.append(validated.authenticationKey)
        }
        if !hasEncryptionKey {
            missingKeys.append(validated.encryptionKey)
        }
        return missingKeys
    }

    private static func makeConnection(
        preview: ConnectionRequest,
        status: ConnectionStatus,
        updatedAt: Date
    ) -> DAppConnection {
        DAppConnection(
            id: preview.appContractId,
            name: preview.appLabel.isEmpty ? NSLocalizedString("Unknown app", comment: "DashConnect") : preview.appLabel,
            url: preview.appUrl,
            status: status,
            updatedAt: updatedAt
        )
    }

    private static func hasRegisteredAuthenticationKey(
        authenticationPublicKeyHash160: Data,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> Bool {
        currentIdentityPublicKeys.contains {
            $0.purpose == .authentication
                && $0.securityLevel == .high
                && $0.keyType == .ecdsaHash160
                && $0.disabledAt == nil
                && $0.data == authenticationPublicKeyHash160
        }
    }

    private static func hasRegisteredEncryptionKey(
        encryptionPublicKey: Data,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> Bool {
        currentIdentityPublicKeys.contains {
            $0.purpose == .encryption
                && $0.securityLevel == .medium
                && $0.keyType == .ecdsaSecp256k1
                && $0.disabledAt == nil
                && $0.data == encryptionPublicKey
        }
    }

    private func persistAndSend(_ connections: [DAppConnection]) {
        let sorted = connections.sorted(by: { $0.updatedAt > $1.updatedAt })
        store.save(sorted)
        subject.send(sorted)
    }

    private func existingConnection(for contractId: String) -> DAppConnection? {
        subject.value.first { $0.id == contractId }
    }

    private func pendingApprovedConnectionForKeyRegistration(
        boundContractId: Data?
    ) throws -> DAppConnection {
        try Self.pendingApprovedConnectionForKeyRegistration(
            in: subject.value,
            boundContractId: boundContractId
        )
    }

    /// The contract every bounded key in the transition points at, or `nil`
    /// when the transition carries no bounds — or carries bounds that disagree,
    /// which names no single app and so identifies nothing.
    static func boundAppContractId(
        in transition: DashConnectKeyRegistrationTransition
    ) -> Data? {
        let boundIds = transition.addPublicKeys.compactMap { key -> Data? in
            switch key.contractBounds {
            case .singleContract(let id):
                return id
            case .singleContractDocumentType(let id, _):
                return id
            case nil:
                return nil
            }
        }

        guard let first = boundIds.first, boundIds.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    static func pendingApprovedConnectionForKeyRegistration(
        in connections: [DAppConnection],
        boundContractId: Data?
    ) throws -> DAppConnection {
        let approved = connections.filter { $0.status == .approved }
        guard !approved.isEmpty else {
            throw DashConnectPlatformError.noApprovedConnectionAwaitingKeyRegistration
        }

        // The transition names its app whenever its keys are bounded. That is
        // an exact answer, so it wins over any ordering heuristic.
        if let boundContractId {
            guard let match = approved.first(where: {
                Self.decodeIdentifier($0.id) == boundContractId
            }) else {
                throw DashConnectPlatformError.noApprovedConnectionAwaitingKeyRegistration
            }
            return match
        }

        // Unbounded transitions are valid but anonymous. Recency is only safe
        // when there is nothing to confuse it with: with two apps approved,
        // guessing wrong derives the wrong keys and rejects a legitimate scan.
        guard approved.count == 1 else {
            throw DashConnectPlatformError.ambiguousKeyRegistrationConnection
        }
        return approved[0]
    }

    /// The `loginKeyResponse` contract id for the network this data source
    /// serves. Testnet is pinned; devnet reads the user-entered id from
    /// `DevnetConfiguration` and throws a normal, user-visible error when it
    /// is absent or not a 32-byte base58 identifier — never a crash on
    /// user input.
    private func loginKeyExchangeContractId() throws -> Data {
        switch supportedNetwork {
        case .testnet:
            return Self.testnetLoginKeyExchangeContractId
        case .devnet:
            guard let raw = DevnetConfiguration.dashConnectContractId,
                  let data = Data.identifier(fromBase58: raw),
                  data.count == 32 else {
                throw DashConnectPlatformError.devnetLoginContractNotConfigured
            }
            return data
        case .mainnet:
            // Unreachable through the app (mainnet gets the mock data
            // source); fail closed rather than publish against a guess.
            throw DashConnectPlatformError.loginContractUnavailable
        }
    }

    private func validateNetwork(_ network: DashConnectNetwork) throws {
        guard network == supportedNetwork else {
            throw DashConnectPlatformError.unsupportedRequestNetwork(
                expected: supportedNetwork,
                actual: network
            )
        }
    }

    private func authorize() async throws {
        do {
            try await authorizer.authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            throw DashConnectPlatformError.authorizationCancelled
        } catch {
            throw DashConnectPlatformError.authorizationFailed
        }
    }

    private func requireContext() async throws -> Context {
        let runtime = await MainActor.run {
            (
                wallet: SwiftDashSDKHost.shared.wallet,
                sdk: SwiftDashSDKHost.shared.sdk,
                modelContainer: SwiftDashSDKHost.shared.modelContainer,
                runningNetwork: SwiftDashSDKHost.shared.runningNetwork,
                identityId: DWCurrentUserIdentityInfo.shared.identityId,
                storedUsername: DWCurrentUserIdentityInfo.shared.username
            )
        }

        guard let wallet = runtime.wallet else {
            Self.logger.error("🔗 DASHCONNECT :: context missing: wallet")
            throw DashConnectPlatformError.noWallet
        }
        guard let sdk = runtime.sdk else {
            Self.logger.error("🔗 DASHCONNECT :: context missing: sdk")
            throw DashConnectPlatformError.noSDK
        }
        guard let modelContainer = runtime.modelContainer else {
            Self.logger.error("🔗 DASHCONNECT :: context missing: modelContainer")
            throw DashConnectPlatformError.noModelContainer
        }
        guard let network = runtime.runningNetwork else {
            Self.logger.error("🔗 DASHCONNECT :: context missing: runningNetwork")
            throw DashConnectPlatformError.noWallet
        }
        let expectedRuntimeNetwork: Network = supportedNetwork == .devnet ? .devnet : .testnet
        guard network == expectedRuntimeNetwork else {
            Self.logger.error("🔗 DASHCONNECT :: wallet is on \(String(describing: network), privacy: .public), DashConnect here expects \(String(describing: expectedRuntimeNetwork), privacy: .public)")
            throw DashConnectPlatformError.unsupportedRuntimeNetwork(network)
        }
        guard let identityId = runtime.identityId else {
            Self.logger.error("🔗 DASHCONNECT :: context missing: identityId — no registered DashPay identity on this wallet")
            throw DashConnectPlatformError.noIdentity
        }

        let identityIndex = try wallet.managedIdentity(identityId: identityId).getIdentityIndex() ?? 0

        return Context(
            wallet: wallet,
            sdk: sdk,
            modelContainer: modelContainer,
            network: network,
            identityId: identityId,
            identityIndex: identityIndex,
            storedUsername: runtime.storedUsername
        )
    }

    private func resolveAppMetadata(for request: DashKeyRequest, sdk: SDK) async -> DashConnectAppMetadata {
        let contractId = request.contractId.toBase58String()
        let fallback = DashConnectFallbackAppMetadata.resolve(
            contractId: contractId,
            unauthenticatedLabel: request.label
        )

        do {
            let contract = try await sdk.dataContractGet(id: contractId)
            let ownerId = contract["ownerId"] as? String ?? contract["$ownerId"] as? String

            if let ownerId,
               let usernames = try? await sdk.dpnsGetUsername(identityId: ownerId, limit: 1),
               let label = usernames.first?["label"] as? String,
               !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return DashConnectAppMetadata(name: label, url: fallback.url)
            }
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: app metadata resolution failed for \(contractId, privacy: .public): \(String(describing: error), privacy: .public)")
        }

        return fallback
    }

    private func resolveWalletUsername(context: Context) async -> String? {
        let identityId = context.identityId.toBase58String()

        if let usernames = try? await context.sdk.dpnsGetUsername(identityId: identityId, limit: 1),
           let label = usernames.first?["label"] as? String,
           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label
        }

        return context.storedUsername
    }

    /// Publishes the login-key response, replacing the existing document when
    /// this identity already has one for this app.
    private func writeLoginKeyResponseDocument(
        context: Context,
        appContractId: Data,
        propertiesJSON: String,
        signer: KeychainSigner
    ) async throws {
        func replace(documentId: Data) async throws {
            let signingKeyId = try selectDocumentSigningKeyId(
                wallet: context.wallet,
                identityId: context.identityId
            )
            _ = try await context.wallet.replaceDocument(
                ownerIdentityId: context.identityId,
                contractId: try loginKeyExchangeContractId(),
                documentType: Self.loginKeyExchangeDocumentType,
                documentId: documentId,
                propertiesJSON: propertiesJSON,
                signingKeyId: signingKeyId,
                signer: signer
            )
        }

        if let existingDocumentId = try await findLoginKeyResponseDocumentId(
            ownerIdentityId: context.identityId,
            appContractId: appContractId,
            sdk: context.sdk
        ) {
            try await replace(documentId: existingDocumentId)
            return
        }

        do {
            _ = try await context.wallet.createDocument(
                ownerIdentityId: context.identityId,
                contractId: try loginKeyExchangeContractId(),
                documentType: Self.loginKeyExchangeDocumentType,
                propertiesJSON: propertiesJSON,
                signer: signer
            )
        } catch {
            // The document can appear between the lookup and the create. Ask
            // once more: if it is there now, the create lost that race and a
            // replace is correct; if it is not, this failure is something else
            // and has to surface.
            guard let racedDocumentId = try? await findLoginKeyResponseDocumentId(
                ownerIdentityId: context.identityId,
                appContractId: appContractId,
                sdk: context.sdk
            ) else {
                throw error
            }

            try await replace(documentId: racedDocumentId)
        }
    }

    /// `nil` means no such document exists; a failed lookup throws. The
    /// create-or-replace branch is decided on this result, so "absent" and
    /// "could not tell" must not collapse into the same value.
    private func findLoginKeyResponseDocumentId(
        ownerIdentityId: Data,
        appContractId: Data,
        sdk: SDK
    ) async throws -> Data? {
        let whereClause = """
        [["$ownerId","==","\(ownerIdentityId.toBase58String())"],["contractId","==","\(appContractId.toBase58String())"]]
        """

        let response = try await sdk.documentList(
            dataContractId: try loginKeyExchangeContractId().toBase58String(),
            documentType: Self.loginKeyExchangeDocumentType,
            whereClause: whereClause,
            limit: 1
        )

        guard let documents = response["documents"] as? [[String: Any]] else {
            throw DashConnectPlatformError.existingDocumentLookupFailed
        }

        guard let id = documents.first?["$id"] as? String else { return nil }

        guard let identifier = Self.decodeIdentifier(id), identifier.count == 32 else {
            throw DashConnectPlatformError.existingDocumentLookupFailed
        }

        return identifier
    }

    private func selectDocumentSigningKeyId(
        wallet: ManagedPlatformWallet,
        identityId: Data
    ) throws -> UInt32 {
        let keys = try wallet.managedIdentity(identityId: identityId)
            .getPublicKeys()
            .map {
                DocumentSigningKeyCandidate(
                    keyId: UInt32(bitPattern: $0.keyId),
                    purpose: $0.purpose,
                    securityLevel: $0.securityLevel,
                    keyType: $0.keyType,
                    disabledAt: $0.disabledAt
                )
            }

        return try Self.selectDocumentSigningKeyId(from: keys)
    }

    static func selectDocumentSigningKeyId(
        from keys: [DocumentSigningKeyCandidate]
    ) throws -> UInt32 {
        let eligible = keys
            .filter {
                $0.disabledAt == nil
                    && $0.purpose == .authentication
                    && $0.keyType == .ecdsaSecp256k1
                    && ($0.securityLevel == .high || $0.securityLevel == .critical)
            }
            .sorted {
                let lhsPriority = signingPriority(for: $0.securityLevel)
                let rhsPriority = signingPriority(for: $1.securityLevel)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return $0.keyId < $1.keyId
            }

        guard let key = eligible.first else {
            throw DashConnectPlatformError.noAuthenticationKey
        }

        return key.keyId
    }

    private static func signingPriority(for securityLevel: SecurityLevel) -> Int {
        switch securityLevel {
        case .high:
            return 0
        case .critical:
            return 1
        case .master, .medium:
            return 2
        }
    }

    private static func makeManagedIdentityPubkey(
        from key: DashConnectKeyRegistrationKey
    ) -> ManagedPlatformWallet.IdentityPubkey {
        ManagedPlatformWallet.IdentityPubkey(
            keyId: key.keyId,
            keyType: key.keyType,
            purpose: key.purpose,
            securityLevel: key.securityLevel,
            pubkeyBytes: key.publicKeyData,
            contractBounds: key.contractBounds.map {
                switch $0 {
                case .singleContract(let id):
                    return .singleContract(id: id)
                case .singleContractDocumentType(let id, let documentTypeName):
                    return .singleContractDocumentType(id: id, documentTypeName: documentTypeName)
                }
            }
        )
    }

    /// A random 32-byte value is a valid secp256k1 scalar with overwhelming
    /// probability, so this exits on the first pass in practice. The bound is
    /// for the other failure mode: if `Secp256k1` is failing for a reason that
    /// has nothing to do with the candidate, an unbounded loop would hang
    /// `approveLogin` forever instead of surfacing an error.
    private static let ephemeralKeyGenerationAttempts = 8

    private static func generateEphemeralPrivateKey() throws -> Data {
        for _ in 0 ..< ephemeralKeyGenerationAttempts {
            var candidate = try randomBytes(count: 32)
            if (try? Secp256k1.compressedPublicKey(privateKey: candidate)) != nil {
                return candidate
            }
            zero(&candidate)
        }

        throw DashConnectPlatformError.ephemeralKeyGenerationFailed
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            zero(&bytes)
            throw DashConnectPlatformError.randomGenerationFailed(status)
        }
        let data = Data(bytes)
        zero(&bytes)
        return data
    }

    private static func decodeIdentifier(_ string: String) -> Data? {
        if let base58 = Data.identifier(fromBase58: string), base58.count == 32 {
            return base58
        }
        if let base64 = Data(base64Encoded: string), base64.count == 32 {
            return base64
        }
        return nil
    }

    private static func makeJSONObjectString(from properties: [String: AnyHashable]) throws -> String {
        let dictionary = Dictionary(uniqueKeysWithValues: properties.map { ($0.key, $0.value.base) })
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return string
    }

    static func zero(_ data: inout Data) {
        data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            baseAddress.initializeMemory(as: UInt8.self, repeating: 0, count: buffer.count)
        }
    }

    private static func zero(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            baseAddress.initializeMemory(as: UInt8.self, repeating: 0, count: buffer.count)
        }
    }
}
