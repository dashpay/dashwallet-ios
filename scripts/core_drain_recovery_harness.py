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
        "    func performCoreDrainAction()",
        "    private func showCoreDrainCompletion()",
        "    private func refreshCoreDrainPreview()",
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
    static let context = CoreShieldedDrainContext(walletId: Data([1]), networkScope: "testnet")
    static var recorded: CoreShieldedDrainOperation?
    static var outcome = WalletDrainOutcome(state: .pending, outpoint: nil)
    static var quotes = 0
    static var lookups: [UUID] = []
    static var suspendNextStatus = false
    static var statusGate: CheckedContinuation<Void, Never>?
    static var didRemoveMarker: (() -> Void)?
    var store: Self { self }
    func load(_ context: CoreShieldedDrainContext) throws -> CoreShieldedDrainOperation? { Self.recorded }
    static func currentContext() throws -> CoreShieldedDrainContext { context }
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
        case contextChanged
        var errorDescription: String? { "Context changed" }
    }
}
@MainActor final class InternalTransferRunner {
    static let shared = InternalTransferRunner()
    func resumeCoreDrain(context: CoreShieldedDrainContext, operation: CoreShieldedDrainOperation?) async -> WalletDrainOutcome? {
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
    var maxNotice: String?
    var amountText = "0"
    var maxAmountDuffs: UInt64?
    var isApplyingMax = false
    func clearMaxSelection() { isCoreShieldedDrain = false }
    func applyMaxAmountText(_ amount: UInt64) { amountText = String(amount) }
''' + methods + "\n}\n")
    (tests / "RecoveryFormTests.swift").write_text(r'''
import XCTest
@testable import CoreDrainHarness
final class RecoveryFormTests: XCTestCase {
    @MainActor private func reset() -> CoreShieldedDrainOperation {
        let operation = CoreShieldedDrainOperation(id: UUID(), context: CoreShieldedDrainService.context)
        CoreShieldedDrainService.recorded = operation
        CoreShieldedDrainService.quotes = 0
        CoreShieldedDrainService.lookups = []
        CoreShieldedDrainService.suspendNextStatus = false
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
    @MainActor func testSuccessfulResumeShowsSuccessAfterRunnerClearsMarker() async throws {
        _ = reset()
        CoreShieldedDrainService.outcome = .init(state: .pending, outpoint: 1)
        let form = RecoveryForm()
        form.refreshCoreDrainPreview()
        await form.coreDrainTask?.value
        form.performCoreDrainAction()
        for _ in 0..<100 where form.isCoreDrainLoading { await Task.yield() }
        XCTAssertTrue(form.coreDrainCompleted)
        XCTAssertNotNil(form.coreDrainCompletionNotice)
        XCTAssertNil(form.maxNotice)
        XCTAssertEqual(CoreShieldedDrainService.quotes, 0)
    }
}
''')
