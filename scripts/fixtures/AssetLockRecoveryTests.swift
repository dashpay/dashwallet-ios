import Foundation
import XCTest
@testable import RecoveryHarness

@MainActor
final class AssetLockRecoveryTests: XCTestCase {
    override func setUp() async throws {
        ShieldedTransferCoordinator.rowLookup = { .none as CoreShieldedDrainRowIdentity }
        CoreShieldedDrainService.marker = .unavailable
        SwiftDashSDKTransactionSender.CoinJoinWalletBinding.selected = nil
    }

    func testExplicitSendRetryAuthorizesRecordedProbeAndPreservesUnverifiedOutcome() async {
        await checkExplicitSendRetryWithRecordedProbe(cancelAuthorization: false)
    }

    func testExplicitSendRetryWithRecordedProbeCannotSubmitWithoutAuthorization() async {
        await checkExplicitSendRetryWithRecordedProbe(cancelAuthorization: true)
    }

    func testExplicitCoinJoinRetryRechecksRecordedProbeWithoutAnotherDrain() async {
        await checkExplicitSendRetryWithRecordedProbe(cancelAuthorization: false, coinJoin: true)
    }

    func testExplicitCoinJoinRetryCannotSubmitWithoutAuthorization() async {
        await checkExplicitSendRetryWithRecordedProbe(cancelAuthorization: true, coinJoin: true)
    }

    func testCoinJoinChoiceAfterCancelledRecoveryKeepsSameLock() async {
        await checkExplicitSendRetryWithRecordedProbe(cancelAuthorization: true, coinJoin: true, fromChoice: true)
    }

    private func checkExplicitSendRetryWithRecordedProbe(cancelAuthorization: Bool, coinJoin: Bool = false,
                                                         fromChoice: Bool = false) async {
        let wallet = Data(repeating: 0x33, count: 32)
        let walletHex = wallet.map { String(format: "%02x", $0) }.joined()
        let txid = Data(repeating: 0x7a, count: 32)
        let recipient = Data(repeating: 5, count: 43)
        defer {
            AssetLockProbeStore.shared.clearForWallet(walletIdHex: walletHex)
            CoreShieldedDrainService.resolveManager = nil
        }
        AssetLockProbeStore.shared.record(txid: txid, vout: 3, walletIdHex: walletHex)
        let manager = TestManager()
        manager.error = PlatformWalletError.assetLockAlreadyConsumed
        let coordinator = ShieldedTransferCoordinator(environment: .init(
            manager: manager, walletId: wallet, shieldedRecipient: Data(repeating: 1, count: 43)))
        coordinator.phase = .failed("test failure")
        coordinator.lastAssetLockContext = .init(walletId: wallet, networkScope: "testnet")
        CoreShieldedDrainService.resolveManager = { context in
            XCTAssertEqual(context.walletId, wallet)
            return manager
        }
        coordinator.lastAssetLockOutPoint = (txid, 3)
        if cancelAuthorization { coordinator.authorizationError = CancellationError() }

        if coinJoin {
            let caller = CoinJoinRetryHarness(coordinator)
            let binding = SwiftDashSDKTransactionSender.CoinJoinWalletBinding(walletId: wallet, network: "testnet")
            caller.binding = binding
            SwiftDashSDKTransactionSender.CoinJoinWalletBinding.selected = binding
            await caller.retryShielded()
            XCTAssertEqual(caller.stage, cancelAuthorization ? CoinJoinRetryHarness.unresumedLockStage : .submittedUnconfirmed)
            if fromChoice {
                coordinator.authorizationError = nil
                await caller.moveToShielded()
                XCTAssertEqual(caller.stage, .submittedUnconfirmed)
            }
            XCTAssertEqual(caller.newDrainCalls, 0)
            if cancelAuthorization && !fromChoice {
                XCTAssertEqual(caller.committedLock?.txidWire, txid)
                XCTAssertEqual(caller.committedLock?.vout, 3)
            }
        } else {
            await coordinator.retryLastAssetLock(recipientRaw43: recipient)
        }

        XCTAssertEqual(coordinator.authorizations, fromChoice ? 2 : 1)
        if !coinJoin {
            XCTAssertEqual(coordinator.lastAssetLockOutPoint?.txidWire, txid)
            XCTAssertEqual(coordinator.lastAssetLockOutPoint?.vout, 3)
        }
        XCTAssertTrue(AssetLockProbeStore.shared.contains(txid, vout: 3, walletIdHex: walletHex))
        if cancelAuthorization && !fromChoice {
            XCTAssertEqual(manager.calls, 0)
            XCTAssertEqual(coordinator.phase, coinJoin ? .idle : .failed("Authentication cancelled"))
        } else {
            XCTAssertEqual(manager.calls, 1)
            XCTAssertEqual(manager.receivedTxid, txid)
            XCTAssertEqual(manager.receivedVout, 3)
            XCTAssertEqual(manager.receivedRecipients.map(\.recipientRaw43),
                           [coinJoin ? Data(repeating: 1, count: 43) : recipient])
            XCTAssertEqual(coordinator.phase, .submittedUnconfirmed)
        }
    }

