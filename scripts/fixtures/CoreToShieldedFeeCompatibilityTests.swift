import XCTest
@testable import ProtocolCompatibilityHarness

final class CoreToShieldedFeeCompatibilityTests: XCTestCase {
    @MainActor
    func testCheckFailureKeepsCachedQuoteAndRealVersionChangeRequotes() async {
        let host = SwiftDashSDKHost.shared
        host.reset()
        XCTAssertEqual(CoreToShieldedAmountPolicy.poolFeeCredits, 50_000_100)
        XCTAssertEqual(CoreToShieldedAmountPolicy.poolFeeCredits, 50_000_100)
        XCTAssertEqual(host.manager?.calls, 1)

        host.compatible = false
        host.generation += 1
        XCTAssertEqual(CoreToShieldedAmountPolicy.poolFeeCredits, 50_000_100)
        XCTAssertEqual(host.manager?.calls, 1)

        host.compatible = true
        host.version = 14
        host.manager?.fee = 200
        XCTAssertEqual(CoreToShieldedAmountPolicy.poolFeeCredits, 50_000_200)
        XCTAssertEqual(host.manager?.calls, 2)
    }

    @MainActor
    func testRecreatedRuntimeCannotReuseSameGenerationQuote() async {
        let host = SwiftDashSDKHost.shared
        host.reset()
        XCTAssertEqual(CoreToShieldedAmountPolicy.poolFeeCredits, 50_000_100)
        host.reset()
        host.manager?.fee = 300
        XCTAssertEqual(CoreToShieldedAmountPolicy.poolFeeCredits, 50_000_300)
        XCTAssertEqual(host.manager?.calls, 1)
    }

    @MainActor
    func testQuoteChangedDuringNativeEstimateIsDiscarded() async {
        let host = SwiftDashSDKHost.shared
        host.reset()
        host.manager?.onEstimate = { host.version += 1 }
        XCTAssertNil(CoreToShieldedAmountPolicy.poolFeeCredits)
        host.manager?.onEstimate = nil
        XCTAssertEqual(CoreToShieldedAmountPolicy.poolFeeCredits, 50_000_100)
        XCTAssertEqual(host.manager?.calls, 2)
    }

    @MainActor
    func testFailedEstimateDoesNotPoisonRetry() async {
        let host = SwiftDashSDKHost.shared
        host.reset()
        host.manager?.onEstimate = { throw SwiftDashSDKHost.Refusal.estimateFailed }
        XCTAssertNil(CoreToShieldedAmountPolicy.poolFeeCredits)
        host.manager?.onEstimate = nil
        XCTAssertEqual(CoreToShieldedAmountPolicy.poolFeeCredits, 50_000_100)
        XCTAssertEqual(host.manager?.calls, 2)
    }
}
