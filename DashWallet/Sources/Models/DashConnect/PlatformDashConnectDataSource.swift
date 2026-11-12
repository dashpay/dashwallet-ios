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
        "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F": .init(name: "Yappr", url: "yap.pr"),
        // The row of DashPay profile keys no connection accounts for.
        AppConnect.dashPayContractId: .init(name: "DashPay", url: ""),
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
    /// The proved read carried no block time, so a request's age cannot be
    /// judged (AC-09).
    case requestAgeUncheckable
    case tokenPurchaseNeedsUsername
    /// The DPNS read failed and no stored name stands in: whether the
    /// identity has a username is not known.
    case tokenPurchaseUsernameUncheckable
    /// The response lookup failed and nothing else says whether the request
    /// was answered before (AC-11).
    case answeredUncheckable
    /// Platform refused the identity update for good (AC-20b). The code is
    /// the consensus error's; Platform's message text is not carried.
    case networkRefused(code: UInt32)

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
        case .requestAgeUncheckable:
            return NSLocalizedString(
                "The wallet could not check how old this sign-in request is. Try again.",
                comment: "DashConnect App Connect v2")
        case .tokenPurchaseNeedsUsername:
            return NSLocalizedString(
                "A DashPay username is needed to buy tokens. Create one, then open the link again.",
                comment: "DashConnect token purchase")
        case .tokenPurchaseUsernameUncheckable:
            return NSLocalizedString(
                "The wallet could not check your DashPay username. Open the link again.",
                comment: "DashConnect token purchase")
        case .answeredUncheckable:
            return NSLocalizedString(
                "The wallet could not check whether this sign-in was already answered. Try again.",
                comment: "DashConnect App Connect v2")
        case .networkRefused:
            return NSLocalizedString(
                "The network refused this sign-in for good. Ask the app for a new code.",
                comment: "DashConnect App Connect v2")
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