    func testExplicitRetryCannotOverrideDrainMarkerRecipient() async {
        let wallet = Data(repeating: 0x34, count: 32)
        let manager = TestManager()
        let coordinator = ShieldedTransferCoordinator(environment: .init(
            manager: manager, walletId: wallet, shieldedRecipient: Data(repeating: 1, count: 43)))
        let operation = CoreShieldedDrainOperation(
            id: UUID(), context: .init(walletId: wallet, networkScope: "testnet"),
            recipient: .external(raw43: Data(repeating: 2, count: 43)))
        ShieldedTransferCoordinator.rowLookup = { .operation(operation.id) }
        CoreShieldedDrainService.marker = .loaded(operation)
        await coordinator.resumeAssetLock(
            outPointTxidWire: Data(repeating: 3, count: 32), outPointVout: 0,
            recipientRaw43: Data(repeating: 4, count: 43), retryUnverifiedConsumption: true)
        XCTAssertEqual(coordinator.authorizations, 0)
        XCTAssertEqual(manager.calls, 0)
        XCTAssertEqual(coordinator.phase, .failed("test failure"))
    }

    func testCoinJoinRetryRefusesChangedWalletWithoutNewDrain() async {
        let wallet = Data(repeating: 0x35, count: 32)
        let manager = TestManager()
        let coordinator = ShieldedTransferCoordinator(environment: .init(
            manager: manager, walletId: wallet, shieldedRecipient: Data(repeating: 1, count: 43)))
        coordinator.phase = .failed("test failure")
        coordinator.lastAssetLockOutPoint = (Data(repeating: 5, count: 32), 1)
        let caller = CoinJoinRetryHarness(coordinator)
        caller.binding = .init(walletId: wallet, network: "testnet")
        SwiftDashSDKTransactionSender.CoinJoinWalletBinding.selected = .init(walletId: Data([9]), network: "testnet")
        await caller.retryShielded()
        XCTAssertEqual(caller.stage, .failed(message: "test failure", destination: .shielded))
        XCTAssertNotNil(caller.committedLock)
        XCTAssertEqual(coordinator.authorizations, 0)
        XCTAssertEqual(manager.calls, 0)
        XCTAssertEqual(caller.newDrainCalls, 0)
    }

    func testOtherSendFailureRetainsOrdinaryRetry() {
        let manager = TestManager()
        let coordinator = ShieldedTransferCoordinator(environment: .init(
            manager: manager, walletId: Data([1]), shieldedRecipient: Data(repeating: 1, count: 43)))
        coordinator.phase = .failed("test failure")
        coordinator.lastFailure = NSError(domain: "test", code: 1)
        let caller = SendRetryHarness(coordinator)
        caller.tryAgain()
        XCTAssertEqual(caller.cancellations, 0)
        XCTAssertEqual(caller.confirmations, 1)
        XCTAssertEqual(coordinator.phase, .idle)
    }

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
        XCTAssertTrue(AssetLockProbeStore.shared.contains(txid, vout: 0, walletIdHex: walletHex))
        XCTAssertFalse(AssetLockProbeStore.shared.contains(txid, vout: 0))

