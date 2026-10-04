//
//  CoinJoinSweepTests.swift
//  DashWalletTests
//
//  The CoinJoin sweep's ownership rules, through the seams it runs on:
//  single-flight admission per wallet and network (`CoinJoinSweepAdmission`),
//  the chunk loop that stops when the swept wallet stops running
//  (`SwiftDashSDKTransactionSender.sweepChunks`), and the recording of the
//  accepted chunks under the wallet that ran them
//  (`WalletSendService.recordCoinJoinSweepChunks`).
//

import Foundation
import XCTest
@testable import dashpay

final class CoinJoinSweepTests: XCTestCase {

    // MARK: Admission

    func testCallsForTheSameWalletShareOneSweepAndItsResult() async throws {
        let admission = CoinJoinSweepAdmission<String>()
        let gate = Gate()
        let sweeps = Counter()

        async let first = admission.run("wallet-a") {
            await sweeps.increment()
            await gate.wait()
            return 42
        }
        try await waitUntil { await sweeps.value == 1 }
        async let second = admission.run("wallet-a") {
            await sweeps.increment()
            return 7
        }
        // The second call has to reach admission while the first still runs;
        // nothing observable marks that, so it gets ample time.
        try await Task.sleep(nanoseconds: 200_000_000)
        await gate.open()

        let results = try await [first, second]
        XCTAssertEqual(results, [42, 42], "the joining call gets the running sweep's result")
        let count = await sweeps.value
        XCTAssertEqual(count, 1, "one authorization and one sweep for both calls")
    }

    func testACallForAnotherWalletOrNetworkWaitsAndGetsItsOwnResult() async throws {
        let admission = CoinJoinSweepAdmission<String>()
        let gate = Gate()
        let events = Log()

        async let first = admission.run("wallet-a/testnet") {
            await events.append("a started")
            await gate.wait()
            await events.append("a ended")
            return 1
        }
        try await waitUntil { await events.entries == ["a started"] }
        async let second = admission.run("wallet-a/mainnet") {
            await events.append("b started")
            return 2
        }
        // Give the second call every chance to start early.
        try await Task.sleep(nanoseconds: 200_000_000)
        let beforeOpen = await events.entries
        XCTAssertEqual(beforeOpen, ["a started"], "the other key does not start while the first runs")
        await gate.open()

        let results = try await [first, second]
        XCTAssertEqual(results, [1, 2], "each key gets its own sweep's result")
        let order = await events.entries
        XCTAssertEqual(order, ["a started", "a ended", "b started"])
    }

    func testAFailedSweepFreesTheSlot() async throws {
        let admission = CoinJoinSweepAdmission<String>()
        let sweeps = Counter()

        do {
            _ = try await admission.run("wallet-a") {
                await sweeps.increment()
                throw TestError.authorizationFailed
            }
            XCTFail("the failure reaches the caller")
        } catch TestError.authorizationFailed {}

        let result = try await admission.run("wallet-a") {
            await sweeps.increment()
            return 5
        }
        XCTAssertEqual(result, 5, "the next call runs its own sweep, not the failed one's")
        let count = await sweeps.value
        XCTAssertEqual(count, 2)
    }

    func testACallWaitingBehindAFailedSweepOfAnotherKeyStillRunsItsOwn() async throws {
        let admission = CoinJoinSweepAdmission<String>()
        let gate = Gate()
        let started = Counter()

        async let first: UInt64 = admission.run("wallet-a") {
            await started.increment()
            await gate.wait()
            throw TestError.sweepFailed
        }
        try await waitUntil { await started.value == 1 }
        async let second = admission.run("wallet-b") { 9 }
        // The second call has to be waiting behind the first when it fails.
        try await Task.sleep(nanoseconds: 200_000_000)
        await gate.open()

        do {
            _ = try await first
            XCTFail("the first sweep failed")
        } catch TestError.sweepFailed {}
        let result = try await second
        XCTAssertEqual(result, 9)
    }

    // MARK: Chunk loop

    func testAWalletChangeStopsTheRemainingChunksAndKeepsTheAcceptedOnes() throws {
        var checks = 0
        var broadcastChunks: [Int] = []
        let outcome = try SwiftDashSDKTransactionSender.sweepChunks(
            [1, 2, 3, 4, 5],
            runningWallet: { () -> String? in
                checks += 1
                return checks <= 2 ? "wallet-a" : nil
            },
            broadcast: { chunk, wallet in
                XCTAssertEqual(wallet, "wallet-a")
                broadcastChunks.append(chunk)
                return Data([UInt8(chunk)])
            })

        XCTAssertEqual(broadcastChunks, [1, 2], "nothing goes out after the wallet stopped running")
        XCTAssertEqual(outcome.txids, [Data([1]), Data([2])])
        XCTAssertEqual(outcome.unattemptedChunkCount, 3)
        XCTAssertEqual(outcome.failedChunkCount, 0)
        XCTAssertTrue(outcome.isPartial)
    }

