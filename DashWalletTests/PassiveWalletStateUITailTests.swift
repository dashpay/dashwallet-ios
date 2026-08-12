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

@MainActor
final class InitialRestoreSyncStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: InitialRestoreSyncStore!

    override func setUp() {
        super.setUp()
        suiteName = "InitialRestoreSyncStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = InitialRestoreSyncStore(
            defaults: defaults,
            notificationCenter: NotificationCenter())
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshWalletHasNoMarkerAndOriginsHaveExpectedSemantics() {
        let walletId = Data([0x01])
        XCTAssertNil(store.state(walletId: walletId))
        XCTAssertFalse(WalletMaterialOrigin.fresh.armsInitialRestoreSync)
        XCTAssertTrue(WalletMaterialOrigin.userRestore.armsInitialRestoreSync)
        XCTAssertTrue(WalletMaterialOrigin.legacyMigration.armsInitialRestoreSync)
        XCTAssertTrue(WalletMaterialOrigin.reconstructed.armsInitialRestoreSync)
    }

    func testImportedPendingCompletesOnceAndDoesNotRearm() {
        let walletId = Data([0x02])
        store.markImportedIfNeeded(walletId: walletId)
        XCTAssertEqual(store.state(walletId: walletId), .pending)
        store.completeIfPending(walletId: walletId)
        XCTAssertEqual(store.state(walletId: walletId), .completed)
        store.markImportedIfNeeded(walletId: walletId)
        XCTAssertEqual(store.state(walletId: walletId), .completed)
    }

    func testReconstructionForcesCompletedWalletBackToPending() {
        let walletId = Data([0x03])
        store.markImportedIfNeeded(walletId: walletId)
        store.completeIfPending(walletId: walletId)
        store.markReconstructed(walletId: walletId)
        XCTAssertEqual(store.state(walletId: walletId), .pending)
    }

    func testStatePersistsAndIsScopedPerWallet() {
        let pending = Data([0x0a])
        let completed = Data([0x0b])
        store.markImportedIfNeeded(walletId: pending)
        store.markImportedIfNeeded(walletId: completed)
        store.completeIfPending(walletId: completed)

        let reloaded = InitialRestoreSyncStore(
            defaults: defaults,
            notificationCenter: NotificationCenter())
        XCTAssertEqual(reloaded.state(walletId: pending), .pending)
        XCTAssertEqual(reloaded.state(walletId: completed), .completed)
    }

    func testDeleteThenLateCompletionDoesNotRecreateMarker() {
        let walletId = Data([0x04])
        store.markImportedIfNeeded(walletId: walletId)
        store.remove(walletId: walletId)
        store.completeIfPending(walletId: walletId)
        XCTAssertNil(store.state(walletId: walletId))
    }

    func testRemoveAllOnlyAfterSuccessfulWipeCanClearEveryWallet() {
        store.markImportedIfNeeded(walletId: Data([0x05]))
        store.markImportedIfNeeded(walletId: Data([0x06]))
        store.removeAll()
        XCTAssertNil(store.state(walletId: Data([0x05])))
        XCTAssertNil(store.state(walletId: Data([0x06])))
    }

    func testEffectiveSyncCompletionPredicate() {
        XCTAssertTrue(SPVSyncState.synced.isEffectivelyComplete(progress: 0))
        XCTAssertTrue(SPVSyncState.waitForEvents.isEffectivelyComplete(progress: 0.999))
        XCTAssertFalse(SPVSyncState.waitForEvents.isEffectivelyComplete(progress: 0.998))
        XCTAssertFalse(SPVSyncState.syncing.isEffectivelyComplete(progress: 1))
        XCTAssertFalse(SPVSyncState.unknown.isEffectivelyComplete(progress: 1))
    }

    func testOnlyNewCoreOperationRequiresRestoreAvailability() {
        XCTAssertTrue(
            ShieldedTransferCoordinator.OperationKind.newCoreSpend
                .requiresCoreSpendAvailability)
        XCTAssertFalse(
            ShieldedTransferCoordinator.OperationKind.resumeCommittedCoreSpend
                .requiresCoreSpendAvailability)
        XCTAssertFalse(
            ShieldedTransferCoordinator.OperationKind.nonCoreSpend
                .requiresCoreSpendAvailability)
    }
}