        // A new presenter (or relaunch) must not authorize or submit again.
        let reopened = ShieldedTransferCoordinator(environment: environment)
        await reopened.resumeAssetLock(outPointTxidWire: txid, outPointVout: 0)
        XCTAssertEqual(reopened.phase, .submittedUnconfirmed)
        XCTAssertEqual(reopened.authorizations, 0)
        XCTAssertEqual(manager.calls, 1)
        let reloaded = AssetLockProbeStore()
        XCTAssertTrue(reloaded.contains(txid, vout: 0, walletIdHex: walletHex))
    }

    func testExplicitRetryRechecksSameOutpointAfterUnverifiedConsumptionReport() async {
        let wallet = Data(repeating: 0x32, count: 32)
        let walletHex = wallet.map { String(format: "%02x", $0) }.joined()
        let txid = Data(repeating: 0x79, count: 32)
        defer { AssetLockProbeStore.shared.clearForWallet(walletIdHex: walletHex) }
        AssetLockProbeStore.shared.record(txid: txid, vout: 2, walletIdHex: walletHex)
        let manager = TestManager()
        let coordinator = ShieldedTransferCoordinator(environment: .init(
            manager: manager, walletId: wallet, shieldedRecipient: Data(repeating: 1, count: 43)))
        await coordinator.resumeAssetLock(outPointTxidWire: txid, outPointVout: 2,
                                          retryUnverifiedConsumption: true)
        XCTAssertEqual(coordinator.authorizations, 1)
        XCTAssertEqual(manager.calls, 1)
        XCTAssertEqual(manager.receivedTxid, txid)
        XCTAssertEqual(coordinator.phase, .success)
    }

    func testLegacyTxidProbeCannotSuppressEveryCreditOutput() {
        let suite = "RecoveryHarness-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let txid = Data(repeating: 3, count: 32)
        defaults.set([txid], forKey: "assetLockProbe.v1.alreadySpentTxids_A")
        let store = AssetLockProbeStore(defaults: defaults)
        XCTAssertFalse(store.contains(txid, vout: 0, walletIdHex: "A"))
        XCTAssertFalse(store.contains(txid, vout: 1, walletIdHex: "A"))
        store.record(txid: txid, vout: 1, walletIdHex: "A")
        let reloaded = AssetLockProbeStore(defaults: defaults)
        XCTAssertTrue(reloaded.contains(txid, vout: 1, walletIdHex: "A"))
        XCTAssertFalse(reloaded.contains(txid, vout: 0, walletIdHex: "A"))
        store.resetForWipe()
        XCTAssertNil(defaults.object(forKey: "assetLockProbe.v1.alreadySpentTxids_A"))
        XCTAssertFalse(AssetLockProbeStore(defaults: defaults).contains(txid, vout: 1, walletIdHex: "A"))
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
        XCTAssertFalse(AssetLockProbeStore.shared.contains(txid, vout: 0, walletIdHex: walletHex))
        XCTAssertNil(coordinator.lastResumeReport)
        XCTAssertEqual(coordinator.phase, .submittedUnconfirmed)
    }

    func testDrainContextChangeAfterAuthorizationNeverResubmitsAssetLock() async {
        let wallet = Data(repeating: 0x31, count: 32)
        let txid = Data(repeating: 0x78, count: 32)
        let manager = TestManager()
        let coordinator = ShieldedTransferCoordinator(environment: .init(
            manager: manager, walletId: wallet, shieldedRecipient: Data(repeating: 1, count: 43)))
        CoreShieldedDrainService.resolveManager = { _ in manager }
        defer { CoreShieldedDrainService.resolveManager = nil }
        coordinator.onAuthorize = {
            CoreShieldedDrainService.resolveManager = { _ in
                throw CoreShieldedDrainService.TestError.contextChanged
            }
        }
        await coordinator.resumeAssetLock(
            outPointTxidWire: txid, outPointVout: 0,
            expectedDrainContext: .init(walletId: wallet, networkScope: "testnet"))
        XCTAssertEqual(coordinator.authorizations, 1)
        XCTAssertEqual(coordinator.phase, .failed("test failure"))
        XCTAssertEqual(manager.calls, 0)
        XCTAssertNil(manager.receivedTxid)
    }

    func testProbePersistenceIsWalletScopedAndNeverMarksAnotherOutpoint() {
        let suite = "RecoveryHarness-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AssetLockProbeStore(defaults: defaults)
        let txid = Data(repeating: 1, count: 32)
        store.record(txid: txid, vout: 0, walletIdHex: "A")
        let reloaded = AssetLockProbeStore(defaults: defaults)
        XCTAssertTrue(reloaded.contains(txid, vout: 0, walletIdHex: "A"))
        XCTAssertFalse(reloaded.contains(txid, vout: 0, walletIdHex: "B"))
        XCTAssertFalse(reloaded.contains(Data(repeating: 2, count: 32), vout: 0, walletIdHex: "A"))
        reloaded.clearForWallet(walletIdHex: "B")
        XCTAssertTrue(reloaded.contains(txid, vout: 0, walletIdHex: "A"))
        reloaded.clearForWallet(walletIdHex: "A")
        XCTAssertFalse(AssetLockProbeStore(defaults: defaults).contains(txid, vout: 0, walletIdHex: "A"))
    }
    func testAmbiguousBroadcastDoesNotBecomeFailureOrSpentProbe() async {
        let wallet = Data(repeating: 0x42, count: 32)
        let walletHex = wallet.map { String(format: "%02x", $0) }.joined()
        defer { AssetLockProbeStore.shared.clearForWallet(walletIdHex: walletHex) }
        let manager = TestManager()
        manager.error = PlatformWalletError.transactionBroadcastUnconfirmed("lost acknowledgement")
        let coordinator = ShieldedTransferCoordinator(environment: .init(
            manager: manager, walletId: wallet, shieldedRecipient: Data(repeating: 1, count: 43)))
        let txid = Data(repeating: 0x43, count: 32)
        await coordinator.resumeAssetLock(outPointTxidWire: txid, outPointVout: 2)
        XCTAssertEqual(coordinator.phase, .submittedUnconfirmed)
        XCTAssertNil(coordinator.lastResumeReport)
        XCTAssertFalse(AssetLockProbeStore.shared.contains(txid, vout: 2, walletIdHex: walletHex))
    }

    func testDefiniteFailureRemainsFailure() async {
        let manager = TestManager()
        manager.error = PlatformWalletError.walletOperation("preflight refusal")
        let coordinator = ShieldedTransferCoordinator(environment: .init(
            manager: manager, walletId: Data([9]), shieldedRecipient: Data(repeating: 1, count: 43)))
        await coordinator.resumeAssetLock(outPointTxidWire: Data(repeating: 4, count: 32), outPointVout: 0)
        XCTAssertEqual(coordinator.phase, .failed("test failure"))
        XCTAssertNil(coordinator.lastResumeReport)
    }

    func testChangedWalletRefusesRetryAndKeepsOriginalLock() async {
        let manager = TestManager()
        let wallet = Data([8])
        let txid = Data(repeating: 8, count: 32)
        let coordinator = ShieldedTransferCoordinator(environment: .init(
            manager: manager, walletId: wallet, shieldedRecipient: Data(repeating: 1, count: 43)))
        coordinator.phase = .failed("test failure")
        coordinator.lastAssetLockOutPoint = (txid, 2)
        coordinator.lastAssetLockContext = .init(walletId: wallet, networkScope: "testnet")
        CoreShieldedDrainService.resolveManager = { _ in throw CoreShieldedDrainService.TestError.contextChanged }
        defer { CoreShieldedDrainService.resolveManager = nil }
        await coordinator.retryLastAssetLock()
        XCTAssertEqual(coordinator.lastAssetLockOutPoint?.txidWire, txid)
        XCTAssertEqual(coordinator.lastAssetLockOutPoint?.vout, 2)
        XCTAssertEqual(coordinator.authorizations, 0)
        XCTAssertEqual(manager.calls, 0)
        XCTAssertEqual(coordinator.newAssetLockCalls, 0)
    }

}
