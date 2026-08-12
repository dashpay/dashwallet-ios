import Foundation
import XCTest

@MainActor
final class InitialRestoreSyncStoreTests: XCTestCase {
    private var suiteName: String?
    private var defaultsUnderTest: UserDefaults?
    private var storeUnderTest: InitialRestoreSyncStore?

    private var defaults: UserDefaults {
        guard let defaultsUnderTest else {
            preconditionFailure("Test defaults accessed outside setUp/tearDown")
        }
        return defaultsUnderTest
    }

    private var store: InitialRestoreSyncStore {
        guard let storeUnderTest else {
            preconditionFailure("Test store accessed outside setUp/tearDown")
        }
        return storeUnderTest
    }

    override func setUp() {
        super.setUp()
        let suiteName = "InitialRestoreSyncStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        self.suiteName = suiteName
        defaultsUnderTest = defaults
        storeUnderTest = InitialRestoreSyncStore(
            defaults: defaults,
            notificationCenter: NotificationCenter())
    }

    override func tearDown() {
        if let suiteName {
            defaultsUnderTest?.removePersistentDomain(forName: suiteName)
        }
        storeUnderTest = nil
        defaultsUnderTest = nil
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
