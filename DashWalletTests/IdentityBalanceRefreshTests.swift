import XCTest
#if canImport(dashpay)
@testable import dashpay
#else
@testable import IdentityBalanceHarness
#endif

@MainActor
final class IdentityBalanceRefreshTests: XCTestCase {
    private enum Failure: Error { case offline, persistence }

    func testPostDpnsPublishesNetworkBalanceOnlyAfterRefreshCompletes() async {
        let before: UInt64 = 2_818_262_560
        let after: UInt64 = 2_743_797_100
        var displayed = before
        var events: [String] = []
        await IdentityBalanceRefresh.run(
            isCurrent: { true },
            refresh: {
                XCTAssertEqual(displayed, before)
                events.append("network-and-persistence")
                return after
            },
            publish: { displayed = $0; events.append("publish") },
            onFailure: { XCTFail("Unexpected failure: \($0)") })
        XCTAssertEqual(before - displayed, 32_138_660 + 42_326_800)
        XCTAssertEqual(events, ["network-and-persistence", "publish"])
    }

    func testReadOrPersistenceFailureDoesNotFailSuccessfulRegistrationOrPublishZero() async {
        for failure in [Failure.offline, .persistence] {
            var reported = false
            await IdentityBalanceRefresh.run(
                isCurrent: { true },
                refresh: { throw failure },
                publish: { _ in XCTFail("Keep last known balance") },
                onFailure: { _ in reported = true })
            // The post-registration refresh returns normally in both cases.
            XCTAssertTrue(reported)
        }
    }

    func testStaleContextDoesNotStartRead() async {
        await IdentityBalanceRefresh.run(
            isCurrent: { false },
            refresh: { XCTFail("Old wallet must not be queried"); return 0 },
            publish: { _ in XCTFail("Old wallet must not be published") },
            onFailure: { _ in XCTFail("No operation expected") })
    }

    func testContextSwitchDuringReadDoesNotPublishToNewProfile() async {
        let original = IdentityBalanceRefresh.Context(network: "testnet", walletId: Data([1]), identityId: Data([2]))
        for destination in [
            IdentityBalanceRefresh.Context(network: "mainnet", walletId: Data([1]), identityId: Data([2])),
            .init(network: "testnet", walletId: Data([3]), identityId: Data([2])),
            .init(network: "testnet", walletId: Data([1]), identityId: Data([4]))
        ] {
            var current = original
            await IdentityBalanceRefresh.run(
                isCurrent: { current == original },
                refresh: { current = destination; return 2_743_797_100 },
                publish: { _ in XCTFail("Stale profile response") },
                onFailure: { _ in XCTFail("Unexpected error") })
        }
    }

    func testCancelledRefreshDoesNotPublishAfterReadCompletes() async {
        let task = Task { @MainActor in
            await IdentityBalanceRefresh.run(
                isCurrent: { true }, previousBalance: { 42 },
                refresh: {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return 43
                },
                publish: { _ in XCTFail("Dismissed profile must not publish") },
                onFailure: { _ in XCTFail() })
        }
        await task.value
    }

    func testUnchangedBalanceStillPersistsWithoutPublishing() async {
        for balance: UInt64 in [0, 42] {
            var persisted = false
            await IdentityBalanceRefresh.run(
                isCurrent: { true }, previousBalance: { balance },
                refresh: { persisted = true; return balance },
                publish: { _ in XCTFail("Unchanged balance must not notify observers") },
                onFailure: { _ in XCTFail() })
            XCTAssertTrue(persisted)
        }
    }

    func testChangedBalancePublishesAfterPersistence() async {
        for balance: UInt64 in [0, 43] {
            var persisted = false
            var published: UInt64?
            await IdentityBalanceRefresh.run(
                isCurrent: { true }, previousBalance: { 42 },
                refresh: { persisted = true; return balance },
                publish: { XCTAssertTrue(persisted); published = $0 },
                onFailure: { _ in XCTFail() })
            XCTAssertEqual(published, balance)
        }
    }

    func testConfirmedZeroBalanceIsPublished() async {
        var result: UInt64?
        await IdentityBalanceRefresh.run(
            isCurrent: { true }, refresh: { 0 },
            publish: { result = $0 }, onFailure: { _ in XCTFail() })
        XCTAssertEqual(result, 0)
    }

    #if !canImport(dashpay)
    // The standalone runner compiles the actual coordinator completion block.
    func testCoordinatorReturnsSuccessAndClearsDraftWhileBalanceReadIsSuspended() async throws {
        let coordinator = RegistrationCompletionHarness()
        UsernameRegistrationDraftStore.didClear = false
        DWContestedNameStatusService.shared.didClearPending = false
        let readStarted = expectation(description: "Balance read started")
        let readFinished = expectation(description: "Balance read finished")
        var resumeRead: CheckedContinuation<Void, Never>?
        var returnedSuccess = false
        DWCurrentUserIdentityInfo.shared.refresh = {
            XCTAssertTrue(returnedSuccess, "Success must return before optional balance read")
            XCTAssertEqual(coordinator.newController.completedIdentity, coordinator.identityId)
            XCTAssertTrue(UsernameRegistrationDraftStore.didClear)
            XCTAssertTrue(DWContestedNameStatusService.shared.didClearPending)
            await withCheckedContinuation { continuation in
                resumeRead = continuation
                readStarted.fulfill()
            }
            readFinished.fulfill()
        }
        defer { DWCurrentUserIdentityInfo.shared.refresh = {} }
        let completed = expectation(description: "Registration returned")
        let registration = Task { @MainActor in
            let identity = try await coordinator.completeRegistration()
            XCTAssertEqual(identity, coordinator.identityId)
            returnedSuccess = true
            completed.fulfill()
        }
        await fulfillment(of: [completed, readStarted], timeout: 2)
        // A context switch while the optional read is suspended cannot undo
        // completed registration or trigger a later coordinator validation.
        coordinator.validateContext = { XCTFail("Registration already completed") }
        resumeRead?.resume()
        await fulfillment(of: [readFinished], timeout: 2)
        try await registration.value
    }
    #endif

}
