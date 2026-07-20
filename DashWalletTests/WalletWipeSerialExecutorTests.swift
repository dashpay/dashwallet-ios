//
//  WalletWipeSerialExecutorTests.swift
//  DashWalletTests
//
//  Regression coverage for the reinstall Delete race: PIN removal is
//  synchronous, while the SDK wallet wipe is queued in the background. The
//  transition barrier must never fire before that queued wipe finishes.
//

import XCTest
@testable import dashwallet

private enum WalletLifecycleTestError: Error {
    case deletionInProgress
    case mnemonicPersistence
    case walletCreation
}

private actor WalletDeletionTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

final class WalletWipeSerialExecutorTests: XCTestCase {
    func testIdleNotificationWaitsForPreviouslyQueuedWipe() {
        let executor = WalletWipeSerialExecutor(
            label: "org.dashfoundation.dash.wallet-wiper-tests.\(UUID().uuidString)")
        let wipeStarted = expectation(description: "wipe started")
        let wipeFinished = expectation(description: "wipe finished")
        let completionCalled = expectation(description: "completion called")
        let releaseWipe = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var events: [String] = []

        executor.enqueue {
            lock.lock()
            events.append("wipe-started")
            lock.unlock()
            wipeStarted.fulfill()

            releaseWipe.wait()

            lock.lock()
            events.append("wipe-finished")
            lock.unlock()
            wipeFinished.fulfill()
            return true
        }

        wait(for: [wipeStarted], timeout: 1)

        executor.notifyWhenIdle(on: .global(qos: .userInitiated)) { succeeded in
            lock.lock()
            events.append(succeeded ? "completion-success" : "completion-failure")
            lock.unlock()
            completionCalled.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            releaseWipe.signal()
        }
        wait(for: [wipeFinished, completionCalled], timeout: 1)

        lock.lock()
        let recordedEvents = events
        lock.unlock()
        XCTAssertEqual(recordedEvents, ["wipe-started", "wipe-finished", "completion-success"])
    }

    func testIdleNotificationPropagatesWipeFailure() {
        let executor = WalletWipeSerialExecutor(
            label: "org.dashfoundation.dash.wallet-wiper-tests.\(UUID().uuidString)")
        let completionCalled = expectation(description: "completion called")

        executor.enqueue { false }
        executor.notifyWhenIdle(on: .global(qos: .userInitiated)) { succeeded in
            XCTAssertFalse(succeeded)
            completionCalled.fulfill()
        }

        wait(for: [completionCalled], timeout: 1)
    }

    @MainActor
    func testOverlappingDeleteFailurePreservesSecondWalletMnemonicAndAppState() async throws {
        let firstWalletId = Data(repeating: 0x11, count: 32)
        let secondWalletId = Data(repeating: 0x22, count: 32)
        var walletIdsWithMnemonic: Set<Data> = [firstWalletId, secondWalletId]
        var clearedAppState: Set<Data> = []
        var deletionInProgress = false
        let firstDeleteStarted = expectation(description: "first delete started")
        let gate = WalletDeletionTestGate()

        let deleteWallet: @MainActor (Data) async throws -> Void = { walletId in
            guard !deletionInProgress else {
                throw WalletLifecycleTestError.deletionInProgress
            }
            deletionInProgress = true
            if walletId == firstWalletId {
                firstDeleteStarted.fulfill()
                await gate.wait()
            }
            walletIdsWithMnemonic.remove(walletId)
            deletionInProgress = false
        }
        let clearAppState: @MainActor (Data) -> Void = { walletId in
            clearedAppState.insert(walletId)
        }

        let firstDelete = Task { @MainActor in
            try await SwiftDashSDKWalletWiper.deleteWalletFromSDK(
                firstWalletId,
                deleteWallet: deleteWallet,
                clearAppState: clearAppState)
        }
        await fulfillment(of: [firstDeleteStarted], timeout: 1)

        do {
            try await SwiftDashSDKWalletWiper.deleteWalletFromSDK(
                secondWalletId,
                deleteWallet: deleteWallet,
                clearAppState: clearAppState)
            XCTFail("overlapping delete should fail")
        } catch WalletLifecycleTestError.deletionInProgress {
            // Expected: no destructive fallback follows this error.
        }

        XCTAssertTrue(walletIdsWithMnemonic.contains(secondWalletId))
        XCTAssertFalse(clearedAppState.contains(secondWalletId))

        await gate.release()
        try await firstDelete.value
        XCTAssertFalse(walletIdsWithMnemonic.contains(firstWalletId))
        XCTAssertTrue(clearedAppState.contains(firstWalletId))
    }
}

final class MnemonicFirstWalletCreationTests: XCTestCase {
    func testPersistenceFailureDoesNotCreateWallet() {
        var storedMnemonic: String?
        var createCalled = false

        XCTAssertThrowsError(try MnemonicFirstWalletCreation.run(
            mnemonic: "test mnemonic",
            persistMnemonic: {
                storedMnemonic = "partially written"
                throw WalletLifecycleTestError.mnemonicPersistence
            },
            retrieveMnemonic: {
                storedMnemonic ?? ""
            },
            rollbackMnemonic: {
                storedMnemonic = nil
            },
            createWallet: {
                createCalled = true
                return 1
            }
        )) { error in
            guard case MnemonicFirstWalletCreationError.mnemonicPersistence = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        XCTAssertFalse(createCalled)
        XCTAssertNil(storedMnemonic)
    }

    func testMnemonicIsAvailableBeforeWalletCreation() throws {
        let mnemonic = "test mnemonic"
        var storedMnemonic: String?

        let wallet = try MnemonicFirstWalletCreation.run(
            mnemonic: mnemonic,
            persistMnemonic: {
                storedMnemonic = mnemonic
            },
            retrieveMnemonic: {
                storedMnemonic ?? ""
            },
            rollbackMnemonic: {
                storedMnemonic = nil
            },
            createWallet: {
                XCTAssertEqual(storedMnemonic, mnemonic)
                return 7
            })

        XCTAssertEqual(wallet, 7)
        XCTAssertEqual(storedMnemonic, mnemonic)
    }

    func testCreationFailureRemovesProvisionalMnemonicAndPropagatesError() {
        let mnemonic = "test mnemonic"
        var storedMnemonic: String?

        XCTAssertThrowsError(try MnemonicFirstWalletCreation.run(
            mnemonic: mnemonic,
            persistMnemonic: {
                storedMnemonic = mnemonic
            },
            retrieveMnemonic: {
                storedMnemonic ?? ""
            },
            rollbackMnemonic: {
                storedMnemonic = nil
            },
            createWallet: { () throws -> Int in
                throw WalletLifecycleTestError.walletCreation
            }
        )) { error in
            guard case MnemonicFirstWalletCreationError.walletCreation = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        XCTAssertNil(storedMnemonic)
    }

    func testCreationFailureRestoresPreviousMnemonic() {
        let previousMnemonic = "previous mnemonic"
        let replacementMnemonic = "replacement mnemonic"
        var storedMnemonic: String? = previousMnemonic

        XCTAssertThrowsError(try MnemonicFirstWalletCreation.run(
            mnemonic: replacementMnemonic,
            persistMnemonic: {
                storedMnemonic = replacementMnemonic
            },
            retrieveMnemonic: {
                storedMnemonic ?? ""
            },
            rollbackMnemonic: {
                storedMnemonic = previousMnemonic
            },
            createWallet: { () throws -> Int in
                throw WalletLifecycleTestError.walletCreation
            }))

        XCTAssertEqual(storedMnemonic, previousMnemonic)
    }
}
