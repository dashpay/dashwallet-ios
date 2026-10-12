import XCTest
#if canImport(dashpay)
@testable import dashpay
#elseif canImport(dashwallet)
@testable import dashwallet
#else
@testable import WalletPreparationHarness
#endif

final class SPVChainStoreRebuildTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "SPVChainStoreRebuildTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func walletId(_ byte: UInt8) -> Data {
        Data(repeating: byte, count: 32)
    }

    func testNothingIsPendingUntilAnImportArmsIt() {
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults))
    }

    func testImportArmsOnlyItsOwnScope() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", defaults: defaults))
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "testnet-sakura", defaults: defaults))
    }

    func testSecondImportJoinsThePendingRebuildAndARepeatAddsNothing() {
        XCTAssertTrue(SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", defaults: defaults))
        XCTAssertTrue(SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "mainnet", defaults: defaults))
        XCTAssertFalse(SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", defaults: defaults))

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", defaults: defaults),
            [walletId(0xA1), walletId(0xB2)])
    }

    func testFinishDropsOnlyTheRebuiltWalletsAndKeepsOnesArmedMeanwhile() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", defaults: defaults)
        SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "mainnet", defaults: defaults)

        SPVChainStoreRebuild.finish(walletIds: [walletId(0xA1)], scope: "mainnet", defaults: defaults)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", defaults: defaults),
            [walletId(0xB2)])

        SPVChainStoreRebuild.finish(walletIds: [walletId(0xB2)], scope: "mainnet", defaults: defaults)
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", defaults: defaults))
    }

    func testFinishOfAWalletThatIsNotPendingChangesNothing() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)

        SPVChainStoreRebuild.finish(walletIds: [walletId(0xEE)], scope: "testnet", defaults: defaults)
        SPVChainStoreRebuild.finish(walletIds: [walletId(0xA1)], scope: "mainnet", defaults: defaults)

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
    }

    func testClearFinishesOneScopeAndLeavesTheOther() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", defaults: defaults)
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)

        SPVChainStoreRebuild.clear(scope: "mainnet", defaults: defaults)

        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", defaults: defaults))
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
    }

    func testPendingRebuildSurvivesANewDefaultsInstance() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xC3), scope: "testnet", defaults: defaults)

        let reopened = UserDefaults(suiteName: suiteName)!
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: reopened),
            [walletId(0xC3)])
    }
}
