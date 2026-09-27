import XCTest
#if canImport(dashwallet)
@testable import dashwallet
#elseif canImport(dashpay)
@testable import dashpay
#else
@testable import ShieldedBalanceHarness
#endif

final class HomeBalancePresentationTests: XCTestCase {
    func testAllUnknownBalancesHaveNoTotal() {
        for showsPlatform in [false, true] {
            let balance = HomeBalancePresentation(transparentDuffs: nil, platformState: .unavailable, shieldedCredits: nil, showsPlatformBalance: showsPlatform)
            XCTAssertNil(balance.transparentDuffs)
            XCTAssertNil(balance.totalDuffs)
            XCTAssertTrue(balance.isPartial)
        }
    }

    func testUnknownTransparentKeepsKnownRowsButHasNoTotal() {
        let balance = HomeBalancePresentation(transparentDuffs: nil, platformState: .available(20_000), shieldedCredits: 30_000, showsPlatformBalance: true)
        XCTAssertNil(balance.transparentDuffs)
        XCTAssertEqual(balance.platformDuffs, 20)
        XCTAssertEqual(balance.shieldedDuffs, 30)
        XCTAssertNil(balance.totalDuffs)
        XCTAssertTrue(balance.isPartial)
    }

    func testKnownZeroComponentsCannotProvideTotalBeforeTransparentRead() {
        let restoredComponents: [(PlatformBalanceState, UInt64?)] = [
            (.available(0), nil),
            (.unavailable, 0),
            (.available(0), 0),
        ]
        for showsPlatform in [false, true] {
            for (platform, shielded) in restoredComponents {
                let balance = HomeBalancePresentation(transparentDuffs: nil, platformState: platform, shieldedCredits: shielded, showsPlatformBalance: showsPlatform)
                XCTAssertNil(balance.totalDuffs)
                XCTAssertTrue(balance.isPartial)
            }
        }
    }

    func testClearedTransparentHidesTotalUntilReseedWithRetainedComponents() {
        for showsPlatform in [false, true] {
            for credits: UInt64 in [0, 20_000] {
                func presentation(_ transparent: UInt64?) -> HomeBalancePresentation {
                    HomeBalancePresentation(transparentDuffs: transparent, platformState: .available(credits), shieldedCredits: credits, showsPlatformBalance: showsPlatform)
                }
                let retainedDuffs = (credits / 1_000) * (showsPlatform ? 2 : 1)
                // A cached Platform/shielded read can arrive before Core at launch.
                XCTAssertNil(presentation(nil).totalDuffs)
                XCTAssertEqual(presentation(9_000).totalDuffs, 9_000 + retainedDuffs)
                // A runtime restart clears Core while retaining other amounts.
                let cleared = presentation(nil)
                XCTAssertNil(cleared.totalDuffs)
                XCTAssertEqual(cleared.platformDuffs, credits / 1_000)
                XCTAssertEqual(cleared.shieldedDuffs, credits / 1_000)
                XCTAssertEqual(presentation(4_000).totalDuffs, 4_000 + retainedDuffs)
                XCTAssertEqual(presentation(0).totalDuffs, retainedDuffs)
            }
        }
    }

    func testRestoredTransparentZeroIsKnown() {
        let balance = HomeBalancePresentation(transparentDuffs: 0, platformState: .available(0), shieldedCredits: 0, showsPlatformBalance: true)
        XCTAssertEqual(balance.transparentDuffs, 0)
        XCTAssertEqual(balance.totalDuffs, 0)
        XCTAssertFalse(balance.isPartial)
    }

    func testTransparentAloneCanProvideAKnownZero() {
        let balance = HomeBalancePresentation(transparentDuffs: 0, platformState: .unavailable, shieldedCredits: nil, showsPlatformBalance: false)
        XCTAssertEqual(balance.totalDuffs, 0)
        XCTAssertTrue(balance.isPartial)
    }

    func testUnknownTransparentInSimpleModeKeepsShieldedRowButHasNoTotal() {
        let balance = HomeBalancePresentation(transparentDuffs: nil, platformState: .available(20_000), shieldedCredits: 30_000, showsPlatformBalance: false)
        XCTAssertEqual(balance.shieldedDuffs, 30)
        XCTAssertNil(balance.totalDuffs)
        XCTAssertTrue(balance.isPartial)
    }

    func testHiddenPlatformCannotSupplyAnOtherwiseUnknownTotal() {
        let balance = HomeBalancePresentation(transparentDuffs: nil, platformState: .available(20_000), shieldedCredits: nil, showsPlatformBalance: false)
        XCTAssertNil(balance.totalDuffs)
        XCTAssertTrue(balance.isPartial)
    }

    func testRestoredPlatformIsIncludedWithoutRuntimeReadiness() {
        let balance = HomeBalancePresentation(transparentDuffs: 10, platformState: .available(20_000), shieldedCredits: 30_000, showsPlatformBalance: true)
        XCTAssertEqual(balance.platformDuffs, 20)
        XCTAssertEqual(balance.totalDuffs, 60)
        XCTAssertFalse(balance.isPartial)
    }

    func testUnknownPlatformKeepsRowAndKnownComponents() {
        let balance = HomeBalancePresentation(transparentDuffs: 10, platformState: .unavailable, shieldedCredits: 30_000, showsPlatformBalance: true)
        XCTAssertNil(balance.platformDuffs)
        XCTAssertEqual(balance.totalDuffs, 40)
        XCTAssertTrue(balance.isPartial)
    }

    func testAdvancedTotalIsPartialBeforeBothLocalReads() {
        let balance = HomeBalancePresentation(transparentDuffs: 10, platformState: .unavailable, shieldedCredits: nil, showsPlatformBalance: true)
        XCTAssertEqual(balance.totalDuffs, 10)
        XCTAssertTrue(balance.isPartial)
    }

    func testSimpleModeKeepsKnownCoreWhileShieldedIsUnavailable() {
        let balance = HomeBalancePresentation(transparentDuffs: 10, platformState: .available(20_000), shieldedCredits: nil, showsPlatformBalance: false)
        XCTAssertEqual(balance.totalDuffs, 10)
        XCTAssertNil(balance.shieldedDuffs)
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
