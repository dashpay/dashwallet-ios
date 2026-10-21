import Foundation
import XCTest
@testable import RecoveryHarness

@MainActor
final class AssetLockRecoveryTests: XCTestCase {
    func testDirectRecoverySheetRecordsSpentProbeUnderOriginatingWallet() async {
        let wallet = Data(repeating: 0x29, count: 32)
        let walletHex = wallet.map { String(format: "%02x", $0) }.joined()
        let txid = Data(repeating: 0x76, count: 32)
        defer {
            AssetLockProbeStore.shared.clearForWallet(walletIdHex: walletHex)
            WalletEnvironment.activeWalletIdHex = nil
        }
        AssetLockProbeStore.shared.clearForWallet(walletIdHex: walletHex)
        WalletEnvironment.activeWalletIdHex = walletHex
        let manager = TestManager()
        manager.error = PlatformWalletError.assetLockAlreadyConsumed
        let environment = ShieldedTransferCoordinator.Environment(manager: manager, walletId: wallet,
                                                                  shieldedRecipient: Data(repeating: 1, count: 43))
        let coordinator = ShieldedTransferCoordinator(environment: environment)
        coordinator.onAuthorize = { WalletEnvironment.activeWalletIdHex = "another-wallet" }
        await coordinator.resumeAssetLock(outPointTxidWire: txid, outPointVout: 0)
        XCTAssertEqual(coordinator.phase, .submittedUnconfirmed)
        XCTAssertEqual(manager.receivedTxid, txid)
        XCTAssertTrue(AssetLockProbeStore.shared.contains(txid, walletIdHex: walletHex))
        XCTAssertFalse(AssetLockProbeStore.shared.contains(txid))

        // A new presenter (or relaunch) must not authorize or submit again.
        let reopened = ShieldedTransferCoordinator(environment: environment)
        await reopened.resumeAssetLock(outPointTxidWire: txid, outPointVout: 0)
        XCTAssertEqual(reopened.phase, .submittedUnconfirmed)
        XCTAssertEqual(reopened.authorizations, 0)
        XCTAssertEqual(manager.calls, 1)
        let reloaded = AssetLockProbeStore()
        XCTAssertTrue(reloaded.contains(txid, walletIdHex: walletHex))
    }

    func testTimeoutDoesNotInventAnAlreadySpentProbe() async {
        let wallet = Data(repeating: 0x30, count: 32)
        let walletHex = wallet.map { String(format: "%02x", $0) }.joined()
        defer { AssetLockProbeStore.shared.clearForWallet(walletIdHex: walletHex) }
        AssetLockProbeStore.shared.clearForWallet(walletIdHex: walletHex)
        let txid = Data(repeating: 0x77, count: 32)
        let manager = TestManager()
        manager.error = PlatformWalletError.shieldedSpendUnconfirmed
        let coordinator = ShieldedTransferCoordinator(environment: .init(manager: manager, walletId: wallet,
                                                                         shieldedRecipient: Data(repeating: 1, count: 43)))
        await coordinator.resumeAssetLock(outPointTxidWire: txid, outPointVout: 0)
        XCTAssertFalse(AssetLockProbeStore.shared.contains(txid, walletIdHex: walletHex))
        XCTAssertNil(coordinator.lastResumeReport)
        XCTAssertEqual(coordinator.phase, .submittedUnconfirmed)
    }

    func testProbePersistenceIsWalletScopedAndNeverMarksAnotherOutpoint() {
        let suite = "RecoveryHarness-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AssetLockProbeStore(defaults: defaults)
        let txid = Data(repeating: 1, count: 32)
        store.record(txid: txid, walletIdHex: "A")
        let reloaded = AssetLockProbeStore(defaults: defaults)
        XCTAssertTrue(reloaded.contains(txid, walletIdHex: "A"))
        XCTAssertFalse(reloaded.contains(txid, walletIdHex: "B"))
        XCTAssertFalse(reloaded.contains(Data(repeating: 2, count: 32), walletIdHex: "A"))
        reloaded.clearForWallet(walletIdHex: "B")
        XCTAssertTrue(reloaded.contains(txid, walletIdHex: "A"))
        reloaded.clearForWallet(walletIdHex: "A")
        XCTAssertFalse(AssetLockProbeStore(defaults: defaults).contains(txid, walletIdHex: "A"))
    }
}
