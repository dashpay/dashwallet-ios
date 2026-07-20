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
        }

        wait(for: [wipeStarted], timeout: 1)

        executor.notifyWhenIdle(on: .global(qos: .userInitiated)) {
            lock.lock()
            events.append("completion")
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
        XCTAssertEqual(recordedEvents, ["wipe-started", "wipe-finished", "completion"])
    }
}