    func testAFailedChunkIsCountedAndTheLoopGoesOn() throws {
        let outcome = try SwiftDashSDKTransactionSender.sweepChunks(
            [1, 2, 3],
            runningWallet: { "wallet-a" },
            broadcast: { chunk, _ in
                if chunk == 2 { throw TestError.sweepFailed }
                return Data([UInt8(chunk)])
            })

        XCTAssertEqual(outcome.txids, [Data([1]), Data([3])])
        XCTAssertEqual(outcome.failedChunkCount, 1)
        XCTAssertEqual(outcome.unattemptedChunkCount, 0)
        XCTAssertTrue(outcome.firstFailure is TestError)
        XCTAssertTrue(outcome.isPartial)
    }

    func testEveryChunkFailingThrowsTheFirstFailure() {
        XCTAssertThrowsError(try SwiftDashSDKTransactionSender.sweepChunks(
            [1, 2],
            runningWallet: { "wallet-a" },
            broadcast: { _, _ in throw TestError.sweepFailed }
        )) { error in
            XCTAssertEqual(error as? TestError, .sweepFailed)
        }
    }

    func testAWalletGoneBeforeTheFirstChunkLeavesEverythingUnattempted() throws {
        let outcome = try SwiftDashSDKTransactionSender.sweepChunks(
            [1, 2],
            runningWallet: { () -> String? in nil },
            broadcast: { _, _ in
                XCTFail("no chunk goes out")
                return Data()
            })

        XCTAssertTrue(outcome.txids.isEmpty)
        XCTAssertEqual(outcome.unattemptedChunkCount, 2)
        XCTAssertFalse(outcome.isPartial)
    }

    // MARK: Recording

    private let originatingWallet = Data([0xA1])

    private func outcome(txids: [Data], unattempted: Int = 0, failure: Error? = nil)
        -> SwiftDashSDKTransactionSender.CoinJoinSweepOutcome {
        .init(txids: txids, failedChunkCount: failure == nil ? 0 : 1,
              firstFailure: failure, unattemptedChunkCount: unattempted)
    }

    func testChunksOfAWalletThatLeftStayWithThatWalletAndNoAlertShows() {
        var recorded: [(txid: Data, walletId: Data)] = []
        XCTAssertThrowsError(try WalletSendService.recordCoinJoinSweepChunks(
            outcome(txids: [Data([1]), Data([2])], unattempted: 3),
            ofWallet: originatingWallet, amount: 1_000,
            isWalletSelected: false,
            isWalletStored: { true },
            record: { recorded.append(($0, $1)) }
        )) { error in
            // Interrupted: the only non-cancel error the sweep surfaces stay silent on.
            XCTAssertFalse(WalletSendService.isAuthenticationCancelledError(error as NSError))
            XCTAssertNil(WalletSendService.coinJoinSweepUserMessage(for: error), "no alert")
        }
        XCTAssertEqual(recorded.map(\.txid), [Data([1]), Data([2])])
        XCTAssertEqual(recorded.map(\.walletId), [originatingWallet, originatingWallet],
                       "attributed to the wallet that ran the sweep")
    }

    func testChunksOfARemovedWalletAreNotRecorded() {
        var recorded = 0
        XCTAssertThrowsError(try WalletSendService.recordCoinJoinSweepChunks(
            outcome(txids: [Data([1])]),
            ofWallet: originatingWallet, amount: 1_000,
            isWalletSelected: false,
            isWalletStored: { false },
            record: { _, _ in recorded += 1 }))
        XCTAssertEqual(recorded, 0)
    }

    func testChunksOfTheSelectedWalletAreRecordedUnderIt() throws {
        var recorded: [(txid: Data, walletId: Data)] = []
        try WalletSendService.recordCoinJoinSweepChunks(
            outcome(txids: [Data([1]), Data([2])]),
            ofWallet: originatingWallet, amount: 1_000,
            isWalletSelected: true,
            isWalletStored: {
                XCTFail("only asked for a wallet that left")
                return true
            },
            record: { recorded.append(($0, $1)) })
        XCTAssertEqual(recorded.map(\.txid), [Data([1]), Data([2])])
        XCTAssertEqual(Set(recorded.map(\.walletId)), [originatingWallet])
    }

    func testASelectedSweepWithNothingAcceptedThrowsItsFailure() {
        XCTAssertThrowsError(try WalletSendService.recordCoinJoinSweepChunks(
            outcome(txids: [], failure: TestError.sweepFailed),
            ofWallet: originatingWallet, amount: 1_000,
            isWalletSelected: true,
            isWalletStored: { true },
            record: { _, _ in XCTFail("nothing to record") }
        )) { error in
            XCTAssertEqual(error as? TestError, .sweepFailed)
        }
    }

}

// MARK: - Helpers

private enum TestError: Error, Equatable {
    case authorizationFailed
    case sweepFailed
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor Log {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
}

/// Holds a sweep until the test lets it finish.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private func waitUntil(
    timeout: TimeInterval = 5, _ condition: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while await !condition() {
        guard Date() < deadline else {
            XCTFail("condition not met in \(timeout)s")
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}
