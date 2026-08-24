//
//  PassiveWalletStateUITailTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//

@testable import dashwallet
import Combine
import SwiftDashSDK
import XCTest

@MainActor
final class PassiveWalletStateUITailTests: XCTestCase {

    func testInitialRestoreSyncBlocksCoreSpendUntilSyncCompletes() {
        XCTAssertTrue(
            WalletSendService.isBlockedByInitialRestoreSync(
                isResyncingWallet: true,
                isChainSynced: false))
        XCTAssertFalse(
            WalletSendService.isBlockedByInitialRestoreSync(
                isResyncingWallet: true,
                isChainSynced: true))
    }

    func testNormalCatchUpDoesNotBlockCoreSpend() {
        XCTAssertFalse(
            WalletSendService.isBlockedByInitialRestoreSync(
                isResyncingWallet: false,
                isChainSynced: false))
    }

    func testAlreadyConsumedAssetLockMapsToUnconfirmedResume() {
        let error = PlatformWalletError.assetLockAlreadyConsumed("test outpoint")

        XCTAssertEqual(
            ShieldedTransferCoordinator.alreadyConsumedAssetLockResumePhase(for: error),
            .submittedUnconfirmed)
        XCTAssertNil(
            ShieldedTransferCoordinator.alreadyConsumedAssetLockResumePhase(
                for: PlatformWalletError.invalidParameter("unrelated")))
    }

    func testHomeBalanceChangesSkipInitialAndDuplicateSnapshots() {
        let balances = CurrentValueSubject<WalletBalance?, Never>(nil)
        var reloadCount = 0
        let cancellable = HomeViewModel.distinctBalanceChanges(from: balances)
            .sink { reloadCount += 1 }

        XCTAssertEqual(reloadCount, 0)

        balances.send(WalletBalance(confirmed: 9_000))
        XCTAssertEqual(reloadCount, 1)

        balances.send(WalletBalance(confirmed: 9_000))
        XCTAssertEqual(reloadCount, 1)

        balances.send(WalletBalance(confirmed: 4_000))
        XCTAssertEqual(reloadCount, 2)

        balances.send(nil)
        XCTAssertEqual(reloadCount, 3)
        withExtendedLifetime(cancellable) {}
    }

    func testBalanceModelAppliesClearsAndReseedsWithoutChangingDisplayContract() async {
        let options = DWGlobalOptions.sharedInstance()
        let originalBalanceHidden = options.balanceHidden
        let originalWalletNeedsBackup = options.walletNeedsBackup
        let originalUserHasBalance = options.userHasBalance
        let originalBalanceChangedDate = options.balanceChangedDate
        defer {
            SwiftDashSDKWalletState.shared.clearAllState()
            options.balanceHidden = originalBalanceHidden
            options.walletNeedsBackup = originalWalletNeedsBackup
            options.userHasBalance = originalUserHasBalance
            options.balanceChangedDate = originalBalanceChangedDate
        }

        SwiftDashSDKWalletState.shared.clearAllState()
        options.balanceHidden = true
        options.walletNeedsBackup = true
        options.userHasBalance = false
        options.balanceChangedDate = nil

        let model = BalanceModel()
        XCTAssertTrue(model.isBalanceHidden)

        await applyBalance(9_000, expecting: 9_000, in: model)
        XCTAssertTrue(options.userHasBalance)
        XCTAssertNotNil(options.balanceChangedDate)
        XCTAssertTrue(model.isBalanceHidden)

        let backupReminderDate = options.balanceChangedDate
        await clearBalance(expecting: model)
        XCTAssertFalse(options.userHasBalance)
        XCTAssertEqual(options.balanceChangedDate, backupReminderDate)
        XCTAssertTrue(model.isBalanceHidden)

        await applyBalance(4_000, expecting: 4_000, in: model)
        XCTAssertEqual(model.value, 4_000)
        XCTAssertTrue(options.userHasBalance)
        XCTAssertTrue(model.isBalanceHidden)
    }

    func testExploreUsesCurrentNetworkAndResolvesAddressForEveryAction() {
        var isTestnet = false
        var activeAddress: String? = "first-address"
        let screen = ExploreMenuScreen(
            vc: UINavigationController(),
            onShowSendPayment: {},
            onShowReceivePayment: {},
            onShowGiftCard: { _ in },
            isTestnetProvider: { isTestnet },
            receiveAddressProvider: { activeAddress })

        XCTAssertFalse(screen.shouldShowGetTestDash)
        isTestnet = true
        XCTAssertTrue(screen.shouldShowGetTestDash)
        XCTAssertEqual(screen.currentTestDashReceiveAddress(), "first-address")

        activeAddress = "second-address"
        XCTAssertEqual(screen.currentTestDashReceiveAddress(), "second-address")
    }

    func testBuySellVisibilityUsesAppOwnedNetworkState() {
        XCTAssertFalse(
            ServiceDataProviderImpl.shouldShow(
                service: .maya,
                isMainnet: true,
                swapKitConfigured: true))
        XCTAssertFalse(
            ServiceDataProviderImpl.shouldShow(
                service: .maya,
                isMainnet: false,
                swapKitConfigured: true))
        XCTAssertFalse(
            ServiceDataProviderImpl.shouldShow(
                service: .swapKit,
                isMainnet: false,
                swapKitConfigured: true))
        XCTAssertFalse(
            ServiceDataProviderImpl.shouldShow(
                service: .swapKit,
                isMainnet: true,
                swapKitConfigured: false))
        XCTAssertTrue(
            ServiceDataProviderImpl.shouldShow(
                service: .swapKit,
                isMainnet: true,
                swapKitConfigured: true))
    }

    private func applyBalance(
        _ confirmed: UInt64,
        expecting expectedBalance: UInt64,
        in model: BalanceModel
    ) async {
        let expectation = expectation(description: "Balance becomes \(expectedBalance)")
        let cancellable = model.$value
            .filter { $0 == expectedBalance }
            .prefix(1)
            .sink { _ in expectation.fulfill() }

        SwiftDashSDKWalletState.shared.applyBalance(WalletBalance(confirmed: confirmed))

        await fulfillment(of: [expectation], timeout: 2)
        withExtendedLifetime(cancellable) {}
    }

    private func clearBalance(expecting model: BalanceModel) async {
        let expectation = expectation(description: "Balance clears")
        let cancellable = model.$value
            .filter { $0 == 0 }
            .prefix(1)
            .sink { _ in expectation.fulfill() }

        SwiftDashSDKWalletState.shared.clearAllState()

        await fulfillment(of: [expectation], timeout: 2)
        withExtendedLifetime(cancellable) {}
    }
}
