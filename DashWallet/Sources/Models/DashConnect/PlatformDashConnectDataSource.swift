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

    /// The app's website, for an app the wallet knows.
    static func brandHost(contractId: String) -> String? {
        knownApps[contractId].flatMap { $0.url.isEmpty ? nil : $0.url }
    }

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
    case tokenPurchaseWrongIdentity
    case tokenPurchaseTokenIdMismatch
    case unsupportedStateTransition(String)
    case sessionKeyUnusable
    case identityKeysOutOfDate
    case grantOnAnotherIdentity
    case grantStoreUnavailable
    case approvalOutOfDate
    case grantNotRecorded
    case noFreeKeyId
    case otherIdentitiesNotChecked
    case walletChanged
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
        case .tokenPurchaseWrongIdentity:
            return "The scanned token purchase targets a different identity."
        case .tokenPurchaseTokenIdMismatch:
            return "The scanned token purchase names a token that does not belong to the contract and position it would buy from."
        case .identityKeysOutOfDate:
            return NSLocalizedString(
                "This wallet's copy of your identity is out of date, so it cannot confirm the app's key was turned off. Try again later.",
                comment: "DashConnect")
        case .grantOnAnotherIdentity:
            return NSLocalizedString(
                "This app has a key on another identity of this wallet. Switch to that identity to turn it off.",
                comment: "DashConnect")
        case .grantStoreUnavailable:
            return NSLocalizedString(
                "This wallet cannot record the key it would give the app, so the sign-in was not started.",
                comment: "DashConnect")
        case .grantNotRecorded:
            return NSLocalizedString(
                "The app's key was added to your identity, but this wallet could not record it. Turn the app off in Connections to remove the key.",
                comment: "DashConnect")
        case .otherIdentitiesNotChecked:
            return NSLocalizedString(
                "The app's keys on this identity are off, but this wallet could not check its other identities. Try again.",
                comment: "DashConnect")
        case .walletChanged:
            return NSLocalizedString("The active wallet or identity changed. Try again.", comment: "DashConnect")
        case .noFreeKeyId:
            return NSLocalizedString("This identity cannot take another key.", comment: "DashConnect")
        case .approvalOutOfDate:
            return NSLocalizedString(
                "The details of this sign-in changed while it was on screen. Check them and approve again.",
                comment: "DashConnect")
        case .sessionKeyUnusable:
            return NSLocalizedString(
                "This sign-in request can no longer be approved. Ask the app for a new code.",
                comment: "DashConnect")
        case .unsupportedStateTransition(let kindName):
            return String(
                format: NSLocalizedString(
                    "This wallet cannot approve the scanned request (%@).",
                    comment: "DashConnect: the placeholder is the kind of the scanned state transition"),
                kindName)
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
    /// Protocol 14 limits the scanned transition put on the key. Carried so
    /// the rebuilt registration grants exactly what was asked for.
    var totalBudget: UInt64? = nil
    var expiresAt: UInt64? = nil
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

/// A token direct purchase parsed out of a `dash-st:` transition: what the
/// approval sheet must show, and what `tokenPurchase(...)` is rebuilt from
/// after the user approves it.
struct DashConnectTokenPurchaseTransition: Equatable {
    /// The identity whose credits pay for the purchase.
    let ownerId: Data
    let dataContractId: Data
    let tokenId: Data
    let tokenContractPosition: UInt16
    let tokenCount: UInt64
    /// Credits the dApp asks the owner to agree to pay in total.
    let totalAgreedPrice: UInt64
}

/// One `dash-st:` payload reduced to app-level types, discriminated by the
/// kind of state transition it carried.
enum DashConnectParsedStateTransition: Equatable {
    case keyRegistration(DashConnectKeyRegistrationTransition)
    case tokenPurchase(DashConnectTokenPurchaseTransition)
}

protocol DashConnectStateTransitionParsing {
    func parse(_ transitionBytes: Data) throws -> DashConnectParsedStateTransition
}

struct PlatformWalletDashConnectStateTransitionParser: DashConnectStateTransitionParsing {
    private let parseTransition: (Data) throws -> ManagedPlatformWallet.ParsedStateTransition

    init(
        parseTransition: @escaping (Data) throws -> ManagedPlatformWallet.ParsedStateTransition = { bytes in
            try MainActor.assumeIsolated {
                guard let wallet = SwiftDashSDKHost.shared.wallet else {
                    throw DashConnectPlatformError.noWallet
                }
                return try wallet.parseStateTransition(bytes)
            }
        }
    ) {
        self.parseTransition = parseTransition
    }

    func parse(_ transitionBytes: Data) throws -> DashConnectParsedStateTransition {
        let transition = try parseTransition(transitionBytes)
        switch transition.kind {
        case .identityUpdate(let parsed):
            return .keyRegistration(
                DashConnectKeyRegistrationTransition(
                    identityId: parsed.identityId,
                    addPublicKeys: try parsed.addPublicKeys.map { key in
                        DashConnectKeyRegistrationKey(
                            keyId: key.keyId,
                            keyType: key.keyType,
                            purpose: key.purpose,
                            securityLevel: key.securityLevel,
                            publicKeyData: key.pubkeyBytes,
                            contractBounds: try key.contractBounds.map {
                                switch $0 {
                                case .singleContract(let id):
                                    return .singleContract(id: id)
                                case .singleContractDocumentType(let id, let documentTypeName):
                                    return .singleContractDocumentType(
                                        id: id,
                                        documentTypeName: documentTypeName
                                    )
                                case .contractGroup:
                                    // The wallet layer reports a contract-group bound since the
                                    // SDK's #4800, and the DPP-layer `ContractBounds` this maps
                                    // into has no case for it (dashpay/platform#4853). Dropping
                                    // the bound is not an option here: the value decides which
                                    // approved app a key registration belongs to, and it is also
                                    // rebuilt into the `IdentityPubkey` handed back to
                                    // `updateIdentity(...)`, so a silently weakened bound would
                                    // mean signing a transition the dApp did not ask for. A key
                                    // bound to a contract group is never one of the login keys
                                    // this flow derives, so refuse the transition instead.
                                    throw DashConnectPlatformError.keyRegistrationUnexpectedMutation
                                }
                            },
                            totalBudget: key.totalBudget,
                            expiresAt: key.expiresAt
                        )
                    },
                    disablePublicKeyIds: parsed.disablePublicKeyIds
                )
            )
        case .batch(let batch):
            // The SDK now describes every batch, where it used to refuse all
            // but a lone token direct purchase. The approval sheet and the
            // rebuild in `approveTokenPurchase` still cover exactly that one
            // case, so everything else is refused here: more than one row
            // would be signed without being shown, and an incomplete summary
            // (a note, group-action info) carries fields the rebuild drops.
            guard transition.complete,
                  batch.transitions.count == 1,
                  case .token(let row) = batch.transitions[0],
                  row.action == Self.tokenDirectPurchaseAction,
                  row.complete,
                  let tokenCount = row.tokenCount,
                  let totalAgreedPrice = row.amount else {
                throw DashConnectPlatformError.unsupportedStateTransition(transition.kindName)
            }
            return .tokenPurchase(
                DashConnectTokenPurchaseTransition(
                    ownerId: batch.ownerId,
                    dataContractId: row.dataContractId,
                    tokenId: row.tokenId,
                    tokenContractPosition: row.tokenContractPosition,
                    tokenCount: tokenCount,
                    totalAgreedPrice: totalAgreedPrice
                )
            )
        case .creditTransfer, .dataContractCreate, .dataContractUpdate, .other:
            throw DashConnectPlatformError.unsupportedStateTransition(transition.kindName)
        }
    }

