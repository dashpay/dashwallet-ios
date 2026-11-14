import Foundation
import OSLog

enum WalletEnvironment {
    static var activeWalletIdHex: String?
}
enum SDKError: Error { case stateTransitionResultUnconfirmed(String) }
enum PlatformWalletError: Error {
    struct Consensus { let code: Int; let kind: String }
    case consensusRejection(Consensus, String)
    var errorDescription: String? { String(describing: self) }
    var failureReason: String? { nil }
    case assetLockAlreadyConsumed
    case shieldedSpendUnconfirmed
    case transactionBroadcastUnconfirmed(String)
    case walletOperation(String)
    case assetLockRecipientMismatch(String)
}
struct WalletDrainOutpoint: Sendable {
    let txidWire: Data
    let vout: UInt32
}
struct WalletDrainOutcome: Sendable {
    enum State: UInt8, Sendable { case notSent, pending, completed }
    let state: State
    let outpoint: WalletDrainOutpoint?
}
struct ShieldedFundFromAssetLockRecipient {
    let recipientRaw43: Data
    let credits: UInt64?
}
typealias PlatformWalletManager = TestManager

@MainActor
final class TestManager {
    var error: Error?
    var calls = 0
    var receivedTxid: Data?
    var receivedVout: UInt32?
    var receivedRecipients: [ShieldedFundFromAssetLockRecipient] = []
    func shieldedResumeFundFromAssetLock(walletId: Data, outPointTxid: Data, outPointVout: UInt32,
                                         recipients: [ShieldedFundFromAssetLockRecipient]) async throws {
        calls += 1
        receivedTxid = outPointTxid
        receivedVout = outPointVout
        receivedRecipients = recipients
        if let error { throw error }
    }
}
@MainActor final class SwiftDashSDKHost {
    static let shared = SwiftDashSDKHost()
    var manager: TestManager?
}

// Dependency seam for the drain context check added by develop. Recovery
// tests must explicitly supply an outcome instead of fabricating a manager.
@MainActor
struct CoreShieldedDrainService {
    enum TestError: Error { case contextChanged }
    static var marker: CoreShieldedDrainMarkerLookup = .unavailable
    /// The wallet/network context the service reports; `nil` reads as a
    /// wallet that is not ready, as in production.
    static var context: CoreShieldedDrainContext?
    func markerLookup() -> (CoreShieldedDrainMarkerLookup, CoreShieldedDrainContext?) { (Self.marker, Self.context) }
    static func currentContext() throws -> CoreShieldedDrainContext {
        guard let context else { throw TestError.contextChanged }
        return context
    }
    static var resolveManager: ((CoreShieldedDrainContext) throws -> TestManager)?
    func manager(for context: CoreShieldedDrainContext) throws -> TestManager {
        guard let resolveManager = Self.resolveManager else { throw TestError.contextChanged }
        return try resolveManager(context)
    }
    /// The drain the runner looks up, and what each later status read returns.
    static var operation: (operation: CoreShieldedDrainOperation, outcome: WalletDrainOutcome)?
    static var statusReads: [Result<WalletDrainOutcome, Error>] = []
    func operationStatus(_ context: CoreShieldedDrainContext) async throws
        -> (operation: CoreShieldedDrainOperation, outcome: WalletDrainOutcome)? {
        Self.operation
    }
    func status(for operation: CoreShieldedDrainOperation) async throws -> WalletDrainOutcome {
        guard !Self.statusReads.isEmpty else { preconditionFailure("Test must supply each drain status read") }
        return try Self.statusReads.removeFirst().get()
    }
}
@MainActor
final class ShieldedTxLookup {
    static let shared = ShieldedTxLookup()
    struct Info { let statusRaw: Int; var drainOperation: UUID? { nil } }
    var consumed = Set<Data>()
    func markConsumed(txidWire: Data) { consumed.insert(txidWire) }
    func info(forTxidHex: String) -> Info? { nil }
    func platformFundingInfo(forTxidHex: String) -> Info? { nil }
    func refresh(reason: String) async {}
}
extension Notification.Name {
    static let swiftDashSDKTransactionProjectionDidChange = Notification.Name("projection")
}
@MainActor
final class ShieldedTransferCoordinator {
    enum CoordinatorError: Error {
        case transferFailed(Error), assetLockInFlight, walletReloading, authCancelled, drainRecipientUnavailable, drainRecipientUnknown, resumeRecipientMismatch, noWallet, addressFundingFeeUnavailable
        var errorDescription: String? { "Authentication cancelled" }
    }
    enum Phase: Equatable {
        case idle, signing, locking, proving, broadcasting, success, submittedUnconfirmed, failed(String)
        var isInFlight: Bool { self == .signing || self == .locking || self == .proving || self == .broadcasting }
    }
    enum ResumeReport { case alreadyConsumed }
    struct Environment {
        let manager: TestManager
        let walletId: Data
        let shieldedRecipient: Data
        var network: String { "testnet" }
        var modelContainer: Void { () }
    }
    struct ResumeRow {
        let identity: CoreShieldedDrainRowIdentity
        let recordedRecipientRaw43: Data?

