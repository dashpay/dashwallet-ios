"""Compile the production Max controller with controlled SDK responses."""


def write_recovery_harness(repository, sources, tests, sdk_stubs):
    """Symlink the real controller into the package and stub only its edges.

    The decision logic (status before quote, retained UUID, resume rejection)
    is the real file, not a copy: `CoreShieldedDrainMaxController.swift` is
    compiled as-is against a stub `SwiftDashSDK` module and stub service,
    runner and confirmation types, as in test_wallet_preparation.py.
    """
    controller = repository / "DashWallet/Sources/UI/Payments/InternalTransfer/Shielded/CoreShieldedDrainMaxController.swift"
    (sources / controller.name).symlink_to(controller)

    (sdk_stubs / "SwiftDashSDK.swift").write_text(r'''
import Foundation
public struct WalletDrainOutpoint: Sendable, Equatable {
    public let txidWire: Data
    public let vout: UInt32
    public init(txidWire: Data, vout: UInt32) { self.txidWire = txidWire; self.vout = vout }
}
public struct WalletDrainOutcome: Sendable {
    public enum State: UInt8, Sendable { case notSent = 0, pending = 1, completed = 2 }
    public let state: State
    public let outpoint: WalletDrainOutpoint?
    public init(state: State, outpoint: WalletDrainOutpoint?) { self.state = state; self.outpoint = outpoint }
}
public struct WalletDrainPreview: Sendable, Equatable {
    public enum Status: UInt8, Sendable { case ready = 0, insufficientFunds = 1, inputLimitMayBeExceeded = 2 }
    public let candidateInputCount: UInt64
    public let candidateBalanceDuffs: UInt64
    public let poolFeeCredits: UInt64
    public let estimatedL1FeeDuffs: UInt64?
    public let estimatedRecipientCredits: UInt64?
    public let status: Status
    public init(candidateInputCount: UInt64, candidateBalanceDuffs: UInt64, poolFeeCredits: UInt64,
                estimatedL1FeeDuffs: UInt64?, estimatedRecipientCredits: UInt64?, status: Status) {
        self.candidateInputCount = candidateInputCount
        self.candidateBalanceDuffs = candidateBalanceDuffs
        self.poolFeeCredits = poolFeeCredits
        self.estimatedL1FeeDuffs = estimatedL1FeeDuffs
        self.estimatedRecipientCredits = estimatedRecipientCredits
        self.status = status
    }
}
''')

    (sources / "RecoveryEdges.swift").write_text(r'''
import Foundation
import SwiftDashSDK
enum CoreShieldedDrainVerdict: Equatable, Sendable {
    case notSent
    case pending(hasOutpoint: Bool)
    case completed
}
extension WalletDrainOutcome {
    var drainVerdict: CoreShieldedDrainVerdict {
        switch state {
        case .notSent: return .notSent
        case .pending: return .pending(hasOutpoint: outpoint != nil)
        case .completed: return .completed
        }
    }
}
struct CoreShieldedDrainConfirmation: Equatable {
    let context: CoreShieldedDrainContext
    let candidateBalanceDuffs: UInt64
    let estimatedRecipientCredits: UInt64?
    let estimatedL1FeeDuffs: UInt64?
    let poolFeeCredits: UInt64
}
@MainActor struct CoreShieldedDrainService {
    static var context = CoreShieldedDrainContext(walletId: Data([1]), networkScope: "testnet")
    static var recorded: CoreShieldedDrainOperation?
    static var outcome = WalletDrainOutcome(state: .pending, outpoint: nil)
    static var preview = WalletDrainPreview(
        candidateInputCount: 0, candidateBalanceDuffs: 0, poolFeeCredits: 0,
        estimatedL1FeeDuffs: nil, estimatedRecipientCredits: nil, status: .insufficientFunds)
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
    func manager(for context: CoreShieldedDrainContext) throws -> Self { self }
    func shieldedWalletDrainPreview(walletId: Data) async throws -> WalletDrainPreview {
        Self.quotes += 1
        return Self.preview
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
        return WalletDrainOutcome(state: .completed, outpoint: WalletDrainOutpoint(txidWire: Data(), vout: 0))
    }
}
''')

    (tests / "RecoveryFormTests.swift").write_text(r'''
import XCTest
@testable import CoreDrainHarness
/// The owning form, reduced to what the controller asks of it: the amount
/// field and a whole-Max reset, as `InternalTransferViewModel` and
/// `SendViewModel` provide them.
@MainActor final class RecoveryForm {
    private(set) var controller: CoreShieldedDrainMaxController!
    var amountText = "0"
    var contextChanges = 0
    init() {
        controller = CoreShieldedDrainMaxController(dependencies: .init(
            insufficientFundsMessage: { "Insufficient funds" },
            applyEstimate: { [unowned self] duffs in self.amountText = duffs.map(String.init) ?? "0" },
            onContextChanged: { [unowned self] in
                self.contextChanges += 1
                self.clearMaxSelection()
                self.amountText = "0"
            },
            completionMessage: { "Completed" }))
    }
    func clearMaxSelection() { controller.clear() }
}
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
        CoreShieldedDrainService.outcome = .init(state: .completed, outpoint: .init(txidWire: Data(), vout: 0))
        let form = RecoveryForm()
        let controller = form.controller!
        controller.select()
        await controller.task?.value
        XCTAssertTrue(controller.isCompleted)
        XCTAssertNotNil(controller.completionNotice)
        XCTAssertNil(controller.notice)
        XCTAssertNil(controller.confirmation)
        XCTAssertNil(CoreShieldedDrainService.recorded)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
        // Balance updates cannot silently replace the success with fee errors.
        controller.refresh()
        await controller.task?.value
        XCTAssertTrue(controller.isCompleted)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
        // Only the explicit separate transfer action may request another quote.
        controller.performAction()
        await controller.task?.value
        XCTAssertFalse(controller.isCompleted)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 1)
    }
    @MainActor func testCheckStatusRetainsUUIDEvenWhenAnotherReaderClearsMarker() async {
        let operation = reset()
        CoreShieldedDrainService.outcome = .init(state: .pending, outpoint: nil)
        let controller = RecoveryForm().controller!
        controller.select()
        await controller.task?.value
        XCTAssertTrue(controller.isPending)
        XCTAssertEqual(controller.actionTitle, "Check status")
        CoreShieldedDrainService.recorded = nil
        CoreShieldedDrainService.outcome = .init(state: .completed, outpoint: .init(txidWire: Data(), vout: 0))
        controller.performAction()
        await controller.task?.value
        XCTAssertTrue(controller.isCompleted)
        XCTAssertEqual(CoreShieldedDrainService.lookups, [operation.id, operation.id])
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
    }
    @MainActor func testBalanceRefreshDuringInitialCompletionRetainsUUIDAfterMarkerRemoval() async {
        let operation = reset()
        CoreShieldedDrainService.outcome = .init(state: .completed, outpoint: .init(txidWire: Data(), vout: 0))
        CoreShieldedDrainService.suspendNextStatus = true
        let markerRemoved = expectation(description: "Status removed marker but has not delivered completion")
        CoreShieldedDrainService.didRemoveMarker = { markerRemoved.fulfill() }
        let controller = RecoveryForm().controller!
        controller.select()
        let initialTask = controller.task
        await fulfillment(of: [markerRemoved], timeout: 2)
        XCTAssertNil(CoreShieldedDrainService.recorded)
        XCTAssertEqual(controller.operation?.id, operation.id)
        // This is the balance subscriber's refresh while the initial status
        // task is suspended in the post-completion projection refresh.
        controller.refresh()
        await controller.task?.value
        CoreShieldedDrainService.statusGate?.resume()
        CoreShieldedDrainService.statusGate = nil
        await initialTask?.value
        XCTAssertTrue(controller.isCompleted)
        XCTAssertNotNil(controller.completionNotice)
        XCTAssertNil(controller.notice)
        XCTAssertEqual(CoreShieldedDrainService.lookups, [operation.id, operation.id])
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
    }
    @MainActor private func suspendedResume() async -> (RecoveryForm, Task<Void, Never>?) {
        _ = reset()
        CoreShieldedDrainService.outcome = .init(state: .pending, outpoint: .init(txidWire: Data(), vout: 0))
        let form = RecoveryForm()
        form.controller.select()
        await form.controller.task?.value
        XCTAssertEqual(form.controller.actionTitle, "Resume transfer")
        let started = expectation(description: "Resume awaits authorization/execution")
        InternalTransferRunner.shared.didStartResume = { started.fulfill() }
        let action = form.controller.performAction()
        XCTAssertNotNil(action)
        await fulfillment(of: [started], timeout: 2)
        return (form, action)
    }
    @MainActor private func completeResume(_ action: Task<Void, Never>?) async {
        InternalTransferRunner.shared.resumeGate?.resume()
        InternalTransferRunner.shared.resumeGate = nil
        // Join the real action, including its rejection/completion logic.
        await action?.value
    }
    @MainActor func testResumeCompletionSurvivesOverlappingPendingBalanceRefresh() async {
        let (form, action) = await suspendedResume()
        form.controller.refresh()
        await form.controller.task?.value
        XCTAssertTrue(form.controller.isPending)
        await completeResume(action)
        XCTAssertTrue(form.controller.isCompleted)
        XCTAssertFalse(form.controller.isPending)
        XCTAssertNil(form.controller.notice)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
    }
    @MainActor func testBalanceRefreshDuringResumeKeepsTheFormBusy() async {
        let (form, action) = await suspendedResume()
        let lookups = CoreShieldedDrainService.lookups
        // A balance change while the runner is still proving the lock: the
        // lock reads as pending, but the form must not offer Resume again.
        form.controller.refresh()
        await form.controller.task?.value
        XCTAssertTrue(form.controller.isLoading)
        XCTAssertNil(form.controller.actionTitle)
        XCTAssertNil(form.controller.performAction())
        XCTAssertEqual(CoreShieldedDrainService.lookups, lookups)
        await completeResume(action)
        XCTAssertTrue(form.controller.isCompleted)
        XCTAssertFalse(form.controller.isLoading)
        XCTAssertNil(form.controller.notice)
    }
    @MainActor func testResumeCompletionIsRejectedAfterReselectingSameOperation() async {
        let (form, action) = await suspendedResume()
        form.clearMaxSelection()
        form.controller.select()
        await form.controller.task?.value
        await completeResume(action)
        XCTAssertFalse(form.controller.isCompleted)
        XCTAssertTrue(form.controller.isPending)
    }
    @MainActor func testResumeCompletionIsRejectedAfterLeavingMax() async {
        let (form, action) = await suspendedResume()
        form.clearMaxSelection()
        await completeResume(action)
        XCTAssertFalse(form.controller.isCompleted)
        XCTAssertFalse(form.controller.isActive)
    }
    @MainActor func testResumeCompletionIsRejectedWhenNetworkChangesBeforeNotification() async {
        let (form, action) = await suspendedResume()
        CoreShieldedDrainService.context = .init(walletId: Data([1]), networkScope: "devnet-b")
        await completeResume(action)
        XCTAssertFalse(form.controller.isCompleted)
        // The rejected result still releases the gate: the form re-derives
        // its state and reports the changed context.
        await form.controller.task?.value
        XCTAssertFalse(form.controller.isLoading)
        XCTAssertFalse(form.controller.isActive)
        XCTAssertEqual(form.contextChanges, 1)
        XCTAssertEqual(form.amountText, "0")
        XCTAssertEqual(form.controller.notice, "Context changed")
    }
    @MainActor func testResumeRejectedWhileWalletUnavailableKeepsAnAction() async {
        let (form, action) = await suspendedResume()
        CoreShieldedDrainService.unavailable = true
        await completeResume(action)
        await form.controller.task?.value
        XCTAssertFalse(form.controller.isCompleted)
        XCTAssertFalse(form.controller.isLoading)
        XCTAssertNotNil(form.controller.actionTitle)
        XCTAssertEqual(form.controller.notice, "Wallet unavailable")
        CoreShieldedDrainService.unavailable = false
        InternalTransferRunner.shared.didStartResume = nil
        let retry = form.controller.performAction()
        XCTAssertNotNil(retry)
        await retry?.value
        XCTAssertTrue(form.controller.isCompleted)
    }
    @MainActor func testSuccessfulResumeShowsSuccessAfterRunnerClearsMarker() async throws {
        _ = reset()
        CoreShieldedDrainService.outcome = .init(state: .pending, outpoint: .init(txidWire: Data(), vout: 0))
        let controller = RecoveryForm().controller!
        controller.select()
        await controller.task?.value
        let action = controller.performAction()
        await action?.value
        XCTAssertTrue(controller.isCompleted)
        XCTAssertNotNil(controller.completionNotice)
        XCTAssertNil(controller.notice)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
    }
    @MainActor func testReadyQuoteFillsTheEstimateAndCarriesAConfirmation() async {
        _ = reset()
        CoreShieldedDrainService.recorded = nil
        CoreShieldedDrainService.preview = .init(
            candidateInputCount: 2, candidateBalanceDuffs: 2_000_000, poolFeeCredits: 9_000,
            estimatedL1FeeDuffs: 500, estimatedRecipientCredits: 1_999_500_000, status: .ready)
        let form = RecoveryForm()
        form.controller.select()
        await form.controller.task?.value
        XCTAssertEqual(CoreShieldedDrainService.lookups, [])
        XCTAssertEqual(CoreShieldedDrainService.quotes, 1)
        XCTAssertEqual(form.amountText, "1999500")
        XCTAssertEqual(form.controller.confirmation?.candidateBalanceDuffs, 2_000_000)
        XCTAssertNotNil(form.controller.estimateNotice)
        XCTAssertNil(form.controller.actionTitle)
        // An insufficient-funds quote carries nothing to confirm and names the owner's reason.
        CoreShieldedDrainService.preview = .init(
            candidateInputCount: 0, candidateBalanceDuffs: 0, poolFeeCredits: 0,
            estimatedL1FeeDuffs: nil, estimatedRecipientCredits: nil, status: .insufficientFunds)
        form.controller.refresh()
        await form.controller.task?.value
        XCTAssertNil(form.controller.confirmation)
        XCTAssertEqual(form.controller.notice, "Insufficient funds")
        XCTAssertEqual(form.controller.actionTitle, "Try again")
    }
}
''')

    source = (repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKWalletWiper.swift").read_text()

    def declaration(start):
        offset = source.index(start)
        opening = source.index("{", offset)
        depth, closing = 1, opening + 1
        while depth:
            depth += (source[closing] == "{") - (source[closing] == "}")
            closing += 1
        return source[offset:closing].replace("private func", "func", 1)

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
