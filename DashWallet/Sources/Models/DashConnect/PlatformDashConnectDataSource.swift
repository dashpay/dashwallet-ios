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
    case noAuthenticationKey
    case existingDocumentLookupFailed
    case tokenPurchaseWrongIdentity
    case tokenPurchaseTokenIdMismatch
    case unsupportedStateTransition(String)
    case sessionKeyUnusable
    case identityKeysOutOfDate
    case grantOnAnotherIdentity
    case grantStoreUnavailable
    case approvalOutOfDate
    case loginUnresolved
    case grantNotRecorded
    case noFreeKeyId
    case appConnectEncryptionKeyChanged
    case appConnectKeysOutOfDate
    case appConnectKeysUnreadable
    case walletChanged
    case ephemeralKeyGenerationFailed
    case loginContractUnavailable
    case tooManyKeysToReplace
    case tooManyKeysToAdd
    case intentsUnreadable
    case identityReadBehind

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
        case .noAuthenticationKey:
            return "No enabled AUTHENTICATION ECDSA key is available for this identity."
        case .existingDocumentLookupFailed:
            return "The loginKeyResponse document on Platform could not be read."
        case .ephemeralKeyGenerationFailed:
            return "Could not generate an ephemeral DashConnect key."
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
                "This wallet could not save the approval, so nothing was sent. Try again.",
                comment: "DashConnect")
        case .appConnectKeysOutOfDate:
            return NSLocalizedString(
                "The network has not caught up with your identity's keys yet. Try again in a moment.",
                comment: "DashConnect App Connect v2")
        case .appConnectKeysUnreadable:
            return NSLocalizedString(
                "The wallet could not read your identity's encryption key for this app from the network. Try again.",
                comment: "DashConnect App Connect v2")
        case .appConnectEncryptionKeyChanged:
            return NSLocalizedString(
                "The app's encryption key on this identity changed after this sign-in was first approved. Ask the app to sign in again.",
                comment: "DashConnect App Connect v2")
        case .walletChanged:
            return NSLocalizedString("The active wallet or identity changed. Try again.", comment: "DashConnect")
        case .noFreeKeyId:
            return NSLocalizedString("This identity cannot take another key.", comment: "DashConnect")
        case .approvalOutOfDate:
            return NSLocalizedString(
                "The details of this sign-in changed while it was on screen. Check them and approve again.",
                comment: "DashConnect")
        case .loginUnresolved:
            return NSLocalizedString(
                "This wallet could not check what this sign-in would give the app.",
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
        case .loginContractUnavailable:
            return "The DashConnect login contract is not available on this network."
        case .identityReadBehind:
            return NSLocalizedString(
                "The network answered with an older copy of your identity. Try again in a moment.",
                comment: "DashConnect")
        case .intentsUnreadable:
            return NSLocalizedString(
                "This wallet holds DashConnect records a newer version wrote. Update the wallet, then try again.",
                comment: "DashConnect")
        case .tooManyKeysToAdd:
            return NSLocalizedString(
                "This app asks for more keys than one approval can add. Ask the app to ask for fewer.",
                comment: "DashConnect App Connect v2")
        case .tooManyKeysToReplace:
            return NSLocalizedString(
                "This app's earlier sign-ins left more keys than one approval can replace. Disconnect the app, then sign in again.",
                comment: "DashConnect App Connect v2")
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
        case .identityUpdate, .creditTransfer, .dataContractCreate, .dataContractUpdate, .other:
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

    /// The connection rows and App Connect intents of one wallet. A context carries
    /// the pair fixed to its own wallet: the stores follow the active wallet,
    /// and an operation that waits on the network or a PIN prompt must still
    /// write to the wallet whose identity it changed.
    private struct Stores {
        let walletIdHex: String
        let connections: any DashConnectStore
        let intents: any AppConnectIntentStore
        /// Where the network is reached, as configured when the pair was
        /// made; `nil` on a network with one fixed set of nodes.
        let endpoint: String?

        /// Names what an operation runs for: the wallet, the network scope
        /// the connection store was fixed to (which tells two devnets of one
        /// wallet apart by name), and the endpoint, so a devnet pointed at
        /// other nodes under the same name is another scope. The stores
        /// themselves are keyed by wallet and name only.
        var scope: String { "\(walletIdHex) \(connections.scopeKey ?? "") \(endpoint ?? "")" }

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

    static let loginKeyExchangeDocumentType = "loginKeyResponse"

    private let supportedNetwork: DashConnectNetwork
    private let store: any DashConnectStore
    private let intentStore: any AppConnectIntentStore
    /// The newest read of each identity this process has seen; a read
    /// behind it is not used (`AppConnect.IdentitySnapshot.mayReplace`).
    private static let newestSnapshots = OSAllocatedUnfairLock<[Data: AppConnect.IdentitySnapshot]>(initialState: [:])
    /// The owners of contracts and contract groups this process has read,
    /// for every data source of the app's run: Platform never changes one.
    private static let ownerMemory = OwnerMemory()
    private let subject: CurrentValueSubject<[DAppConnection], Never>
    private let shownRows: ShownRows
    private let operationGate: DashConnectOperationGate
    private let activeWalletIdHex: () -> String?
    private let networkEndpoint: () -> String?
    private var walletChangeObserver: AnyCancellable?
    private let authorizer: DWIdentityAuthorizer
    private let stateTransitionParser: any DashConnectStateTransitionParsing
    private let now: () -> Date

    /// Prefix of the shared profile keys an earlier build let the user keep.
    static let keptSharedProfileKeysPrefix = "DashConnect.keptSharedProfileKeys "

    /// Set once `removeKeptSharedProfileKeys` has run.
    static let keptSharedProfileKeysRemovedKey = "DashConnect.keptSharedProfileKeysRemoved"

    /// Removes, once, what an earlier build noted about kept shared profile
    /// keys: nothing reads it now that such keys are turned off with a
    /// disconnect.
    static func removeKeptSharedProfileKeys(from defaults: UserDefaults) {
        guard !defaults.bool(forKey: keptSharedProfileKeysRemovedKey) else { return }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keptSharedProfileKeysPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: keptSharedProfileKeysRemovedKey)
    }

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
        intentStore: (any AppConnectIntentStore)? = nil,
        activeWalletIdHex: @escaping () -> String? = { WalletEnvironment.activeWalletIdHex as String? },
        authorizer: DWIdentityAuthorizer = DWIdentityAuthorizer(),
        stateTransitionParser: any DashConnectStateTransitionParsing = PlatformWalletDashConnectStateTransitionParser(),
        networkEndpoint: (() -> String?)? = nil,
        notificationCenter: NotificationCenter = .default,
        operationGate: DashConnectOperationGate = .shared,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        assert(
            supportedNetwork == .testnet || supportedNetwork == .devnet,
            "DashConnect Platform publish runs on testnet and devnet only.")
        self.supportedNetwork = supportedNetwork
        self.store = store ?? UserDefaultsDashConnectStore(network: supportedNetwork)
        self.intentStore = intentStore ?? UserDefaultsAppConnectIntentStore(network: supportedNetwork)
        self.authorizer = authorizer
        self.stateTransitionParser = stateTransitionParser
        self.now = now
        Self.removeKeptSharedProfileKeys(from: defaults)
        self.activeWalletIdHex = activeWalletIdHex
        self.operationGate = operationGate
        // Only a devnet's nodes are configurable.
        let networkEndpoint = networkEndpoint
            ?? (supportedNetwork == .devnet ? { DevnetConfiguration.quorumURL } : { nil })
        self.networkEndpoint = networkEndpoint
        let active = Self.pinnedStores(
            walletIdHex: activeWalletIdHex(), store: self.store, intentStore: self.intentStore,
            endpoint: networkEndpoint())
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

        // `dashpay://connect` and a `dash-key:` version 2 URI carry the same
        // request body and are processed identically.
        let isConnectUri = DashConnectUri.isConnectUri(trimmed)
        if isConnectUri || DashConnectUri.isAppConnectUri(trimmed) {
            let uri: AppConnectUri
            do {
                uri = try isConnectUri
                    ? DashConnectUri.parseConnectRequest(trimmed)
                    : DashConnectUri.parseAppConnectRequest(trimmed)
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

        // A `dash-key:` request other than v2. One that parses as v1 is on
        // the right network and is refused; any other is malformed or newer.
        if DashConnectUri.isKeyUri(trimmed) {
            let request = try DashConnectUri.parseKeyRequest(trimmed)
            try validateNetwork(request.network)
            throw AppConnect.v1Refusal
        }

        if DashConnectUri.isStUri(trimmed) {
            let request = try DashConnectUri.parseStRequest(trimmed)
            try validateNetwork(request.network)
            return .stateTransition(request)
        }

        if DashConnectUri.isUnsupportedDashpayVerb(trimmed) {
            throw DashConnectMockError.needsNewerWallet
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

        // A row there only for keys another identity's read saw is no
        // connection of this identity.
        let me = context.identityId.toBase58String()
        let ownIntent = context.stores.intents.load().contains {
            $0.appId.toBase58String() == fallback.appContractId && $0.identityId == context.identityId && $0.closedAt == nil
        }
        let existingConnection = rows(in: context.stores).first {
            $0.id == fallback.appContractId && ($0.seenOn.isEmpty || $0.seenOn.contains(me) || ownIntent)
        }

        // Which login this network gets is settled here, so the sheet can
        // show what the app is given. With the version unknown the request
        // says so, and the sheet offers nothing to approve. The lookup runs
        // alongside the two below.
        async let resolvedProtocolVersion = Self.networkProtocolVersion(sdk: context.sdk, network: context.network)
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
        var login: AppConnect.Login = loginRequest.appConnect == nil ? .refused(AppConnect.v1Refusal) : .unresolved
        if let appConnect = loginRequest.appConnect, let protocolVersion {
            (login, unresolvedLoginReason) = await appConnectLogin(
                appConnect, protocolVersion: protocolVersion, context: context)
            // A request this wallet already took is spent (it is answered
            // at most once): the sheet says so before any PIN is asked.
            if let plan = login.grantPlan, context.stores.intents.load().contains(where: {
                $0.appId == plan.appId && $0.requestHash == plan.appEphemeralPubKeyHash
            }) {
                login = .refused(Self.spentRequest(after: nil))
            }
        }

        return ConnectionRequest(
            loginRequest: loginRequest,
            appLabel: metadata.name.isEmpty ? fallback.appLabel : metadata.name,
            appUrl: metadata.url,
            walletUsername: walletUsername,
            walletIdentityId: context.identityId.toBase58String(),
            existingConnection: existingConnection,
            login: login,
            unresolvedLoginReason: unresolvedLoginReason,
            scope: context.stores.scope
        )
    }

    /// One approval or disconnect at a time for the active
    /// wallet, whichever data source it came through. The turn is for the
    /// wallet that was active when it was asked for: if another one is
    /// active when it comes, the operation does not start.
    ///
    /// An operation that already has a context names that context's wallet,
    /// so its turn is that wallet's whichever one is active by now.
    private func gated<T>(
        walletIdHex: String? = nil,
        _ operation: () async throws -> T
    ) async throws -> T {
        let walletIdHex = walletIdHex ?? activeWalletIdHex() ?? ""
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
            if let hint = plan.identityHint, hint != context.identityId {
                return (.refused(AppConnect.Refusal(.invalid, NSLocalizedString(
                    "This sign-in is for another identity. Switch to it in this wallet and ask the app again.",
                    comment: "DashConnect App Connect v2"))), nil)
            }
            let sdk = context.sdk
            let ownership = try await Self.appConnectOwnership(
                plan,
                readContract: { try await sdk.dataContractGetOffMain(id: $0.toBase58String()) },
                readGroup: { try await sdk.getContractGroupInfo(contractGroupId: $0.toBase58String()) })
            if let refusal = ownership.refusal {
                return (.refused(refusal), nil)
            }
            plan.administeredGroupIds = ownership.administeredGroupIds
            plan.currentKeyRules = ownership.currentKeyRules
            return (.appConnect(plan), nil)
        } catch let refusal as AppConnect.Refusal {
            return (.refused(refusal), nil)
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: App Connect request not checked — \(error.localizedDescription, privacy: .public)")
            return (.unresolved, error.localizedDescription)
        }
    }

    /// The owner a contract read from Platform names, nil when it names
    /// none this build can read.
    static func contractOwnerId(_ contract: [String: Any]) -> Data? {
        (contract["ownerId"] as? String ?? contract["$ownerId"] as? String).flatMap(decodeIdentifier)
    }

    /// The owner a contract group read from Platform names, nil when it
    /// names none this build can read.
    static func groupOwnerId(_ info: [String: Any]) -> Data? {
        (info["ownerId"] as? String).flatMap(decodeIdentifier)
    }

    /// The owner a key bound to a contract group is attributed by: the
    /// group's, unless its admins may add their own contracts to it (read
    /// as administered unless the read shows none, as for an approval);
    /// then `AppConnect.administeredGroupOwnerId`.
    static func groupOwnerForAttribution(_ info: [String: Any]) -> Data? {
        guard let owner = groupOwnerId(info) else { return nil }
        return (info["adminIds"] as? [Any])?.isEmpty == true ? owner : AppConnect.administeredGroupOwnerId
    }

    /// The owners of contracts and contract groups, read from Platform and
    /// remembered in memory, never on disk: Platform never changes an
    /// owner. A read that fails, finds nothing, or names no readable owner
    /// is not remembered, so the owner stays unknown and is read again.
    final class OwnerMemory: Sendable {
        private struct Key: Hashable {
            let network: String
            let id: Data
        }

        private let known = OSAllocatedUnfairLock<[Key: Data]>(initialState: [:])

        /// The known owners of `contracts` and `groups` on `network`: those
        /// remembered, and the rest read in parallel. An id that could not
        /// be read is absent. Never throws.
        func owners(
            contracts: Set<Data>, groups: Set<Data>, network: String,
            readContract: @escaping @Sendable (Data) async throws -> [String: Any],
            readGroup: @escaping @Sendable (Data) async throws -> [String: Any]
        ) async -> [Data: Data] {
            let ids = contracts.union(groups)
            var owners = known.withLock { known in
                Dictionary(uniqueKeysWithValues: ids.compactMap { id in known[Key(network: network, id: id)].map { (id, $0) } })
            }
            let unknown = ids.subtracting(owners.keys)
            guard !unknown.isEmpty else { return owners }
            let read = await withTaskGroup(of: (Data, Data?).self) { group -> [Data: Data] in
                for id in unknown {
                    group.addTask {
                        if groups.contains(id) {
                            return (id, (try? await readGroup(id)).flatMap(PlatformDashConnectDataSource.groupOwnerForAttribution))
                        }
                        return (id, (try? await readContract(id)).flatMap(PlatformDashConnectDataSource.contractOwnerId))
                    }
                }
                var read: [Data: Data] = [:]
                for await (id, owner) in group {
                    read[id] = owner
                }
                return read
            }
            known.withLock { known in
                for (id, owner) in read { known[Key(network: network, id: id)] = owner }
            }
            PlatformDashConnectDataSource.logger.info(
                "🔗 DASHCONNECT :: owners read: \(unknown.count, privacy: .public), not read: \(unknown.count - read.count, privacy: .public)")
            owners.merge(read) { _, new in new }
            return owners
        }
    }

    /// Reads the owners wallet rule 3 compares from Platform. A group the
    /// network proves absent counts as not the app's; any other failure to
    /// read throws, so the sheet offers to try again. The caller's reads run
    /// off the main actor (`dataContractGetOffMain`; `getContractGroupInfo`
    /// is nonisolated), so the sheet stays responsive while they wait. Also
    /// returns the groups that have administrators, for the sheet.
    static func appConnectOwnership(
        _ plan: AppConnect.GrantPlan,
        readContract: (Data) async throws -> [String: Any],
        readGroup: (Data) async throws -> [String: Any]
    ) async throws -> (
        refusal: AppConnect.Refusal?,
        administeredGroupIds: Set<Data>,
        currentKeyRules: [KeyPurpose: AppConnect.CurrentKeyRule]
    ) {
        let app: [String: Any]
        do {
            app = try await readContract(plan.appId)
        } catch SDKError.notFound {
            return (AppConnect.Refusal(.invalid, NSLocalizedString(
                "The app's contract does not exist on this network.", comment: "DashConnect App Connect v2")), [], [:])
        }
        guard let appOwnerId = contractOwnerId(app) else {
            return (AppConnect.Refusal(.invalid, NSLocalizedString(
                "The app's contract has no readable owner.", comment: "DashConnect App Connect v2")), [], [:])
        }
        var groupOwners: [Data: Data] = [:]
        var administeredGroupIds: Set<Data> = []
        var contractOwners: [Data: Data] = [plan.appId: appOwnerId]
        var contracts: [Data: [String: Any]] = [plan.appId: app]
        for grant in plan.auth {
            let id = grant.binding.id
            switch grant.binding.kind {
            case .contractGroup:
                guard groupOwners[id] == nil else { continue }
                do {
                    let info = try await readGroup(id)
                    groupOwners[id] = groupOwnerId(info)
                    // Read as administered unless the proof shows none.
                    if (info["adminIds"] as? [Any])?.isEmpty != true { administeredGroupIds.insert(id) }
                } catch SDKError.notFound {
                    continue
                }
            case .singleContract, .documentType:
                let name = grant.binding.documentTypeName ?? ""
                guard contractOwners[id] == nil,
                      !AppConnect.allowedForeignDocumentTypes.contains("\(id.toBase58String())/\(name)") else { continue }
                // A contract the network proves absent has no owner, so
                // rule 3 refuses the request; any other failure throws.
                let contract: [String: Any]
                do {
                    contract = try await readContract(id)
                } catch SDKError.notFound {
                    continue
                }
                contracts[id] = contract
                contractOwners[id] = contractOwnerId(contract)
            }
        }
        // A contract whose config this build cannot read says nothing of its
        // key requirements, which is not the same as having none.
        let config = app["config"] as? [String: Any]
        var currentKeyRules: [KeyPurpose: AppConnect.CurrentKeyRule] = [:]
        var unreadableKeyPurposes: Set<KeyPurpose> = []
        for (purpose, field) in [
            (KeyPurpose.encryption, "requiresIdentityEncryptionBoundedKey"),
            (.decryption, "requiresIdentityDecryptionBoundedKey"),
        ] {
            guard let config else {
                unreadableKeyPurposes.insert(purpose)
                continue
            }
            switch AppConnect.keyRequirement(config[field]) {
            case .currentKey(let rule): currentKeyRules[purpose] = rule
            case .noCurrentKey: break
            case .unreadable: unreadableKeyPurposes.insert(purpose)
            }
        }
        let refusal = AppConnect.ownershipRefusal(
            for: plan,
            appOwnerId: appOwnerId,
            groupOwners: groupOwners,
            contractOwners: contractOwners,
            appBoundedKeyPurposes: Set(currentKeyRules.keys),
            appUnreadableKeyPurposes: unreadableKeyPurposes)
            ?? AppConnect.documentTypeRefusal(for: plan, contracts: contracts)
        return (refusal, administeredGroupIds, currentKeyRules)
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
        // The sheet was resolved for one identity of one wallet on one
        // network, and the login acts for that identity: it has to be
        // the active one here, and again after the PIN prompt. The same
        // wallet and identity under another devnet name is not what was
        // shown.
        guard consent.wasResolved(
            forIdentityId: context.identityId.toBase58String(), scope: context.stores.scope) else {
            Self.logger.error("🔗 DASHCONNECT :: the approved sign-in was resolved for another identity, wallet or network")
            throw DashConnectPlatformError.approvalOutOfDate
        }
        // The sheet showed the plan `makeConnectionRequest` resolved for
        // this request. The network has to still take App Connect.
        guard let appConnect = request.appConnect, let plan = consent.login.grantPlan else {
            throw DashConnectPlatformError.approvalOutOfDate
        }
        let protocolVersion: UInt32
        do {
            protocolVersion = try await Self.networkProtocolVersion(sdk: context.sdk, network: context.network)
        } catch {
            // The wallet cannot tell any more whether the network takes the
            // login the sheet offered. Nothing was signed.
            Self.logger.error("🔗 DASHCONNECT :: protocol version unknown — \(error.localizedDescription, privacy: .public)")
            throw DashConnectPlatformError.loginUnresolved
        }
        let requestHash = try KeyExchangeCrypto.hash160(appConnect.request.appEphemeralPubKey)
        let approvedLogin = AppConnect.isAvailable(protocolVersion: protocolVersion)
            && plan.appEphemeralPubKeyHash == requestHash
        guard approvedLogin else {
            Self.logger.error("🔗 DASHCONNECT :: the network now answers with another login than the one approved")
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
        Self.logger.info("🔗 DASHCONNECT :: authorized; App Connect request v2")
        return try await approveAppConnectV2Login(appConnect, plan: plan, consent: consent, context: context)
    }

    /// The protocol version a login is chosen by. An SDK pinned to a
    /// version (`SwiftDashSDKHost.platformVersion(for:)`) builds only that
    /// version's transitions, so its pin decides, with no network read. An
    /// unpinned one gets the network's version from a proved read of the
    /// current epoch, which throws when the read fails: the SDK's own
    /// refreshed number is not used, since a failed refresh leaves its
    /// starting value in place without an error.
    private static func networkProtocolVersion(sdk: SDK, network: Network) async throws -> UInt32 {
        let pin = await MainActor.run { SwiftDashSDKHost.platformVersion(for: network) }
        guard pin == 0 else { return pin }
        return try await DashConnectPlatformQueries.currentEpochProtocolVersion(sdk: sdk)
    }

    /// One read of the active identity: its keys from Platform, their bounds
    /// from the wallet's key store. A read behind one already seen in this
    /// process comes from a node that is behind, and throws
    /// `identityReadBehind`.
    private func identitySnapshot(
        context: Context
    ) async throws -> (snapshot: AppConnect.IdentitySnapshot, keys: [ManagedIdentity.IdentityPublicKeyInfo]) {
        let (keys, revision) = try await refreshedIdentityKeysAndRevision(context: context)
        let bindings = try Self.storedKeyBindings(
            identityId: context.identityId.toBase58String(), modelContainer: context.modelContainer)
        let read = AppConnect.IdentitySnapshot(
            identityId: context.identityId,
            revision: revision,
            keys: keys.map { key in
                AppConnect.platformKey(key, binding: bindings.first { $0.keyId == UInt32(bitPattern: key.keyId) })
            },
            // TODO(dashconnect-platform-time): proved block time arrives with
            // dashpay/platform#5715; until the app pins it no key is judged
            // expired.
            platformTime: nil)
        let newest = Self.newestSnapshots.withLock { $0[context.identityId] }
        guard read.mayReplace(newest) else {
            // The SDK's copy of the identity is now that older one too, so
            // nothing is built on it: the user tries again.
            Self.logger.error("🔗 DASHCONNECT :: the identity read is behind one already seen")
            throw DashConnectPlatformError.identityReadBehind
        }
        Self.newestSnapshots.withLock { $0[context.identityId] = read }
        return (read, keys)
    }

    /// Reads, changes and writes the intents in one step, from the store each
    /// time. Every caller runs inside `gated`, so no other operation of this
    /// wallet writes them in between.
    @discardableResult
    private func updateIntents<T>(in stores: Stores, _ change: (inout [AppConnect.ConnectionIntent]) -> T) -> T {
        var intents = stores.intents.load()
        let result = change(&intents)
        stores.intents.save(intents)
        return result
    }

    /// Where the owners a projection needs come from: what `memory` knows on
    /// `network`, and the rest read with `readContract` and `readGroup`.
    struct OwnerReader: Sendable {
        let network: String
        let memory: OwnerMemory
        let readContract: @Sendable (Data) async throws -> [String: Any]
        let readGroup: @Sendable (Data) async throws -> [String: Any]

        /// The owners the projection of `snapshot` needs that are known. An
        /// owner that could not be read is absent: unknown.
        func knownOwners(for snapshot: AppConnect.IdentitySnapshot, intents: [AppConnect.ConnectionIntent]) async -> [Data: Data] {
            let needed = AppConnect.ownerIdsNeeded(snapshot: snapshot, intents: intents)
            guard !needed.isEmpty else { return [:] }
            let groups = Set(snapshot.keys.compactMap { key -> Data? in
                guard case .contractGroup(let id) = key.bound else { return nil }
                return id
            }).intersection(needed)
            let started = ContinuousClock.now
            let owners = await memory.owners(
                contracts: needed.subtracting(groups), groups: groups, network: network,
                readContract: readContract, readGroup: readGroup)
            let elapsed = (ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds]))
            PlatformDashConnectDataSource.logger.info(
                "🔗 DASHCONNECT :: owners for the projection: \(owners.count, privacy: .public) of \(needed.count, privacy: .public) known, in \(elapsed, privacy: .public)")
            return owners
        }
    }

    /// Owners from the memory every data source shares, kept apart per
    /// wallet, network and endpoint (`ownerScope`), the rest read from
    /// Platform off the main actor.
    private static func ownerReader(context: Context) -> OwnerReader {
        let sdk = context.sdk
        return OwnerReader(
            network: ownerScope(context.stores.connections.scopeKey, context.stores.endpoint), memory: ownerMemory,
            readContract: { try await sdk.dataContractGetOffMain(id: $0.toBase58String()) },
            readGroup: { try await sdk.getContractGroupInfo(contractGroupId: $0.toBase58String()) })
    }

    /// The Platform an owner is remembered for, both halves from the stores
    /// the operation is pinned to: their scope, which names the network (and
    /// a devnet by name), and the endpoint it is reached at, since devnets of
    /// one name at other nodes are other chains.
    static func ownerScope(_ storeScope: String?, _ endpoint: String?) -> String {
        "\(storeScope ?? "") \(endpoint ?? "")"
    }

    /// The projection of `snapshot` with the owners it needs that are known.
    /// A key whose owner is unknown keeps its own row.
    static func projectWithOwners(
        _ snapshot: AppConnect.IdentitySnapshot, intents: [AppConnect.ConnectionIntent], owners: OwnerReader
    ) async -> AppConnect.Projection {
        let known = await owners.knownOwners(for: snapshot, intents: intents)
        return AppConnect.project([snapshot], intents: intents, owners: known)
    }

    /// What a disconnect of one app submits on one read of the identity, and
    /// what its result reports.
    struct PlannedDisconnect {
        var plan: AppConnect.DisconnectPlan
        /// The read it is planned on.
        var snapshot: AppConnect.IdentitySnapshot
        /// The keys it turns off: the app's, the listed unrecorded ones it
        /// still offers (`offered`), and the fences it adds.
        var appKeysOff: Int
        /// The unrecorded keys it offers to turn off, DashPay profile keys
        /// no intent names among them.
        var offered: Set<UInt32>
        var notChecked: Int
        var notAttributable: Int
        /// Offered keys the question did not list: they stay on.
        var leftAfterQuestion: Int
    }

    /// The disconnect of `appId` on `snapshot`, with the owners it needs
    /// that are known: none for an app with no intent on the identity, whose
    /// row keeps its contract's keys whatever their owner. `unrecordedKeyIds`:
    /// the keys the user's question listed, nil before the question; only
    /// those still offered are turned off. `fences`: the wallet's fence keys
    /// still live.
    static func plannedDisconnect(
        appId: Data, snapshot: AppConnect.IdentitySnapshot, intents: [AppConnect.ConnectionIntent],
        unrecordedKeyIds: Set<UInt32>?, fences: [UInt32], owners reader: OwnerReader
    ) async -> PlannedDisconnect {
        let hasIntent = intents.contains { $0.appId == appId && $0.identityId == snapshot.identityId }
        let owners = hasIntent ? await reader.knownOwners(for: snapshot, intents: intents) : [:]
        return plannedDisconnect(
            appId: appId, snapshot: snapshot, intents: intents, unrecordedKeyIds: unrecordedKeyIds, fences: fences,
            knownOwners: owners)
    }

    /// `plannedDisconnect` with owners already read (`knownOwners`), so a
    /// caller can plan and refresh the rows from the same owners.
    static func plannedDisconnect(
        appId: Data, snapshot: AppConnect.IdentitySnapshot, intents: [AppConnect.ConnectionIntent],
        unrecordedKeyIds: Set<UInt32>?, fences: [UInt32], knownOwners known: [Data: Data]
    ) -> PlannedDisconnect {
        let hasIntent = intents.contains { $0.appId == appId && $0.identityId == snapshot.identityId }
        let owners = hasIntent ? known : [:]
        var plan = AppConnect.disconnectPlan(
            appId: appId, snapshot: snapshot, intents: intents, owners: owners, listedUnrecordedKeyIds: unrecordedKeyIds)
        // DashPay profile keys no intent names are no one app's: no record
        // proves which app was given one, on this device or another. A
        // disconnect turns off everything that may be the app's, so they
        // are offered with any app's, on the user's confirm.
        let profileKeys = Set(AppConnect.project([snapshot], intents: intents, owners: owners)
            .unrecordedProfileKeyIds[snapshot.identityId] ?? [])
        let profileKeysOff = unrecordedKeyIds.map { profileKeys.intersection($0) } ?? []
        let appKeysOff = Set(plan.disable).union(profileKeysOff).count + plan.fence.count
        plan.disable = AppConnect.disableOrder(appKeyIds: plan.disable, otherKeyIds: Array(profileKeysOff) + fences)
        let offered = Set(plan.offeredUnrecorded).union(profileKeys)
        return PlannedDisconnect(
            plan: plan, snapshot: snapshot, appKeysOff: appKeysOff, offered: offered,
            notChecked: plan.notChecked.count, notAttributable: plan.notAttributable.count,
            leftAfterQuestion: unrecordedKeyIds.map { offered.subtracting($0).count } ?? 0)
    }

    /// Puts the App Connect rows of `stores` in step with what `snapshot`
    /// and the intents show.
    private func refreshRows(from snapshot: AppConnect.IdentitySnapshot, context: Context) async {
        let stores = context.stores
        let change = await Self.refreshedRows(
            snapshot: snapshot, intents: stores.intents.load(), owners: Self.ownerReader(context: context), at: now())
        await updateRows(in: stores, change)
    }

    /// The change a refresh makes to the stored rows: the projection of
    /// `snapshot` with the owners it needs that are known, applied to the
    /// rows as `rows(_:after:of:intents:at:)` does.
    static func refreshedRows(
        snapshot: AppConnect.IdentitySnapshot, intents all: [AppConnect.ConnectionIntent], owners: OwnerReader,
        at updatedAt: Date
    ) async -> ([DAppConnection]) -> [DAppConnection] {
        let projection = await projectWithOwners(snapshot, intents: all, owners: owners)
        let elsewhere = all.filter { $0.identityId != snapshot.identityId && $0.closedAt == nil }
        return { rows($0, after: projection, of: snapshot.identityId, intents: elsewhere, at: updatedAt) }
    }

    /// What a disconnect leaves on `after`, the read after its update: the
    /// change to the rows and what stays on (`remaining`), both from one read
    /// of the owners. Owners read apart could differ, a failed read being
    /// tried again, and the result could then name a row the list no longer
    /// has, or call a key unchecked that the rows place. After the question
    /// (`unrecordedKeyIds` set), every offered key still on is left on,
    /// listed or not: a listed key a failed owner read kept out of the
    /// update is on too. `holder`: another app whose row shows all those
    /// keys but the DashPay profile ones, which every disconnect offers, so
    /// the user can be sent there when the app's own row is gone and its
    /// disconnect offers every key the result counts.
    static func settledDisconnect(
        appId: Data, after: AppConnect.IdentitySnapshot, intents: [AppConnect.ConnectionIntent],
        unrecordedKeyIds: Set<UInt32>?, owners reader: OwnerReader, at updatedAt: Date
    ) async -> (rows: ([DAppConnection]) -> [DAppConnection], remaining: PlannedDisconnect, holder: Data?) {
        let known = await reader.knownOwners(for: after, intents: intents)
        let projection = AppConnect.project([after], intents: intents, owners: known)
        let elsewhere = intents.filter { $0.identityId != after.identityId && $0.closedAt == nil }
        var remaining = plannedDisconnect(
            appId: appId, snapshot: after, intents: intents, unrecordedKeyIds: unrecordedKeyIds, fences: [],
            knownOwners: known)
        if unrecordedKeyIds != nil { remaining.leftAfterQuestion = remaining.offered.count }
        let left = unrecordedKeyIds == nil ? [] : remaining.offered
        let appKeys = left.subtracting(projection.unrecordedProfileKeyIds[after.identityId] ?? [])
        let shown = appKeys.isEmpty ? left : appKeys
        let holder = shown.isEmpty ? nil : projection.connections.first {
            $0.appId != appId && shown.isSubset(of: $0.unrecordedKeyIds[after.identityId] ?? [])
        }?.appId
        return (
            { rows($0, after: projection, of: after.identityId, intents: elsewhere, at: updatedAt) },
            remaining, holder)
    }

    /// `rows` with the App Connect connections of `projection`, the read of
    /// `identityId`: an app with live keys or an update that may still land
    /// has a row; one whose keys are all off, or whose update never landed,
    /// has none, unless another identity's intents hold it or its last read
    /// saw keys there no approval names (`seenOn`). While the read has a key
    /// whose bound is unknown, that key may be any app's: no row goes, so
    /// each keeps its Disconnect until a read places every key.
    static func rows(
        _ rows: [DAppConnection],
        after projection: AppConnect.Projection,
        of identityId: Data,
        intents elsewhere: [AppConnect.ConnectionIntent],
        at updatedAt: Date
    ) -> [DAppConnection] {
        let me = identityId.toBase58String()
        func shownStatus(_ status: AppConnect.IntentStatus) -> ConnectionStatus? {
            switch status {
            case .active, .expired: return .active
            case .confirming: return .confirming
            case .disconnected, .neverLanded: return nil
            }
        }
        let shownIds = Set(projection.connections.filter { shownStatus($0.status) != nil }.map { $0.appId.toBase58String() })
        // An App Connect row stands for intents: it stays only while another
        // identity's intents hold it, since this read says nothing of them.
        let heldElsewhere = Set(elsewhere.map { $0.appId.toBase58String() })
        let hasUnplacedKey = projection.unplacedKeyIds[identityId]?.isEmpty == false
        var result: [DAppConnection] = rows.compactMap { row in
            guard !shownIds.contains(row.id) else { return nil }
            if hasUnplacedKey { return row }
            var seenOn = row.seenOn
            seenOn.remove(me)
            if heldElsewhere.contains(row.id) { return DAppConnection(row, seenOn: seenOn) }
            // Live keys seen on another identity: that is the access left.
            guard !seenOn.isEmpty else { return nil }
            return DAppConnection(row, status: .active, seenOn: seenOn, at: row.status == .active ? row.updatedAt : updatedAt)
        }
        for connection in projection.connections {
            let id = connection.appId.toBase58String()
            guard var status = shownStatus(connection.status) else { continue }
            if status == .active && connection.isUndelivered { status = .undelivered }
            let existing = rows.first { $0.id == id }
            let latest = connection.intents.first
            let fallback = DashConnectFallbackAppMetadata.resolve(contractId: id, unauthenticatedLabel: "")
            let name = latest?.appLabel ?? existing?.name ?? fallback.name
            var seenOn = existing?.seenOn ?? []
            seenOn.remove(me)
            if connection.unrecordedKeyIds[identityId]?.isEmpty == false { seenOn.insert(me) }
            result.removeAll { $0.id == id }
            result.append(DAppConnection(
                id: id,
                name: name.isEmpty ? NSLocalizedString("Unknown app", comment: "DashConnect") : name,
                url: latest?.appUrl ?? existing?.url ?? fallback.url,
                status: status,
                updatedAt: existing?.status == status ? existing?.updatedAt ?? updatedAt : updatedAt,
                seenOn: seenOn))
        }
        return result
    }

    /// App Connect request v2 (Yappr `docs/APP_CONNECT_PROFILE.md`): one key
    /// per auth binding, the identity's encryption key for the app, and the
    /// previous grant on the same connection disabled, all in one
    /// MASTER-signed identity update; then the sealed response is published
    /// once the keys show.
    ///
    /// The intent is written before the update is submitted and names every
    /// key it adds, so whatever happens to the update, the keys are found
    /// and can be turned off. A request is answered at most once: approving
    /// it again after it stopped is refused, and the app asks anew.
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
        guard stores.intents.canPersist else {
            throw DashConnectPlatformError.grantStoreUnavailable
        }
        guard !stores.intents.hasUnreadableRows(identityId: context.identityId) else {
            throw DashConnectPlatformError.intentsUnreadable
        }
        // The app stops looking for an answer ten minutes after it asked.
        guard uri.request.age(now: now()) == .fresh else {
            throw AppConnect.Refusal(.stale, NSLocalizedString(
                "This sign-in request has expired. Ask the app for a new one.",
                comment: "DashConnect App Connect v2"))
        }
        // A request is answered at most once, by any identity of the wallet:
        // approving it again is refused, whether the first attempt answered
        // it or stopped. A sealed response is never published by a later
        // attempt, as what it was sealed for may no longer hold. The app asks
        // again.
        guard !stores.intents.load().contains(where: {
            $0.appId == plan.appId && $0.requestHash == plan.appEphemeralPubKeyHash
        }) else {
            throw Self.spentRequest(after: nil)
        }
        let request = uri.request
        let signer = KeychainSigner(modelContainer: context.modelContainer)
        let (read, currentPublicKeys) = try await identitySnapshot(context: context)
        // From here on the read the intent was made from: a fence reads again.
        let (intent, snapshot) = try await newAppConnectIntent(
            request: request, plan: plan, consent: consent, snapshot: read,
            currentPublicKeys: currentPublicKeys, context: context)
        updateIntents(in: stores) { $0.append(intent) }
        guard stores.intents.load().contains(where: { $0.id == intent.id }) else {
            throw DashConnectPlatformError.grantNotRecorded
        }
        // The row goes with the intent, before anything is submitted: however
        // the update ends, the user can turn the connection off.
        await refreshRows(from: snapshot, context: context)
        do {
            try await submitAndPublish(
                intent, request: request, plan: plan, snapshot: snapshot, responseContractId: responseContractId,
                context: context, signer: signer)
        } catch {
            // The request is spent from here on: the row shows where it
            // stopped, and the app asks again.
            await settle(after: intent, responseContractId: responseContractId, context: context, signer: signer)
            throw Self.spentRequest(after: error)
        }
        await settle(after: intent, responseContractId: responseContractId, context: context, signer: signer)
        return Self.connection(consent: consent, at: now())
    }

    /// After an approval ends, however it ended: the earlier grants of the
    /// connection whose keys are off are done, and their responses go with
    /// them; the rows follow a fresh read.
    private func settle(
        after intent: AppConnect.ConnectionIntent, responseContractId: Data, context: Context, signer: KeychainSigner
    ) async {
        let stores = context.stores
        guard let read = try? await identitySnapshot(context: context).snapshot else {
            // The row is put right by the next read, at the latest when
            // Connections opens.
            Self.logger.info("🔗 DASHCONNECT :: identity not read after the approval; its row is refreshed later")
            return
        }
        let superseded = intent.connectionId.map { connectionId in
            stores.intents.load().filter {
                $0.id != intent.id && $0.identityId == context.identityId && $0.appId == intent.appId
                    && $0.connectionId == connectionId
                    && $0.closedAt == nil && [.disconnected, .neverLanded].contains(AppConnect.status(of: $0, in: read))
            }
        } ?? []
        let ids = Set(superseded.map(\.id))
        if !ids.isEmpty {
            let closedAt = now()
            updateIntents(in: stores) { intents in
                for index in intents.indices where ids.contains(intents[index].id) { intents[index].closedAt = closedAt }
            }
        }
        let toDelete = ids.union(AppConnect.responsesLeft(identityId: context.identityId, intents: stores.intents.load()))
        if !toDelete.isEmpty {
            await deleteResponses(of: Array(toDelete), responseContractId: responseContractId, context: context, signer: signer)
        }
        await refreshRows(from: read, context: context)
    }

    /// Submits the new intent's update and publishes its sealed response,
    /// once a read shows the update and the keys it carries still hold.
    private func submitAndPublish(
        _ intent: AppConnect.ConnectionIntent,
        request: AppConnectRequest,
        plan: AppConnect.GrantPlan,
        snapshot: AppConnect.IdentitySnapshot,
        responseContractId: Data,
        context: Context,
        signer: KeychainSigner
    ) async throws {
        let landed = try await submitIntent(
            intent, request: request, plan: plan, snapshot: snapshot, context: context, signer: signer)
        let stores = context.stores
        guard stores.intents.load().first(where: { $0.id == intent.id })?.closedAt == nil else {
            throw DashConnectPlatformError.sessionKeyUnusable
        }
        // The response carries the keys' secrets. Its keys may hold no more
        // than the sheet showed, none may have been turned off meanwhile, and
        // each encryption key must still be the app's current one. The
        // identity is read again for it, until a read shows the update (a node
        // may be behind); when none does, nothing is published. A read that
        // already showed the update is the one checked: what it saw stands,
        // as a later read may be behind and show less.
        let current: AppConnect.IdentitySnapshot
        if let landed {
            current = landed
        } else {
            current = try await readShowingUpdate(of: intent, context: context)
        }
        guard AppConnect.landedKeysWithinPlan(intent, plan, in: current),
              AppConnect.authKeysUsable(intent, in: current) else {
            throw DashConnectPlatformError.sessionKeyUnusable
        }
        guard AppConnect.encryptionKeysUsable(intent, in: current),
              try await encryptionKeysAreCurrent(of: intent, in: current, context: context) else {
            throw DashConnectPlatformError.appConnectEncryptionKeyChanged
        }
        try await publishResponse(of: intent, responseContractId: responseContractId, context: context, signer: signer)
    }

    /// Records the response of each open intent whose keys are live but
    /// whose response this wallet did not record publishing: a publish can
    /// land without confirming, and its row would show "Not delivered".
    private func recordPublishedResponses(in snapshot: AppConnect.IdentitySnapshot, context: Context) async {
        guard let responseContractId = Self.decodeIdentifier(AppConnect.contractId) else { return }
        // A publish lands within the approval that made it, minutes after
        // the request; an intent a day old has nothing more to find.
        let since = now().addingTimeInterval(-24 * 60 * 60)
        let unrecorded = context.stores.intents.load().filter { intent in
            guard intent.identityId == snapshot.identityId, intent.closedAt == nil, intent.responseDocumentId == nil,
                  intent.createdAt > since, case .active = AppConnect.status(of: intent, in: snapshot) else { return false }
            return true
        }
        guard !unrecorded.isEmpty else { return }
        let identityId = context.identityId
        let sdk = context.sdk
        let found = await withTaskGroup(of: (UUID, Data)?.self) { group in
            for intent in unrecorded {
                group.addTask {
                    guard let published = try? await Self.findAppConnectResponse(
                        ownerIdentityId: identityId, appEphemeralPubKeyHash: intent.requestHash,
                        responseContractId: responseContractId, sdk: sdk) else { return nil }
                    return (intent.id, published.documentId)
                }
            }
            return await group.reduce(into: [UUID: Data]()) { found, pair in
                if let pair { found[pair.0] = pair.1 }
            }
        }
        guard !found.isEmpty else { return }
        Self.logger.info("🔗 DASHCONNECT :: \(found.count, privacy: .public) response(s) published without confirming were found")
        for (id, documentId) in found { recordResponse(documentId, of: id, in: context.stores) }
    }

    /// A read of the identity that shows `intent`'s update (`hasLanded`). A
    /// node may be behind: reads a few seconds apart are tried, and when none
    /// shows it `identityReadBehind`, or the read's failure, is thrown.
    private func readShowingUpdate(
        of intent: AppConnect.ConnectionIntent, context: Context
    ) async throws -> AppConnect.IdentitySnapshot {
        var readFailure: Error?
        for attempt in 0 ... 2 {
            if attempt > 0 { await Self.pauseForLaggingNode(attempt) }
            do {
                let read = try await identitySnapshot(context: context).snapshot
                readFailure = nil
                if AppConnect.hasLanded(intent, in: read) { return read }
            } catch {
                Self.logger.error("🔗 DASHCONNECT :: identity not read while looking for the update — \(error.localizedDescription, privacy: .public)")
                readFailure = error
            }
        }
        if let readFailure { throw readFailure }
        Self.logger.error("🔗 DASHCONNECT :: no read shows the identity update")
        throw DashConnectPlatformError.identityReadBehind
    }

    /// The error of a request that cannot be approved again: what stopped
    /// it, when that says something the user can act on, and that the app has
    /// to ask anew. A refusal with the `failed` status, so the sheet offers no
    /// Approve and the app is told the request failed. Causes whose own text
    /// would advise trying again are logged, not shown.
    private static func spentRequest(after cause: Error?) -> AppConnect.Refusal {
        let spent = DashConnectPlatformError.sessionKeyUnusable.localizedDescription
        guard let cause else { return AppConnect.Refusal(.failed, spent) }
        logger.error("🔗 DASHCONNECT :: the request is spent — \(cause.localizedDescription, privacy: .public)")
        // A refusal says what to do itself (update the wallet, for one).
        if let refusal = cause as? AppConnect.Refusal { return refusal }
        let platformError = cause as? DashConnectPlatformError
        // Its own text already sends the user to the app.
        if platformError == .appConnectEncryptionKeyChanged { return AppConnect.Refusal(.failed, cause.localizedDescription) }
        let retrying: [DashConnectPlatformError] = [
            .sessionKeyUnusable, .identityReadBehind, .approvalOutOfDate, .appConnectKeysOutOfDate, .appConnectKeysUnreadable,
            .walletChanged, .identityKeysOutOfDate,
        ]
        if cause is CancellationError || platformError.map(retrying.contains) == true {
            return AppConnect.Refusal(.failed, spent)
        }
        return AppConnect.Refusal(.failed, "\(cause.localizedDescription) \(spent)")
    }

    /// The row an answered approval shows.
    private static func connection(consent: ConnectionRequest, at updatedAt: Date) -> DAppConnection {
        DAppConnection(
            id: consent.appContractId,
            name: consent.appLabel.isEmpty ? NSLocalizedString("Unknown app", comment: "DashConnect") : consent.appLabel,
            url: consent.appUrl,
            status: .active,
            updatedAt: updatedAt)
    }

    /// The intent of a new approval: the keys it adds under ids no key or
    /// intent of the identity holds, the earlier keys of the same connection
    /// it turns off, and the response, sealed now. With it comes the read
    /// the intent was made from: the read after a fence, when it fenced.
    private func newAppConnectIntent(
        request: AppConnectRequest,
        plan: AppConnect.GrantPlan,
        consent: ConnectionRequest,
        snapshot: AppConnect.IdentitySnapshot,
        currentPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        context: Context
    ) async throws -> (intent: AppConnect.ConnectionIntent, snapshot: AppConnect.IdentitySnapshot) {
        let stores = context.stores
        var authKeys = try await deriveAuthKeys(request: request, plan: plan, context: context)
        defer { for index in authKeys.indices { Self.zero(&authKeys[index].privateKey) } }
        // A derived key already on the identity with no intent of this
        // request: an answer this wallet no longer has a record of. Platform
        // never adds a key twice, so the app has to ask again.
        guard !authKeys.contains(where: { key in currentPublicKeys.contains { $0.data == key.publicKeyHash160 } }) else {
            throw DashConnectPlatformError.sessionKeyUnusable
        }
        var encryption = try await encryptionSlots(plan: plan, currentPublicKeys: currentPublicKeys, context: context)
        defer { for index in encryption.indices { Self.zero(&encryption[index].privateKey) } }

        // Wallet rule 8: this connection's earlier grants go in the same
        // update. More than one update can turn off is refused before
        // anything is written. An earlier grant whose update may still land
        // is fenced first, so it cannot add keys this one replaces.
        let intents = stores.intents.load()
        let supersession = plan.connectionId.map { connectionId in
            AppConnect.disconnectPlan(
                appId: plan.appId, snapshot: snapshot,
                intents: intents.filter { $0.connectionId == connectionId },
                owners: [:], listedUnrecordedKeyIds: nil)
        } ?? AppConnect.DisconnectPlan()
        let superseded = supersession.disable
        guard superseded.count <= AppConnect.maxKeysDisabledPerUpdate else {
            throw DashConnectPlatformError.tooManyKeysToReplace
        }
        let newCount = authKeys.count + encryption.filter { $0.keyId == nil }.count
        guard newCount <= AppConnect.maxKeysAddedPerUpdate else {
            throw DashConnectPlatformError.tooManyKeysToAdd
        }
        var snapshot = snapshot
        if !supersession.fence.isEmpty {
            try await fenceAndDisable(
                AppConnect.DisconnectPlan(fence: supersession.fence), context: context,
                signer: KeychainSigner(modelContainer: context.modelContainer))
            snapshot = try await identitySnapshot(context: context).snapshot
            let fenced = snapshot
            let closedAt = now()
            updateIntents(in: stores) { intents in
                for index in intents.indices where intents[index].closedAt == nil
                    && intents[index].identityId == context.identityId
                    && AppConnect.status(of: intents[index], in: fenced) == .neverLanded {
                    intents[index].closedAt = closedAt
                }
            }
        }

        guard var ids = AppConnect.newKeyIds(count: newCount, snapshot: snapshot, intents: intents)?.makeIterator() else {
            throw DashConnectPlatformError.noFreeKeyId
        }
        var keys: [AppConnect.IntendedKey] = []
        for (grant, key) in zip(plan.auth, authKeys) {
            guard let id = ids.next() else { throw DashConnectPlatformError.noFreeKeyId }
            keys.append(AppConnect.IntendedKey(
                id: id, purpose: .authentication, securityLevel: grant.securityLevel, keyType: .ecdsaHash160,
                data: key.publicKeyHash160, readOnly: false, bound: grant.storedBound,
                totalBudget: grant.totalBudget, expiresAt: grant.expiresAt))
        }
        for index in encryption.indices where encryption[index].keyId == nil {
            guard let id = ids.next() else { throw DashConnectPlatformError.noFreeKeyId }
            let grant = plan.encryption[encryption[index].grantIndex]
            let pubkey = AppConnect.encryptionIdentityPubkey(grant, keyId: id, publicKey: encryption[index].publicKey)
            keys.append(AppConnect.IntendedKey(
                id: id, purpose: pubkey.purpose, securityLevel: pubkey.securityLevel, keyType: pubkey.keyType,
                data: pubkey.pubkeyBytes, readOnly: pubkey.readOnly,
                bound: pubkey.contractBounds.map(AppConnect.storedBound(of:)),
                totalBudget: nil, expiresAt: nil))
            encryption[index].keyId = id
        }

        // Slots: the auth keys in request order, then the encryption keys
        // that are sent.
        var slots = authKeys.map(\.privateKey) + encryption.map(\.privateKey)
        defer { for index in slots.indices { Self.zero(&slots[index]) } }
        var walletEphemeralPrivateKey = try Self.generateEphemeralPrivateKey()
        defer { Self.zero(&walletEphemeralPrivateKey) }
        let response = AppConnect.ResponseValues(
            appEphemeralPubKeyHash: plan.appEphemeralPubKeyHash.toHexString(),
            walletEphemeralPubKey: try Secp256k1.compressedPublicKey(privateKey: walletEphemeralPrivateKey).toHexString(),
            encryptedPayload: try KeyExchangeCrypto.encryptAppConnectSlots(
                slots,
                walletEphemeralPriv: walletEphemeralPrivateKey,
                appEphemeralPub: request.appEphemeralPubKey,
                ownerId: context.identityId
            ).toHexString()
        )
        let added = Set(keys.map(\.id))
        let intent = AppConnect.ConnectionIntent(
            id: UUID(),
            identityId: context.identityId,
            appId: plan.appId,
            appLabel: consent.appLabel,
            appUrl: consent.appUrl,
            requestHash: plan.appEphemeralPubKeyHash,
            connectionId: plan.connectionId,
            keys: keys,
            sentEncryptionKeyIds: encryption.compactMap(\.keyId).filter { !added.contains($0) },
            disables: superseded,
            response: response,
            responseDocumentId: nil,
            responseRemoved: false,
            createdAt: now(),
            closedAt: nil)
        return (intent, snapshot)
    }

    /// The auth keys of `plan`, derived from the request: the same keys on
    /// every try of one request.
    private func deriveAuthKeys(
        request: AppConnectRequest,
        plan: AppConnect.GrantPlan,
        context: Context
    ) async throws -> [(publicKeyHash160: Data, privateKey: Data)] {
        var keys: [(publicKeyHash160: Data, privateKey: Data)] = []
        do {
            for grant in plan.auth {
                let leaf = AppConnect.authKeyLeaf(
                    appEphemeralPubKey: request.appEphemeralPubKey, bindingIndex: grant.bindingIndex)
                // `deriveConnectKey` is main-actor isolated in the SDK. Only
                // the two buffers leave the closure.
                let (publicKey, derivedPrivateKey) = try await MainActor.run {
                    let key = try context.wallet.deriveConnectKey(
                        subFeature: .sessionAuthentication, identityId: context.identityId, leaf: leaf, network: context.network)
                    return (key.publicKeyData, key.privateKeyData)
                }
                var privateKey = derivedPrivateKey
                defer { Self.zero(&privateKey) }
                keys.append((try KeyExchangeCrypto.hash160(publicKey), privateKey))
            }
        } catch {
            for index in keys.indices { Self.zero(&keys[index].privateKey) }
            throw error
        }
        return keys
    }

    /// One encryption slot of a response: the grant it answers, the key it
    /// carries and that key's id, nil until the update that adds it is
    /// built.
    private struct EncryptionSlotKey {
        let grantIndex: Int
        let publicKey: Data
        var privateKey: Data
        var keyId: UInt32?
    }

    /// Wallet rule 7 (DIP "Encryption Keys"): re-send the identity's current
    /// key for the app when this wallet derives it, at any rotation or
    /// (testnet and devnet) the path without one; register rotation 0' only
    /// when the identity has no key for the app at all; leave the slot out
    /// otherwise. Which key is current is Platform's to say: the app's
    /// verifier checks the slot against the same proved read.
    private func encryptionSlots(
        plan: AppConnect.GrantPlan,
        currentPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        context: Context
    ) async throws -> [EncryptionSlotKey] {
        guard !plan.encryption.isEmpty else { return [] }
        let identityId = context.identityId.toBase58String()
        let appId = plan.appId.toBase58String()
        let sdk = context.sdk
        let purposes = Set(plan.encryption.map(\.keyPurpose)).sorted { $0.rawValue < $1.rawValue }
        func readCurrentKeys() async throws -> [KeyPurpose: AppConnect.CurrentContractKey] {
            try await Self.readCurrentContractKeys(sdk: sdk, identityId: identityId, appId: appId, purposes: purposes)
        }

        var derived: [[AppConnect.DerivedEncryptionKey]] = []
        defer {
            for grant in derived.indices {
                for index in derived[grant].indices { Self.zero(&derived[grant][index].privateKey) }
            }
        }
        for grant in plan.encryption {
            derived.append(try await MainActor.run {
                try Self.derivableEncryptionKeys(
                    for: grant, wallet: context.wallet, identityId: context.identityId,
                    network: context.network, currentIdentityPublicKeys: currentPublicKeys)
            })
        }
        let bindings = try Self.storedKeyBindings(identityId: identityId, modelContainer: context.modelContainer)

        var firstRead: [KeyPurpose: AppConnect.CurrentContractKey]?
        var failure: Error?
        for attempt in 0 ... 2 where firstRead == nil && !(failure.map(Self.isUnreadableAnswer) ?? false) {
            if attempt > 0 { await Self.pauseForLaggingNode(attempt) }
            do { firstRead = try await readCurrentKeys() } catch { failure = error }
        }
        guard let currentKeys = firstRead else {
            throw Self.failedCurrentKeyRead(failure ?? DashConnectPlatformError.appConnectKeysUnreadable)
        }
        func states(_ currentKeys: [KeyPurpose: AppConnect.CurrentContractKey]) throws -> [AppConnect.EncryptionKeyState] {
            try plan.encryption.enumerated().map { index, grant in
                guard let rule = plan.currentKeyRules[grant.keyPurpose] else {
                    throw DashConnectPlatformError.approvalOutOfDate
                }
                return AppConnect.encryptionKeyState(
                    derivedPublicKeys: derived[index].map(\.publicKey),
                    purpose: grant.keyPurpose,
                    contractId: grant.binding.contractId,
                    rule: rule,
                    currentKey: currentKeys[grant.keyPurpose],
                    currentIdentityPublicKeys: currentPublicKeys,
                    bindings: bindings)
            }
        }
        // A state that holds only if Platform's read is not behind holds
        // once a read a few seconds later says the same.
        let keyStates: [AppConnect.EncryptionKeyState]
        do {
            keyStates = try await AppConnect.settle(
                currentKeys: currentKeys, states: states, reread: readCurrentKeys, pause: Self.pauseForLaggingNode,
                isFinal: Self.isUnreadableAnswer)
        } catch let error as DashConnectPlatformError {
            throw error
        } catch let refusal as AppConnect.Refusal {
            throw refusal
        } catch {
            throw Self.failedCurrentKeyRead(error)
        }
        var slots: [EncryptionSlotKey] = []
        for (index, state) in keyStates.enumerated() {
            switch AppConnect.encryptionSlot(
                for: state, derivedPublicKeys: derived[index].map(\.publicKey), currentIdentityPublicKeys: currentPublicKeys
            ) {
            case .send(let keyId, let derivedIndex):
                slots.append(EncryptionSlotKey(
                    grantIndex: index, publicKey: derived[index][derivedIndex].publicKey,
                    privateKey: derived[index][derivedIndex].privateKey, keyId: keyId))
            case .register:
                slots.append(EncryptionSlotKey(
                    grantIndex: index, publicKey: derived[index][0].publicKey,
                    privateKey: derived[index][0].privateKey, keyId: nil))
            case .omit:
                Self.logger.info("🔗 DASHCONNECT :: the app's encryption key on this identity is not this wallet's, or none is live; slot left out")
            case nil:
                Self.logger.error("🔗 DASHCONNECT :: the identity's keys and Platform's current encryption key disagree")
                throw DashConnectPlatformError.appConnectKeysOutOfDate
            }
        }
        return slots
    }

    /// The current key Platform names for `identityId`, the app and each
    /// purpose.
    private static func readCurrentContractKeys(
        sdk: SDK, identityId: String, appId: String, purposes: [KeyPurpose]
    ) async throws -> [KeyPurpose: AppConnect.CurrentContractKey] {
        let response = try await DashConnectPlatformQueries.identityContractKeys(
            sdk: sdk, identityId: identityId, contractId: appId, purposes: purposes)
        var keys: [KeyPurpose: AppConnect.CurrentContractKey] = [:]
        for purpose in purposes {
            keys[purpose] = try AppConnect.currentContractKey(from: response, identityId: identityId, purpose: purpose)
        }
        return keys
    }

    /// An answer this build cannot read reads the same on every try.
    private static func isUnreadableAnswer(_ error: Error) -> Bool {
        if let sdkError = error as? SDKError, case .serializationError = sdkError { return true }
        return false
    }

    private static func failedCurrentKeyRead(_ error: Error) -> Error {
        logger.error("🔗 DASHCONNECT :: the app's current encryption keys could not be read — \(error.localizedDescription, privacy: .public)")
        guard isUnreadableAnswer(error) else { return DashConnectPlatformError.appConnectKeysUnreadable }
        return AppConnect.Refusal(.unsupported, NSLocalizedString(
            "This version of the wallet cannot read the network's answer about your identity's encryption key for this app. Update the wallet.",
            comment: "DashConnect App Connect v2"))
    }

    /// A node one block behind has usually caught up within a second; one
    /// that has not gets longer.
    private static func pauseForLaggingNode(_ attempt: Int) async {
        try? await Task.sleep(nanoseconds: attempt == 1 ? 1_000_000_000 : 3_000_000_000)
    }

    /// Whether each encryption key `intent`'s response carries is the one
    /// Platform names current for the app and its purpose, and no key is
    /// current yet for one it is still to register: the app's verifier
    /// refuses any other. Another key current, or this one off, is a "no"
    /// at once, whatever a later read says. No key current yet for one the
    /// identity shows may be a node that is behind: it is read again, a key
    /// one read showed current stays so, and one no read shows current
    /// throws `appConnectKeysOutOfDate`. Throws the read's failure when no
    /// read answered, or when an answer cannot be read.
    private func encryptionKeysAreCurrent(
        of intent: AppConnect.ConnectionIntent, in snapshot: AppConnect.IdentitySnapshot, context: Context
    ) async throws -> Bool {
        let expected = AppConnect.expectedCurrentEncryptionKeys(of: intent, in: snapshot)
        guard !expected.isEmpty else { return true }
        let identityId = context.identityId.toBase58String()
        let purposes = expected.keys.sorted { $0.rawValue < $1.rawValue }
        let all = expected.flatMap { purpose, keys in keys.map { (purpose, $0) } }
        var matched = Set<Int>()
        var answered = false
        var failure: Error?
        for attempt in 0 ... 2 {
            if attempt > 0 { await Self.pauseForLaggingNode(attempt) }
            do {
                let current = try await Self.readCurrentContractKeys(
                    sdk: context.sdk, identityId: identityId, appId: intent.appId.toBase58String(), purposes: purposes)
                answered = true
                for (index, (purpose, key)) in all.enumerated() {
                    switch AppConnect.check(current[purpose], against: key) {
                    case .differs: return false
                    case .matches: matched.insert(index)
                    case .notYet: break
                    }
                }
                if matched.count == all.count { return true }
            } catch {
                failure = error
                if Self.isUnreadableAnswer(error) { throw Self.failedCurrentKeyRead(error) }
            }
        }
        if !answered, let failure { throw Self.failedCurrentKeyRead(failure) }
        throw DashConnectPlatformError.appConnectKeysOutOfDate
    }

    /// Submits what of `intent` is not on the identity yet, and returns once
    /// every key it adds shows and every key it turns off is off. An update
    /// that reports a failure may still have landed: the identity is read
    /// again, and if it does not show the intent the intent stays, shown as
    /// confirming, and the failure stands. Returns the read that showed the
    /// update when the update itself did not confirm, else nil.
    private func submitIntent(
        _ intent: AppConnect.ConnectionIntent,
        request: AppConnectRequest,
        plan: AppConnect.GrantPlan,
        snapshot: AppConnect.IdentitySnapshot,
        context: Context,
        signer: KeychainSigner
    ) async throws -> AppConnect.IdentitySnapshot? {
        let missing = intent.keys.filter { AppConnect.presence(of: $0, in: snapshot) == .missing }
        let disable = AppConnect.outstandingDisables(of: intent, in: snapshot)

        // The private keys of the auth keys to add, derived again from the
        // request, and of the encryption keys, from the wallet.
        var signingKeys: [(publicKey: Data, privateKey: Data)] = []
        defer { for index in signingKeys.indices { Self.zero(&signingKeys[index].privateKey) } }
        // Intent auth keys are in the order of the plan's bindings.
        let bindingIndexes = Dictionary(uniqueKeysWithValues: zip(intent.authKeys.map(\.id), plan.auth.map(\.bindingIndex)))
        for key in missing where key.isAuthentication {
            guard let index = bindingIndexes[key.id] else { throw DashConnectPlatformError.approvalOutOfDate }
            let leaf = AppConnect.authKeyLeaf(appEphemeralPubKey: request.appEphemeralPubKey, bindingIndex: index)
            let (publicKey, derivedPrivateKey) = try await MainActor.run {
                let derived = try context.wallet.deriveConnectKey(
                    subFeature: .sessionAuthentication, identityId: context.identityId, leaf: leaf, network: context.network)
                return (derived.publicKeyData, derived.privateKeyData)
            }
            var privateKey = derivedPrivateKey
            defer { Self.zero(&privateKey) }
            guard try KeyExchangeCrypto.hash160(publicKey) == key.data else { throw DashConnectPlatformError.approvalOutOfDate }
            signingKeys.append((key.data, privateKey))
        }
        for key in missing where !key.isAuthentication {
            guard let grant = plan.encryption.first(where: {
                $0.keyPurpose == key.purpose && key.bound.map(AppConnect.contractId(of:)) == $0.binding.contractId
            }) else {
                throw DashConnectPlatformError.approvalOutOfDate
            }
            var candidates = try await MainActor.run {
                try Self.derivableEncryptionKeys(
                    for: grant, wallet: context.wallet, identityId: context.identityId,
                    network: context.network, currentIdentityPublicKeys: try context.wallet
                        .managedIdentity(identityId: context.identityId).getPublicKeys())
            }
            defer { for index in candidates.indices { Self.zero(&candidates[index].privateKey) } }
            guard let match = candidates.first(where: { $0.publicKey == key.data }) else {
                throw DashConnectPlatformError.approvalOutOfDate
            }
            signingKeys.append((key.data, match.privateKey))
        }

        Self.logger.info("🔗 DASHCONNECT :: registering \(missing.count, privacy: .public) key(s), disabling \(disable.count, privacy: .public)")
        do {
            try await signer.withAdditionalSigningKeys(signingKeys) {
                try await context.wallet.updateIdentity(
                    identityId: context.identityId,
                    addPublicKeys: missing.map(AppConnect.identityPubkey(of:)),
                    disablePublicKeyIds: disable,
                    signer: signer)
            }
        } catch {
            // The update may have landed without confirming. Its keys
            // decide; nothing else does.
            guard let read = try? await readShowingUpdate(of: intent, context: context) else { throw error }
            Self.logger.info("🔗 DASHCONNECT :: the identity update landed without confirming")
            return read
        }
        Self.logger.info("🔗 DASHCONNECT :: identity updated")
        return nil
    }

    /// Publishes the response `intent` sealed. A publish can land without
    /// confirming, and the response is unique per request and identity, so
    /// a failed one is checked against Platform.
    private func publishResponse(
        of intent: AppConnect.ConnectionIntent,
        responseContractId: Data,
        context: Context,
        signer: KeychainSigner
    ) async throws {
        Self.logger.info("🔗 DASHCONNECT :: publishing loginKeyResponse")
        let documentId: Data
        do {
            (documentId, _) = try await context.wallet.createDocument(
                ownerIdentityId: context.identityId,
                contractId: responseContractId,
                documentType: AppConnect.documentType,
                propertiesJSON: try intent.response.propertiesJSON(),
                signer: signer)
            Self.logger.info("🔗 DASHCONNECT :: loginKeyResponse published")
        } catch {
            guard let published = try? await Self.findAppConnectResponse(
                ownerIdentityId: context.identityId,
                appEphemeralPubKeyHash: intent.requestHash,
                responseContractId: responseContractId,
                sdk: context.sdk
            ) else {
                throw error
            }
            Self.logger.info("🔗 DASHCONNECT :: loginKeyResponse was already published")
            documentId = published.documentId
        }
        recordResponse(documentId, of: intent.id, in: context.stores)
    }

    /// Records that the response of the intent `id` is on Platform.
    private func recordResponse(_ documentId: Data, of id: UUID, in stores: Stores) {
        updateIntents(in: stores) { intents in
            guard let index = intents.firstIndex(where: { $0.id == id }) else { return }
            intents[index].responseDocumentId = documentId
            intents[index].responseRemoved = false
        }
    }

    /// Deletes, by its original values, the response of each intent in `ids`
    /// that may be on Platform. Best effort: one that cannot be deleted now
    /// stays marked and is tried again by the next disconnect or approval on
    /// the identity (`AppConnect.responsesLeft`).
    private func deleteResponses(
        of ids: [UUID],
        responseContractId: Data,
        context: Context,
        signer: KeychainSigner
    ) async {
        for intent in context.stores.intents.load() where ids.contains(intent.id) && !intent.responseRemoved {
            do {
                // Deleted by the values it has on Platform, which are this
                // intent's unless another install answered the same request.
                guard let found = try await Self.findAppConnectResponse(
                    ownerIdentityId: context.identityId,
                    appEphemeralPubKeyHash: intent.requestHash,
                    responseContractId: responseContractId,
                    sdk: context.sdk
                ) else {
                    markResponseRemoved(intent.id, in: context.stores)
                    continue
                }
                let signingKeyId = try selectDocumentSigningKeyId(wallet: context.wallet, identityId: context.identityId)
                _ = try await context.wallet.deleteDocument(
                    ownerIdentityId: context.identityId,
                    contractId: responseContractId,
                    documentType: AppConnect.documentType,
                    documentId: found.documentId,
                    propertiesJSON: try found.values.propertiesJSON(),
                    signingKeyId: signingKeyId,
                    signer: signer)
                markResponseRemoved(intent.id, in: context.stores)
            } catch {
                Self.logger.error("🔗 DASHCONNECT :: loginKeyResponse not deleted — \(error.localizedDescription, privacy: .public)")
                // A delete can land without confirming; only Platform says.
                // A lookup that fails says nothing.
                do {
                    let remaining = try await Self.findAppConnectResponse(
                        ownerIdentityId: context.identityId,
                        appEphemeralPubKeyHash: intent.requestHash,
                        responseContractId: responseContractId,
                        sdk: context.sdk)
                    if remaining == nil { markResponseRemoved(intent.id, in: context.stores) }
                } catch {
                    continue
                }
            }
        }
    }

    private func markResponseRemoved(_ id: UUID, in stores: Stores) {
        updateIntents(in: stores) { intents in
            guard let index = intents.firstIndex(where: { $0.id == id }) else { return }
            intents[index].responseRemoved = true
        }
    }

    /// This identity's response to one request, with the values it has on
    /// Platform, or `nil` when there is none; a failed lookup or a response
    /// that cannot be read throws.
    private static func findAppConnectResponse(
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
        case .tokenPurchase(let purchase):
            return .tokenPurchaseApprovalRequired(
                try await makeTokenPurchaseRequest(purchase, context: context)
            )
        }
    }

    /// The context to go on with after a wait — a PIN prompt, a turn at
    /// the operation gate — which can outlast a wallet, network or identity
    /// switch: what is active now, and only while it is still the identity,
    /// the wallet and the network scope of `context`.
    private func contextAfterAuthorization(matching context: Context) async throws -> Context {
        let authorized = try await requireContext(pinnedTo: context.stores)
        guard authorized.identityId == context.identityId else {
            throw DashConnectPlatformError.walletChanged
        }
        return authorized
    }

    /// What is active now, only while it is the wallet and the network
    /// scope `stores` belongs to, and carrying that pair. The same wallet on
    /// another devnet is refused: its identity and SDK are that devnet's,
    /// and the records would go to this one's.
    private func requireContext(pinnedTo stores: Stores) async throws -> Context {
        var context = try await requireContext()
        guard context.stores.scope == stores.scope else {
            throw DashConnectPlatformError.walletChanged
        }
        context.stores = stores
        return context
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

    func refreshConnections() async {
        do {
            try await gated {
                guard let stores = await showActiveWalletRows() else { return }
                let context = try await requireContext(pinnedTo: stores)
                let snapshot = try await identitySnapshot(context: context).snapshot
                await recordPublishedResponses(in: snapshot, context: context)
                await refreshRows(from: snapshot, context: context)
            }
        } catch {
            Self.logger.info("🔗 DASHCONNECT :: connections not refreshed — \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func disconnect(id: String, scope: String?, unrecordedKeys: DashConnectOfferedKeys?) async throws -> DashConnectDisconnectResult {
        try await gated { try await disconnectInTurn(id: id, scope: scope, unrecordedKeys: unrecordedKeys) }
    }

    private func disconnectInTurn(
        id: String,
        scope: String?,
        unrecordedKeys: DashConnectOfferedKeys?
    ) async throws -> DashConnectDisconnectResult {
        guard let stores = await showActiveWalletRows() else {
            throw DashConnectPlatformError.noWallet
        }
        // The row names the wallet it was published for. When that is not
        // the wallet that is active now, nothing of the row's wallet can be
        // turned off from here.
        guard scope == stores.scope else {
            throw DashConnectPlatformError.walletChanged
        }
        guard let appId = Self.decodeIdentifier(id) else {
            throw DashConnectPlatformError.loginContractUnavailable
        }
        var context = try await requireContext(pinnedTo: stores)
        // An intent this build cannot read may name keys of the app that are
        // still to land: nothing is turned off until it can be read.
        guard !stores.intents.hasUnreadableRows(identityId: context.identityId) else {
            throw DashConnectPlatformError.intentsUnreadable
        }
        try Self.requireOffered(unrecordedKeys, on: context.identityId)
        let unrecordedKeyIds = unrecordedKeys?.keyIds
        var planned = try await disconnectPlan(appId: appId, unrecordedKeyIds: unrecordedKeyIds, context: context)
        // The PIN is asked for only when there is something to sign.
        if !planned.plan.isEmpty {
            try await authorize()
            context = try await contextAfterAuthorization(matching: context)
            try Self.requireOffered(unrecordedKeys, on: context.identityId)
            // Read again: the prompt can take any time. Owners still
            // unknown are read again; a known one comes from memory.
            planned = try await disconnectPlan(appId: appId, unrecordedKeyIds: unrecordedKeyIds, context: context)
        }
        let plan = planned.plan
        let signer = KeychainSigner(modelContainer: context.modelContainer)
        if !plan.fence.isEmpty || !plan.disable.isEmpty {
            try await fenceAndDisable(plan, context: context, signer: signer)
        }
        let after = plan.fence.isEmpty && plan.disable.isEmpty
            ? planned.snapshot
            : try await identitySnapshot(context: context).snapshot

        // An intent is done once none of its keys can still be live or land.
        // A key whose bound is unknown (`planned.notChecked`) keeps the row,
        // with its Disconnect, through `rows(_:after:of:intents:at:)`.
        let closedAt = now()
        updateIntents(in: stores) { intents in
            for index in intents.indices
            where intents[index].appId == appId && intents[index].identityId == context.identityId
                && intents[index].closedAt == nil {
                switch AppConnect.status(of: intents[index], in: after) {
                case .disconnected, .neverLanded: intents[index].closedAt = closedAt
                case .active, .confirming, .expired: break
                }
            }
        }
        // With the PIN given, the responses an earlier disconnect could not
        // delete go too, whether or not this app has one of its own.
        if !plan.isEmpty, let responseContractId = Self.decodeIdentifier(AppConnect.contractId) {
            let ids = Set(plan.deleteResponses).union(AppConnect.responsesLeft(identityId: context.identityId, intents: stores.intents.load()))
            if !ids.isEmpty {
                await deleteResponses(of: Array(ids), responseContractId: responseContractId, context: context, signer: signer)
            }
        }
        // What stays on is told from the read after the update, as the rows
        // are, and from the same owners. A key that landed during the update
        // is reported too.
        let (rowsAfter, remaining, holder) = await Self.settledDisconnect(
            appId: appId, after: after, intents: stores.intents.load(), unrecordedKeyIds: unrecordedKeyIds,
            owners: Self.ownerReader(context: context), at: now())
        await updateRows(in: stores, rowsAfter)
        let rowsNow = rows(in: stores)

        // A key turned off is checked on the read after the update; one that
        // still shows live means that read is behind, or a new key landed.
        let ownIntents = stores.intents.load().filter { $0.appId == appId && $0.identityId == context.identityId }
        let stillOn = plan.disable.contains { id in after.keys.contains { $0.id == id && $0.disabledAt == nil } }
        guard ownIntents.allSatisfy({ $0.closedAt != nil }), !stillOn else {
            throw DashConnectPlatformError.identityKeysOutOfDate
        }
        // The app's intents on another identity of this wallet can only be
        // reached while that identity is the active one.
        if stores.intents.load().contains(where: {
            $0.appId == appId && $0.identityId != context.identityId && $0.closedAt == nil
        }) {
            throw DashConnectPlatformError.grantOnAnotherIdentity
        }
        var result = Self.disconnectResult(
            of: planned, remaining: remaining, listed: unrecordedKeyIds, identityId: context.identityId,
            // Keys a read of another identity saw stay, and so does the row.
            keysOnAnotherIdentity: rowsNow.first { $0.id == id }?.seenOn
                .subtracting([context.identityId.toBase58String()]).isEmpty == false)
        result.keysLeftUnder = Self.keysLeftUnder(app: id, holder: holder, rows: rowsNow)
        return result
    }

    /// The name of the row the keys left on show under, when the app's own
    /// row is gone: a second disconnect of the app could no longer be asked
    /// for. Nil while the app's row is there.
    static func keysLeftUnder(app id: String, holder: Data?, rows: [DAppConnection]) -> String? {
        guard let holder, !rows.contains(where: { $0.id == id }) else { return nil }
        return rows.first { $0.id == holder.toBase58String() }?.name
    }

    /// Throws `walletChanged` when keys offered on one identity would be
    /// turned off while another is active: their ids could name its keys.
    static func requireOffered(_ offered: DashConnectOfferedKeys?, on identityId: Data) throws {
        if let offered, offered.identityId != identityId { throw DashConnectPlatformError.walletChanged }
    }

    /// What a disconnect planned as `planned` reports: the keys it turned
    /// off, and what stays on as `remaining`, the same disconnect planned on
    /// the read after the update. The offered keys are reported only before
    /// the question (`listed` nil): the user's answer to it passes them back.
    static func disconnectResult(
        of planned: PlannedDisconnect, remaining: PlannedDisconnect, listed: Set<UInt32>?, identityId: Data,
        keysOnAnotherIdentity: Bool
    ) -> DashConnectDisconnectResult {
        DashConnectDisconnectResult(
            keysTurnedOff: planned.appKeysOff,
            offeredUnrecordedKeys: listed == nil && !remaining.offered.isEmpty
                ? DashConnectOfferedKeys(identityId: identityId, keyIds: remaining.offered) : nil,
            keysNotChecked: remaining.notChecked,
            keysNotAttributable: remaining.notAttributable,
            keysLeftAfterQuestion: remaining.leftAfterQuestion,
            keysOnAnotherIdentity: keysOnAnotherIdentity)
    }

    /// What a disconnect of `appId` submits on the active identity, from a
    /// fresh read and the owners it needs (`plannedDisconnect`).
    private func disconnectPlan(
        appId: Data,
        unrecordedKeyIds: Set<UInt32>?,
        context: Context
    ) async throws -> PlannedDisconnect {
        let snapshot = try await identitySnapshot(context: context).snapshot
        let all = context.stores.intents.load()
        // A fence an earlier try added and could not turn off yet.
        let fences = try await liveFenceKeyIds(snapshot: snapshot, intents: all, context: context)
        return await Self.plannedDisconnect(
            appId: appId, snapshot: snapshot, intents: all, unrecordedKeyIds: unrecordedKeyIds, fences: fences,
            owners: Self.ownerReader(context: context))
    }

    /// The ids of this wallet's fence keys that are still live: a fence is
    /// turned off once it holds its id, and an update that failed in between
    /// leaves it on.
    private func liveFenceKeyIds(
        snapshot: AppConnect.IdentitySnapshot,
        intents: [AppConnect.ConnectionIntent],
        context: Context
    ) async throws -> [UInt32] {
        let ids = Set(intents.filter { $0.identityId == snapshot.identityId }.flatMap { $0.authKeys.map(\.id) })
        var live: [UInt32] = []
        for key in snapshot.keys where key.disabledAt == nil && ids.contains(key.id) && key.bound == nil
            && key.keyType == .ecdsaHash160 {
            let leaf = AppConnect.fenceKeyLeaf(identityId: context.identityId, keyId: key.id)
            let (publicKey, derivedPrivateKey) = try await MainActor.run {
                let derived = try context.wallet.deriveConnectKey(
                    subFeature: .sessionAuthentication, identityId: context.identityId, leaf: leaf, network: context.network)
                return (derived.publicKeyData, derived.privateKeyData)
            }
            var privateKey = derivedPrivateKey
            Self.zero(&privateKey)
            if try KeyExchangeCrypto.hash160(publicKey) == key.data { live.append(key.id) }
        }
        return live
    }

    /// Submits a disconnect: a fence key under each id an intent may still
    /// land on, and every key to turn off, as many per update as Platform
    /// takes.
    private func fenceAndDisable(
        _ plan: AppConnect.DisconnectPlan,
        context: Context,
        signer: KeychainSigner
    ) async throws {
        var fences: [(key: ManagedPlatformWallet.IdentityPubkey, privateKey: Data)] = []
        defer { for index in fences.indices { Self.zero(&fences[index].privateKey) } }
        for id in plan.fence {
            let leaf = AppConnect.fenceKeyLeaf(identityId: context.identityId, keyId: id)
            let (publicKey, derivedPrivateKey) = try await MainActor.run {
                let key = try context.wallet.deriveConnectKey(
                    subFeature: .sessionAuthentication, identityId: context.identityId, leaf: leaf, network: context.network)
                return (key.publicKeyData, key.privateKeyData)
            }
            var privateKey = derivedPrivateKey
            defer { Self.zero(&privateKey) }
            fences.append((AppConnect.fenceKey(keyId: id, publicKeyHash160: try KeyExchangeCrypto.hash160(publicKey)),
                           privateKey))
        }
        Self.logger.info("🔗 DASHCONNECT :: fencing \(fences.count, privacy: .public) key id(s), disabling \(plan.disable.count, privacy: .public) key(s)")
        let addBatches = stride(from: 0, to: fences.count, by: AppConnect.maxKeysAddedPerUpdate).map {
            Array(fences[$0 ..< min($0 + AppConnect.maxKeysAddedPerUpdate, fences.count)])
        }
        let disableBatches = stride(from: 0, to: plan.disable.count, by: AppConnect.maxKeysDisabledPerUpdate).map {
            Array(plan.disable[$0 ..< min($0 + AppConnect.maxKeysDisabledPerUpdate, plan.disable.count)])
        }
        for index in 0 ..< max(addBatches.count, disableBatches.count) {
            let add = index < addBatches.count ? addBatches[index] : []
            let disable = index < disableBatches.count ? disableBatches[index] : []
            try await signer.withAdditionalSigningKeys(add.map { ($0.key.pubkeyBytes, $0.privateKey) }) {
                try await context.wallet.updateIdentity(
                    identityId: context.identityId,
                    addPublicKeys: add.map(\.key),
                    disablePublicKeyIds: disable,
                    signer: signer)
            }
        }
        // A disabled key still holds its id, so the fences are turned off once
        // they are there: none stays able to sign. One left on by a failure
        // here is the wallet's own key, limited to one credit.
        let fenceIds = fences.map(\.key.keyId)
        for start in stride(from: 0, to: fenceIds.count, by: AppConnect.maxKeysDisabledPerUpdate) {
            try await context.wallet.updateIdentity(
                identityId: context.identityId,
                disablePublicKeyIds: Array(fenceIds[start ..< min(start + AppConnect.maxKeysDisabledPerUpdate, fenceIds.count)]),
                signer: signer)
        }
    }

    /// The stores fixed to one wallet; `nil` with no wallet.
    private static func pinnedStores(
        walletIdHex: String?,
        store: any DashConnectStore,
        intentStore: any AppConnectIntentStore,
        endpoint: String?
    ) -> Stores? {
        guard let walletIdHex, !walletIdHex.isEmpty else { return nil }
        return Stores(
            walletIdHex: walletIdHex,
            connections: store.pinned(toWalletIdHex: walletIdHex),
            intents: intentStore.pinned(toWalletIdHex: walletIdHex),
            endpoint: endpoint)
    }

    /// The stores fixed to the wallet that is active at this call, read
    /// once; `nil` with no wallet.
    private func pinnedActiveStores() -> Stores? {
        Self.pinnedStores(
            walletIdHex: activeWalletIdHex(), store: store, intentStore: intentStore,
            endpoint: networkEndpoint())
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

    /// The identity's keys and revision as Platform has them, both read from
    /// one copy of the identity.
    private func refreshedIdentityKeysAndRevision(
        context: Context
    ) async throws -> (keys: [ManagedIdentity.IdentityPublicKeyInfo], revision: UInt64) {
        guard try await context.wallet.loadIdentity(atIndex: context.identityIndex) == context.identityId else {
            throw DashConnectPlatformError.noIdentity
        }
        let identity = try context.wallet.managedIdentity(identityId: context.identityId)
        return (try identity.getPublicKeys(), try identity.getRevision())
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
                    // A bound of a kind this build reads whose ids or name it
                    // cannot place is as unknown as a kind it does not read.
                    hasUnreadableBound: !AppConnect.isReadableBound(
                        boundsKind: $0.effectiveContractBoundsKind,
                        boundIds: $0.contractBounds
                    ) || ($0.effectiveContractBoundsKind != 0 && AppConnect.storedBound(
                        boundsKind: $0.effectiveContractBoundsKind,
                        boundIds: $0.contractBounds,
                        documentTypeName: $0.contractBoundsDocumentTypeName
                    ) == nil),
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

        // The devnet name and endpoint the stores name are read from the
        // settings, after the runtime above. A change to them first stops
        // that runtime and builds another, so if it is still the one
        // running once they are read, they are the settings it runs on.
        let stores = Stores(
            walletIdHex: walletIdHex,
            connections: store.pinned(toWalletIdHex: walletIdHex),
            intents: intentStore.pinned(toWalletIdHex: walletIdHex),
            endpoint: networkEndpoint())
        guard await MainActor.run(body: { SwiftDashSDKHost.shared.sdk === sdk }) else {
            Self.logger.error("🔗 DASHCONNECT :: the SDK runtime changed while its context was read")
            throw DashConnectPlatformError.walletChanged
        }

        return Context(
            wallet: wallet,
            sdk: sdk,
            modelContainer: modelContainer,
            network: network,
            identityId: identityId,
            identityIndex: identityIndex,
            storedUsername: runtime.storedUsername,
            stores: stores
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

    /// Every key this wallet derives for one encryption grant
    /// (`AppConnect.derivableEncryptionKeys`): rotations at the DIP-13 path
    /// with the rotation level, and on testnet and devnet the path without
    /// it. `storage` is the SDK's default outside tests.
    @MainActor
    static func derivableEncryptionKeys(
        for grant: AppConnect.EncryptionGrant,
        wallet: ManagedPlatformWallet,
        identityId: Data,
        network: Network,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        storage: WalletStorage = WalletStorage()
    ) throws -> [AppConnect.DerivedEncryptionKey] {
        try AppConnect.derivableEncryptionKeys(
            network: network,
            purpose: grant.keyPurpose,
            currentIdentityPublicKeys: currentIdentityPublicKeys,
            rotation: { rotation in
                let key = try wallet.deriveConnectKey(
                    subFeature: .appEncryption,
                    identityId: identityId,
                    leaf: grant.binding.contractId,
                    purpose: grant.connectPurpose,
                    rotation: rotation,
                    network: network,
                    storage: storage
                )
                return (key.publicKeyData, key.privateKeyData)
            },
            legacy: {
                let key = try wallet.deriveLegacyAppEncryptionKey(
                    identityId: identityId,
                    contractId: grant.binding.contractId,
                    purpose: grant.connectPurpose,
                    network: network,
                    storage: storage
                )
                return (key.publicKeyData, key.privateKeyData)
            }
        )
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

/// Platform reads the Swift SDK offers only on the main actor (the current
/// epoch and an identity's contract keys), where their blocking FFI calls
/// would hold the UI for a network round trip. They run here on queues of
/// their own instead, with the SDK kept alive for the call; each copies the
/// native result and releases it before returning.
/// TODO(dashconnect-off-main-queries): use the SDK's own off-main reads once
/// it has them for these, as it has for `documentList`.
enum DashConnectPlatformQueries {
    private static let epochQueue = DispatchQueue(label: "org.dashfoundation.dash.dashconnect.epoch-query")
    /// Concurrent: a read a failed login no longer waits for cannot be
    /// stopped, and must not hold back the next login's read.
    private static let contractKeysQueue = DispatchQueue(
        label: "org.dashfoundation.dash.dashconnect.contract-keys-query", attributes: .concurrent)

    /// The protocol version the network runs, from a proved read of the
    /// current epoch. It throws when that read fails: there is no fallback
    /// value.
    static func currentEpochProtocolVersion(sdk: SDK) async throws -> UInt32 {
        let epoch = try await run(sdk, on: epochQueue) { handle in
            try json(from: dash_sdk_system_get_current_epoch(handle))
        }
        guard let version = (epoch["protocol_version"] as? NSNumber)?.uint32Value else {
            throw SDKError.serializationError("The current epoch carries no protocol version")
        }
        return version
    }

    /// `SDK.identityGetContractKeys(identityIds:contractId:documentType:purposes:)`
    /// off the main actor: the proved current key of each purpose the
    /// identity holds for the contract, as `AppConnect.currentContractKey`
    /// reads it.
    static func identityContractKeys(
        sdk: SDK,
        identityId: String,
        contractId: String,
        purposes: [KeyPurpose]
    ) async throws -> [String: Any] {
        let purposeList = purposes.map { String($0.rawValue) }.joined(separator: ",")
        return try await run(sdk, on: contractKeysQueue) { handle in
            try json(from: dash_sdk_identities_fetch_contract_keys(handle, identityId, contractId, nil, purposeList))
        }
    }

    private static func run(
        _ sdk: SDK,
        on queue: DispatchQueue,
        _ body: @escaping (OpaquePointer) throws -> [String: Any]
    ) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                // The SDK owns the handle and releases it when it goes, so
                // it is held until the call is done.
                withExtendedLifetime(sdk) {
                    guard let handle = sdk.handle else {
                        continuation.resume(throwing: SDKError.invalidState("SDK not initialized"))
                        return
                    }
                    continuation.resume(with: Result { try body(handle) })
                }
            }
        }
    }

    /// The JSON object a result carries, with the result released.
    private static func json(from result: DashSDKResult) throws -> [String: Any] {
        if let error = result.error {
            defer { dash_sdk_error_free(error) }
            throw SDKError.fromDashSDKError(error.pointee)
        }
        guard let data = result.data else { throw SDKError.notFound("No data returned") }
        let string = data.assumingMemoryBound(to: CChar.self)
        let text = String(cString: string)
        dash_sdk_string_free(string)
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw SDKError.serializationError("The result is not a JSON object")
        }
        return object
    }
}