        func recipient(
            marker: () -> CoreShieldedDrainMarkerLookup,
            callerRaw43: Data?,
            ownRaw43: Data
        ) -> ShieldedResumeRecipient {
            ShieldedResumeRecipient.resolve(
                recordedRaw43: recordedRecipientRaw43,
                row: identity,
                marker: marker,
                callerRaw43: callerRaw43,
                ownRaw43: ownRaw43)
        }
    }
    var platformFunding: PlatformAddressSyncCoordinator { .shared }
    static var rowLookup: (() -> CoreShieldedDrainRowIdentity?)?
    /// The recipient the SDK recorded on the row; `nil` for a row tracked
    /// before the SDK recorded recipients.
    static var recordedRecipient: Data?
    static func resumeRow(outPointTxidWire: Data, vout: UInt32, walletId: Data, in container: Void) -> ResumeRow? {
        guard let rowLookup else { preconditionFailure("Test must configure the asset-lock row") }
        return rowLookup().map { ResumeRow(identity: $0, recordedRecipientRaw43: recordedRecipient) }
    }
    typealias BasicEnvironment = Environment
    var basicEnvironmentOverride: Environment?
    func resolveBasicEnvironment() throws -> BasicEnvironment { basicEnvironmentOverride ?? environment }
    static let addressAssetLockFundingType = 4
    static let shieldedAssetLockFundingType = 5
    let failureStore = AssetLockFailureStore(defaults: UserDefaults(suiteName: "RecoveryHarness." + UUID().uuidString)!)
    static let logger = Logger(subsystem: "RecoveryHarness", category: "test")
    var phase: Phase = .idle {
        didSet {
            if !phase.isInFlight { releaseInFlightOutPoint() }
            onPhaseChange?(phase)
        }
    }
    var onPhaseChange: ((Phase) -> Void)?
    var inputLimitCheck: AssetLockInputLimit.Check? { nil }
    var inFlightOutPoint: ShieldedAssetLocksInFlight.OutPoint?
    static let drainSettleTimeout: TimeInterval = 30
    var lastResumeReport: ResumeReport?
    var lastFailure: Error?
    var lastAssetLockContext: CoreShieldedDrainContext?
    var lastAssetLockOutPoint: ShieldedAssetLocksInFlight.OutPoint?
    let environment: Environment
    var authorizations = 0
    var onAuthorize: (() -> Void)?
    var authorizationError: Error?
    init(environment: Environment) { self.environment = environment }
    func resolveEnvironment() throws -> Environment { environment }
    func authorize() async throws {
        authorizations += 1
        onAuthorize?()
        if let authorizationError { throw authorizationError }
    }
    func stopAssetLockPolling() {}
    func handleFailure(_ error: Error) {
        lastFailure = error
        phase = .failed(error is CancellationError ? CoordinatorError.authCancelled.errorDescription! : "test failure")
    }
    enum Funding { case coinJoinDrain }
    var newAssetLockCalls = 0
    func performAssetLock(funding: Funding) async { newAssetLockCalls += 1 }
    func scheduleShieldedResync(manager: TestManager) {}
    func schedulePlatformResync() {}
    // PRODUCTION_METHODS
}