/// What a disconnect asks of the wallet and Platform: the identity it acts
/// for, the PIN prompt, a fresh read of the identity, the hash of a fence key
/// and the response document of a request. The live implementation wraps the
/// wallet and the SDK; a data source built with another one reads and asks
/// through it only.
protocol DashConnectPlatformPort: Sendable {
    var identityId: Data { get }
    func authorize() async throws
    func readIdentity() async throws -> AppConnect.IdentitySnapshot
    /// The hash160 of the public key the wallet derives for the fence under `keyId`.
    func fenceKeyHash(keyId: UInt32) async throws -> Data
    /// This identity's response to the request, or `nil` when there is none.
    func findResponse(requestHash: Data) async throws -> (documentId: Data, values: AppConnect.ResponseValues)?
    /// Where the owners of contracts and contract groups come from.
    var owners: PlatformDashConnectDataSource.OwnerReader { get }
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
    /// behind it is not used (`AppConnect.IdentitySnapshot.admitted`).
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
    private var storeSaveObserver: AnyCancellable?
    private let authorizer: DWIdentityAuthorizer
    private let stateTransitionParser: any DashConnectStateTransitionParsing
    private let now: () -> Date
    /// Builds the executor of a disconnect's writes from its submit; `nil`
    /// builds the live one (`writeExecutor(submit:)`). Every write is sent through
    /// `makeExecutor(submit:)`.
    private let makeWriteExecutor: ((@escaping @Sendable (PlatformWrite) async throws -> Void) -> AppConnectWriteExecutor)?
    /// What a disconnect reads and asks through; `nil` uses the live wallet
    /// and SDK (`LiveDashConnectPlatform`).
    private let platform: (any DashConnectPlatformPort)?
    /// The wait before the read at `attempt` (1, 2) when a node is behind.
    private let pauseForLaggingNode: @Sendable (Int) async -> Void

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
    /// what the default data source serves: the same network on every kind,
    /// mainnet included.
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
        now: @escaping () -> Date = Date.init,
        makeWriteExecutor: ((@escaping @Sendable (PlatformWrite) async throws -> Void) -> AppConnectWriteExecutor)? = nil,
        platform: (any DashConnectPlatformPort)? = nil,
        pauseForLaggingNode: @escaping @Sendable (Int) async -> Void = { await PlatformDashConnectDataSource.pauseForLaggingNode($0) }
    ) {
        self.pauseForLaggingNode = pauseForLaggingNode
        self.makeWriteExecutor = makeWriteExecutor
        self.platform = platform
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
        // Another data source over the same rows (a page opened again while
        // an earlier one's operation runs) writes them too.
        self.storeSaveObserver = notificationCenter
            .publisher(for: UserDefaultsDashConnectStore.didSaveNotification)
            .sink { [weak self] notification in
                let scopeKey = notification.userInfo?[UserDefaultsDashConnectStore.scopeKeyUserInfoKey] as? String
                Task { @MainActor in self?.showStoredRows(savedUnder: scopeKey) }
            }
    }

    var connections: AnyPublisher<[DAppConnection], Never> {
        subject.eraseToAnyPublisher()
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if let refusal = AppConnect.intakeRefusal(forCode: trimmed, network: supportedNetwork) {
            throw refusal
        }

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
        let walletUsername = await resolveWalletUsername(context: context).name
        let protocolVersion: UInt32?
        var unresolvedLoginReason: String?
        do {
            protocolVersion = try await resolvedProtocolVersion
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: protocol version unknown — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
            protocolVersion = nil
            unresolvedLoginReason = error.localizedDescription
        }
        var login: AppConnect.Login = loginRequest.appConnect == nil ? .refused(AppConnect.v1Refusal) : .unresolved
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
            // The request's age is judged by the block time of a proved read.
            let (snapshot, _) = try await identitySnapshot(context: context)
            var plan = try AppConnect.grantPlan(for: uri, blockTimeMs: snapshot.platformTime)
            plan.brandHost = DashConnectFallbackAppMetadata.brandHost(contractId: plan.appId.toBase58String())
            if let hint = plan.identityHint, hint != context.identityId {
                return (.refused(AppConnect.Refusal(.invalid, NSLocalizedString(
                    "This sign-in is for another identity. Switch to it in this wallet and ask the app again.",
                    comment: "DashConnect App Connect v2"))), nil)
            }
            // A request answered before is spent (it is answered at most
            // once): the sheet says so before any PIN is asked.
            switch await answeredState(of: uri.request, plan: plan, snapshot: snapshot, context: context) {
            case .notAnswered: break
            case .answered: return (.refused(Self.spentRequest(after: nil)), nil)
            case .uncheckable: return (.unresolved, DashConnectPlatformError.answeredUncheckable.localizedDescription)
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
            Self.logger.error("🔗 DASHCONNECT :: App Connect request not checked — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
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
            Self.logger.error("🔗 DASHCONNECT :: no context — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
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
            Self.logger.error("🔗 DASHCONNECT :: protocol version unknown — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
            throw DashConnectPlatformError.loginUnresolved
        }
        let requestHash = try KeyExchangeCrypto.hash160(appConnect.request.appEphemeralPubKey)
        let approvedLogin = AppConnect.isAvailable(protocolVersion: protocolVersion)
            && plan.appEphemeralPubKeyHash == requestHash
        guard approvedLogin else {
            Self.logger.error("🔗 DASHCONNECT :: the network now answers with another login than the one approved")
            throw DashConnectPlatformError.approvalOutOfDate
        }
        // A request answered before is refused before the PIN is asked.
        let (answeredSnapshot, _) = try await identitySnapshot(context: context)
        try await Self.authorizeUnlessAnswered(
            answered: { [self] in
                await answeredState(of: appConnect.request, plan: plan, snapshot: answeredSnapshot, context: context)
            },
            authorize: { [self] in
                do {
                    try await authorize()
                } catch {
                    Self.logger.error("🔗 DASHCONNECT :: authorization failed — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
                    throw error
                }
            })
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

    /// One read of the active identity: its keys and the block time Platform
    /// proved them at, their bounds from the wallet's key store, and the
    /// revision of the wallet's copy, loaded first. A read behind one already
    /// seen in this process comes from a node that is behind, and throws
    /// `identityReadBehind`.
    private func identitySnapshot(
        context: Context
    ) async throws -> (snapshot: AppConnect.IdentitySnapshot, keys: [ManagedIdentity.IdentityPublicKeyInfo]) {
        let (copyKeys, revision) = try await refreshedIdentityKeysAndRevision(context: context)
        // The proved keys read carries no revision, so the revision below is
        // the wallet copy's. The keys read is held against that copy's keys
        // instead (`requireKeysNotBehind`); a node behind in ways the keys do
        // not show (no key added or turned off) still passes.
        let fetched = try await context.sdk.fetchIdentityPublicKeys(identityId: context.identityId)
        let bindings = try Self.storedKeyBindings(
            identityId: context.identityId.toBase58String(), modelContainer: context.modelContainer)
        let (read, keys) = try Self.identitySnapshot(
            identityId: context.identityId, revision: revision, fetched: fetched, bindings: bindings)
        try Self.requireKeysNotBehind(copy: copyKeys, proved: keys)
        // Held against the newest read and stored in one step, so two reads
        // at once cannot both pass against the same newest one.
        let admitted = Self.newestSnapshots.withLock { newest -> AppConnect.IdentitySnapshot? in
            guard let admitted = read.admitted(after: newest[context.identityId]) else { return nil }
            newest[context.identityId] = admitted
            return admitted
        }
        guard let admitted else {
            // The SDK's copy of the identity is now that older one too, so
            // nothing is built on it: the user tries again.
            Self.logger.error("🔗 DASHCONNECT :: the identity read is behind one already seen")
            throw DashConnectPlatformError.identityReadBehind
        }
        return (admitted, keys)
    }

    /// Throws `identityReadBehind` when the proved keys lack a key of the
    /// wallet's copy, show enabled a key the copy has turned off, or show a
    /// lower budget or an earlier expiry than the copy: a node that answered
    /// from before the change the copy already has. Platform only ever raises
    /// a key's limits, and without a new identity revision, so the revision
    /// cannot tell. An expiry is the SDK's bit pattern of a block time and is
    /// compared unsigned. Newer keys in the proved read are fine.
    static func requireKeysNotBehind(
        copy: [ManagedIdentity.IdentityPublicKeyInfo],
        proved: [ManagedIdentity.IdentityPublicKeyInfo]
    ) throws {
        let provedById = Dictionary(proved.map { ($0.keyId, $0) }, uniquingKeysWith: { first, _ in first })
        for key in copy {
            guard let seen = provedById[key.keyId], key.disabledAt == nil || seen.disabledAt != nil,
                  !Self.isLower(seen.totalBudget, than: key.totalBudget),
                  !Self.isLower(seen.expiresAt.map(UInt64.init(bitPattern:)), than: key.expiresAt.map(UInt64.init(bitPattern:)))
            else {
                Self.logger.error("🔗 DASHCONNECT :: the keys read is behind the wallet's copy")
                throw DashConnectPlatformError.identityReadBehind
            }
        }
    }

    /// Whether the limit `proved` is below `copy`, both set.
    private static func isLower<Limit: Comparable>(_ proved: Limit?, than copy: Limit?) -> Bool {
        guard let proved, let copy else { return false }
        return proved < copy
    }

    /// The snapshot of one proved keys read: every key Platform holds for the
    /// identity, turned-off ones included, and the read's block time. A read
    /// that finds no identity throws `noIdentity`.
    static func identitySnapshot(
        identityId: Data,
        revision: UInt64,
        fetched: FetchedIdentityPublicKeys,
        bindings: [AppConnect.KeyBinding]
    ) throws -> (snapshot: AppConnect.IdentitySnapshot, keys: [ManagedIdentity.IdentityPublicKeyInfo]) {
        guard let keys = fetched.keys?.map(\.key) else {
            throw DashConnectPlatformError.noIdentity
        }
        let snapshot = AppConnect.IdentitySnapshot(
            identityId: identityId,
            revision: revision,
            keys: keys.map { key in
                AppConnect.platformKey(key, binding: bindings.first { $0.keyId == UInt32(bitPattern: key.keyId) })
            },
            platformTime: fetched.blockTimeMs)
        return (snapshot, keys)
    }

    /// Reads, changes and writes the intents in one step, from the store each
    /// time. Every caller runs inside `gated`, so no other operation of this
    /// wallet writes them in between.
    @discardableResult
    private func updateIntents<T>(in stores: Stores, _ change: (inout [AppConnect.ConnectionIntent]) -> T) -> T {
        Self.update(stores.intents, change)
    }

    @discardableResult
    private static func update<T>(_ store: any AppConnectIntentStore, _ change: (inout [AppConnect.ConnectionIntent]) -> T) -> T {
        var intents = store.load()
        let result = change(&intents)
        store.save(intents)
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

    /// Puts the App Connect rows of `stores` in step with what `snapshot`
    /// and the intents show.
    private func refreshRows(from snapshot: AppConnect.IdentitySnapshot, context: Context) async {
        await refreshRows(from: snapshot, stores: context.stores, owners: Self.ownerReader(context: context))
    }

    /// The same, with the owners the projection needs from `owners`: a key
    /// whose owner is unknown keeps its own row.
    private func refreshRows(from snapshot: AppConnect.IdentitySnapshot, stores: Stores, owners: OwnerReader) async {
        let known = await owners.knownOwners(for: snapshot, intents: stores.intents.load())
        await refreshRows(from: snapshot, stores: stores, knownOwners: known)
    }

    /// The same, with the owners already read (`knownOwners`), so a
    /// disconnect can tell its rows and its result from the same owners.
    private func refreshRows(from snapshot: AppConnect.IdentitySnapshot, stores: Stores, knownOwners: [Data: Data]) async {
        let updatedAt = now()
        // An open Disconnected intent a disconnect left open, whose app has a
        // row: while the read has a key of unknown bound the row stays as it
        // is; with none left the intent is closed at `updatedAt`, so the row
        // shows Disconnected. An intent whose keys went off without a
        // disconnect of this wallet is left as it is.
        let hasUnplacedKey = Self.unplacedKeyCount(of: snapshot, intents: stores.intents.load()) > 0
        let shownApps = Set(rows(in: stores).map(\.id))
        var kept = Set<String>()
        updateIntents(in: stores) { intents in
            for index in intents.indices
            where intents[index].identityId == snapshot.identityId && intents[index].closedAt == nil
                && intents[index].disconnectedAt != nil
                && shownApps.contains(intents[index].appId.toBase58String())
                && AppConnect.status(of: intents[index], in: snapshot) == .disconnected {
                if hasUnplacedKey {
                    kept.insert(intents[index].appId.toBase58String())
                } else {
                    intents[index].closedAt = updatedAt
                }
            }
        }
        let all = stores.intents.load()
        let projection = AppConnect.project([snapshot], intents: all, owners: knownOwners)
        let elsewhere = all.filter { $0.identityId != snapshot.identityId && $0.closedAt == nil }
        await updateRows(in: stores) { rows in
            Self.rows(rows, after: projection, of: snapshot.identityId, intents: elsewhere, at: updatedAt, keeping: kept)
        }
    }

    /// How many keys of `snapshot`'s identity have a bound that is unknown
    /// (the projection's `unplacedKeyIds`).
    private static func unplacedKeyCount(
        of snapshot: AppConnect.IdentitySnapshot,
        intents: [AppConnect.ConnectionIntent]
    ) -> Int {
        AppConnect.project([snapshot], intents: intents).unplacedKeyIds[snapshot.identityId]?.count ?? 0
    }

    /// `rows` with the App Connect connections of `projection`, the read of
    /// `identityId`: an app whose card (the intents it follows,
    /// `followedIntents`) is Active, Not delivered, Confirming, Expired,
    /// Refused, or Disconnected by the user has a row of that status, named
    /// after those intents; one whose update never landed, or whose keys went
    /// off without a disconnect, has none, unless another identity's intents
    /// hold it or its last read saw keys there no approval names (`seenOn`).
    /// Such access elsewhere also keeps a row from showing Disconnected.
    /// A row whose app is in `keeping` stays as it is. While the read has a
    /// key whose bound is unknown, that key may be any app's: no row goes;
    /// one that would is Confirming, so it keeps its Disconnect until a
    /// read places every key.
    static func rows(
        _ rows: [DAppConnection],
        after projection: AppConnect.Projection,
        of identityId: Data,
        intents elsewhere: [AppConnect.ConnectionIntent],
        at updatedAt: Date,
        keeping: Set<String> = []
    ) -> [DAppConnection] {
        let me = identityId.toBase58String()
        func shownStatus(_ connection: AppConnect.ProjectedConnection) -> ConnectionStatus? {
            switch connection.status {
            case .active: return .active
            case .expired: return .expired
            case .confirming: return .confirming
            case .refused: return .refused
            // Only a disconnect the user made leaves a row: a closed intent
            // among those the card follows.
            case .disconnected: return connection.followedIntents.contains { $0.closedAt != nil } ? .disconnected : nil
            case .neverLanded: return nil
            }
        }
        let shownIds = Set(projection.connections.filter { shownStatus($0) != nil }.map { $0.appId.toBase58String() })
        // An App Connect row stands for intents: it stays only while another
        // identity's intents hold it, since this read says nothing of them.
        let heldElsewhere = Set(elsewhere.map { $0.appId.toBase58String() })
        let hasUnplacedKey = projection.unplacedKeyIds[identityId]?.isEmpty == false
        var result: [DAppConnection] = rows.compactMap { row in
            if keeping.contains(row.id) { return row }
            guard !shownIds.contains(row.id) else { return nil }
            var seenOn = row.seenOn
            seenOn.remove(me)
            if heldElsewhere.contains(row.id) { return DAppConnection(row, seenOn: seenOn) }
            // Live keys seen on another identity: that is the access left.
            guard !seenOn.isEmpty else {
                // A key of unknown bound may still be the app's: the row
                // stays, Confirming rather than Active, with its Disconnect.
                guard hasUnplacedKey else { return nil }
                return DAppConnection(
                    row, status: .confirming, seenOn: seenOn, at: row.status == .confirming ? row.updatedAt : updatedAt)
            }
            return DAppConnection(row, status: .active, seenOn: seenOn, at: row.status == .active ? row.updatedAt : updatedAt)
        }
        for connection in projection.connections {
            let id = connection.appId.toBase58String()
            guard var status = shownStatus(connection) else { continue }
            if status == .active && connection.isUndelivered { status = .undelivered }
            let existing = rows.first { $0.id == id }
            let latest = connection.followedIntents.first ?? connection.intents.first
            let fallback = DashConnectFallbackAppMetadata.resolve(contractId: id, unauthenticatedLabel: "")
            let name = latest?.appLabel ?? existing?.name ?? fallback.name
            var seenOn = existing?.seenOn ?? []
            seenOn.remove(me)
            if connection.unrecordedKeyIds[identityId]?.isEmpty == false { seenOn.insert(me) }
            // Disconnected here, but another identity of the wallet still
            // holds the app (its intents, or live keys its last read saw):
            // the row keeps that access, and its Disconnect, until that
            // identity's own read.
            if status == .disconnected, let existing, heldElsewhere.contains(id) || !seenOn.isEmpty {
                let kept: ConnectionStatus = existing.status == .disconnected ? .active : existing.status
                result.removeAll { $0.id == id }
                result.append(DAppConnection(
                    existing, status: kept, seenOn: seenOn, at: existing.status == kept ? existing.updatedAt : updatedAt))
                continue
            }
            // Disconnected here while the read has a key of unknown bound,
            // which may be the app's: a row that still showed access is
            // Confirming, with its Disconnect, until a read places every key.
            if status == .disconnected, hasUnplacedKey, let existing, existing.status != .disconnected {
                result.removeAll { $0.id == id }
                result.append(DAppConnection(
                    existing, status: .confirming, seenOn: seenOn,
                    at: existing.status == .confirming ? existing.updatedAt : updatedAt))
                continue
            }
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

    /// Passes a fresh request and throws the refusal or error that matches any other age.
    static func requireFreshRequest(age: AppConnectRequest.Age) throws {
        switch age {
        case .fresh: return
        case .uncheckable: throw DashConnectPlatformError.requestAgeUncheckable
        case .stale:
            throw AppConnect.Refusal(.stale, NSLocalizedString(
                "This sign-in request has expired. Ask the app for a new one.",
                comment: "DashConnect App Connect v2"))
        case .future:
            throw AppConnect.Refusal(.stale, AppConnect.futureRequestMessage)
        }
    }

    /// A token purchase is shown only with the wallet's DashPay username.
    /// With no name, a failed DPNS read means the name is not known, not
    /// that there is none.
    static func requireTokenPurchaseUsername(_ resolved: String?, lookupFailed: Bool) throws -> String {
        guard let name = resolved?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw lookupFailed
                ? DashConnectPlatformError.tokenPurchaseUsernameUncheckable
                : DashConnectPlatformError.tokenPurchaseNeedsUsername
        }
        return name
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
        let (snapshot, currentPublicKeys) = try await identitySnapshot(context: context)
        // The app stops looking for an answer ten minutes after it asked.
        try Self.requireFreshRequest(age: uri.request.age(blockTimeMs: snapshot.platformTime))
        // A request is answered at most once, by any identity of the wallet:
        // approving it again is refused, whether the first attempt answered
        // it or stopped. A sealed response is never published by a later
        // attempt, as what it was sealed for may no longer hold. The app asks
        // again.
        try await requireNotAnswered(uri.request, plan: plan, snapshot: snapshot, context: context)
        let request = uri.request
        let signer = KeychainSigner(modelContainer: context.modelContainer)
        // From here on the read the intent was made from: a fence reads again.
        let (intent, read) = try await newAppConnectIntent(
            request: request, plan: plan, consent: consent, snapshot: snapshot,
            currentPublicKeys: currentPublicKeys, context: context)
        do {
            try await submitAndPublish(
                intent, request: request, plan: plan, snapshot: read, responseContractId: responseContractId,
                context: context, signer: signer)
        } catch {
            // The request is spent from here on: the row shows where it
            // stopped, and the app asks again.
            // Nothing was recorded or sent: there is nothing to settle.
            if let platformError = error as? DashConnectPlatformError, platformError == .grantNotRecorded { throw error }
            await settle(after: intent, responseContractId: responseContractId, context: context, signer: signer)
            // Typed, so the caller can tell a refusal that is for good.
            throw Self.approvalFailure(after: error)
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
        guard let read = await readRetryingWhileBehind({ try await identitySnapshot(context: context).snapshot }) else {
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
            await deleteResponses(
                of: Array(toDelete), responseContractId: responseContractId, stores: context.stores,
                port: LiveDashConnectPlatform(source: self, context: context), context: context, signer: signer)
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
            if attempt > 0 { await pauseForLaggingNode(attempt) }
            do {
                let read = try await identitySnapshot(context: context).snapshot
                readFailure = nil
                if AppConnect.hasLanded(intent, in: read) { return read }
            } catch {
                Self.logger.error("🔗 DASHCONNECT :: identity not read while looking for the update — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
                readFailure = error
            }
        }
        if let readFailure { throw readFailure }
        Self.logger.error("🔗 DASHCONNECT :: no read shows the identity update")
        throw DashConnectPlatformError.identityReadBehind
    }

    /// The result of `read`, tried up to three times with the lagging-node
    /// pauses between; `nil` when every try failed.
    private func readRetryingWhileBehind<Read>(_ read: () async throws -> Read) async -> Read? {
        for attempt in 0 ... 2 {
            if attempt > 0 { await pauseForLaggingNode(attempt) }
            if let result = try? await read() { return result }
        }
        return nil
    }

    /// The one list of errors that make an identity update's refusal
    /// permanent (ADR-0021): a consensus rejection, which is Platform's own
    /// verdict from validating the state transition, from the SDK or from the
    /// wallet layer, of any family. Everything else is not, because the update
    /// may have landed or may still: a timeout, a transport error or a
    /// cancellation says nothing of what Platform did with the transition; an
    /// unconfirmed broadcast is by its name unknown; an unknown or internal
    /// error has no verdict; a typed rejection the wallet layer promoted to a
    /// case of its own (an address-nonce race) carries no code and is one to
    /// retry. The refusal holds the code and the date, never Platform's text.
    static func consensusRefusal(from error: Error, at date: Date) -> AppConnect.ConsensusRefusal? {
        let consensus: PlatformConsensusError?
        switch error {
        case let error as SDKError: consensus = error.consensusError
        case let error as PlatformWalletError: consensus = error.consensusError
        default: consensus = nil
        }
        return consensus.map { AppConnect.ConsensusRefusal(code: $0.code, at: date) }
    }

    /// What an identity update that ended with `error` (a failure or a
    /// timeout, not a permanent refusal) left: it may have landed without
    /// confirming; its keys decide, nothing else does. The read that shows
    /// them is returned, else `error` is thrown.
    private func readAfterFailedUpdate(
        _ error: Error, of intent: AppConnect.ConnectionIntent, context: Context
    ) async throws -> AppConnect.IdentitySnapshot {
        guard let read = try? await readShowingUpdate(of: intent, context: context) else { throw error }
        Self.logger.info("🔗 DASHCONNECT :: the identity update landed without confirming")
        return read
    }

    /// Writes the permanent `refusal` (`consensusRefusal`) that `error` carried
    /// on `intent`, logs the error's type, its case and the consensus code (the
    /// message text of a consensus error can name the identity and keys), and
    /// returns the error that fails the approval.
    private static func recordRefusal(
        _ refusal: AppConnect.ConsensusRefusal, of error: Error, on intent: AppConnect.ConnectionIntent,
        in intents: any AppConnectIntentStore
    ) -> DashConnectPlatformError {
        let type = String(describing: Swift.type(of: error))
        let code = refusal.code
        logger.error(
            "🔗 DASHCONNECT :: refused: \(type, privacy: .public).consensusRejection \(code, privacy: .public)")
        update(intents) { $0 = AppConnect.recordRefusal(refusal, on: intent.id, in: $0) }
        return .networkRefused(code: refusal.code)
    }

    /// The error an approval that stopped ends with: a refusal that is for
    /// good stays typed, so the caller can tell; anything else spends the
    /// request.
    static func approvalFailure(after error: Error) -> Error {
        isNetworkRefused(error) ? error : spentRequest(after: error)
    }

    private static func isNetworkRefused(_ error: Error) -> Bool {
        guard let error = error as? DashConnectPlatformError, case .networkRefused = error else { return false }
        return true
    }

    /// The error of a request that cannot be approved again: what stopped
    /// it, when that says something the user can act on, and that the app has
    /// to ask anew. A refusal with the `failed` status, so the sheet offers no
    /// Approve and the app is told the request failed. Causes whose own text
    /// would advise trying again are logged, not shown.
    private static func spentRequest(after cause: Error?) -> AppConnect.Refusal {
        let spent = DashConnectPlatformError.sessionKeyUnusable.localizedDescription
        guard let cause else { return AppConnect.Refusal(.failed, spent) }
        logger.error("🔗 DASHCONNECT :: the request is spent — \(AppConnectWriteExecutor.logDescription(of: cause), privacy: .public)")
        // A refusal says what to do itself (update the wallet, for one).
        if let refusal = cause as? AppConnect.Refusal { return refusal }
        let platformError = cause as? DashConnectPlatformError
        // Its own text already sends the user to the app.
        if platformError == .appConnectEncryptionKeyChanged { return AppConnect.Refusal(.failed, cause.localizedDescription) }
        let retrying: [DashConnectPlatformError] = [
            .sessionKeyUnusable, .identityReadBehind, .approvalOutOfDate, .appConnectKeysOutOfDate, .appConnectKeysUnreadable,
            .walletChanged, .identityKeysOutOfDate,
        ]
        if cause is CancellationError || cause is AppConnectWriteTimedOut || platformError.map(retrying.contains) == true {
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

    /// The earlier grants of the connection `connectionId` (one install of one
    /// app) that a new grant of it replaces: the keys to turn off in the same
    /// update, and the pending ones to fence first. A request without an
    /// install replaces nothing.
    static func supersededKeys(
        connectionId: Data?, appId: Data, snapshot: AppConnect.IdentitySnapshot, intents: [AppConnect.ConnectionIntent]
    ) -> AppConnect.DisconnectPlan {
        connectionId.map { connectionId in
            AppConnect.recordedDisconnectPlan(
                appId: appId, snapshot: snapshot,
                intents: intents.filter { $0.connectionId == connectionId })
        } ?? AppConnect.DisconnectPlan()
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
        let supersession = Self.supersededKeys(
            connectionId: plan.connectionId, appId: plan.appId, snapshot: snapshot, intents: intents)
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
            let fenced = try await fenceAndDisable(
                AppConnect.DisconnectPlan(fence: supersession.fence), identityId: context.identityId,
                port: LiveDashConnectPlatform(source: self, context: context), context: context,
                signer: KeychainSigner(modelContainer: context.modelContainer))
            if let failure = fenced.failure { throw failure }
            snapshot = try await identitySnapshot(context: context).snapshot
            let fencedSnapshot = snapshot
            let closedAt = now()
            updateIntents(in: stores) { intents in
                for index in intents.indices where intents[index].closedAt == nil
                    && intents[index].identityId == context.identityId
                    && AppConnect.status(of: intents[index], in: fencedSnapshot) == .neverLanded {
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
            closedAt: nil,
            administeredGroupIds: plan.administeredGroupIds.sorted { $0.lexicographicallyPrecedes($1) })
        return (intent, snapshot)
    }

    /// Whether the request was answered before (AC-11): this wallet's
    /// intents, the identity's keys in `snapshot` that are the request's own
    /// auth keys, and this identity's response on Platform. The keys are
    /// derived from the wallet's seed, which needs no PIN. A derivation that
    /// fails counts as a failed lookup: with the request's keys unknown, no
    /// response and no key found does not mean it was not answered.
    private func answeredState(
        of request: AppConnectRequest,
        plan: AppConnect.GrantPlan,
        snapshot: AppConnect.IdentitySnapshot,
        context: Context
    ) async -> AppConnect.AnsweredState {
        var authKeyHashes: [Data] = []
        var lookup = await responseLookup(for: plan, context: context)
        do {
            var keys = try await deriveAuthKeys(request: request, plan: plan, context: context)
            authKeyHashes = keys.map(\.publicKeyHash160)
            for index in keys.indices { Self.zero(&keys[index].privateKey) }
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: the request's keys were not derived — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
            lookup = .failure(error)
        }
        return AppConnect.answeredState(
            responseLookup: lookup, requestAuthKeyHashes: authKeyHashes, snapshot: snapshot,
            intents: context.stores.intents.load(), appId: plan.appId, requestHash: plan.appEphemeralPubKeyHash)
    }

    /// Whether this identity has a response on Platform for the request; a
    /// failed lookup is a failure, never "no response".
    private func responseLookup(for plan: AppConnect.GrantPlan, context: Context) async -> Result<Bool, Error> {
        guard let responseContractId = Self.decodeIdentifier(AppConnect.contractId) else {
            return .failure(DashConnectPlatformError.loginContractUnavailable)
        }
        do {
            let list = try await context.sdk.documentList(
                dataContractId: responseContractId.toBase58String(),
                documentType: AppConnect.documentType,
                whereClause: AppConnect.responseLookupWhereClause(
                    appEphemeralPubKeyHash: plan.appEphemeralPubKeyHash, ownerIdentityId: context.identityId),
                limit: 1)
            return .success(try AppConnect.responseExists(inDocumentList: list))
        } catch {
            Self.logger.error("🔗 DASHCONNECT :: response lookup failed — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
            return .failure(error)
        }
    }

    /// Throws unless the request is known not to have been answered: the
    /// refusal of a spent request when it was, `answeredUncheckable` when
    /// that cannot be told.
    private func requireNotAnswered(
        _ request: AppConnectRequest,
        plan: AppConnect.GrantPlan,
        snapshot: AppConnect.IdentitySnapshot,
        context: Context
    ) async throws {
        switch await answeredState(of: request, plan: plan, snapshot: snapshot, context: context) {
        case .notAnswered: return
        case .answered: throw Self.spentRequest(after: nil)
        case .uncheckable: throw DashConnectPlatformError.answeredUncheckable
        }
    }

    /// The check before the PIN: a request answered before, or one that
    /// cannot be told, is refused and `authorize` is not asked; only a
    /// request known not to be answered asks for the PIN, once.
    static func authorizeUnlessAnswered(
        answered: () async -> AppConnect.AnsweredState,
        authorize: () async throws -> Void
    ) async throws {
        switch await answered() {
        case .notAnswered: try await authorize()
        case .answered: throw spentRequest(after: nil)
        case .uncheckable: throw DashConnectPlatformError.answeredUncheckable
        }
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
        logger.error("🔗 DASHCONNECT :: the app's current encryption keys could not be read — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
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
        // The private keys of the auth keys to add, derived again from the
        // request, and of the encryption keys, from the wallet.
        let signingKeys = SharedValue<[(publicKey: Data, privateKey: Data)]>([])
        defer { for index in signingKeys.value.indices { Self.zero(&signingKeys.value[index].privateKey) } }
        return try await Self.recordAndSubmitIdentityUpdate(
            intent, snapshot: snapshot, intents: context.stores.intents,
            makeExecutor: { [self] in
                try await deriveSigningKeys(
                    of: intent, request: request, plan: plan, snapshot: snapshot, context: context, into: signingKeys)
                let missing = Self.missingKeys(of: intent, in: snapshot)
                let disable = AppConnect.outstandingDisables(of: intent, in: snapshot)
                let addPublicKeys = missing.map(AppConnect.identityPubkey(of:))
                return makeExecutor { _ in
                    try await signer.withAdditionalSigningKeys(signingKeys.value) {
                        try await context.wallet.updateIdentity(
                            identityId: context.identityId,
                            addPublicKeys: addPublicKeys,
                            disablePublicKeyIds: disable,
                            signer: signer)
                    }
                }
            },
            now: now,
            // The row goes with the intent, before anything is submitted:
            // however the update ends, the user can turn the connection off.
            afterRecording: { [self] in await refreshRows(from: snapshot, context: context) },
            readAfterFailure: { [self] cause in try await readAfterFailedUpdate(cause, of: intent, context: context) })
    }

    private static func missingKeys(
        of intent: AppConnect.ConnectionIntent, in snapshot: AppConnect.IdentitySnapshot
    ) -> [AppConnect.IntendedKey] {
        intent.keys.filter { AppConnect.presence(of: $0, in: snapshot) == .missing }
    }

    /// The update that adds what of `intent` is not on the identity yet and
    /// turns off what it still has to.
    static func identityUpdateWrite(
        for intent: AppConnect.ConnectionIntent, in snapshot: AppConnect.IdentitySnapshot
    ) -> PlatformWrite {
        .updateKeys(
            add: missingKeys(of: intent, in: snapshot).map(\.id),
            disable: AppConnect.outstandingDisables(of: intent, in: snapshot))
    }

    /// Records `intent`, then sends its identity update, so whatever happens
    /// to the update the keys are named. An intent the store does not hold
    /// afterwards sends nothing. A consensus refusal is saved on the intent
    /// before it is thrown; any other failure is checked by
    /// `readAfterFailure`, which returns the read that showed the update or
    /// throws, and the intent stays, shown as confirming. Returns nil when
    /// the update was submitted.
    static func recordAndSubmitIdentityUpdate(
        _ intent: AppConnect.ConnectionIntent,
        snapshot: AppConnect.IdentitySnapshot,
        intents: any AppConnectIntentStore,
        makeExecutor: () async throws -> AppConnectWriteExecutor,
        now: () -> Date,
        afterRecording: () async -> Void,
        readAfterFailure: (Error) async throws -> AppConnect.IdentitySnapshot
    ) async throws -> AppConnect.IdentitySnapshot? {
        update(intents) { $0.append(intent) }
        guard intents.load().contains(where: { $0.id == intent.id }) else {
            throw DashConnectPlatformError.grantNotRecorded
        }
        await afterRecording()
        let executor = try await makeExecutor()
        let write = identityUpdateWrite(for: intent, in: snapshot)
        if case .updateKeys(let add, let disable) = write {
            logger.info("🔗 DASHCONNECT :: registering \(add.count, privacy: .public) key(s), disabling \(disable.count, privacy: .public)")
        }
        let outcome = await executor.run(write)
        switch AppConnect.nextStep(after: write, outcome: outcome, at: now()) {
        case .done:
            logger.info("🔗 DASHCONNECT :: identity updated")
            return nil
        case .recordRefusal(let refusal):
            throw recordRefusal(refusal, of: outcome.failure ?? AppConnectWriteTimedOut(), on: intent, in: intents)
        case .readIdentity, .lookUpResponse, .stop:
            // An identity update only ends in the cases above or a read; the
            // read is also the safe step for any other.
            return try await readAfterFailure(outcome.failure ?? AppConnectWriteTimedOut())
        }
    }

    /// Derives the private keys of the keys `intent` still has to add into
    /// `signingKeys`: the auth keys again from the request, the encryption
    /// keys from the wallet.
    private func deriveSigningKeys(
        of intent: AppConnect.ConnectionIntent,
        request: AppConnectRequest,
        plan: AppConnect.GrantPlan,
        snapshot: AppConnect.IdentitySnapshot,
        context: Context,
        into signingKeys: SharedValue<[(publicKey: Data, privateKey: Data)]>
    ) async throws {
        let missing = Self.missingKeys(of: intent, in: snapshot)
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
            signingKeys.value.append((key.data, privateKey))
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
            signingKeys.value.append((key.data, match.privateKey))
        }
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
        let propertiesJSON = try intent.response.propertiesJSON()
        let created = SharedValue<Data?>(nil)
        let executor = makeExecutor { _ in
            let (documentId, _) = try await context.wallet.createDocument(
                ownerIdentityId: context.identityId,
                contractId: responseContractId,
                documentType: AppConnect.documentType,
                propertiesJSON: propertiesJSON,
                signer: signer)
            created.value = documentId
        }
        try await Self.publishAndRecord(
            intent, intents: context.stores.intents, executor: executor, now: now,
            createdDocumentId: { created.value },
            lookUp: {
                try await Self.findAppConnectResponse(
                    ownerIdentityId: context.identityId,
                    appEphemeralPubKeyHash: intent.requestHash,
                    responseContractId: responseContractId,
                    sdk: context.sdk
                )?.documentId
            })
    }

    /// Sends the publish and records the response's document. Published only
    /// if the publish was submitted and created a document, or `lookUp` shows
    /// the response on Platform; otherwise the publish's failure is thrown.
    static func publishAndRecord(
        _ intent: AppConnect.ConnectionIntent,
        intents: any AppConnectIntentStore,
        executor: AppConnectWriteExecutor,
        now: () -> Date,
        createdDocumentId: @Sendable () -> Data?,
        lookUp: () async throws -> Data?
    ) async throws {
        let write = PlatformWrite.publish(requestHash: intent.requestHash)
        let outcome = await executor.run(write)
        let documentId: Data
        switch AppConnect.nextStep(after: write, outcome: outcome, at: now()) {
        case .done where createdDocumentId() != nil:
            documentId = createdDocumentId()!
            logger.info("🔗 DASHCONNECT :: loginKeyResponse published")
        case .done, .lookUpResponse, .recordRefusal, .readIdentity, .stop:
            // Published only if Platform shows the response.
            guard let published = try? await lookUp() else {
                throw outcome.failure ?? DashConnectPlatformError.existingDocumentLookupFailed
            }
            logger.info("🔗 DASHCONNECT :: loginKeyResponse was already published")
            documentId = published
        }
        update(intents) { intents in
            guard let index = intents.firstIndex(where: { $0.id == intent.id }) else { return }
            intents[index].responseDocumentId = documentId
            intents[index].responseRemoved = false
        }
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
        stores: Stores,
        port: any DashConnectPlatformPort,
        context: Context?,
        signer: KeychainSigner?
    ) async {
        let intents = stores.intents
        for intent in intents.load() where ids.contains(intent.id) && !intent.responseRemoved {
            func lookUp() async throws -> Data? {
                try await port.findResponse(requestHash: intent.requestHash)?.documentId
            }
            let found: (documentId: Data, values: AppConnect.ResponseValues)
            let propertiesJSON: String
            do {
                // Deleted by the values it has on Platform, which are this
                // intent's unless another install answered the same request.
                guard let response = try await port.findResponse(requestHash: intent.requestHash) else {
                    Self.markResponseRemoved(intent.id, in: intents)
                    continue
                }
                found = (response.documentId, response.values)
                propertiesJSON = try found.values.propertiesJSON()
            } catch {
                await Self.markRemovedIfGone(after: error, intent.id, in: intents, lookUp: lookUp)
                continue
            }
            let executor = makeExecutor { [self] _ in
                guard let context, let signer else { throw UnroutedWrite() }
                let signingKeyId = try selectDocumentSigningKeyId(wallet: context.wallet, identityId: context.identityId)
                _ = try await context.wallet.deleteDocument(
                    ownerIdentityId: context.identityId,
                    contractId: responseContractId,
                    documentType: AppConnect.documentType,
                    documentId: found.documentId,
                    propertiesJSON: propertiesJSON,
                    signingKeyId: signingKeyId,
                    signer: signer)
            }
            await Self.deleteResponse(
                documentId: found.documentId, of: intent.id, intents: intents, executor: executor, now: now,
                lookUp: lookUp)
        }
    }

    /// Sends the delete of a response and marks it removed when it was
    /// submitted. Best effort: a delete can land without confirming, so a
    /// failed one is marked removed only if `lookUp` shows no response; an
    /// id or a failed lookup leaves it marked as it was.
    static func deleteResponse(
        documentId: Data,
        of intentId: UUID,
        intents: any AppConnectIntentStore,
        executor: AppConnectWriteExecutor,
        now: () -> Date,
        lookUp: () async throws -> Data?
    ) async {
        let write = PlatformWrite.deleteResponse(documentId: documentId)
        let outcome = await executor.run(write)
        switch AppConnect.nextStep(after: write, outcome: outcome, at: now()) {
        case .done:
            markResponseRemoved(intentId, in: intents)
        case .lookUpResponse, .recordRefusal, .readIdentity, .stop:
            // Handled as a failed delete: only a lookup says it is gone.
            await markRemovedIfGone(after: outcome.failure ?? AppConnectWriteTimedOut(), intentId, in: intents, lookUp: lookUp)
        }
    }

    private static func markRemovedIfGone(
        after error: Error, _ id: UUID, in intents: any AppConnectIntentStore, lookUp: () async throws -> Data?
    ) async {
        logger.error("🔗 DASHCONNECT :: loginKeyResponse not deleted — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
        // A delete can land without confirming; only Platform says.
        // A lookup that fails says nothing.
        do {
            if try await lookUp() == nil { markResponseRemoved(id, in: intents) }
        } catch {
            return
        }
    }

    private static func markResponseRemoved(_ id: UUID, in intents: any AppConnectIntentStore) {
        update(intents) { intents in
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

        let resolved = await resolveWalletUsername(context: context)
        let username = try Self.requireTokenPurchaseUsername(resolved.name, lookupFailed: resolved.lookupFailed)

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
            walletUsername: username,
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
            let reason = AppConnectWriteExecutor.logDescription(of: error)
            logger.error("🔗 DASHCONNECT :: token purchase: contract fetch failed for \(id, privacy: .public): \(reason, privacy: .public); quantity shown as base units")
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
                "🔗 DASHCONNECT :: token purchase failed after submission; outcome unknown: \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
            throw DashConnectTokenPurchaseFailure.outcomeUnknown(error)
        }
    }

    func remove(id: String, scope: String?) async {
        // A row published for another wallet was not picked from this one.
        guard let stores = await showActiveWalletRows(), scope == stores.scope else { return }
        // An App Connect connection is hidden by its intents, and only when
        // it shows Refused; any other row is dropped from the list.
        if let appId = Self.decodeIdentifier(id), stores.intents.load().contains(where: { $0.appId == appId }) {
            await removeRefusedConnection(appId: appId, stores: stores)
            return
        }
        await updateRows(in: stores) { rows in rows.filter { $0.id != id } }
    }

    /// Sets `removedAt` on the Refused intents of `appId` in `snapshot`.
    /// Returns false, writing nothing, when the connection does not show
    /// Refused.
    static func hideRefused(
        appId: Data, intents: any AppConnectIntentStore, snapshot: AppConnect.IdentitySnapshot, at removedAt: Date
    ) -> Bool {
        let loaded = intents.load()
        guard let hidden = AppConnect.removing(
            appId: appId, intents: loaded, snapshots: [snapshot], at: removedAt) else { return false }
        intents.save(hidden)
        return true
    }

    /// Sets `removedAt` on the Refused intents of `appId` after a fresh read
    /// of the active identity, so a key that landed since is not hidden.
    /// Asks for no PIN and writes nothing to Platform. A connection that does
    /// not show Refused, and a read that fails, write nothing.
    private func removeRefusedConnection(appId: Data, stores: Stores) async {
        do {
            try await gated {
                let context = try await requireContext(pinnedTo: stores)
                let snapshot = try await identitySnapshot(context: context).snapshot
                let removed = Self.hideRefused(appId: appId, intents: stores.intents, snapshot: snapshot, at: now())
                guard removed else {
                    Self.logger.info("🔗 DASHCONNECT :: remove ignored; the connection does not show Refused")
                    return
                }
                await refreshRows(from: snapshot, context: context)
            }
        } catch {
            let type = String(describing: Swift.type(of: error))
            Self.logger.info("🔗 DASHCONNECT :: connection not removed — \(type, privacy: .public)")
        }
    }

    /// The protocol version of the network the wallet runs on, read without
    /// an identity: the Connections page is gated by it before any identity
    /// is involved.
    func refreshConnections() async {
        do {
            try await gated {
                guard let stores = await showActiveWalletRows() else { return }
                // The injected platform port reads the identity when one is set.
                if let platform {
                    await refreshRows(from: try await platform.readIdentity(), stores: stores, owners: platform.owners)
                    return
                }
                let context = try await requireContext(pinnedTo: stores)
                let snapshot = try await identitySnapshot(context: context).snapshot
                await recordPublishedResponses(in: snapshot, context: context)
                await refreshRows(from: snapshot, context: context)
            }
        } catch {
            Self.logger.info("🔗 DASHCONNECT :: connections not refreshed — \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
        }
    }

    func connectionDetails(id: String, scope: String?) async -> ConnectionDetails? {
        guard let stores = await showActiveWalletRows(), scope == stores.scope else { return nil }
        return await details(of: id, stores: stores)
    }

    /// The app's connection on the active identity, as the intents that hold
    /// it show it. With a read of the identity, only the intents whose keys
    /// are live, expired or may still land count, and what is left of each
    /// landed key's budget is read from Platform. Without one, every open
    /// intent counts and nothing is read.
    private func details(of appId: String, stores: Stores) async -> ConnectionDetails? {
        // Not read: the sheet says so and keeps details it already shows.
        guard let context = try? await requireContext(pinnedTo: stores) else { return nil }
        let open = stores.intents.load().filter {
            $0.identityId == context.identityId && $0.appId.toBase58String() == appId && $0.closedAt == nil
        }
        let snapshot = Self.newestSnapshots.withLock { $0[context.identityId] }
        let held = snapshot.map { snapshot in
            open.filter {
                switch AppConnect.status(of: $0, in: snapshot) {
                case .active, .expired, .confirming: return true
                case .refused, .disconnected, .neverLanded: return false
                }
            }
        } ?? open
        // The app's row is held by another identity of the wallet: its
        // intents are not the active identity's to show.
        guard !held.isEmpty else {
            return ConnectionDetails(appId: appId, identityId: nil, username: nil, access: nil)
        }
        let identityId = context.identityId.toBase58String()
        var details = ConnectionDetails(
            appId: appId, identityId: identityId, username: context.storedUsername,
            access: ConnectionAccess(intents: held, snapshot: snapshot), connectedAt: held.map(\.createdAt).max())
        // Funding is read only for keys that landed and are not disabled:
        // an intent that may still land names ids another key may hold.
        guard let snapshot else { return details }
        let landed = held.filter { AppConnect.hasLanded($0, in: snapshot) }
        let keyIds = KeyFunding.keyIds(of: landed, snapshot: snapshot)
        if !keyIds.isEmpty {
            // A read-only query: it does not touch the identity copy the
            // operations that sign use, so it does not wait on them.
            if let remaining = try? await context.sdk.fetchKeysRemainingBudgets(identityId: identityId, keyIds: keyIds) {
                details.keyFunding = KeyFunding.of(intents: landed, snapshot: snapshot, remaining: remaining)
            } else {
                details.fundingReadFailed = true
            }
        }
        return details
    }

    @discardableResult
    func disconnect(id: String, scope: String?) async throws -> DashConnectDisconnectResult {
        try await gated { try await disconnectInTurn(id: id, scope: scope) }
    }

    private func disconnectInTurn(
        id: String,
        scope: String?
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
        // The live wallet and SDK, unless a platform was given.
        var context: Context?
        var port: any DashConnectPlatformPort
        if let platform {
            port = platform
        } else {
            let live = try await requireContext(pinnedTo: stores)
            context = live
            port = LiveDashConnectPlatform(source: self, context: live)
        }
        let identityId = port.identityId
        // An intent this build cannot read may name keys of the app that are
        // still to land: nothing is turned off until it can be read.
        guard !stores.intents.hasUnreadableRows(identityId: identityId) else {
            throw DashConnectPlatformError.intentsUnreadable
        }
        var planned = try await disconnectPlan(appId: appId, port: port, intents: stores.intents)
        // The PIN is asked for only when there is something to sign.
        if !planned.plan.isEmpty {
            try await port.authorize()
            if let before = context {
                let renewed = try await contextAfterAuthorization(matching: before)
                context = renewed
                port = LiveDashConnectPlatform(source: self, context: renewed)
            }
            // Read again: the prompt can take any time. Owners still
            // unknown are read again; a known one comes from memory.
            planned = try await disconnectPlan(appId: appId, port: port, intents: stores.intents)
        }
        let plan = planned.plan
        let signer = context.map { KeychainSigner(modelContainer: $0.modelContainer) }
        var submission = DisconnectSubmission()
        if !plan.fence.isEmpty || !plan.disable.isEmpty {
            submission = try await fenceAndDisable(plan, identityId: identityId, port: port, context: context, signer: signer)
        }
        let stopped = submission.progress.stopped
        // The read after the disconnect; `nil` when it failed.
        let afterRead: AppConnect.IdentitySnapshot?
        if plan.fence.isEmpty && plan.disable.isEmpty {
            afterRead = planned.snapshot
        } else if stopped {
            // Whatever the stop came from may keep the read from working
            // too: the plan's own read then stands for the rows, and the
            // progress for the keys still live.
            afterRead = try? await port.readIdentity()
        } else {
            afterRead = await readRetryingWhileBehind { try await port.readIdentity() }
        }
        // Every update was reported done but no read shows it: the keys the
        // submission turned off are marked off in the plan's read for the
        // intents and rows, and the result counts from the progress.
        let after = afterRead ?? (stopped ? planned.snapshot : Self.projectingLanded(
            planned.snapshot, plan: plan, submission: submission, intents: stores.intents.load()))

        // An intent is done once none of its keys can still be live or land;
        // it is then closed and marked as one a disconnect ran on. While a
        // key's bound is unknown (`unplaced`, told from the read after the
        // update, or from the plan's read when that read failed, so a key
        // that landed during the update counts) the app's newest intent
        // stays open, and is marked when none of its keys can still be live
        // or land either, so its row keeps its status and Disconnect (AC-18). An intent left live is
        // marked, and stays open, only when a stopped run sent one of its
        // keys in an update reported done or of unknown outcome, or a run
        // that was not stopped left a fence on under one of its ids: once the
        // reads show it, a refresh shows Disconnected. An intent that read
        // Never landed in the plan's read, before any write, because a key
        // other than this wallet's own fence (on or off) holds one of its ids, is
        // closed without the mark, and is never the newest left open: its
        // row does not name the disconnected entry.
        let closedAt = now()
        let unplaced = afterRead.map { Self.unplacedKeyCount(of: $0, intents: stores.intents.load()) } ?? planned.unplaced
        let ownFences = Set(planned.ownFenceIds)
        let neverLandedBefore = Set(stores.intents.load().filter { intent in
            AppConnect.status(of: intent, in: planned.snapshot) == .neverLanded && intent.keys.contains {
                !ownFences.contains($0.id) && AppConnect.presence(of: $0, in: planned.snapshot) == .conflicting
            }
        }.map(\.id))
        let newestOpen = unplaced > 0
            ? stores.intents.load().filter {
                $0.appId == appId && $0.identityId == identityId && $0.closedAt == nil
                    && !neverLandedBefore.contains($0.id)
            }.max { $0.createdAt < $1.createdAt }?.id
            : nil
        updateIntents(in: stores) { intents in
            for index in intents.indices
            where intents[index].appId == appId && intents[index].identityId == identityId
                && intents[index].closedAt == nil {
                switch AppConnect.status(of: intents[index], in: after) {
                case .disconnected, .neverLanded, .refused:
                    if neverLandedBefore.contains(intents[index].id) {
                        intents[index].closedAt = closedAt
                        continue
                    }
                    if intents[index].id != newestOpen { intents[index].closedAt = closedAt }
                    intents[index].disconnectedAt = closedAt
                case .active, .confirming, .expired:
                    if intents[index].keys.contains(where: { submission.markKeyIds.contains($0.id) }) {
                        intents[index].disconnectedAt = closedAt
                    }
                }
            }
        }
        // With the PIN given, the responses an earlier disconnect could not
        // delete go too, whether or not this app has one of its own.
        if !stopped, !plan.isEmpty, let responseContractId = Self.decodeIdentifier(AppConnect.contractId) {
            let ids = Set(plan.deleteResponses).union(AppConnect.responsesLeft(identityId: identityId, intents: stores.intents.load()))
            if !ids.isEmpty {
                await deleteResponses(
                    of: Array(ids), responseContractId: responseContractId, stores: stores, port: port,
                    context: context, signer: signer)
            }
        }
        // The rows and what stays on are told from the read after the
        // update and from one read of the owners: owners read apart could
        // differ, a failed read being tried again. A key of the app that
        // landed during the update, or that an owner read now places, is
        // reported too. Without that read, the plan and the progress stand.
        let intentsAfter = stores.intents.load()
        let hasIntent = intentsAfter.contains { $0.appId == appId && $0.identityId == identityId }
        let ownersAfter = await port.owners.knownOwners(for: after, intents: intentsAfter)
        await refreshRows(from: after, stores: stores, knownOwners: ownersAfter)
        // As in the plan: an app with no intent here takes no key by owner.
        let remaining = afterRead.map {
            AppConnect.disconnectPlan(
                appId: appId, snapshot: $0, intents: intentsAfter, owners: hasIntent ? ownersAfter : [:])
        }

        // A key turned off is checked on the read after the update; one that
        // still shows live means that read is behind, or a new key landed.
        // A live key under a fence id is the wallet's fence only when it is
        // the key the wallet derives for that id; when that cannot be told,
        // it is reported as a key still live.
        let fenceKeyIds: Set<UInt32>
        if let afterRead {
            fenceKeyIds = Set(
                (try? await ownFenceKeyIds(
                    snapshot: afterRead, intents: stores.intents.load(), port: port, turnedOff: false)) ?? [])
        } else {
            fenceKeyIds = []
        }
        var result = Self.disconnectResult(
            plan: plan, appKeysOff: planned.appKeysOff, leftoverFenceIds: planned.leftoverFenceIds,
            keysNotChecked: remaining?.notChecked.count ?? planned.notChecked, fenceKeyIds: fenceKeyIds,
            after: afterRead, submission: submission)
        if let remaining {
            result.keysStillLive += Self.keysFoundAfter(
                plan: plan, remaining: remaining, fenceIds: fenceKeyIds.union(planned.leftoverFenceIds))
        }
        let ownIntents = stores.intents.load().filter { $0.appId == appId && $0.identityId == identityId }
        let unfinished = result.keysStillLive + result.fencesNotPlaced
        guard stopped || unfinished > 0 || unplaced > 0 || ownIntents.allSatisfy({ $0.closedAt != nil }) else {
            throw DashConnectPlatformError.identityKeysOutOfDate
        }
        // The app's intents on another identity of this wallet can only be
        // reached while that identity is the active one.
        if unfinished == 0, stores.intents.load().contains(where: {
            $0.appId == appId && $0.identityId != identityId && $0.closedAt == nil
        }) {
            throw DashConnectPlatformError.grantOnAnotherIdentity
        }
        result.keysNotAttributable = remaining?.notAttributable.count ?? planned.notAttributable
        // Keys a read of another identity saw stay, and so does the row.
        result.keysOnAnotherIdentity = rows(in: stores).first { $0.id == id }?.seenOn
            .subtracting([identityId.toBase58String()]).isEmpty == false
        return result
    }

    /// `snapshot` with the updates of a submission that was not stopped
    /// applied: the plan's keys turned off, and each fence key added and
    /// turned off shown as a disabled key under its id, with payload the
    /// intent's key does not have (another key holds the id). A fence left on
    /// is not shown.
    static func projectingLanded(
        _ snapshot: AppConnect.IdentitySnapshot,
        plan: AppConnect.DisconnectPlan,
        submission: DisconnectSubmission,
        intents: [AppConnect.ConnectionIntent]
    ) -> AppConnect.IdentitySnapshot {
        let offAt = snapshot.platformTime ?? 1
        let off = Set(plan.disable)
        var keys = snapshot.keys.map { key -> AppConnect.PlatformKey in
            guard off.contains(key.id), key.disabledAt == nil else { return key }
            return AppConnect.PlatformKey(
                id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType,
                data: key.data, readOnly: key.readOnly, bound: key.bound, boundKnown: key.boundKnown,
                totalBudget: key.totalBudget, expiresAt: key.expiresAt, disabledAt: offAt)
        }
        let present = Set(keys.map(\.id))
        let intended = intents.filter { $0.identityId == snapshot.identityId }.flatMap(\.authKeys)
        for id in Set(plan.fence).subtracting(submission.fencesLeftOn).subtracting(present) {
            guard let key = intended.first(where: { $0.id == id }) else { continue }
            keys.append(AppConnect.PlatformKey(
                id: id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType,
                data: Data(), readOnly: key.readOnly, bound: nil, boundKnown: false,
                totalBudget: nil, expiresAt: nil, disabledAt: offAt))
        }
        return AppConnect.IdentitySnapshot(
            identityId: snapshot.identityId, revision: snapshot.revision, keys: keys, platformTime: snapshot.platformTime)
    }

    /// What a disconnect reports. App keys still live are counted from the
    /// fresh read `after` (the plan's keys that show live, without the
    /// wallet's own fence keys); the progress stands for them only when that
    /// read failed (`after` is `nil`). Each fence key the disconnect added or
    /// may have added is sorted by that read: a live key that is the wallet's
    /// fence (`fenceKeyIds`) is placed and still on (`fencesLeftOn`: the
    /// sign-in it guards can no longer land); any other live key under the id
    /// is the app's sign-in that landed and counts as an app key still live;
    /// disabled is off; and one the read does not show may not be placed yet
    /// (`fencesNotPlaced`: the sign-in can still land). With no read, a fence
    /// whose update was not placed is `fencesNotPlaced`, and one added and not
    /// turned off, or a leftover fence the progress has still live, is
    /// `fencesLeftOn`.
    static func disconnectResult(
        plan: AppConnect.DisconnectPlan,
        appKeysOff: Int,
        leftoverFenceIds: [UInt32],
        keysNotChecked: Int,
        fenceKeyIds: Set<UInt32>,
        after: AppConnect.IdentitySnapshot?,
        submission: DisconnectSubmission
    ) -> DashConnectDisconnectResult {
        let progress = submission.progress
        let leftover = Set(leftoverFenceIds)
        let appKeys = plan.disable.filter { !leftover.contains($0) }
        let stillLiveApp: Set<UInt32>
        if let after {
            stillLiveApp = Set(appKeys.filter { id in after.keys.contains { $0.id == id && $0.disabledAt == nil } })
        } else {
            stillLiveApp = Set(progress.stillLive).subtracting(leftover)
        }
        let candidates = leftover.union(submission.fencesLeftOn).union(progress.unplacedFences)
        var fencesLeftOn = 0
        var fencesNotPlaced = 0
        var stillLiveUnderFenceIds = 0
        for id in candidates {
            guard let after else {
                // No read: what the submission reports stands.
                if progress.unplacedFences.contains(id) {
                    fencesNotPlaced += 1
                } else if submission.fencesLeftOn.contains(id) || progress.stillLive.contains(id) {
                    fencesLeftOn += 1
                }
                continue
            }
            guard let key = after.keys.first(where: { $0.id == id }) else {
                fencesNotPlaced += 1
                continue
            }
            guard key.disabledAt == nil else { continue }
            if fenceKeyIds.contains(id) {
                fencesLeftOn += 1
            } else {
                // Not the wallet's fence: the app's key landed under the id.
                stillLiveUnderFenceIds += 1
            }
        }
        let keysTurnedOff: Int
        if !progress.stopped {
            keysTurnedOff = max(0, appKeysOff - stillLiveApp.count - submission.fencesLeftOn.count)
        } else if after != nil {
            keysTurnedOff = appKeys.count - stillLiveApp.count
        } else {
            keysTurnedOff = progress.turnedOff.count
        }
        return DashConnectDisconnectResult(
            keysTurnedOff: keysTurnedOff, keysStillLive: stillLiveApp.count + stillLiveUnderFenceIds,
            keysNotChecked: keysNotChecked, fencesLeftOn: fencesLeftOn, fencesNotPlaced: fencesNotPlaced,
            unrecordedKeysTurnedOff: Set(plan.unrecorded).subtracting(stillLiveApp).count)
    }

    /// The app's live keys the plan on the read after the update would turn
    /// off that the disconnect's own plan did not have: a key that landed
    /// during the update, or one an owner read now places with the app. The
    /// wallet's fences are not the app's, and a key under an id the plan
    /// fenced is counted already (`disconnectResult`).
    static func keysFoundAfter(
        plan: AppConnect.DisconnectPlan, remaining: AppConnect.DisconnectPlan, fenceIds: Set<UInt32>
    ) -> Int {
        Set(remaining.disable).subtracting(plan.disable).subtracting(plan.fence).subtracting(fenceIds).count
    }

    /// What a disconnect of `appId` submits on the active identity, from a
    /// fresh read: the app's recorded keys, its live keys no intent names
    /// (bound to its contracts, or attributed to it by owner) and the DashPay
    /// profile keys no intent names (`AppConnect.disconnectPlan`), and the
    /// fences an earlier try left on (`leftoverFenceIds`). The owners it
    /// needs come from the port's owner memory, the rest read from Platform;
    /// an app with no intent on the identity reads none, so its row keeps its
    /// contract's keys whatever their owner. It also gives the wallet's own
    /// fences (`ownFenceIds`): the live ones, and the turned-off ones under
    /// the ids of this app's open intents that read Never landed, the only
    /// intents a turned-off fence tells apart. A fence key the wallet cannot
    /// derive in either lookup stops the disconnect here, before any write.
    /// `unplaced` counts the keys whose bound is unknown; `notChecked` adds
    /// to them the keys an unread owner keeps from being told the app's, and
    /// `notAttributable` counts the keys of the app's owner that another app
    /// here has too.
    private func disconnectPlan(
        appId: Data,
        port: any DashConnectPlatformPort,
        intents: any AppConnectIntentStore
    ) async throws -> (
        plan: AppConnect.DisconnectPlan, snapshot: AppConnect.IdentitySnapshot,
        appKeysOff: Int, leftoverFenceIds: [UInt32], ownFenceIds: [UInt32], unplaced: Int,
        notChecked: Int, notAttributable: Int
    ) {
        let snapshot = try await port.readIdentity()
        let all = intents.load()
        let hasIntent = all.contains { $0.appId == appId && $0.identityId == snapshot.identityId }
        let owners = hasIntent ? await port.owners.knownOwners(for: snapshot, intents: all) : [:]
        var plan = AppConnect.disconnectPlan(appId: appId, snapshot: snapshot, intents: all, owners: owners)
        let appKeysOff = plan.disable.count + plan.fence.count
        // A fence an earlier try added and could not turn off yet.
        let fences = try await ownFenceKeyIds(snapshot: snapshot, intents: all, port: port, turnedOff: false)
        let neverLanded = all.filter {
            $0.appId == appId && $0.closedAt == nil && AppConnect.status(of: $0, in: snapshot) == .neverLanded
        }
        let fencesOff = try await ownFenceKeyIds(snapshot: snapshot, intents: neverLanded, port: port, turnedOff: true)
        plan.disable = Set(fences).subtracting(plan.disable).sorted() + plan.disable
        let unplaced = Self.unplacedKeyCount(of: snapshot, intents: all)
        return (plan, snapshot, appKeysOff, fences, fences + fencesOff, unplaced,
                plan.notChecked.count, plan.notAttributable.count)
    }

    /// The ids of this wallet's fence keys under the key ids of `intents`
    /// that are live, or with `turnedOff` turned off: a fence is turned off
    /// once it holds its id, and an update that failed in between leaves it on.
    private func ownFenceKeyIds(
        snapshot: AppConnect.IdentitySnapshot,
        intents: [AppConnect.ConnectionIntent],
        port: any DashConnectPlatformPort,
        turnedOff: Bool
    ) async throws -> [UInt32] {
        let ids = Set(intents.filter { $0.identityId == snapshot.identityId }.flatMap { $0.authKeys.map(\.id) })
        var own: [UInt32] = []
        for key in snapshot.keys
        where (key.disabledAt != nil) == turnedOff && ids.contains(key.id) && key.bound == nil
            && key.keyType == .ecdsaHash160 {
            if try await port.fenceKeyHash(keyId: key.id) == key.data { own.append(key.id) }
        }
        return own
    }

    /// The port over the active wallet and the SDK: the PIN prompt, the
    /// proved identity read, the fence key the wallet derives and the
    /// response document the SDK lists.
    private struct LiveDashConnectPlatform: DashConnectPlatformPort, @unchecked Sendable {
        let source: PlatformDashConnectDataSource
        let context: Context

        var identityId: Data { context.identityId }

        var owners: OwnerReader { PlatformDashConnectDataSource.ownerReader(context: context) }

        func authorize() async throws {
            try await source.authorize()
        }

        func readIdentity() async throws -> AppConnect.IdentitySnapshot {
            try await source.identitySnapshot(context: context).snapshot
        }

        func fenceKeyHash(keyId: UInt32) async throws -> Data {
            let leaf = AppConnect.fenceKeyLeaf(identityId: context.identityId, keyId: keyId)
            let context = context
            let (publicKey, derivedPrivateKey) = try await MainActor.run {
                let derived = try context.wallet.deriveConnectKey(
                    subFeature: .sessionAuthentication, identityId: context.identityId, leaf: leaf, network: context.network)
                return (derived.publicKeyData, derived.privateKeyData)
            }
            var privateKey = derivedPrivateKey
            PlatformDashConnectDataSource.zero(&privateKey)
            return try KeyExchangeCrypto.hash160(publicKey)
        }

        func findResponse(requestHash: Data) async throws -> (documentId: Data, values: AppConnect.ResponseValues)? {
            guard let responseContractId = PlatformDashConnectDataSource.decodeIdentifier(AppConnect.contractId) else {
                throw DashConnectPlatformError.loginContractUnavailable
            }
            return try await PlatformDashConnectDataSource.findAppConnectResponse(
                ownerIdentityId: context.identityId,
                appEphemeralPubKeyHash: requestHash,
                responseContractId: responseContractId,
                sdk: context.sdk)
        }
    }

    /// What `submitDisconnect` got done.
    struct DisconnectSubmission {
        var progress = AppConnect.DisconnectProgress()
        /// Fence keys added and not turned off.
        var fencesLeftOn: [UInt32] = []
        /// The first error of an update that failed.
        var failure: Error?
        /// The key ids whose intents the disconnect marks though they may
        /// still read live. When the run stopped: the ids (turned off and
        /// fence) of the phase-1 updates that landed or may still land, those
        /// reported done and the one whose outcome is unknown; a refused
        /// update's ids and those of updates never sent are not in it. When it
        /// was not stopped: the fences left on, placed under the ids of the
        /// intents the disconnect ran on.
        var markKeyIds: Set<UInt32> = []
    }

    /// Submits a disconnect through `AppConnect.submit`: a fence key under
    /// each id an intent may still land on, and every key to turn off, as many
    /// per update as Platform takes. A failing update stops it and is
    /// returned, not thrown.
    private func fenceAndDisable(
        _ plan: AppConnect.DisconnectPlan,
        identityId: Data,
        port: any DashConnectPlatformPort,
        context: Context?,
        signer: KeychainSigner?
    ) async throws -> DisconnectSubmission {
        var fenceKeys: [UInt32: ManagedPlatformWallet.IdentityPubkey] = [:]
        for id in plan.fence {
            fenceKeys[id] = AppConnect.fenceKey(keyId: id, publicKeyHash160: try await port.fenceKeyHash(keyId: id))
        }
        let fences = fenceKeys
        Self.logger.info("🔗 DASHCONNECT :: fencing \(fences.count, privacy: .public) key id(s), disabling \(plan.disable.count, privacy: .public) key(s)")
        // One executor for both phases. The phase that adds fence keys and
        // turns off the plan's keys is an `updateKeys`; the phase that turns
        // the added fences off, which only disables, is a `fence`. The
        // private key of each fence to add is derived inside the write and
        // zeroed when the write ends.
        let submit: @Sendable (PlatformWrite) async throws -> Void = { write in
            guard let context, let signer else { throw UnroutedWrite() }
            switch write {
            case .updateKeys(let add, let disable):
                var signingKeys: [(publicKey: Data, privateKey: Data)] = []
                defer { for index in signingKeys.indices { Self.zero(&signingKeys[index].privateKey) } }
                for id in add {
                    guard let key = fences[id] else { continue }
                    let leaf = AppConnect.fenceKeyLeaf(identityId: identityId, keyId: id)
                    let derivedPrivateKey = try await MainActor.run {
                        try context.wallet.deriveConnectKey(
                            subFeature: .sessionAuthentication, identityId: identityId, leaf: leaf, network: context.network
                        ).privateKeyData
                    }
                    signingKeys.append((key.pubkeyBytes, derivedPrivateKey))
                }
                try await signer.withAdditionalSigningKeys(signingKeys) {
                    try await context.wallet.updateIdentity(
                        identityId: identityId,
                        addPublicKeys: add.compactMap { fences[$0] },
                        disablePublicKeyIds: disable,
                        signer: signer)
                }
            case .fence(let keyIds):
                try await context.wallet.updateIdentity(
                    identityId: identityId, disablePublicKeyIds: keyIds, signer: signer)
            case .publish, .deleteResponse:
                throw UnroutedWrite()
            }
        }
        let executor = makeExecutor(submit: submit)
        return await Self.submitDisconnect(plan, executor: executor, now: now)
    }

    /// Runs the plan's writes through `executor`: phase 1 adds the fence keys
    /// and turns off the plan's keys (`AppConnect.submit`); phase 2 turns the
    /// added fences off. Phase 2 is skipped when phase 1 stopped, and stops at
    /// its first step that is not `.done`.
    static func submitDisconnect(
        _ plan: AppConnect.DisconnectPlan,
        executor: AppConnectWriteExecutor,
        now: () -> Date
    ) async -> DisconnectSubmission {
        var failure: Error?
        var added: [UInt32] = []
        var sentKeyIds: Set<UInt32> = []
        let progress = await AppConnect.submit(plan) { update in
            let write = PlatformWrite.updateKeys(add: update.fence, disable: update.disable)
            let outcome = await executor.run(write)
            let step = AppConnect.nextStep(after: write, outcome: outcome, at: now())
            switch step {
            case .done:
                added += update.fence
                sentKeyIds.formUnion(update.disable)
                sentKeyIds.formUnion(update.fence)
            case .recordRefusal, .readIdentity, .lookUpResponse, .stop:
                if case .readIdentity = step {
                    sentKeyIds.formUnion(update.disable)
                    sentKeyIds.formUnion(update.fence)
                }
                // The update is not known to have landed: the run stops, the
                // keys of the updates not confirmed count as still live, and
                // the next disconnect reads and carries on.
                let cause = outcome.failure ?? AppConnectWriteTimedOut()
                failure = failure ?? cause
                throw cause
            }
        }
        var fencesLeftOn: [UInt32] = []
        // A disabled key still holds its id, so the fences are turned off once
        // they are there: none stays able to sign. One left on by a failure
        // here is the wallet's own key, limited to one credit; the next
        // disconnect finds it and turns it off.
        var start = 0
        if progress.stopped {
            fencesLeftOn = added
            start = added.count
        }
        while start < added.count {
            let end = min(start + AppConnect.maxKeysDisabledPerUpdate, added.count)
            let write = PlatformWrite.fence(keyIds: Array(added[start ..< end]))
            let outcome = await executor.run(write)
            guard case .done = AppConnect.nextStep(after: write, outcome: outcome, at: now()) else {
                failure = failure ?? outcome.failure ?? AppConnectWriteTimedOut()
                fencesLeftOn = Array(added[start...])
                break
            }
            start = end
        }
        return DisconnectSubmission(
            progress: progress, fencesLeftOn: fencesLeftOn, failure: failure,
            markKeyIds: progress.stopped ? sentKeyIds : Set(fencesLeftOn))
    }

    /// A write handed to the executor that this call does not route.
    private struct UnroutedWrite: Error {}

    /// A value shared between a call and the write it hands to the executor.
    /// A submit that outlives its timeout keeps running, so a secret a write
    /// reads lives here, where the call zeroes it in place when it ends; the
    /// reads and writes of one call do not overlap, which is why it has no lock.
    private final class SharedValue<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    /// The executor of one write: the injected factory's, or the live one.
    private func makeExecutor(
        submit: @escaping @Sendable (PlatformWrite) async throws -> Void
    ) -> AppConnectWriteExecutor {
        makeWriteExecutor?(submit) ?? writeExecutor(submit: submit)
    }

    /// The executor of one write: the clock is `Task.sleep`, the log lines go
    /// to this class's logger (a failed or timed-out write as an error, the
    /// rest as info), and `submit` is the SDK call.
    private func writeExecutor(
        submit: @escaping @Sendable (PlatformWrite) async throws -> Void
    ) -> AppConnectWriteExecutor {
        AppConnectWriteExecutor(
            sleep: { try await Task.sleep(for: $0) },
            log: { line in
                if line.hasSuffix(": start") || line.hasSuffix(": submitted") {
                    Self.logger.info("🔗 DASHCONNECT :: \(line, privacy: .public)")
                } else {
                    Self.logger.error("🔗 DASHCONNECT :: \(line, privacy: .public)")
                }
            },
            submit: submit)
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

    /// Publishes the active wallet's rows as stored, after a save under
    /// `scopeKey` by any store instance.
    @MainActor
    private func showStoredRows(savedUnder scopeKey: String?) {
        guard store.scopeKey == scopeKey, let active = pinnedActiveStores(),
              active.connections.scopeKey == scopeKey,
              shownRows.scope == active.scope else { return }
        subject.send(active.published(rows(in: active)))
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
        let expectedRuntimeNetwork: Network
        switch supportedNetwork {
        case .mainnet: expectedRuntimeNetwork = .mainnet
        case .testnet: expectedRuntimeNetwork = .testnet
        case .devnet: expectedRuntimeNetwork = .devnet
        }
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
            Self.logger.error("🔗 DASHCONNECT :: app metadata resolution failed for \(contractId, privacy: .public): \(AppConnectWriteExecutor.logDescription(of: error), privacy: .public)")
        }

        return fallback
    }

    /// The identity's DPNS name, else the stored one; `lookupFailed` when the
    /// DPNS read failed rather than found no name.
    private func resolveWalletUsername(context: Context) async -> (name: String?, lookupFailed: Bool) {
        let identityId = context.identityId.toBase58String()

        let usernames: [[String: Any]]
        do {
            usernames = try await context.sdk.dpnsGetUsername(identityId: identityId, limit: 1)
        } catch {
            return (context.storedUsername, true)
        }
        if let label = usernames.first?["label"] as? String,
           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (label, false)
        }

        return (context.storedUsername, false)
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
    /// One queue per kind of read, so a slow contract-keys read does not hold
    /// back the protocol-version read a sheet waits for.
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

extension AppConnect {
    /// The answer to a `dash-key:` v2 request on mainnet: a connection
    /// request reaches mainnet through a DashPay connect link or code only.
    static var dashKeyOnMainnetRefusal: Refusal { Refusal(.unsupported, NSLocalizedString(
        "This kind of code is not accepted on mainnet. Ask the app for a DashPay connect link or code.",
        comment: "DashConnect App Connect: a dash-key code scanned on mainnet")) }

    /// Which codes the wallet refuses on `network`, from the code's scheme
    /// and `v=` alone: a `dash-key:` code that is not version 2 is refused
    /// on every network (`v1Refusal`), and a version 2 one on mainnet
    /// (`dashKeyOnMainnetRefusal`). Whether the rest of the code parses is
    /// the parser's business.
    static func intakeRefusal(forCode code: String, network: DashConnectNetwork) -> Refusal? {
        guard DashConnectUri.isKeyUri(code) else { return nil }
        guard DashConnectUri.isAppConnectUri(code) else { return v1Refusal }
        return network == .mainnet ? dashKeyOnMainnetRefusal : nil
    }
}