    /// rs-dpp's action name for a token direct purchase, as the SDK reports
    /// it on a batch row.
    private static let tokenDirectPurchaseAction = "DirectPurchase"
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
        /// One pair for the whole operation: a context resolved again after
        /// a PIN prompt takes over the pair of the one it replaces.
        var stores: Stores
    }

    /// The connection rows and grant records of one wallet. A context carries
    /// the pair fixed to its own wallet: the stores follow the active wallet,
    /// and an operation that waits on the network or a PIN prompt must still
    /// write to the wallet whose identity it changed.
    private struct Stores {
        let walletIdHex: String
        let connections: any DashConnectStore
        let grants: any AppConnectResponseStore

        /// Names what the rows belong to: the wallet, and the network scope
        /// the connection store was fixed to, which tells two devnets of one
        /// wallet apart.
        var scope: String { "\(walletIdHex) \(connections.scopeKey ?? "")" }

        /// The rows as they are published: each names this scope.
        func published(_ rows: [DAppConnection]) -> [DAppConnection] {
            Self.rows(rows, scope: scope)
        }

        /// The rows as they are stored: without the scope a published row
        /// carries.
        static func stored(_ rows: [DAppConnection]) -> [DAppConnection] {
            Self.rows(rows, scope: nil)
        }

        private static func rows(_ rows: [DAppConnection], scope: String?) -> [DAppConnection] {
            rows.map { row in
                var row = row
                row.scope = scope
                return row
            }
        }
    }

    /// The scope of the rows `subject` holds. Read and written on the main
    /// actor together with every send, so the two cannot come apart.
    @MainActor
    private final class ShownRows {
        var scope: String?

        nonisolated init(scope: String?) {
            self.scope = scope
        }
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
    private let responseStore: any AppConnectResponseStore
    private let subject: CurrentValueSubject<[DAppConnection], Never>
    private let shownRows: ShownRows
    private let operationGate: DashConnectOperationGate
    private let activeWalletIdHex: () -> String?
    private var walletChangeObserver: AnyCancellable?
    private let authorizer: DWIdentityAuthorizer
    private let stateTransitionParser: any DashConnectStateTransitionParsing
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
        responseStore: (any AppConnectResponseStore)? = nil,
        activeWalletIdHex: @escaping () -> String? = { WalletEnvironment.activeWalletIdHex as String? },
        authorizer: DWIdentityAuthorizer = DWIdentityAuthorizer(),
        stateTransitionParser: any DashConnectStateTransitionParsing = PlatformWalletDashConnectStateTransitionParser(),
        notificationCenter: NotificationCenter = .default,
        operationGate: DashConnectOperationGate = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        assert(
            supportedNetwork == .testnet || supportedNetwork == .devnet,
            "DashConnect Platform publish runs on testnet and devnet only.")
        self.supportedNetwork = supportedNetwork
        self.store = store ?? UserDefaultsDashConnectStore(network: supportedNetwork)
        self.responseStore = responseStore ?? UserDefaultsAppConnectResponseStore(network: supportedNetwork)
        self.authorizer = authorizer
        self.stateTransitionParser = stateTransitionParser
        self.now = now
        self.activeWalletIdHex = activeWalletIdHex
        self.operationGate = operationGate
        let active = Self.pinnedStores(
            walletIdHex: activeWalletIdHex(), store: self.store, responseStore: self.responseStore)
        self.shownRows = ShownRows(scope: active?.scope)
        self.subject = CurrentValueSubject(active.map { $0.published($0.connections.load()) } ?? [])
        // The list is loaded once, and the active wallet can change while
        // this data source lives.
        self.walletChangeObserver = notificationCenter
            .publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.showActiveWalletRows() }
            }
    }

    var connections: AnyPublisher<[DAppConnection], Never> {
        subject.eraseToAnyPublisher()
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if DashConnectUri.isAppConnectUri(trimmed) {
            let uri: AppConnectUri
            do {
                uri = try DashConnectUri.parseAppConnectRequest(trimmed)
            } catch let error as AppConnectRequestError {
                throw AppConnect.Refusal(error)
            }
            try validateNetwork(uri.network)
            return .login(DashKeyRequest(
                appEphemeralPubKey: uri.request.appEphemeralPubKey,
                contractId: uri.request.appId,
                label: uri.request.label,
                network: uri.network,
                appConnect: uri))
        }

        if DashConnectUri.isKeyUri(trimmed) {
            let request = try DashConnectUri.parseKeyRequest(trimmed)
            try validateNetwork(request.network)
            return .login(request)
        }

        if DashConnectUri.isStUri(trimmed) {
            let request = try DashConnectUri.parseStRequest(trimmed)
            try validateNetwork(request.network)
            return .stateTransition(request)
        }

        throw DashConnectMockError.notDashConnectQrCode
    }

    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest {
        let fallback = ConnectionRequest(loginRequest: loginRequest)
        await showActiveWalletRows()

        let context: Context
        do {
            context = try await requireContext()
        } catch {
            let existingConnection = await shownRow(id: fallback.appContractId)
            return ConnectionRequest(
                loginRequest: loginRequest,
                appLabel: fallback.appLabel,
                appUrl: fallback.appUrl,
                walletUsername: nil,
                walletIdentityId: nil,
                existingConnection: existingConnection,
                unresolvedLoginReason: error.localizedDescription
            )
        }

        let existingConnection = rows(in: context.stores).first { $0.id == fallback.appContractId }

        // Which login this network gets is settled here, so the sheet can
        // show what the app is given. With the version unknown the request
        // says so, and the sheet offers nothing to approve. The lookup runs
        // alongside the two below.
        async let resolvedProtocolVersion = Self.networkProtocolVersion(sdk: context.sdk)
        let metadata = await resolveAppMetadata(for: loginRequest, sdk: context.sdk)
        let walletUsername = await resolveWalletUsername(context: context)
        let protocolVersion: UInt32?
        var unresolvedLoginReason: String?
        do {
            protocolVersion = try await resolvedProtocolVersion
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: protocol version unknown — \(error.localizedDescription, privacy: .public)")
            protocolVersion = nil
            unresolvedLoginReason = error.localizedDescription
        }
        var login = protocolVersion.map(AppConnect.login(protocolVersion:)) ?? .unresolved
        if let appConnect = loginRequest.appConnect, let protocolVersion {
            (login, unresolvedLoginReason) = await appConnectLogin(
                appConnect, protocolVersion: protocolVersion, context: context)
        }

        return ConnectionRequest(
            loginRequest: loginRequest,
            appLabel: metadata.name.isEmpty ? fallback.appLabel : metadata.name,
            appUrl: metadata.url,
            walletUsername: walletUsername,
            walletIdentityId: context.identityId.toBase58String(),
            existingConnection: existingConnection,
            login: login,
            unresolvedLoginReason: unresolvedLoginReason
        )
    }

    /// One approval, key registration or disconnect at a time for the active
    /// wallet, whichever data source it came through. The turn is for the
    /// wallet that was active when it was asked for: if another one is
    /// active when it comes, the operation does not start.
    private func gated<T>(_ operation: () async throws -> T) async throws -> T {
        let walletIdHex = activeWalletIdHex() ?? ""
        return try await operationGate.run(
            for: walletIdHex,
            onWait: { Self.logger.info("🔗 DASHCONNECT :: waiting for another DashConnect operation to finish") }
        ) {
            guard (activeWalletIdHex() ?? "") == walletIdHex else {
                throw DashConnectPlatformError.walletChanged
            }
            return try await operation()
        }
    }

    /// The login a v2 request gets: its grant plan once the request is fresh,
    /// meant for this identity, and every contract and group it names belongs
    /// to the app's owner; otherwise why it is refused. Unresolved, with the
    /// reason, when the network could not be asked.
    private func appConnectLogin(
        _ uri: AppConnectUri,
        protocolVersion: UInt32,
        context: Context
    ) async -> (AppConnect.Login, String?) {
        guard AppConnect.isAvailable(protocolVersion: protocolVersion) else {
            return (.refused(AppConnect.Refusal(.unsupported, NSLocalizedString(
                "This network does not support this kind of sign-in yet.",
                comment: "DashConnect App Connect v2"))), nil)
        }
        do {
            var plan = try AppConnect.grantPlan(for: uri, now: now())
            plan.brandHost = DashConnectFallbackAppMetadata.brandHost(contractId: plan.appId.toBase58String())
            if let refusal = AppConnect.callbackRefusal(callbackHost: plan.callbackHost, brandHost: plan.brandHost) {
                return (.refused(refusal), nil)
            }
            if let hint = plan.identityHint, hint != context.identityId {
                return (.refused(AppConnect.Refusal(.invalid, NSLocalizedString(
                    "This sign-in is for another identity. Switch to it in this wallet and ask the app again.",
                    comment: "DashConnect App Connect v2"))), nil)
            }
            if let refusal = try await appConnectOwnershipRefusal(plan, sdk: context.sdk) {
                return (.refused(refusal), nil)
            }
            return (.appConnect(plan), nil)
        } catch let refusal as AppConnect.Refusal {
            return (.refused(refusal), nil)
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: App Connect request not checked — \(error.localizedDescription, privacy: .public)")
            return (.unresolved, error.localizedDescription)
        }
    }

    /// Reads the owners wallet rule 3 compares from Platform. A group the
    /// network proves absent counts as not the app's; any other failure to
    /// read throws, so the sheet offers to try again.
    private func appConnectOwnershipRefusal(_ plan: AppConnect.GrantPlan, sdk: SDK) async throws -> AppConnect.Refusal? {
        func ownerId(of contract: [String: Any]) -> Data? {
            (contract["ownerId"] as? String ?? contract["$ownerId"] as? String).flatMap(Self.decodeIdentifier)
        }
        let app = try await sdk.dataContractGet(id: plan.appId.toBase58String())
        guard let appOwnerId = ownerId(of: app) else {
            return AppConnect.Refusal(.invalid, NSLocalizedString(
                "The app's contract has no readable owner.", comment: "DashConnect App Connect v2"))
        }
        var groupOwners: [Data: Data] = [:]
        var contractOwners: [Data: Data] = [plan.appId: appOwnerId]
        for grant in plan.auth {
            let id = grant.binding.id
            switch grant.binding.kind {
            case .contractGroup:
                guard groupOwners[id] == nil else { continue }
                do {
                    let info = try await sdk.getContractGroupInfo(contractGroupId: id.toBase58String())
                    groupOwners[id] = (info["ownerId"] as? String).flatMap(Self.decodeIdentifier)
                } catch SDKError.notFound {
                    continue
                }
            case .singleContract, .documentType:
                let name = grant.binding.documentTypeName ?? ""
                guard contractOwners[id] == nil,
                      !AppConnect.allowedForeignDocumentTypes.contains("\(id.toBase58String())/\(name)") else { continue }
                contractOwners[id] = ownerId(of: try await sdk.dataContractGet(id: id.toBase58String()))
            }
        }
        let config = app["config"] as? [String: Any] ?? [:]
        var boundedKeyPurposes: Set<KeyPurpose> = []
        if config["requiresIdentityEncryptionBoundedKey"].map({ !($0 is NSNull) }) == true {
            boundedKeyPurposes.insert(.encryption)
        }
        if config["requiresIdentityDecryptionBoundedKey"].map({ !($0 is NSNull) }) == true {
            boundedKeyPurposes.insert(.decryption)
        }
        return AppConnect.ownershipRefusal(
            for: plan,
            appOwnerId: appOwnerId,
            groupOwners: groupOwners,
            contractOwners: contractOwners,
            appBoundedKeyPurposes: boundedKeyPurposes)
    }

    func approveLogin(_ request: DashKeyRequest, consent: ConnectionRequest) async throws -> DAppConnection {
        try await gated { try await approveLoginInTurn(request, consent: consent) }
    }

    private func approveLoginInTurn(
        _ request: DashKeyRequest,
        consent: ConnectionRequest
    ) async throws -> DAppConnection {
        Self.logger.info("🔗 DASHCONNECT :: approveLogin started")
        try validateNetwork(request.network)
        await showActiveWalletRows()
        guard consent.appContractId == request.contractId.toBase58String(), consent.login.isApprovable else {
            throw DashConnectPlatformError.approvalOutOfDate
        }

        var context: Context
        do {
            context = try await requireContext()
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: no context — \(error.localizedDescription, privacy: .public)")
            throw error
        }
        // Which login this network can answer is decided before the PIN
        // prompt: from protocol version 14 the response goes to the App
        // Connect system contract and the wallet registers the key itself;
        // below it that contract does not exist and the two-QR flow runs.
        // A pinned SDK reports its pin (testnet is pinned to 13 in
        // `SwiftDashSDKHost.platformVersion(for:)`), so testnet stays on the
        // two-QR flow until that pin moves.
        let protocolVersion: UInt32
        do {
            protocolVersion = try await Self.networkProtocolVersion(sdk: context.sdk)
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: protocol version unknown — \(error.localizedDescription, privacy: .public)")
            throw error
        }
        // The sheet showed the login `makeConnectionRequest` resolved, with
        // its terms for the one-QR login. If the network now gets the other
        // one, what was approved is not what would run. Either login acts
        // for the identity that was on the sheet: it has to be the active
        // one here, and again after the PIN prompt.
        let login = AppConnect.login(protocolVersion: protocolVersion)
        // A v2 request was approved with the plan the sheet showed. It has
        // to be the plan for this request, and the network has to still take
        // App Connect.
        let approvedLogin: Bool
        if let appConnect = request.appConnect {
            guard let plan = consent.login.grantPlan else {
                throw DashConnectPlatformError.approvalOutOfDate
            }
            let requestHash = try KeyExchangeCrypto.hash160(appConnect.request.appEphemeralPubKey)
            approvedLogin = AppConnect.isAvailable(protocolVersion: protocolVersion)
                && plan.appEphemeralPubKeyHash == requestHash
        } else {
            approvedLogin = consent.login == login
        }
        guard approvedLogin,
              consent.walletIdentityId == context.identityId.toBase58String() else {
            Self.logger.error("🔗 DASHCONNECT :: the approved sign-in no longer matches the network or the identity")
            throw DashConnectPlatformError.approvalOutOfDate
        }
        do {
            try await authorize()
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: authorization failed — \(error.localizedDescription, privacy: .public)")
            throw error
        }
        // The PIN prompt can outlast a wallet or identity switch: sign with
        // what is active now, and only if it is still the identity that was
        // shown.
        do {
            context = try await contextAfterAuthorization(matching: context)
        } catch DashConnectPlatformError.walletChanged {
            throw DashConnectPlatformError.approvalOutOfDate
        }
        if let appConnect = request.appConnect, let plan = consent.login.grantPlan {
            Self.logger.info("🔗 DASHCONNECT :: authorized; App Connect request v2")
            return try await approveAppConnectV2Login(appConnect, plan: plan, consent: consent, context: context)
        }
        if let terms = login.sessionKeyTerms {
            Self.logger.info("🔗 DASHCONNECT :: authorized; protocol \(protocolVersion, privacy: .public), one-QR login")
            return try await approveAppConnectLogin(request, terms: terms, context: context)
        }
        Self.logger.info("🔗 DASHCONNECT :: authorized; deriving login key")

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
        // Step markers: everything between `approveLogin started` and the
        // finish was silent, so a stall anywhere in derive → write → preview
        // was indistinguishable from a stall in any other step.
        Self.logger.info("🔗 DASHCONNECT :: writing loginKeyResponse document")
        try await writeLoginKeyResponseDocument(
            context: context,
            appContractId: request.contractId,
            propertiesJSON: propertiesJSON,
            signer: signer
        )
        Self.logger.info("🔗 DASHCONNECT :: loginKeyResponse document written")

        let preview = await makeConnectionRequest(from: request)
        Self.logger.info("🔗 DASHCONNECT :: connection preview resolved")
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

        await updateRows(in: context.stores) { rows in
            rows.filter { $0.id != connection.id } + [connection]
        }
        return connection
    }

    /// `SDK.refreshProtocolVersion()` is a synchronous FFI call that makes a
    /// proven network query. It runs on a plain dispatch queue so it does not
    /// hold a cooperative-pool thread for a DAPI round trip.
    private static func networkProtocolVersion(sdk: SDK) async throws -> UInt32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try sdk.refreshProtocolVersion() })
            }
        }
    }

    /// The one-QR login: derive the request's session key, register it on the
    /// identity with its bounds and limits, and only then publish the
    /// encrypted key, so the app finds a live key on its first check.
    ///
    /// The grant and the connection row are recorded as soon as the key is
    /// known to be on the identity, before the publish: whatever happens to
    /// the publish, the key stays visible in Connections and can be disabled.
    ///
    /// Approving the same QR again finds the key registered and does not
    /// register it twice; if the response is already recorded as published it
    /// does nothing more.
    private func approveAppConnectLogin(
        _ request: DashKeyRequest,
        terms: AppConnect.SessionKeyTerms,
        context: Context
    ) async throws -> DAppConnection {
        guard let responseContractId = Self.decodeIdentifier(AppConnect.contractId) else {
            throw DashConnectPlatformError.loginContractUnavailable
        }
        let stores = context.stores
        guard stores.grants.canPersist else {
            throw DashConnectPlatformError.grantStoreUnavailable
        }

        let requestId = AppConnect.requestId(appEphemeralPubKey: request.appEphemeralPubKey)
        // `deriveConnectKey` is main-actor isolated in the SDK. Only the two
        // buffers leave the closure, so the private key below is the sole
        // owner of its storage and the deferred wipe reaches the real bytes.
        var (sessionPublicKey, sessionPrivateKey) = try await MainActor.run {
            let key = try context.wallet.deriveConnectKey(
                subFeature: .sessionAuthentication,
                identityId: context.identityId,
                leaf: requestId,
                network: context.network
            )
            return (key.publicKeyData, key.privateKeyData)
        }
        defer { Self.zero(&sessionPrivateKey) }
        let sessionKeyHash160 = try KeyExchangeCrypto.hash160(sessionPublicKey)

        var walletEphemeralPrivateKey = try Self.generateEphemeralPrivateKey()
        let sealed = try AppConnect.seal(
            sessionPrivateKey,
            appEphemeralPubKey: request.appEphemeralPubKey,
            walletEphemeralPrivateKey: &walletEphemeralPrivateKey
        )

        let identityId = context.identityId.toBase58String()
        let appContractId = request.contractId.toBase58String()
        let requestHash = sealed.appEphemeralPubKeyHash.toHexString()
        let signer = KeychainSigner(modelContainer: context.modelContainer)
        let currentPublicKeys = try await refreshedIdentityPublicKeys(context: context)
        func isGrantForRequest(_ grant: AppConnectGrant) -> Bool {
            grant.identityId == identityId && grant.appContractId == appContractId
                && grant.values.appEphemeralPubKeyHash == requestHash
        }

        // Read only for a key that is already on the identity. If the store
        // cannot be read, such a key needs a grant record instead.
        var bindings: [AppConnect.KeyBinding] = []
        var grantedKeyIds: Set<UInt32> = []
        if currentPublicKeys.contains(where: { $0.keyType == .ecdsaHash160 && $0.data == sessionKeyHash160 }) {
            bindings = (try? Self.storedKeyBindings(
                identityId: identityId, modelContainer: context.modelContainer)) ?? []
            grantedKeyIds = Set(stores.grants.load().filter(isGrantForRequest).map(\.sessionKeyId))
        }

        let sessionKeyId: UInt32
        var totalBudget: UInt64?
        var expiresAt: UInt64?
        switch AppConnect.sessionKeyState(
            publicKeyHash160: sessionKeyHash160,
            currentIdentityPublicKeys: currentPublicKeys,
            appContractId: request.contractId,
            bindings: bindings,
            grantedKeyIds: grantedKeyIds,
            terms: terms,
            now: now()
        ) {
        case .unusable:
            throw DashConnectPlatformError.sessionKeyUnusable
        case .usable(let keyId):
            Self.logger.info("🔗 DASHCONNECT :: session key already registered")
            sessionKeyId = keyId
            let registered = currentPublicKeys.first { UInt32(bitPattern: $0.keyId) == keyId }
            totalBudget = registered?.totalBudget
            expiresAt = registered?.expiresAt.map { UInt64(max(0, $0)) }
        case .absent:
            guard let keyId = AppConnect.nextKeyId(currentIdentityPublicKeys: currentPublicKeys) else {
                throw DashConnectPlatformError.noFreeKeyId
            }
            let budget = terms.budgetCredits
            let expiry = terms.expiresAt(from: now())
            let key = AppConnect.sessionIdentityPubkey(
                keyId: keyId,
                publicKeyHash160: sessionKeyHash160,
                appContractId: request.contractId,
                totalBudget: budget,
                expiresAt: expiry
            )
            Self.logger.info("🔗 DASHCONNECT :: registering session key")
            try await signer.withAdditionalSigningKeys([
                (publicKey: sessionKeyHash160, privateKey: sessionPrivateKey),
            ]) {
                try await context.wallet.updateIdentity(
                    identityId: context.identityId,
                    addPublicKeys: [key],
                    signer: signer
                )
            }
            Self.logger.info("🔗 DASHCONNECT :: session key registered")
            sessionKeyId = keyId
            totalBudget = budget
            expiresAt = expiry
        }

        // From here the app-side key exists on the identity. Record it, and
        // show the connection, before anything else can fail. A grant already
        // recorded for this request keeps its values: if an earlier publish
        // landed without confirming, those are the ones on Platform.
        let grant = updateGrants(in: stores) { grants -> AppConnectGrant in
            if let existing = grants.first(where: { isGrantForRequest($0) && $0.sessionKeyId == sessionKeyId }) {
                return existing
            }
            let new = AppConnectGrant(
                identityId: identityId,
                appContractId: appContractId,
                documentId: nil,
                values: AppConnect.ResponseValues(sealed),
                sessionKeyId: sessionKeyId,
                totalBudget: totalBudget,
                expiresAt: expiresAt,
                publishedAt: now()
            )
            grants.append(new)
            return new
        }

        let preview = await makeConnectionRequest(from: request)
        let connection = Self.makeConnection(
            preview: preview, status: .active, updatedAt: now(), loginKind: .oneQR)
        await updateRows(in: stores) { rows in
            rows.filter { $0.id != connection.id } + [connection]
        }

        try await publishAppConnectResponse(
            grant: grant,
            appEphemeralPubKeyHash: sealed.appEphemeralPubKeyHash,
            responseContractId: responseContractId,
            context: context,
            signer: signer
        )
        return connection
    }

    /// Publishes the response a grant records, once its keys are on the
    /// identity and the grant and its connection row are recorded. Shared by
    /// the one-QR login and App Connect request v2.
    private func publishAppConnectResponse(
        grant: AppConnectGrant,
        appEphemeralPubKeyHash: Data,
        responseContractId: Data,
        context: Context,
        signer: KeychainSigner
    ) async throws {
        let stores = context.stores
        let identityId = grant.identityId
        let appContractId = grant.appContractId
        let requestHash = grant.values.appEphemeralPubKeyHash

        // The store was writable when the login started. If the record did
        // not land all the same, a response published now could not be found
        // again. The key is live, so the row above stays: a disconnect finds
        // the key by its contract bound.
        guard stores.grants.load().contains(where: { $0.key == grant.key }) else {
            Self.logger.error("🔗 DASHCONNECT :: the session key was registered but its record could not be saved")
            throw DashConnectPlatformError.grantNotRecorded
        }

        // A response deleted by a later login to this app is published again
        // when its own request comes back.
        guard !grant.hasDeletableResponse else {
            Self.logger.info("🔗 DASHCONNECT :: response already published for this request")
            return
        }

        // Besides this app's earlier responses, this takes whatever an earlier
        // disconnect of any app left behind for this identity: its row is
        // gone, so a login is the only moment left to finish that cleanup.
        await deleteAppConnectResponses(
            where: {
                guard $0.identityId == identityId else { return false }
                return $0.keyDisabled == true
                    || ($0.appContractId == appContractId && $0.values.appEphemeralPubKeyHash != requestHash)
            },
            responseContractId: responseContractId,
            context: context,
            signer: signer
        )

        // Recorded before the publish is submitted: a response this record
        // had as deleted may be back on Platform after a publish that fails
        // to confirm, and a disconnect must then look for it.
        updateGrants(in: stores) { grants in
            guard let index = grants.firstIndex(where: { $0.key == grant.key }) else { return }
            grants[index].markPublishStarted()
        }

        Self.logger.info("🔗 DASHCONNECT :: publishing loginKeyResponse")
        let documentId: Data
        var publishedValues = grant.values
        do {
            (documentId, _) = try await context.wallet.createDocument(
                ownerIdentityId: context.identityId,
                contractId: responseContractId,
                documentType: AppConnect.documentType,
                propertiesJSON: try grant.values.propertiesJSON(),
                signer: signer
            )
            Self.logger.info("🔗 DASHCONNECT :: loginKeyResponse published")
        } catch {
            // A publish can land without confirming, and the response is
            // unique per request and identity, so the retry is then refused.
            // If the response is there, this login is complete; if it is not,
            // or that cannot be told, the failure stands.
            guard let published = try? await findAppConnectResponse(
                ownerIdentityId: context.identityId,
                appEphemeralPubKeyHash: appEphemeralPubKeyHash,
                responseContractId: responseContractId,
                sdk: context.sdk
            ) else {
                throw error
            }
            Self.logger.info("🔗 DASHCONNECT :: loginKeyResponse was already published")
            documentId = published.documentId
            publishedValues = published.values
        }

        updateGrants(in: stores) { grants in
            guard let index = grants.firstIndex(where: { $0.key == grant.key }) else { return }
            grants[index].documentId = documentId.toBase58String()
            grants[index].values = publishedValues
        }
    }

    /// App Connect request v2 (Yappr `docs/APP_CONNECT_PROFILE.md`): one key
    /// per auth binding, the identity's encryption key for the app, and the
    /// previous grant on the same connection disabled, all in one
    /// MASTER-signed identity update; then the grant and the connection row
    /// are recorded and the sealed response is published, as for the one-QR
    /// login.
    ///
    /// Approving the same request again finds its keys registered and
    /// recorded, registers nothing and publishes the recorded response if it
    /// is not on Platform yet.
    private func approveAppConnectV2Login(
        _ uri: AppConnectUri,
        plan: AppConnect.GrantPlan,
        consent: ConnectionRequest,
        context: Context
    ) async throws -> DAppConnection {
        guard let responseContractId = Self.decodeIdentifier(AppConnect.contractId) else {
            throw DashConnectPlatformError.loginContractUnavailable
        }
        let stores = context.stores
        guard stores.grants.canPersist else {
            throw DashConnectPlatformError.grantStoreUnavailable
        }
        // The app stops looking for an answer ten minutes after it asked.
        guard uri.request.age(now: now()) == .fresh else {
            throw AppConnect.Refusal(.stale, NSLocalizedString(
                "This sign-in request has expired. Ask the app for a new one.",
                comment: "DashConnect App Connect v2"))
        }
        let request = uri.request
        let identityId = context.identityId.toBase58String()
        let appId = plan.appId.toBase58String()
        let requestHash = plan.appEphemeralPubKeyHash.toHexString()
        let connectionId = plan.connectionId?.toHexString()
        func isGrantForRequest(_ grant: AppConnectGrant) -> Bool {
            grant.identityId == identityId && grant.appContractId == appId
                && grant.values.appEphemeralPubKeyHash == requestHash
        }

        // `deriveConnectKey` is main-actor isolated in the SDK. Only the two
        // buffers leave the closure, so the arrays below own the private keys
        // and the deferred wipe reaches the real bytes.
        var authKeys: [(publicKeyHash160: Data, privateKey: Data)] = []
        var encryptionKeys: [(publicKey: Data, privateKey: Data)] = []
        defer {
            for index in authKeys.indices { Self.zero(&authKeys[index].privateKey) }
            for index in encryptionKeys.indices { Self.zero(&encryptionKeys[index].privateKey) }
        }
        for grant in plan.auth {
            let leaf = AppConnect.authKeyLeaf(
                appEphemeralPubKey: request.appEphemeralPubKey, bindingIndex: grant.bindingIndex)
            let (publicKey, privateKey) = try await MainActor.run {
                let key = try context.wallet.deriveConnectKey(
                    subFeature: .sessionAuthentication,
                    identityId: context.identityId,
                    leaf: leaf,
                    network: context.network
                )
                return (key.publicKeyData, key.privateKeyData)
            }
            authKeys.append((try KeyExchangeCrypto.hash160(publicKey), privateKey))
        }
        for grant in plan.encryption {
            encryptionKeys.append(try await MainActor.run {
                let key = try context.wallet.deriveConnectKey(
                    subFeature: .appEncryption,
                    identityId: context.identityId,
                    leaf: grant.binding.contractId,
                    purpose: grant.connectPurpose,
                    network: context.network
                )
                return (key.publicKeyData, key.privateKeyData)
            })
        }

        let signer = KeychainSigner(modelContainer: context.modelContainer)
        let currentPublicKeys = try await refreshedIdentityPublicKeys(context: context)
        let bindings = try Self.storedKeyBindings(identityId: identityId, modelContainer: context.modelContainer)

        // An auth key already on the identity at a binding's derived payload
        // is sent again only as this request answered before: bound as the
        // binding asks, within the plan's terms, and named by the grant
        // recorded for this request. Anything else fails closed: a request
        // repeating another's ephemeral key derives the same payload, and a
        // key whose record is lost cannot be shown to be this request's.
        // Platform never re-adds a key, so the app then has to ask again.
        var authKeyIds: [UInt32?] = try zip(plan.auth, authKeys).map { grant, key in
            guard let existing = currentPublicKeys.first(where: {
                $0.keyType == .ecdsaHash160 && $0.data == key.publicKeyHash160
            }) else { return nil }
            let keyId = UInt32(bitPattern: existing.keyId)
            guard AppConnect.canResendAuthKey(
                existing, for: grant,
                binding: bindings.first { $0.keyId == keyId && $0.data == existing.data },
                now: now()
            ) else {
                throw DashConnectPlatformError.sessionKeyUnusable
            }
            return keyId
        }
        // The grant recorded for this request must name exactly these keys:
        // its response carries them. A key recorded for another app or
        // request is that one's, and must not be taken over.
        let reused = Set(authKeyIds.compactMap { $0 })
        if !reused.isEmpty {
            let grants = stores.grants.load().filter { $0.identityId == identityId }
            guard let recorded = grants.first(where: isGrantForRequest),
                  Set(recorded.keyIds) == reused, !authKeyIds.contains(nil) else {
                throw DashConnectPlatformError.sessionKeyUnusable
            }
            if grants.contains(where: { !isGrantForRequest($0) && !reused.isDisjoint(with: $0.keyIds) }) {
                throw DashConnectPlatformError.sessionKeyUnusable
            }
        }

        // Wallet rule 7: re-send the identity's key for the app when this
        // wallet made it, register it when there is none, leave it out when
        // another wallet made it.
        var encryptionSlots: [(keyIndex: Int, keyId: UInt32?)] = []
        for (index, grant) in plan.encryption.enumerated() {
            switch AppConnect.encryptionKeyState(
                derivedPublicKey: encryptionKeys[index].publicKey,
                purpose: grant.keyPurpose,
                contractId: grant.binding.contractId,
                currentIdentityPublicKeys: currentPublicKeys,
                bindings: bindings
            ) {
            case .current(let keyId):
                encryptionSlots.append((index, keyId))
            case .absent:
                encryptionSlots.append((index, nil))
            case .notThisWallets:
                Self.logger.info("🔗 DASHCONNECT :: the app's encryption key on this identity is not this wallet's; slot left out")
            }
        }

        // Wallet rule 8: this connection's previous grant goes in the same
        // update. A key of it the fetched list lacks means the list is
        // behind, and it could not be shown to be off.
        func isSuperseded(_ grant: AppConnectGrant) -> Bool {
            connectionId != nil && grant.identityId == identityId && grant.appContractId == appId
                && grant.connectionId == connectionId && !isGrantForRequest(grant)
        }
        let superseded = stores.grants.load().filter(isSuperseded)
        guard AppConnect.sessionKeyIdsMissing(from: currentPublicKeys, for: superseded).isEmpty else {
            throw DashConnectPlatformError.identityKeysOutOfDate
        }
        let disable = Array(AppConnect.supersededKeyIds(
            grants: superseded,
            identityId: identityId,
            appId: appId,
            connectionId: connectionId,
            keeping: reused,
            currentIdentityPublicKeys: currentPublicKeys
        ).prefix(AppConnect.maxKeysDisabledPerUpdate))
        // The grants whose every key is off once the update lands.
        let liveAfterUpdate = Set(currentPublicKeys.filter(AppConnect.isLiveGrantedKey)
            .map { UInt32(bitPattern: $0.keyId) }).subtracting(disable)
        let retiredGrantKeys = Set(superseded.filter { !$0.keyIds.contains(where: liveAfterUpdate.contains) }.map(\.key))

        guard var nextKeyId = AppConnect.nextKeyId(currentIdentityPublicKeys: currentPublicKeys) else {
            throw DashConnectPlatformError.noFreeKeyId
        }
        var add: [ManagedPlatformWallet.IdentityPubkey] = []
        var signingKeys: [(publicKey: Data, privateKey: Data)] = []
        for (index, grant) in plan.auth.enumerated() where authKeyIds[index] == nil {
            add.append(AppConnect.authIdentityPubkey(
                grant, keyId: nextKeyId, publicKeyHash160: authKeys[index].publicKeyHash160))
            signingKeys.append((authKeys[index].publicKeyHash160, authKeys[index].privateKey))
            authKeyIds[index] = nextKeyId
            nextKeyId += 1
        }
        for slot in encryptionSlots.indices where encryptionSlots[slot].keyId == nil {
            let keyIndex = encryptionSlots[slot].keyIndex
            add.append(AppConnect.encryptionIdentityPubkey(
                plan.encryption[keyIndex], keyId: nextKeyId, publicKey: encryptionKeys[keyIndex].publicKey))
            signingKeys.append((encryptionKeys[keyIndex].publicKey, encryptionKeys[keyIndex].privateKey))
            encryptionSlots[slot].keyId = nextKeyId
            nextKeyId += 1
        }
        defer { for index in signingKeys.indices { Self.zero(&signingKeys[index].privateKey) } }

        if !add.isEmpty || !disable.isEmpty {
            Self.logger.info(
                "🔗 DASHCONNECT :: registering \(add.count, privacy: .public) key(s), disabling \(disable.count, privacy: .public)")
            do {
                try await signer.withAdditionalSigningKeys(signingKeys) {
                    try await context.wallet.updateIdentity(
                        identityId: context.identityId,
                        addPublicKeys: add,
                        disablePublicKeyIds: disable,
                        signer: signer
                    )
                }
            } catch {
                // An update can land without confirming, and the node asked
                // next may not have it yet. If every new key shows up and
                // every replaced key is off, it went through.
                func landed(_ keys: [ManagedIdentity.IdentityPublicKeyInfo]) -> Bool {
                    add.allSatisfy { new in keys.contains {
                        UInt32(bitPattern: $0.keyId) == new.keyId && $0.data == new.pubkeyBytes && $0.disabledAt == nil
                    } } && disable.allSatisfy { id in keys.contains {
                        UInt32(bitPattern: $0.keyId) == id && $0.disabledAt != nil
                    } }
                }
                var confirmed = false
                for attempt in 0 ..< 3 where !confirmed {
                    if attempt > 0 { try? await Task.sleep(nanoseconds: 3_000_000_000) }
                    if let refreshed = try? await refreshedIdentityPublicKeys(context: context) {
                        confirmed = landed(refreshed)
                    }
                }
                guard confirmed else { throw error }
                Self.logger.info("🔗 DASHCONNECT :: the identity update landed without confirming")
            }
            Self.logger.info("🔗 DASHCONNECT :: identity updated")
        }

        // Slots: the auth keys in request order, then the encryption keys
        // that are sent.
        var slots = authKeys.map(\.privateKey) + encryptionSlots.map { encryptionKeys[$0.keyIndex].privateKey }
        defer { for index in slots.indices { Self.zero(&slots[index]) } }
        var walletEphemeralPrivateKey = try Self.generateEphemeralPrivateKey()
        defer { Self.zero(&walletEphemeralPrivateKey) }
        let values = AppConnect.ResponseValues(
            appEphemeralPubKeyHash: requestHash,
            walletEphemeralPubKey: try Secp256k1.compressedPublicKey(privateKey: walletEphemeralPrivateKey).toHexString(),
            encryptedPayload: try KeyExchangeCrypto.encryptAppConnectSlots(
                slots,
                walletEphemeralPriv: walletEphemeralPrivateKey,
                appEphemeralPub: request.appEphemeralPubKey,
                ownerId: context.identityId
            ).toHexString()
        )

        // From here the keys are on the identity. Record them, and show the
        // connection, before anything else can fail. The grants this one
        // replaces are done: their keys are off. A grant already recorded
        // for this request keeps its values: if an earlier publish landed
        // without confirming, those are the ones on Platform.
        let grantedKeyIds = authKeyIds.compactMap { $0 }
        let primary = plan.auth[0]
        let grant = updateGrants(in: stores) { grants -> AppConnectGrant in
            AppConnect.markKeysDisabled(in: &grants) { retiredGrantKeys.contains($0.key) }
            if let existing = grants.first(where: { isGrantForRequest($0) && $0.sessionKeyId == grantedKeyIds[0] }) {
                return existing
            }
            let new = AppConnectGrant(
                identityId: identityId,
                appContractId: appId,
                documentId: nil,
                values: values,
                sessionKeyId: grantedKeyIds[0],
                totalBudget: primary.totalBudget,
                expiresAt: primary.expiresAt,
                publishedAt: now(),
                additionalKeyIds: Array(grantedKeyIds.dropFirst()),
                connectionId: connectionId
            )
            grants.append(new)
            return new
        }

        let connection = Self.makeConnection(
            preview: consent, status: .active, updatedAt: now(), loginKind: .oneQR)
        await updateRows(in: stores) { rows in
            rows.filter { $0.id != connection.id } + [connection]
        }

        try await publishAppConnectResponse(
            grant: grant,
            appEphemeralPubKeyHash: plan.appEphemeralPubKeyHash,
            responseContractId: responseContractId,
            context: context,
            signer: signer
        )
        return connection
    }

    /// This identity's response to one request, with the values it has on
    /// Platform, or `nil` when there is none; a failed lookup or a response
    /// that cannot be read throws.
    private func findAppConnectResponse(
        ownerIdentityId: Data,
        appEphemeralPubKeyHash: Data,
        responseContractId: Data,
        sdk: SDK
    ) async throws -> (documentId: Data, values: AppConnect.ResponseValues)? {
        let response = try await sdk.documentList(
            dataContractId: responseContractId.toBase58String(),
            documentType: AppConnect.documentType,
            whereClause: AppConnect.responseLookupWhereClause(
                appEphemeralPubKeyHash: appEphemeralPubKeyHash,
                ownerIdentityId: ownerIdentityId
            ),
            limit: 1
        )
        guard let documents = response["documents"] as? [[String: Any]] else {
            throw DashConnectPlatformError.existingDocumentLookupFailed
        }
        guard let document = documents.first else { return nil }
        guard let id = document["$id"] as? String,
              let identifier = Self.decodeIdentifier(id), identifier.count == 32,
              let values = AppConnect.responseValues(
                  fromDocument: document, appEphemeralPubKeyHash: appEphemeralPubKeyHash) else {
            throw DashConnectPlatformError.existingDocumentLookupFailed
        }
        return (identifier, values)
    }

    /// Reads, changes and writes the grant records in one step, from the
    /// store each time. Every caller runs inside `gated`, so no other
    /// operation of this wallet writes them in between.
    @discardableResult
    private func updateGrants<T>(in stores: Stores, _ change: (inout [AppConnectGrant]) -> T) -> T {
        var grants = stores.grants.load()
        let result = change(&grants)
        stores.grants.save(grants)
        return result
    }

    /// Deletes, by their original values, the responses of the matching
    /// grants that are still on Platform. Best effort: a response that cannot
    /// be deleted now stays recorded and is tried again by the next login
    /// with this identity. It does not hold the caller back — the entry it leaves is
    /// the encrypted key of a request the app has already finished with.
    ///
    /// A grant whose key is still live keeps its record, marked as having no
    /// response left: a later disconnect picks the keys it has records for
    /// without looking their app up in the wallet's key store. A grant whose
    /// key is already disabled has no further use and is dropped.
    private func deleteAppConnectResponses(
        where matches: (AppConnectGrant) -> Bool,
        responseContractId: Data,
        context: Context,
        signer: KeychainSigner
    ) async {
        await resolveUnconfirmedAppConnectResponses(
            where: matches, responseContractId: responseContractId, context: context)
        let pending = context.stores.grants.load().filter { matches($0) && $0.hasDeletableResponse }
        for grant in pending {
            do {
                guard let documentIdText = grant.documentId,
                      let documentId = Self.decodeIdentifier(documentIdText) else {
                    throw DashConnectPlatformError.existingDocumentLookupFailed
                }
                let signingKeyId = try selectDocumentSigningKeyId(
                    wallet: context.wallet,
                    identityId: context.identityId
                )
                _ = try await context.wallet.deleteDocument(
                    ownerIdentityId: context.identityId,
                    contractId: responseContractId,
                    documentType: AppConnect.documentType,
                    documentId: documentId,
                    propertiesJSON: try grant.values.propertiesJSON(),
                    signingKeyId: signingKeyId,
                    signer: signer
                )
                markAppConnectResponseGone(grant, in: context.stores)
            } catch {
                Self.logger.error(
                    "🔗 DASHCONNECT :: previous loginKeyResponse not deleted — \(error.localizedDescription, privacy: .public)")
                // A delete can land without confirming, and every retry is
                // then refused because there is nothing left to delete. Only
                // Platform can say which failure this was.
                guard let hash = AppConnect.data(fromHex: grant.values.appEphemeralPubKeyHash) else { continue }
                do {
                    let remaining = try await findAppConnectResponse(
                        ownerIdentityId: context.identityId,
                        appEphemeralPubKeyHash: hash,
                        responseContractId: responseContractId,
                        sdk: context.sdk
                    )
                    if remaining == nil { markAppConnectResponseGone(grant, in: context.stores) }
                } catch {
                    continue
                }
            }
        }
    }

    /// Records that a grant has no response on Platform any more. The record
    /// of a live key stays for a disconnect to disable that key by; the
    /// record of a disabled key has no further use.
    private func markAppConnectResponseGone(_ grant: AppConnectGrant, in stores: Stores) {
        updateGrants(in: stores) { grants in
            guard let index = grants.firstIndex(where: { $0.key == grant.key }) else { return }
            if grants[index].keyDisabled == true {
                grants.remove(at: index)
            } else {
                grants[index].responseDeleted = true
            }
        }
    }

    /// Settles the matching grants whose publish never confirmed, by asking
    /// Platform. A response that is there gets its id and its values on
    /// Platform, so it can be deleted; one that is not there needs nothing
    /// more. A lookup that fails leaves the record as it is for the next try.
    private func resolveUnconfirmedAppConnectResponses(
        where matches: (AppConnectGrant) -> Bool,
        responseContractId: Data,
        context: Context
    ) async {
        for grant in context.stores.grants.load() where matches(grant) && grant.hasUnconfirmedResponse {
            guard let hash = AppConnect.data(fromHex: grant.values.appEphemeralPubKeyHash) else { continue }
            do {
                let published = try await findAppConnectResponse(
                    ownerIdentityId: context.identityId,
                    appEphemeralPubKeyHash: hash,
                    responseContractId: responseContractId,
                    sdk: context.sdk
                )
                guard let published else {
                    markAppConnectResponseGone(grant, in: context.stores)
                    continue
                }
                updateGrants(in: context.stores) { grants in
                    guard let index = grants.firstIndex(where: { $0.key == grant.key }) else { return }
                    grants[index].documentId = published.documentId.toBase58String()
                    grants[index].values = published.values
                }
            } catch {
                Self.logger.error(
                    "🔗 DASHCONNECT :: unconfirmed loginKeyResponse not resolved — \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func handleStateTransition(_ request: DashStRequest) async throws -> DashConnectStAction {
        try validateNetwork(request.network)
        await showActiveWalletRows()
        let context = try await requireContext()
        // The incoming bytes are parsed only to learn the intent — they are
        // never signed. Each branch validates the parsed values and rebuilds
        // the operation through the SDK itself.
        let parsed = try await MainActor.run {
            try stateTransitionParser.parse(request.transitionBytes)
        }

        switch parsed {
        case .keyRegistration(let transition):
            // Only this branch changes the identity and the rows.
            try await gated { try await completeKeyRegistration(transition, context: context) }
            return .keyRegistrationCompleted
        case .tokenPurchase(let purchase):
            return .tokenPurchaseApprovalRequired(
                try await makeTokenPurchaseRequest(purchase, context: context)
            )
        }
    }

    /// The key-registration half of a scanned `dash-st:` payload. Verifies
    /// the parsed transition only adds the exact derived login keys for our
    /// identity, then rebuilds the equivalent `updateIdentity(...)` call
    /// through the SDK.
    private func completeKeyRegistration(
        _ transition: DashConnectKeyRegistrationTransition,
        context: Context
    ) async throws {
        // The transition was parsed before the connection is chosen:
        // `DashStRequest` carries no app identifier, but the transition's
        // keys usually do, in their contract bounds. Picking the most
        // recently approved connection instead would derive app B's keys for
        // a QR scanned from app A.
        let pendingConnection = try Self.pendingApprovedConnectionForKeyRegistration(
            in: rows(in: context.stores),
            boundContractId: Self.boundAppContractId(in: transition)
        )
        guard let pendingAppContractId = Self.decodeIdentifier(pendingConnection.id) else {
            throw DashConnectPlatformError.noApprovedConnectionAwaitingKeyRegistration
        }

        var derivedMaterial = try await deriveKeyRegistrationMaterial(
            appContractId: pendingAppContractId, context: context)
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
            await markActive(pendingConnection, in: context.stores)
            return
        }

        try await authorize()
        // The keys were derived and checked for the identity above.
        let authorized = try await contextAfterAuthorization(matching: context)

        let signer = KeychainSigner(modelContainer: authorized.modelContainer)
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
            try await authorized.wallet.updateIdentity(
                identityId: authorized.identityId,
                addPublicKeys: missingKeys.map(Self.makeManagedIdentityPubkey),
                signer: signer
            )
        }

        await markActive(pendingConnection, in: authorized.stores)
    }

    /// The context to sign with after a PIN prompt, which can outlast a
    /// wallet or identity switch: what is active now, and only while it is
    /// still the identity and the wallet of `context`.
    private func contextAfterAuthorization(matching context: Context) async throws -> Context {
        let authorized = try await requireContext(pinnedTo: context.stores)
        guard authorized.identityId == context.identityId else {
            throw DashConnectPlatformError.walletChanged
        }
        return authorized
    }

    /// What is active now, only while it is the wallet `stores` belongs to,
    /// and carrying that pair.
    private func requireContext(pinnedTo stores: Stores) async throws -> Context {
        var context = try await requireContext()
        guard context.stores.walletIdHex == stores.walletIdHex else {
            throw DashConnectPlatformError.walletChanged
        }
        context.stores = stores
        return context
    }

    private func markActive(_ pendingConnection: DAppConnection, in stores: Stores) async {
        let activatedAt = now()
        await updateRows(in: stores) { rows in
            rows.map { connection in
                guard connection.id == pendingConnection.id else { return connection }
                return DAppConnection(
                    id: connection.id,
                    name: connection.name,
                    url: connection.url,
                    status: .active,
                    updatedAt: activatedAt
                )
            }
        }
    }

    /// Builds the user-facing approval request for a parsed token purchase,
    /// refusing purchases that name someone else's identity. Reads the token's
    /// denomination from the contract over the network (see
    /// `tokenDenomination`), because the quantity on the sheet is meaningless
    /// without it; no other metadata is resolved.
    private func makeTokenPurchaseRequest(
        _ purchase: DashConnectTokenPurchaseTransition,
        context: Context
    ) async throws -> DashConnectTokenPurchaseRequest {
        // Checked before anything is shown: a purchase that would charge a
        // different identity must be refused, not rendered for approval.
        guard purchase.ownerId == context.identityId else {
            throw DashConnectPlatformError.tokenPurchaseWrongIdentity
        }

        let contractIdBase58 = purchase.dataContractId.toBase58String()

        // The sheet shows the token id the payload claims, but the purchase
        // is rebuilt from the contract id and position alone — the SDK
        // derives the real token id from those and never sees the claimed
        // one. Without this check a crafted payload could display one token
        // while buying another. `calculateTokenId` is the protocol formula
        // (double_sha256("dash_token" || contract_id || u16_be(position))),
        // so what is displayed is what will be bought.
        let derivedTokenId = try context.sdk.calculateTokenId(
            contractId: contractIdBase58,
            position: purchase.tokenContractPosition)
        guard derivedTokenId == purchase.tokenId.toBase58String() else {
            Self.logger.error(
                "🔗 DASHCONNECT :: token purchase names a token id the contract/position does not derive")
            throw DashConnectPlatformError.tokenPurchaseTokenIdMismatch
        }

        // Denomination read from the token's contract on Platform, not from
        // any local row. Nothing else on this path resolves it: the parser
        // copies the count through and `tokenPurchase(amount:)` spends base
        // units, so without this the sheet would name a quantity that can be
        // wrong by orders of magnitude.
        let denomination = await Self.tokenDenomination(
            sdk: context.sdk,
            contractId: purchase.dataContractId,
            position: Int(purchase.tokenContractPosition))

        return DashConnectTokenPurchaseRequest(
            // A connection approved earlier for the same contract names the
            // app; otherwise the sheet falls back to the contract id.
            appName: rows(in: context.stores).first { $0.id == contractIdBase58 }?.name,
            ownerId: purchase.ownerId,
            dataContractId: purchase.dataContractId,
            tokenId: purchase.tokenId,
            tokenContractPosition: purchase.tokenContractPosition,
            tokenCount: purchase.tokenCount,
            tokenDecimals: denomination?.decimals,
            tokenName: denomination?.name,
            totalAgreedPriceCredits: purchase.totalAgreedPrice,
            walletUsername: context.storedUsername,
            walletIdentityId: context.identityId.toBase58String()
        )
    }

    /// The token's declared decimals and name, from the contract as Platform
    /// holds it NOW.
    ///
    /// Deliberately not the wallet's persisted `PersistentToken` row: token
    /// denomination is mutable on Platform, so a row written at the last sync
    /// can describe a different denomination than the one the base-unit amount
    /// will be spent under — and this number goes on a screen where the user
    /// authorizes money. `nil` when the contract cannot be fetched or carries
    /// no token at that position; the sheet then shows base units and says so,
    /// rather than implying a denominated quantity nobody verified.
    ///
    /// Fetched through `dataContractGetOffMain`, not `dataContractGet`: the
    /// latter is declared in the SDK's `@MainActor` extension and is `async`
    /// without ever suspending, over an FFI entry point that runs
    /// `runtime.block_on` — so awaiting it would hold the main actor for the
    /// whole DAPI round trip and freeze the sheet. The off-main query runs the
    /// native read on the SDK's own worker queue instead.
    private static func tokenDenomination(
        sdk: SDK,
        contractId: Data,
        position: Int
    ) async -> (decimals: Int, name: String)? {
        let id = contractId.toBase58String()
        do {
            let contract = try await sdk.dataContractGetOffMain(id: id)
            guard let tokens = contract["tokens"] as? [String: Any],
                  let tokenDict = tokens[String(position)] as? [String: Any] else {
                logger.info("🔗 DASHCONNECT :: token purchase: contract \(id, privacy: .public) has no token at position \(position, privacy: .public); quantity shown as base units")
                return nil
            }
            // `conventions.decimals` wins where both are present — the same
            // precedence `DataContractParser.parseTokenConfiguration` applies
            // when it writes the persisted row.
            let conventions = tokenDict["conventions"] as? [String: Any]
            guard let decimals = (conventions?["decimals"] as? Int) ?? (tokenDict["decimals"] as? Int) else {
                logger.info("🔗 DASHCONNECT :: token purchase: contract \(id, privacy: .public) declares no decimals; quantity shown as base units")
                return nil
            }
            let name = (tokenDict["name"] as? String)
                ?? (conventions?["name"] as? String)
                ?? ""
            return (decimals, name)
        } catch {
            logger.error("🔗 DASHCONNECT :: token purchase: contract fetch failed for \(id, privacy: .public): \(String(describing: error), privacy: .public); quantity shown as base units")
            return nil
        }
    }

    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws {
        var context: Context
        let signer: KeychainSigner
        do {
            context = try await requireContext()
            // Re-checked at approve time: the sheet can sit open while the
            // wallet's identity changes, and the purchase must only ever debit
            // the identity the user saw on the sheet.
            guard request.ownerId == context.identityId else {
                throw DashConnectPlatformError.tokenPurchaseWrongIdentity
            }

            try await authorize()

            // Re-resolved AFTER the prompt, not before it. `authorize()` waits
            // on the user, and the active wallet or identity can change while
            // it is open — a switch, a wipe-and-restore. Building the signer
            // from the context captured beforehand would sign for an identity
            // the user never saw on the sheet and debit its credits.
            let authorized = try await requireContext()
            guard authorized.identityId == request.ownerId,
                  authorized.identityId == context.identityId else {
                throw DashConnectPlatformError.tokenPurchaseWrongIdentity
            }
            context = authorized
            signer = KeychainSigner(modelContainer: authorized.modelContainer)
        } catch {
            // Everything above happens before anything is signed or sent, so
            // the purchase provably did not start and the caller may offer it
            // again.
            throw DashConnectTokenPurchaseFailure.beforeSubmission(error)
        }

        // `expectedTotalCost` is the same credits figure the approval sheet
        // rendered, and it is a CEILING: Platform rejects the transition when
        // the on-chain price is higher, and charges the lower amount when it
        // is lower. So the user can never be charged more than what they
        // approved, but they may be charged less.
        // `signingKeyId` is left at its default: the signer selects a
        // CRITICAL key itself and fails with a clear error when the identity
        // has none.
        do {
            try await context.wallet.tokenPurchase(
                identityId: context.identityId,
                contractId: request.dataContractId,
                tokenPosition: request.tokenContractPosition,
                amount: request.tokenCount,
                expectedTotalCost: request.totalAgreedPriceCredits,
                signer: signer
            )
        } catch {
            // One opaque error covers "the transition was rejected" and "it
            // was submitted and the wait for its outcome failed", and nothing
            // in the FFI result separates them. Report the ambiguity rather
            // than guess: a purchase that did land must not be offered for a
            // retry that would buy the tokens again on the next nonce.
            Self.logger.error(
                "🔗 DASHCONNECT :: token purchase failed after submission; outcome unknown: \(String(describing: error), privacy: .public)")
            throw DashConnectTokenPurchaseFailure.outcomeUnknown(error)
        }
    }

    func remove(id: String, scope: String?) async {
        // A row published for another wallet was not picked from this one.
        guard let stores = await showActiveWalletRows(), scope == stores.scope else { return }
        await updateRows(in: stores) { rows in rows.filter { $0.id != id } }
    }

    func disconnect(id: String, scope: String?) async throws {
        try await gated { try await disconnectInTurn(id: id, scope: scope) }
    }

    private func disconnectInTurn(id: String, scope: String?) async throws {
        guard let stores = await showActiveWalletRows() else {
            throw DashConnectPlatformError.noWallet
        }
        // The row names the wallet it was published for. When that is not
        // the wallet that is active now, nothing of the row's wallet can be
        // turned off from here, and a row this wallet has for the same app
        // is not the one that was picked.
        guard scope == stores.scope else {
            throw DashConnectPlatformError.walletChanged
        }
        let isOneQR = rows(in: stores).first { $0.id == id }?.loginKind == .oneQR
        let hasGrants = stores.grants.load().contains { $0.appContractId == id }
        if isOneQR || hasGrants {
            let liveElsewhere = try await revokeAppConnectGrants(
                appContractId: id, checksUnrecordedKeys: isOneQR, stores: stores)
            // The row stands for the app, and the app still holds a key on
            // another identity of this wallet. That key can only be disabled
            // while its identity is the active one, so the row stays to get
            // there, and the user is told; this identity's keys are off.
            if liveElsewhere { throw DashConnectPlatformError.grantOnAnotherIdentity }
        }
        if isOneQR {
            // The session keys are disabled, and so are the keys of an
            // earlier two-QR login that were found: the same QR can no
            // longer be approved and there is no second step to wait for,
            // so the row goes instead of sitting in the two-QR "approved"
            // state.
            await updateRows(in: stores) { rows in rows.filter { $0.id != id } }
            return
        }

        let disconnectedAt = now()
        // Local-only for a two-QR connection: its `loginKeyResponse` document
        // stays, and re-approving the same `dash-key:` QR returns it to
        // `.active` while the identity keys are still registered.
        await updateRows(in: stores) { rows in
            rows.map { connection in
                guard connection.id == id else { return connection }
                return DAppConnection(
                    id: connection.id,
                    name: connection.name,
                    url: connection.url,
                    status: .approved,
                    updatedAt: disconnectedAt
                )
            }
        }
    }

    /// Ends the access one-QR logins gave an app: disables its session keys
    /// on the identity, then deletes the responses that carried them.
    ///
    /// The key goes first because it is what the app signs with. A response
    /// that could not be deleted afterwards stays recorded, with its key
    /// marked disabled, and is retried by the next login with this identity.
    ///
    /// The keys are the ones recorded here plus the live keys on the identity
    /// that are bound to the app's contract and shaped as this login
    /// registers them, so the keys a reinstalled wallet kept no record of go
    /// too. A key another wallet gave the app in a different shape stays.
    /// TODO(app-connect-orphan-responses): the response behind a key with no
    /// record stays on Platform. It can only be found by its request hash,
    /// which the record held.
    ///
    /// For a row made by the one-QR login the keys of an earlier two-QR
    /// login to the app are disabled as well. That login derives the same keys
    /// every time and Platform never re-adds a key, so the app cannot sign
    /// in with two QRs again. A two-QR row keeps them.
    ///
    /// Returns whether a grant record shows the app with a live key on
    /// another identity of this wallet. When this identity gave it none, that
    /// is thrown instead: nothing was turned off.
    /// For a row made by the one-QR login that also covers keys on another
    /// identity that no grant record names, as far as the wallet's store
    /// shows them.
    ///
    /// `checksUnrecordedKeys` is set for a row made by the one-QR login: with
    /// no record for this identity the keys are still looked for on it. When
    /// it holds none bound to the app, there was nothing to turn off here and
    /// the call returns without an error.
    private func revokeAppConnectGrants(
        appContractId: String,
        checksUnrecordedKeys: Bool,
        stores: Stores
    ) async throws -> Bool {
        // The row was picked in the wallet `stores` belongs to; another
        // wallet's identity is not the one the row belongs to.
        var context = try await requireContext(pinnedTo: stores)
        let identityId = context.identityId.toBase58String()
        func isGranted(_ grant: AppConnectGrant) -> Bool {
            grant.identityId == identityId && grant.appContractId == appContractId
        }
        func hasLiveGrantElsewhere() -> Bool {
            stores.grants.load().contains {
                $0.appContractId == appContractId && $0.identityId != identityId && $0.keyDisabled != true
            }
        }
        guard let appContract = Self.decodeIdentifier(appContractId) else {
            throw DashConnectPlatformError.loginContractUnavailable
        }
        if !stores.grants.load().contains(where: isGranted) {
            // Before the PIN prompt, from the store alone: whether this
            // identity holds a key of the app's that has no record.
            let holdsUnrecordedKey = try checksUnrecordedKeys && Self
                .storedKeyBindings(identityId: identityId, modelContainer: context.modelContainer)
                .contains { $0.singleContractId == appContract && !$0.isDisabled && $0.isSessionKeyShaped }
            // A one-QR row goes on to the PIN prompt either way: the keys of
            // an earlier two-QR login can only be looked for after it.
            if !holdsUnrecordedKey, !checksUnrecordedKeys {
                if hasLiveGrantElsewhere() { throw DashConnectPlatformError.grantOnAnotherIdentity }
                return false
            }
        }

        try await authorize()
        context = try await contextAfterAuthorization(matching: context)

        let signer = KeychainSigner(modelContainer: context.modelContainer)
        let currentPublicKeys = try await refreshedIdentityPublicKeys(context: context)
        let granted = stores.grants.load().filter(isGranted)
        guard AppConnect.sessionKeyIdsMissing(from: currentPublicKeys, for: granted).isEmpty else {
            // Platform never removes a key, so the node that answered is
            // behind. A key it does not know cannot be shown to be disabled,
            // so nothing is reported as turned off.
            throw DashConnectPlatformError.identityKeysOutOfDate
        }
        let bindings = try Self.storedKeyBindings(identityId: identityId, modelContainer: context.modelContainer)
        guard AppConnect.sessionKeyIdsWithUnknownBinding(
            for: granted,
            bindings: bindings,
            currentIdentityPublicKeys: currentPublicKeys
        ).isEmpty, AppConnect.boundKeyIdsMissing(
            from: currentPublicKeys,
            appContractId: appContract,
            bindings: bindings
        ).isEmpty else {
            // A live session key the wallet's store cannot place may be this
            // app's, and a stored key of the app's that the fetched list
            // lacks means the list is behind. Either way nothing is reported
            // as turned off.
            throw DashConnectPlatformError.identityKeysOutOfDate
        }
        // The keys the two-QR login derives for this app, known before
        // anything is disabled: its authentication key has the kind and the
        // bound of a session key. A one-QR row disables both of them; a
        // two-QR row keeps them, so there the authentication key is named
        // as one to leave. If they cannot be derived, nothing is turned off.
        let twoQRKeys = try await twoQRLoginPublicKeys(appContractId: appContract, context: context)
        var keyIds = AppConnect.sessionKeyIdsToDisable(
            for: granted,
            appContractId: appContract,
            bindings: bindings,
            currentIdentityPublicKeys: currentPublicKeys,
            twoQRAuthenticationKeyHash160: checksUnrecordedKeys ? nil : twoQRKeys.authenticationPublicKeyHash160
        )
        if checksUnrecordedKeys {
            keyIds = Array(Set(keyIds).union(Self.liveLoginKeyIds(
                authenticationPublicKeyHash160: twoQRKeys.authenticationPublicKeyHash160,
                encryptionPublicKey: twoQRKeys.encryptionPublicKey,
                currentIdentityPublicKeys: currentPublicKeys
            ))).sorted()
        }
        // For a one-QR row, the keys on another identity that no grant
        // record shows. `nil` when that could not be told.
        let heldOnAnotherIdentity: Bool? = checksUnrecordedKeys && !hasLiveGrantElsewhere()
            ? await anotherIdentityHoldsAppKeys(appContractId: appContract, context: context)
            : false
        if granted.isEmpty, keyIds.isEmpty, hasLiveGrantElsewhere() || heldOnAnotherIdentity == true {
            throw DashConnectPlatformError.grantOnAnotherIdentity
        }
        if !keyIds.isEmpty {
            Self.logger.info("🔗 DASHCONNECT :: disabling \(keyIds.count, privacy: .public) app key(s)")
            // Platform takes a limited number of keys per update. A failure
            // part way leaves the rest live and the row in place; the next
            // attempt picks up what is still live.
            for start in stride(from: 0, to: keyIds.count, by: AppConnect.maxKeysDisabledPerUpdate) {
                try await context.wallet.updateIdentity(
                    identityId: context.identityId,
                    disablePublicKeyIds: Array(keyIds[start ..< min(start + AppConnect.maxKeysDisabledPerUpdate, keyIds.count)]),
                    signer: signer
                )
            }
            Self.logger.info("🔗 DASHCONNECT :: app key(s) disabled")
        }

        // The session keys of the grants read above are now off, and only
        // those are marked.
        let revoked = Set(granted.map(\.key))
        func isRevoked(_ grant: AppConnectGrant) -> Bool { revoked.contains(grant.key) }
        updateGrants(in: stores) { AppConnect.markKeysDisabled(in: &$0, where: isRevoked) }

        if let responseContractId = Self.decodeIdentifier(AppConnect.contractId) {
            await deleteAppConnectResponses(
                where: isRevoked,
                responseContractId: responseContractId,
                context: context,
                signer: signer
            )
        }
        if hasLiveGrantElsewhere() || heldOnAnotherIdentity == true { return true }
        // This identity's keys are off. Whether another one holds a key of
        // the app could not be read from the store, so the row stays, with
        // an error rather than without one.
        guard heldOnAnotherIdentity != nil else { throw DashConnectPlatformError.otherIdentitiesNotChecked }
        return false
    }

    /// Whether the wallet's store shows another identity of this wallet with
    /// a live key of the app that no grant record names: a session key bound
    /// to the app's contract, or a key the two-QR login derives for it.
    /// `nil` when no identity shows one and at least one could not be told:
    /// its keys are not in the store, a live session-shaped key there has a
    /// bound this build cannot read, or its two-QR keys could not be derived.
    /// TODO(app-connect-other-identity-keys): the store is as fresh as each
    /// identity's last load from Platform, and an identity it does not hold
    /// is not seen, so the row can go while such a key is live.
    private func anotherIdentityHoldsAppKeys(appContractId: Data, context: Context) async -> Bool? {
        let others: [(identityId: Data, identityIndex: UInt32)]
        do {
            others = try Self.storedWalletIdentities(
                walletId: context.wallet.walletId,
                network: context.network,
                modelContainer: context.modelContainer
            ).filter { $0.identityId != context.identityId }
        } catch {
            Self.logger.error(
                "🔗 DASHCONNECT :: other identities not read — \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // One identity that cannot be told does not hide a key found on
        // another.
        var hasUnknown = false
        for other in others {
            do {
                let bindings = try Self.storedKeyBindings(
                    identityId: other.identityId.toBase58String(), modelContainer: context.modelContainer)
                if AppConnect.holdsLiveSessionKey(appContractId: appContractId, bindings: bindings) { return true }
                // An identity always has keys, so none stored means not
                // loaded; and a session-shaped key with an unreadable bound
                // may be the app's.
                if bindings.isEmpty || bindings.contains(where: {
                    !$0.isDisabled && $0.isSessionKeyShaped && $0.hasUnreadableBound
                }) {
                    hasUnknown = true
                }
                // Derive only for an identity that has a live key of either
                // two-QR kind at all.
                guard bindings.contains(where: {
                    !$0.isDisabled && ($0.isTwoQRAuthenticationKeyShaped || $0.isTwoQREncryptionKeyShaped)
                }) else { continue }
                let twoQRKeys = try await twoQRLoginPublicKeys(
                    appContractId: appContractId,
                    identityId: other.identityId,
                    identityIndex: other.identityIndex,
                    context: context)
                if AppConnect.holdsLiveTwoQRLoginKey(
                    authenticationPublicKeyHash160: twoQRKeys.authenticationPublicKeyHash160,
                    encryptionPublicKey: twoQRKeys.encryptionPublicKey,
                    bindings: bindings
                ) {
                    return true
                }
            } catch {
                Self.logger.error(
                    "🔗 DASHCONNECT :: keys of another identity not checked — \(error.localizedDescription, privacy: .public)")
                hasUnknown = true
            }
        }
        return hasUnknown ? nil : false
    }

    /// The identities the SDK's store attaches to this wallet on `network`.
    private static func storedWalletIdentities(
        walletId: Data,
        network: Network,
        modelContainer: ModelContainer
    ) throws -> [(identityId: Data, identityIndex: UInt32)] {
        let descriptor = FetchDescriptor<PersistentIdentity>(predicate: PersistentIdentity.predicate(network: network))
        let modelContext = ModelContext(modelContainer)
        // The rows are only readable while their context is alive.
        return try withExtendedLifetime(modelContext) {
            try modelContext.fetch(descriptor)
                .filter { $0.wallet?.walletId == walletId }
                .map { ($0.identityId, $0.identityIndex) }
        }
    }

    /// The public halves of the keys the two-QR login derives for the active
    /// identity and an app.
    private func twoQRLoginPublicKeys(
        appContractId: Data,
        context: Context
    ) async throws -> (authenticationPublicKeyHash160: Data, encryptionPublicKey: Data) {
        try await twoQRLoginPublicKeys(
            appContractId: appContractId,
            identityId: context.identityId,
            identityIndex: context.identityIndex,
            context: context)
    }

    /// The same for any identity of the active wallet, by its index.
    private func twoQRLoginPublicKeys(
        appContractId: Data,
        identityId: Data,
        identityIndex: UInt32,
        context: Context
    ) async throws -> (authenticationPublicKeyHash160: Data, encryptionPublicKey: Data) {
        var derivedMaterial = try await deriveKeyRegistrationMaterial(
            appContractId: appContractId,
            identityId: identityId,
            identityIndex: identityIndex,
            context: context)
        defer {
            Self.zero(&derivedMaterial.loginKey)
            Self.zero(&derivedMaterial.authenticationPrivateKey)
            Self.zero(&derivedMaterial.encryptionPrivateKey)
        }
        return (derivedMaterial.authenticationPublicKeyHash160, derivedMaterial.encryptionPublicKey)
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
        let sealed = try AppConnect.seal(
            loginKey,
            appEphemeralPubKey: appEphemeralPubKey,
            walletEphemeralPrivateKey: &walletEphemeralPrivateKey,
            encrypt: encryptLoginKey
        )
        let values = AppConnect.ResponseValues(sealed)

        return DashConnectLoginKeyResponseDraft(
            properties: [
                "contractId": appContractId.toBase58String(),
                "appEphemeralPubKeyHash": values.appEphemeralPubKeyHash,
                "walletEphemeralPubKey": values.walletEphemeralPubKey,
                "encryptedPayload": values.encryptedPayload,
                "keyIndex": LoginKeyDerivation.defaultKeyIndex,
            ],
            walletEphemeralPublicKey: sealed.walletEphemeralPublicKey,
            encryptedPayload: sealed.encryptedPayload
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

    /// The two-QR login's keys for the active identity and one app. The
    /// caller wipes the returned private keys.
    private func deriveKeyRegistrationMaterial(
        appContractId: Data,
        context: Context
    ) async throws -> DashConnectKeyRegistrationDerivedMaterial {
        try await deriveKeyRegistrationMaterial(
            appContractId: appContractId,
            identityId: context.identityId,
            identityIndex: context.identityIndex,
            context: context)
    }

    /// The same for any identity of the active wallet, by its index.
    private func deriveKeyRegistrationMaterial(
        appContractId: Data,
        identityId: Data,
        identityIndex: UInt32,
        context: Context
    ) async throws -> DashConnectKeyRegistrationDerivedMaterial {
        // `deriveIdentityAuthKeyAtSlot` is main-actor isolated in the SDK.
        var chainKey = try await MainActor.run {
            try context.wallet.deriveIdentityAuthKeyAtSlot(
                identityIndex: identityIndex,
                keyId: UInt32(LoginKeyDerivation.defaultKeyIndex),
                network: context.network
            ).privateKeyData
        }
        defer { Self.zero(&chainKey) }
        return try Self.deriveKeyRegistrationMaterial(
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
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

    /// The ids of the two-QR login's keys that are on the identity and not
    /// disabled.
    static func liveLoginKeyIds(
        authenticationPublicKeyHash160: Data,
        encryptionPublicKey: Data,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> [UInt32] {
        currentIdentityPublicKeys
            .filter { key in
                hasRegisteredAuthenticationKey(
                    authenticationPublicKeyHash160: authenticationPublicKeyHash160,
                    currentIdentityPublicKeys: [key]
                ) || hasRegisteredEncryptionKey(
                    encryptionPublicKey: encryptionPublicKey,
                    currentIdentityPublicKeys: [key]
                )
            }
            .map { UInt32(bitPattern: $0.keyId) }
            .sorted()
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
        updatedAt: Date,
        loginKind: DashConnectLoginKind = .twoQR
    ) -> DAppConnection {
        DAppConnection(
            id: preview.appContractId,
            name: preview.appLabel.isEmpty ? NSLocalizedString("Unknown app", comment: "DashConnect") : preview.appLabel,
            url: preview.appUrl,
            status: status,
            updatedAt: updatedAt,
            loginKind: loginKind
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

    /// The stores fixed to one wallet; `nil` with no wallet.
    private static func pinnedStores(
        walletIdHex: String?,
        store: any DashConnectStore,
        responseStore: any AppConnectResponseStore
    ) -> Stores? {
        guard let walletIdHex, !walletIdHex.isEmpty else { return nil }
        return Stores(
            walletIdHex: walletIdHex,
            connections: store.pinned(toWalletIdHex: walletIdHex),
            grants: responseStore.pinned(toWalletIdHex: walletIdHex))
    }

    /// The stores fixed to the wallet that is active at this call, read
    /// once; `nil` with no wallet.
    private func pinnedActiveStores() -> Stores? {
        Self.pinnedStores(walletIdHex: activeWalletIdHex(), store: store, responseStore: responseStore)
    }

    /// Publishes the active wallet's rows when the published list holds
    /// another wallet's. Returns the active wallet's stores, read once.
    @MainActor
    @discardableResult
    private func showActiveWalletRows() -> Stores? {
        let active = pinnedActiveStores()
        guard shownRows.scope != active?.scope else { return active }
        shownRows.scope = active?.scope
        subject.send(active.map { $0.published($0.connections.load()) } ?? [])
        return active
    }

    /// The rows of the wallet `stores` belongs to, as stored. Not the
    /// published list: another data source over the same store may have
    /// written since this one loaded it.
    private func rows(in stores: Stores) -> [DAppConnection] {
        stores.connections.load()
    }

    @MainActor
    private func shownRow(id: String) -> DAppConnection? {
        subject.value.first { $0.id == id }
    }

    /// Changes the rows of the wallet `stores` belongs to in one step, saves
    /// them there, and publishes them only while the published list is that
    /// wallet's.
    @MainActor
    private func updateRows(in stores: Stores, _ change: ([DAppConnection]) -> [DAppConnection]) {
        let sorted = Stores.stored(change(rows(in: stores))).sorted(by: { $0.updatedAt > $1.updatedAt })
        stores.connections.save(sorted)
        if shownRows.scope == stores.scope { subject.send(stores.published(sorted)) }
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

    /// The identity's keys as Platform has them now. The SDK's own copy is
    /// only replaced when an identity update returns success, so a
    /// registration or a disable that landed without confirming is missing
    /// from it; deciding from that copy would add the key twice or disable it
    /// twice. The reload also replaces the copy the SDK signs the next update
    /// against.
    private func refreshedIdentityPublicKeys(
        context: Context
    ) async throws -> [ManagedIdentity.IdentityPublicKeyInfo] {
        guard try await context.wallet.loadIdentity(atIndex: context.identityIndex) == context.identityId else {
            throw DashConnectPlatformError.noIdentity
        }
        return try context.wallet
            .managedIdentity(identityId: context.identityId)
            .getPublicKeys()
    }

    /// What the wallet's store holds for each key of the identity. The store
    /// is written by the SDK as it loads and updates the identity.
    private static func storedKeyBindings(
        identityId: String,
        modelContainer: ModelContainer
    ) throws -> [AppConnect.KeyBinding] {
        let descriptor = FetchDescriptor<PersistentPublicKey>(predicate: #Predicate { $0.identityId == identityId })
        let modelContext = ModelContext(modelContainer)
        // The rows are only readable while their context is alive.
        return try withExtendedLifetime(modelContext) {
            try modelContext.fetch(descriptor).map {
                AppConnect.KeyBinding(
                    keyId: UInt32(bitPattern: $0.keyId),
                    data: $0.publicKeyData,
                    singleContractId: AppConnect.singleContractId(
                        boundsKind: $0.effectiveContractBoundsKind,
                        boundIds: $0.contractBounds
                    ),
                    isDisabled: $0.disabledAt != nil,
                    isSessionKeyShaped: $0.keyTypeEnum == .ecdsaHash160
                        && $0.purposeEnum == .authentication
                        && $0.securityLevelEnum == .high
                        && $0.totalBudget != nil
                        && $0.expiresAt != nil,
                    hasUnreadableBound: !AppConnect.isReadableBound(
                        boundsKind: $0.effectiveContractBoundsKind,
                        boundIds: $0.contractBounds
                    ),
                    isTwoQRAuthenticationKeyShaped: $0.keyTypeEnum == .ecdsaHash160
                        && $0.purposeEnum == .authentication
                        && $0.securityLevelEnum == .high,
                    isTwoQREncryptionKeyShaped: $0.keyTypeEnum == .ecdsaSecp256k1
                        && $0.purposeEnum == .encryption
                        && $0.securityLevelEnum == .medium,
                    bound: AppConnect.storedBound(
                        boundsKind: $0.effectiveContractBoundsKind,
                        boundIds: $0.contractBounds,
                        documentTypeName: $0.contractBoundsDocumentTypeName
                    )
                )
            }
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

        // The stores below are fixed to this wallet. While a switch is under
        // way the SDK can still hold the wallet that is being left.
        let walletIdHex = wallet.walletId.hexEncodedString()
        guard activeWalletIdHex() == walletIdHex else {
            Self.logger.error("🔗 DASHCONNECT :: the SDK wallet is not the active wallet")
            throw DashConnectPlatformError.walletChanged
        }

        let identityIndex = try wallet.managedIdentity(identityId: identityId).getIdentityIndex() ?? 0

        return Context(
            wallet: wallet,
            sdk: sdk,
            modelContainer: modelContainer,
            network: network,
            identityId: identityId,
            identityIndex: identityIndex,
            storedUsername: runtime.storedUsername,
            stores: Stores(
                walletIdHex: walletIdHex,
                connections: store.pinned(toWalletIdHex: walletIdHex),
                grants: responseStore.pinned(toWalletIdHex: walletIdHex))
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
            },
            totalBudget: key.totalBudget,
            expiresAt: key.expiresAt
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