// Actual caller retry methods are inserted by the runner. Presentation and
// fresh-send boundaries only record calls; native work uses the coordinator above.
@MainActor final class SwiftDashSDKWalletState {
    static let shared = SwiftDashSDKWalletState()
    func refreshCoinJoinBalance() {}
}
@MainActor final class CoinJoinRetryHarness {
    enum Destination { case shielded }
    enum Stage: Equatable {
        case choice, shielding, success(Destination), submittedUnconfirmed
        case failed(message: String, destination: Destination)
    }
    var stage: Stage = .choice
    var isInFlight = false
    let coordinator: ShieldedTransferCoordinator
    var newDrainCalls: Int { coordinator.newAssetLockCalls }
    init(_ coordinator: ShieldedTransferCoordinator) { self.coordinator = coordinator }
    var binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding?
    var unresumedLock: ShieldedAssetLocksInFlight.OutPoint?
    enum Preparation { case authorizing }
    var preparation: Preparation?
    var consolidationSent = false
    static let genericFailureMessage = "test failure"
    nonisolated static var unresumedLockMessage: String { "Resume the existing lock" }
    static func log(_ message: String) {}
    func unobservedConsolidationRefusal() -> String? { preconditionFailure("Unexpected fresh drain") }
    struct Plan {
        struct State { let binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding }
        let state: State?
        let needsPreparation: Bool
        let description: String
    }
    static func plan(expecting binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding?) -> Plan {
        preconditionFailure("Unexpected fresh drain planning")
    }
    func authorizeShieldedMove() async -> Bool { preconditionFailure("Unexpected fresh drain authorization") }
    func prepareForDrain(needed: Bool, from state: Plan.State) async -> Bool { preconditionFailure("Unexpected fresh drain preparation") }
    func drainToShielded(expecting binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding) async { preconditionFailure("Unexpected second drain") }
    // COINJOIN_HELPERS
    // COINJOIN_MOVE
    // COINJOIN_FINISH
    // COINJOIN_RETRY
}

@MainActor final class SendRetryHarness {
    enum Route { case coreToShielded, platformToShielded }
    var route: Route = .platformToShielded
    var isCoreDrain = false
    var destinationRaw43: Data?
    let coordinator: ShieldedTransferCoordinator
    var cancellations = 0
    var confirmations = 0
    init(_ coordinator: ShieldedTransferCoordinator) { self.coordinator = coordinator }
    func onCancel() { cancellations += 1 }
    func confirm() { confirmations += 1 }
    // SEND_RETRY
}

// The Max drain runner's resume and its mirroring of the coordinator's phase
// are production methods; authorization and request metadata are fakes.
struct InternalTransferRequest {
    enum Kind { case route(Int) }
    let kind: Kind
    var coreShieldedDrain: Int?
}
@MainActor final class RunnerAuthorizer {
    var authorizations = 0
    func authorize() async throws { authorizations += 1 }
}
enum DWIdentityAuthorizer {
    static func preauthorized<T>(_ body: () async -> T) async -> T { await body() }
}
@MainActor final class InternalTransferRunner {
    var phase: Phase = .idle
    var notice: Notice?
    var request: InternalTransferRequest?
    var isAwaitingAuthorization = false
    var isCoreDrainRecovery = false
    let coordinator: ShieldedTransferCoordinator
    let authorizer = RunnerAuthorizer()
    init(_ coordinator: ShieldedTransferCoordinator) {
        self.coordinator = coordinator
        coordinator.onPhaseChange = { [weak self] in self?.apply($0) }
    }
    func notePlatformShieldCapacityChange() {}
    // RUNNER_RESUME
}

// Input-limit edge: no recovery test exceeds it, and the coordinator's only
// envelope is `transferFailed`.
enum AssetLockInputLimit {
    struct Check: Equatable {}
    static func innermost(_ error: Error) -> Error {
        if case ShieldedTransferCoordinator.CoordinatorError.transferFailed(let underlying) = error {
            return innermost(underlying)
        }
        return error
    }
}

@MainActor enum SwiftDashSDKTransactionSender {
    struct CoinJoinWalletBinding: Equatable {
        let walletId: Data
        let network: String
        static var selected: Self?
        static func current() -> Self? { selected }
    }
}

// Diagnostic output edges; retry decisions and failure persistence are production code.
enum AssetLockRecoveryService {
    enum RecoveryError: Error { case failed(String, Error?) }
}
enum DiagnosticLogExporter {
    static func fundingTypeName(_ value: Int) -> String { String(value) }
    static func assetLockStatusName(_ value: Int) -> String { String(value) }
}
enum DWLogger { static func log(_ message: String) {} }

@MainActor final class DrainClaimSettler {
    init(operation: UUID, timeout: TimeInterval, lookup: ShieldedTxLookup) {}
    func start() { preconditionFailure("Completed drain settling belongs to the application tests") }
}

@MainActor final class PlatformAddressSyncCoordinator {
    static let shared = PlatformAddressSyncCoordinator()
    var resume: ((Data, UInt32, UInt64) async throws -> Void)?
    func checkFundFromCoreResumable(outPointTxid: Data, outPointVout: UInt32) throws {}
    func resumeFundFromCore(outPointTxid: Data, outPointVout: UInt32, recipientAmountDuffs: UInt64) async throws {
        guard let resume else { preconditionFailure("Test must supply the native resume outcome") }
        try await resume(outPointTxid, outPointVout, recipientAmountDuffs)
    }
}
