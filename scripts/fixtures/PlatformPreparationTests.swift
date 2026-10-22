import Foundation
import XCTest
@testable import PlatformPreparationHarness

@MainActor
final class PlatformPreparationTests: XCTestCase {
    private let firstWallet = Data([1])
    private let secondWallet = Data([2])

    private func makeHost(selectedWallet: Bool = true) -> SwiftDashSDKHost {
        WalletEnvironment.network = .mainnet
        WalletEnvironment.selectedWalletID = selectedWallet ? firstWallet : nil
        return SwiftDashSDKHost(sdk: SDK(), walletID: firstWallet)
    }

    private func expectExpired(
        _ host: SwiftDashSDKHost,
        _ preparation: SwiftDashSDKHost.PlatformPreparation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        var didRun = false
        do {
            _ = try await host.withPlatformOperation(preparation: preparation) {
                didRun = true
                return "submitted"
            }
            XCTFail("An obsolete confirmation must be rejected", file: file, line: line)
        } catch WalletOperationPreparationError.expired {
            XCTAssertFalse(didRun, "Refuse before invoking the operation", file: file, line: line)
        } catch {
            XCTFail("Expected a local expired-preparation error, got \(error)", file: file, line: line)
        }
    }

    func testStatusGenerationAndNewerObservationDoNotInvalidateConfirmation() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        var completed = 0
        for status in ProtocolCompatibility.Status.allCases {
            host.sdk!.snapshot.status = status
            host.sdk!.snapshot.generation += 1
            host.sdk!.snapshot.verifiedProtocolVersion = 99
            try host.validatePlatformOperation(preparation)
            try await host.withPlatformOperation(preparation: preparation) { completed += 1 }
        }
        XCTAssertEqual(completed, 3)
    }

    func testUnavailableAndCheckingSnapshotsAllowPreparationWithoutVerifiedVersion() async throws {
        for status in [ProtocolCompatibility.Status.unavailable, .checking] {
            let host = makeHost()
            host.sdk!.snapshot.status = status
            host.sdk!.snapshot.verifiedProtocolVersion = nil
            let preparation = try host.preparePlatformOperation()
            let value = try await host.withPlatformOperation(preparation: preparation) { 42 }
            XCTAssertEqual(value, 42)
        }
    }

    func testSelectedWalletChangeRejectsConfirmation() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        WalletEnvironment.selectedWalletID = secondWallet
        await expectExpired(host, preparation)
    }

    func testSelectedAndPublishedWalletMismatchRejectsPreparation() async {
        let host = makeHost()
        WalletEnvironment.selectedWalletID = secondWallet
        do {
            _ = try host.preparePlatformOperation()
            XCTFail("The selected wallet must match the wallet that will execute the operation")
        } catch WalletOperationPreparationError.unavailable {
            // The selected wallet has not been published by the host yet.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPublishedWalletReplacementRejectsConfirmationWithUnchangedSelection() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        host.wallet = ManagedPlatformWallet(walletId: secondWallet)
        XCTAssertEqual(WalletEnvironment.selectedWalletID, firstWallet)
        await expectExpired(host, preparation)
    }

    func testMissingPublishedWalletRejectsPreparationEvenWithSelection() async {
        let host = makeHost()
        host.wallet = nil
        XCTAssertEqual(WalletEnvironment.selectedWalletID, firstWallet)
        do {
            _ = try host.preparePlatformOperation()
            XCTFail("A registry ID cannot substitute for a published wallet")
        } catch WalletOperationPreparationError.unavailable {
            // A wallet must be bound before a quote can be confirmed.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingPublishedWalletRejectsConfirmationWithUnchangedSelection() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        host.wallet = nil
        await expectExpired(host, preparation)
    }

    func testAbsentSelectionUsesPublishedWallet() async throws {
        let host = makeHost(selectedWallet: false)
        let preparation = try host.preparePlatformOperation()
        let value = try await host.withPlatformOperation(preparation: preparation) { "submitted" }
        XCTAssertEqual(value, "submitted")
    }

    func testFallbackWalletChangeRejectsConfirmation() async throws {
        let host = makeHost(selectedWallet: false)
        let preparation = try host.preparePlatformOperation()
        host.wallet = ManagedPlatformWallet(walletId: secondWallet)
        await expectExpired(host, preparation)
    }

    func testSelectedNetworkChangeRejectsConfirmation() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        WalletEnvironment.network = .testnet
        await expectExpired(host, preparation)
    }

    func testRunningNetworkChangeRejectsConfirmation() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        host.runningNetwork = .testnet
        await expectExpired(host, preparation)
    }

    func testSDKReplacementWithSameSnapshotRejectsConfirmation() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        let replacement = SDK()
        replacement.snapshot = host.sdk!.snapshot
        host.sdk = replacement
        await expectExpired(host, preparation)
    }

    func testRuntimeReplacementRejectsConfirmation() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        host.runtimeID = UUID()
        await expectExpired(host, preparation)
    }

    func testEffectiveOperationVersionChangeRejectsConfirmation() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        host.sdk!.snapshot.effectiveProtocolVersion += 1
        await expectExpired(host, preparation)
    }

    func testMissingLocalContextRejectsPreparation() async {
        let mutations: [(SwiftDashSDKHost) -> Void] = [
            { $0.sdk = nil },
            { $0.runningNetwork = nil },
            { $0.runningNetwork = .testnet },
            { $0.wallet = nil; WalletEnvironment.selectedWalletID = nil },
        ]
        for mutate in mutations {
            let host = makeHost()
            mutate(host)
            do {
                _ = try host.preparePlatformOperation()
                XCTFail("Missing wallet/runtime context must refuse preparation")
            } catch WalletOperationPreparationError.unavailable {
                // Expected local context failure, independent of check status.
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private enum TestFailure: Error, Equatable { case snapshot, operation }

    private func retryCoordinator(_ host: SwiftDashSDKHost) throws -> RetryCoordinator {
        SwiftDashSDKHost.shared = host
        let coordinator = RetryCoordinator()
        coordinator.confirmationPreparation = .success(try host.preparePlatformOperation())
        coordinator.lastAssetLockOutPoint = (Data([7, 8]), 3)
        return coordinator
    }

    func testRepeatedAssetLockRetryRefreshesVersionAndRetainsExactOutpointAndRecipient() async throws {
        let host = makeHost()
        let coordinator = try retryCoordinator(host)
        let recipient = Data(repeating: 9, count: 43)
        for version: UInt32 in [15, 16] {
            host.sdk!.snapshot.effectiveProtocolVersion = version
            await coordinator.retryLastAssetLock(recipientRaw43: recipient)
            XCTAssertEqual(coordinator.lastAssetLockOutPoint?.txidWire, Data([7, 8]))
            XCTAssertEqual(coordinator.lastAssetLockOutPoint?.vout, 3)
        }
        XCTAssertEqual(coordinator.authorized.count, 2)
        for attempt in coordinator.authorized {
            XCTAssertEqual(attempt.0, Data([7, 8]))
            XCTAssertEqual(attempt.1, 3)
            XCTAssertEqual(attempt.2, recipient)
        }
    }

    func testAssetLockRetryCannotRebindChangedWalletNetworkOrRuntime() async throws {
        let mutations: [(SwiftDashSDKHost) -> Void] = [
            { $0.wallet = .init(walletId: Data([2])); WalletEnvironment.selectedWalletID = Data([2]) },
            { $0.runningNetwork = .testnet; WalletEnvironment.network = .testnet },
            { $0.runtimeID = UUID() },
            { $0.sdk = SDK() },
        ]
        for mutate in mutations {
            let host = makeHost()
            let coordinator = try retryCoordinator(host)
            mutate(host)
            await coordinator.retryLastAssetLock(recipientRaw43: Data(repeating: 9, count: 43))
            XCTAssertTrue(coordinator.attempted.isEmpty)
            XCTAssertNotNil(coordinator.lastFailure)
            XCTAssertEqual(coordinator.lastAssetLockOutPoint?.txidWire, Data([7, 8]))
        }
    }

    func testAssetLockRetryRevalidatesContextAfterAuthorizationAndKeepsLock() async throws {
        let host = makeHost()
        let coordinator = try retryCoordinator(host)
        coordinator.onAuthorize = { host.runtimeID = UUID() }
        await coordinator.retryLastAssetLock(recipientRaw43: Data(repeating: 9, count: 43))
        XCTAssertEqual(coordinator.attempted.count, 1)
        XCTAssertTrue(coordinator.authorized.isEmpty)
        XCTAssertEqual(coordinator.lastAssetLockOutPoint?.vout, 3)
        await coordinator.retryLastAssetLock(recipientRaw43: Data(repeating: 9, count: 43))
        XCTAssertEqual(coordinator.attempted.count, 1)
    }

    func testAssetLockRetryRequiresFailedPhaseAndExistingLock() async throws {
        let host = makeHost()
        let coordinator = try retryCoordinator(host)
        coordinator.phase = .signing
        await coordinator.retryLastAssetLock(recipientRaw43: Data())
        coordinator.phase = .failed("failure")
        coordinator.lastAssetLockOutPoint = nil
        await coordinator.retryLastAssetLock(recipientRaw43: Data())
        XCTAssertTrue(coordinator.attempted.isEmpty)
    }

    func testSnapshotBridgeFailurePropagatesWithoutInvokingOperation() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        host.sdk!.snapshotError = TestFailure.snapshot
        var didRun = false
        do {
            try await host.withPlatformOperation(preparation: preparation) { didRun = true }
            XCTFail("A missing effective operation version must propagate its error")
        } catch {
            XCTAssertEqual(error as? TestFailure, .snapshot)
        }
        XCTAssertFalse(didRun)
    }

    func testSuccessfulOperationHasNoRetroactivePreparationFailure() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        let result = try await host.withPlatformOperation(preparation: preparation) {
            // The operation has been dispatched. Lifecycle changes during its
            // await cannot turn its successful outcome into a retry prompt.
            host.runtimeID = UUID()
            host.sdk!.snapshot.effectiveProtocolVersion += 1
            WalletEnvironment.selectedWalletID = secondWallet
            await Task.yield()
            return "confirmed transaction"
        }
        XCTAssertEqual(result, "confirmed transaction")
        await expectExpired(host, preparation)
    }

    func testOperationFailureIsPreserved() async throws {
        let host = makeHost()
        let preparation = try host.preparePlatformOperation()
        do {
            try await host.withPlatformOperation(preparation: preparation) {
                host.runtimeID = UUID()
                throw TestFailure.operation
            }
            XCTFail("The operation error must propagate")
        } catch {
            XCTAssertEqual(error as? TestFailure, .operation)
        }
    }
}
