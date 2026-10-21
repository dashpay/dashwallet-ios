"""Compile the production form's recovery methods with controlled SDK responses."""


def write_recovery_harness(repository, sources, tests):
    source = (repository / "DashWallet/Sources/UI/Payments/InternalTransfer/InternalTransferViewModel.swift").read_text()

    def declaration(start):
        offset = source.index(start)
        opening = source.index("{", offset)
        depth, closing = 1, opening + 1
        while depth:
            depth += (source[closing] == "{") - (source[closing] == "}")
            closing += 1
        return source[offset:closing].replace("private func", "func", 1)

    methods = "\n".join(declaration(start) for start in (
        "    var coreDrainCompletionNotice:",
        "    var coreDrainActionTitle:",
        "    @discardableResult\n    func performCoreDrainAction()",
        "    private func showCoreDrainCompletion()",
        "    private func refreshCoreDrainPreview()",
        "    private func clearMaxSelection()",
    ))
    # No duplicate implementation of the status/quote decision: those methods
    # above are extracted verbatim from the app. Only external dependencies and
    # unrelated form fields are substituted, as in test_wallet_preparation.py.
    (sources / "RecoveryForm.swift").write_text(r'''
import Foundation
struct WalletDrainOutcome {
    enum State { case pending, completed, notStarted }
    let state: State
    let outpoint: Int?
}
struct CoreShieldedDrainConfirmation {
    let context: CoreShieldedDrainContext
    let candidateBalanceDuffs: UInt64
    let estimatedRecipientCredits: UInt64?
    let estimatedL1FeeDuffs: UInt64?
    let poolFeeCredits: UInt64
}
struct Quote {
    enum Status { case insufficientFunds, ready, inputLimitMayBeExceeded }
    let status: Status = .insufficientFunds
    let candidateBalanceDuffs: UInt64 = 0
    let estimatedRecipientCredits: UInt64? = nil
    let estimatedL1FeeDuffs: UInt64? = nil
    let poolFeeCredits: UInt64 = 0
}
@MainActor struct CoreShieldedDrainService {
    static var context = CoreShieldedDrainContext(walletId: Data([1]), networkScope: "testnet")
    static var recorded: CoreShieldedDrainOperation?
    static var outcome = WalletDrainOutcome(state: .pending, outpoint: nil)
    static var quotes = 0
    static var lookups: [UUID] = []
    static var suspendNextStatus = false
    static var unavailable = false
    static var statusGate: CheckedContinuation<Void, Never>?
    static var didRemoveMarker: (() -> Void)?
    var store: Self { self }
    func load(_ context: CoreShieldedDrainContext) throws -> CoreShieldedDrainOperation? { Self.recorded }
    static func currentContext() throws -> CoreShieldedDrainContext {
        if unavailable { throw ServiceError.unavailable }
        return context
    }
    func status(for operation: CoreShieldedDrainOperation) async throws -> WalletDrainOutcome {
        Self.lookups.append(operation.id)
        let outcome = Self.outcome
        if outcome.state != .pending { Self.recorded = nil }
        if Self.suspendNextStatus {
            Self.suspendNextStatus = false
            await withCheckedContinuation { continuation in
                Self.statusGate = continuation
                Self.didRemoveMarker?()
            }
        }
        return outcome
    }
    func operationStatus(_ context: CoreShieldedDrainContext) async throws
        -> (operation: CoreShieldedDrainOperation, outcome: WalletDrainOutcome)? {
        guard let operation = Self.recorded else { return nil }
        return (operation, try await status(for: operation))
    }
    func manager(for context: CoreShieldedDrainContext) throws -> Self { self }
    func shieldedWalletDrainPreview(walletId: Data) async throws -> Quote {
        Self.quotes += 1
        return Quote()
    }
    enum ServiceError: LocalizedError {
        case contextChanged, unavailable
        var errorDescription: String? { self == .unavailable ? "Wallet unavailable" : "Context changed" }
    }
}
@MainActor final class InternalTransferRunner {
    static let shared = InternalTransferRunner()
    var resumeGate: CheckedContinuation<Void, Never>?
    var didStartResume: (() -> Void)?
    func resumeCoreDrain(context: CoreShieldedDrainContext, operation: CoreShieldedDrainOperation?) async -> WalletDrainOutcome? {
        if didStartResume != nil {
            await withCheckedContinuation { continuation in
                resumeGate = continuation
                didStartResume?()
            }
        }
        CoreShieldedDrainService.recorded = nil
        return WalletDrainOutcome(state: .completed, outpoint: 1)
    }
}
@MainActor final class RecoveryForm {
    var isCoreShieldedDrain = true
    var isCoreDrainLoading = false
    var coreShieldedDrainConfirmation: CoreShieldedDrainConfirmation?
    var coreDrainPending = false
    var coreDrainCompleted = false
    var coreDrainOperation: CoreShieldedDrainOperation?
    var coreDrainHasOutpoint = false
    var coreDrainContext: CoreShieldedDrainContext?
    var coreDrainTask: Task<Void, Never>?
    var coreDrainGeneration = UUID()
    var coreDrainSelection = UUID()
    var coreDrainResumeSelection: UUID?
    var isFullShieldedSweep = false
    var shieldedSweepAmountCredits: UInt64?
    var isPlatformShieldMaxDerived = false
    var isPlatformShieldMaxQueued = false
    var hasPlatformShieldCapacityChangeNotice = false
    var maxNotice: String?
    var amountText = "0"
    var maxAmountDuffs: UInt64?
    var isApplyingMax = false
    func applyMaxAmountText(_ amount: UInt64) { amountText = String(amount) }
    func coreDrainInsufficientFundsMessage() -> String { "Insufficient funds" }
''' + methods + "\n}\n")
    (tests / "RecoveryFormTests.swift").write_text(r'''
import XCTest
@testable import CoreDrainHarness
final class RecoveryFormTests: XCTestCase {
    @MainActor private func reset() -> CoreShieldedDrainOperation {
        CoreShieldedDrainService.context = .init(walletId: Data([1]), networkScope: "testnet")
        InternalTransferRunner.shared.resumeGate = nil
        InternalTransferRunner.shared.didStartResume = nil
        let operation = CoreShieldedDrainOperation(id: UUID(), context: CoreShieldedDrainService.context)
        CoreShieldedDrainService.recorded = operation
        CoreShieldedDrainService.quotes = 0
        CoreShieldedDrainService.lookups = []
        CoreShieldedDrainService.suspendNextStatus = false
        CoreShieldedDrainService.unavailable = false
        CoreShieldedDrainService.statusGate = nil
        CoreShieldedDrainService.didRemoveMarker = nil
        return operation
    }
    @MainActor func testCompletedStatusShowsSuccessWithZeroCoreWithoutRequestingNewQuote() async {
        _ = reset()
        CoreShieldedDrainService.outcome = .init(state: .completed, outpoint: 1)
        let form = RecoveryForm()
        form.refreshCoreDrainPreview()
        await form.coreDrainTask?.value
        XCTAssertTrue(form.coreDrainCompleted)
        XCTAssertNotNil(form.coreDrainCompletionNotice)
        XCTAssertNil(form.maxNotice)
        XCTAssertNil(form.coreShieldedDrainConfirmation)
        XCTAssertNil(CoreShieldedDrainService.recorded)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
        // Balance updates cannot silently replace the success with fee errors.
        form.refreshCoreDrainPreview()
        await form.coreDrainTask?.value
        XCTAssertTrue(form.coreDrainCompleted)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
        // Only the explicit separate transfer action may request another quote.
        form.performCoreDrainAction()
        await form.coreDrainTask?.value
        XCTAssertFalse(form.coreDrainCompleted)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 1)
    }
    @MainActor func testCheckStatusRetainsUUIDEvenWhenAnotherReaderClearsMarker() async {
        let operation = reset()
        CoreShieldedDrainService.outcome = .init(state: .pending, outpoint: nil)
        let form = RecoveryForm()
        form.refreshCoreDrainPreview()
        await form.coreDrainTask?.value
        XCTAssertTrue(form.coreDrainPending)
        CoreShieldedDrainService.recorded = nil
        CoreShieldedDrainService.outcome = .init(state: .completed, outpoint: 1)
        form.performCoreDrainAction()
        await form.coreDrainTask?.value
        XCTAssertTrue(form.coreDrainCompleted)
        XCTAssertEqual(CoreShieldedDrainService.lookups, [operation.id, operation.id])
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
    }
    @MainActor func testBalanceRefreshDuringInitialCompletionRetainsUUIDAfterMarkerRemoval() async {
        let operation = reset()
        CoreShieldedDrainService.outcome = .init(state: .completed, outpoint: 1)
        CoreShieldedDrainService.suspendNextStatus = true
        let markerRemoved = expectation(description: "Status removed marker but has not delivered completion")
        CoreShieldedDrainService.didRemoveMarker = { markerRemoved.fulfill() }
        let form = RecoveryForm()
        form.refreshCoreDrainPreview()
        let initialTask = form.coreDrainTask
        await fulfillment(of: [markerRemoved], timeout: 2)
        XCTAssertNil(CoreShieldedDrainService.recorded)
        XCTAssertEqual(form.coreDrainOperation?.id, operation.id)
        // This is the balance subscriber's refresh while the initial status
        // task is suspended in the post-completion projection refresh.
        form.refreshCoreDrainPreview()
        await form.coreDrainTask?.value
        CoreShieldedDrainService.statusGate?.resume()
        CoreShieldedDrainService.statusGate = nil
        await initialTask?.value
        XCTAssertTrue(form.coreDrainCompleted)
        XCTAssertNotNil(form.coreDrainCompletionNotice)
        XCTAssertNil(form.maxNotice)
        XCTAssertEqual(CoreShieldedDrainService.lookups, [operation.id, operation.id])
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
    }
    @MainActor private func suspendedResume() async -> (RecoveryForm, Task<Void, Never>?) {
        _ = reset()
        CoreShieldedDrainService.outcome = .init(state: .pending, outpoint: 1)
        let form = RecoveryForm()
        form.refreshCoreDrainPreview()
        await form.coreDrainTask?.value
        let started = expectation(description: "Resume awaits authorization/execution")
        InternalTransferRunner.shared.didStartResume = { started.fulfill() }
        let action = form.performCoreDrainAction()
        XCTAssertNotNil(action)
        await fulfillment(of: [started], timeout: 2)
        return (form, action)
    }
    @MainActor private func completeResume(_ action: Task<Void, Never>?) async {
        InternalTransferRunner.shared.resumeGate?.resume()
        InternalTransferRunner.shared.resumeGate = nil
        // Join the real form action, including its rejection/completion logic.
        await action?.value
    }
    @MainActor func testResumeCompletionSurvivesOverlappingPendingBalanceRefresh() async {
        let (form, action) = await suspendedResume()
        form.refreshCoreDrainPreview()
        await form.coreDrainTask?.value
        XCTAssertTrue(form.coreDrainPending)
        await completeResume(action)
        XCTAssertTrue(form.coreDrainCompleted)
        XCTAssertFalse(form.coreDrainPending)
        XCTAssertNil(form.maxNotice)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
    }
    @MainActor func testBalanceRefreshDuringResumeKeepsTheFormBusy() async {
        let (form, action) = await suspendedResume()
        let lookups = CoreShieldedDrainService.lookups
        // A balance change while the runner is still proving the lock: the
        // lock reads as pending, but the form must not offer Resume again.
        form.refreshCoreDrainPreview()
        await form.coreDrainTask?.value
        XCTAssertTrue(form.isCoreDrainLoading)
        XCTAssertNil(form.coreDrainActionTitle)
        XCTAssertNil(form.performCoreDrainAction())
        XCTAssertEqual(CoreShieldedDrainService.lookups, lookups)
        await completeResume(action)
        XCTAssertTrue(form.coreDrainCompleted)
        XCTAssertFalse(form.isCoreDrainLoading)
        XCTAssertNil(form.maxNotice)
    }
    @MainActor func testResumeCompletionIsRejectedAfterReselectingSameOperation() async {
        let (form, action) = await suspendedResume()
        form.clearMaxSelection()
        form.isCoreShieldedDrain = true
        form.refreshCoreDrainPreview()
        await form.coreDrainTask?.value
        await completeResume(action)
        XCTAssertFalse(form.coreDrainCompleted)
        XCTAssertTrue(form.coreDrainPending)
    }
    @MainActor func testResumeCompletionIsRejectedAfterLeavingMax() async {
        let (form, action) = await suspendedResume()
        form.clearMaxSelection()
        await completeResume(action)
        XCTAssertFalse(form.coreDrainCompleted)
        XCTAssertFalse(form.isCoreShieldedDrain)
    }
    @MainActor func testResumeCompletionIsRejectedWhenNetworkChangesBeforeNotification() async {
        let (form, action) = await suspendedResume()
        CoreShieldedDrainService.context = .init(walletId: Data([1]), networkScope: "devnet-b")
        await completeResume(action)
        XCTAssertFalse(form.coreDrainCompleted)
        // The rejected result still releases the gate: the form re-derives
        // its state and reports the changed context.
        await form.coreDrainTask?.value
        XCTAssertFalse(form.isCoreDrainLoading)
        XCTAssertFalse(form.isCoreShieldedDrain)
        XCTAssertEqual(form.maxNotice, "Context changed")
    }
    @MainActor func testResumeRejectedWhileWalletUnavailableKeepsAnAction() async {
        let (form, action) = await suspendedResume()
        CoreShieldedDrainService.unavailable = true
        await completeResume(action)
        await form.coreDrainTask?.value
        XCTAssertFalse(form.coreDrainCompleted)
        XCTAssertFalse(form.isCoreDrainLoading)
        XCTAssertNotNil(form.coreDrainActionTitle)
        XCTAssertEqual(form.maxNotice, "Wallet unavailable")
        CoreShieldedDrainService.unavailable = false
        InternalTransferRunner.shared.didStartResume = nil
        let retry = form.performCoreDrainAction()
        XCTAssertNotNil(retry)
        await retry?.value
        XCTAssertTrue(form.coreDrainCompleted)
    }
    @MainActor func testSuccessfulResumeShowsSuccessAfterRunnerClearsMarker() async throws {
        _ = reset()
        CoreShieldedDrainService.outcome = .init(state: .pending, outpoint: 1)
        let form = RecoveryForm()
        form.refreshCoreDrainPreview()
        await form.coreDrainTask?.value
        let action = form.performCoreDrainAction()
        await action?.value
        XCTAssertTrue(form.coreDrainCompleted)
        XCTAssertNotNil(form.coreDrainCompletionNotice)
        XCTAssertNil(form.maxNotice)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
    }
}
''')

    source = (repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKWalletWiper.swift").read_text()
    deletion = declaration("    static func deleteWalletFromSDK(")
    (sources / "WalletDeletion.swift").write_text(r'''
import Foundation
import OSLog
// Only unrelated app state and SDK deletion are substituted. Tests inject
// deletion success/failure and use the real drain store on temporary files.
enum SwiftDashSDKWalletDeletionError: Error { case managerUnavailable }
@MainActor final class SwiftDashSDKHost {
    static let shared = SwiftDashSDKHost()
    var manager: Manager? { nil }
    final class Manager {
        func deleteWallet(walletId: Data) throws { fatalError("Tests must inject SDK deletion") }
    }
}
final class UnrelatedPerWalletState {
    static let shared = UnrelatedPerWalletState()
    func clearPerWalletKeys(forWalletIdHex: String) {}
    func clearForWallet(walletIdHex: String) {}
}
typealias CrowdNodeDefaults = UnrelatedPerWalletState
typealias CoinJoinWithdrawalStore = UnrelatedPerWalletState
typealias ShieldedWithdrawalStore = UnrelatedPerWalletState
typealias AssetLockProbeStore = UnrelatedPerWalletState
enum GeneratedWalletIdentityMarker { static func clear(walletId: Data) {} }
enum SPVChainStoreRebuild { static func finish(walletIds: [Data], scope: String) {} }
@MainActor enum SwiftDashSDKWalletWiper {
    static let logger = Logger(subsystem: "core-drain-tests", category: "deletion")
''' + deletion + "\n}\n")
