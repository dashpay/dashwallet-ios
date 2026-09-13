import XCTest
#if canImport(dashwallet)
@testable import dashwallet
#elseif canImport(dashpay)
@testable import dashpay
#else
@testable import ShieldedBalanceHarness
#endif

final class HomeBalancePresentationTests: XCTestCase {
    func testRestoredPlatformIsIncludedWithoutRuntimeReadiness() {
        let balance = HomeBalancePresentation(transparentDuffs: 10, platformState: .available(20_000), shieldedCredits: 30_000, showsPlatformBalance: true)
        XCTAssertTrue(balance.showsBreakdown)
        XCTAssertEqual(balance.platformDuffs, 20)
        XCTAssertEqual(balance.totalDuffs, 60)
        XCTAssertFalse(balance.isPartial)
    }

    func testUnknownPlatformKeepsRowAndKnownComponents() {
        let balance = HomeBalancePresentation(transparentDuffs: 10, platformState: .unavailable, shieldedCredits: 30_000, showsPlatformBalance: true)
        XCTAssertTrue(balance.showsBreakdown)
        XCTAssertNil(balance.platformDuffs)
        XCTAssertEqual(balance.totalDuffs, 40)
        XCTAssertTrue(balance.isPartial)
    }

    func testAdvancedBreakdownIsVisibleBeforeBothLocalReads() {
        let balance = HomeBalancePresentation(transparentDuffs: 10, platformState: .unavailable, shieldedCredits: nil, showsPlatformBalance: true)
        XCTAssertTrue(balance.showsBreakdown)
        XCTAssertEqual(balance.totalDuffs, 10)
        XCTAssertTrue(balance.isPartial)
    }

    func testKnownZeroIsComplete() {
        let balance = HomeBalancePresentation(transparentDuffs: 10, platformState: .available(0), shieldedCredits: 0, showsPlatformBalance: true)
        XCTAssertEqual(balance.platformDuffs, 0)
        XCTAssertEqual(balance.totalDuffs, 10)
        XCTAssertFalse(balance.isPartial)
    }

    func testSimpleModeExcludesPlatformAndItsAvailability() {
        for state in [PlatformBalanceState.unavailable, .available(20_000)] {
            let balance = HomeBalancePresentation(transparentDuffs: 10, platformState: state, shieldedCredits: 30_000, showsPlatformBalance: false)
            XCTAssertEqual(balance.totalDuffs, 40)
            XCTAssertFalse(balance.isPartial)
        }
    }

    func testUnknownShieldedKeepsKnownPlatform() {
        let balance = HomeBalancePresentation(transparentDuffs: 10, platformState: .available(20_000), shieldedCredits: nil, showsPlatformBalance: true)
        XCTAssertEqual(balance.totalDuffs, 30)
        XCTAssertTrue(balance.isPartial)
    }
}
