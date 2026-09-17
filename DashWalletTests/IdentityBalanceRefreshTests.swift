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

    func testConfirmedZeroBalanceIsPublished() async {
        var result: UInt64?
        await IdentityBalanceRefresh.run(
            isCurrent: { true }, refresh: { 0 },
            publish: { result = $0 }, onFailure: { _ in XCTFail() })
        XCTAssertEqual(result, 0)
    }
}
