//
//  ShieldedTxLookupConsumedOverlayTests.swift
//  DashWalletTests
//
//  When a transfer finishes, the SDK can flush its lock's Consumed status
//  after the call returns, and the next lookup refresh can be superseded or
//  fail. `markConsumed` makes reads report the lock consumed until a
//  published snapshot shows status 4, so the Home row and the details don't
//  offer to finish a transfer that just completed (#1042 / PR #1212).
//

import XCTest
@testable import dashpay

/// Counts `shieldedTxLookupDidChange` posts; they arrive on the posting
/// (main) thread.
private final class PostCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

final class ShieldedTxLookupConsumedOverlayTests: XCTestCase {

    private typealias Info = ShieldedTxLookup.ShieldedLockInfo

    private let txidWire = Data((0..<32).map { UInt8($0) })
    private var txidHex: String { Transaction.displayHex(txidWire).lowercased() }

    private func info(status: Int, fundingType: Int = 5) -> Info {
        Info(amountDuffs: 1_000, statusRaw: status, vout: 0, fundingTypeRaw: fundingType, walletId: Data(repeating: 1, count: 32))
    }

    @MainActor
    func testConsumedMarkHoldsUntilASnapshotShowsTheLockConsumed() {
        let lookup = ShieldedTxLookup()
        lookup.store([txidHex: info(status: 2)])
        lookup.markConsumed(txidWire: txidWire)
        XCTAssertEqual(lookup.info(forTxidHex: txidHex)?.statusRaw, 4)

        // Pending, RecoveredFromChain and a snapshot without the lock (what a
        // refresh with no model container stores) all keep the mark.
        for snapshot in [[txidHex: info(status: 3)], [txidHex: info(status: 5)], [:]] {
            lookup.store(snapshot)
            lookup.store([txidHex: info(status: 2)])
            XCTAssertEqual(lookup.info(forTxidHex: txidHex)?.statusRaw, 4, "after \(snapshot)")
        }

        // A snapshot that shows the lock consumed retires the mark: a later
        // pending row reads as pending again.
        lookup.store([txidHex: info(status: 4)])
        lookup.store([txidHex: info(status: 2)])
        XCTAssertEqual(lookup.info(forTxidHex: txidHex)?.statusRaw, 2)
    }

    @MainActor
    func testConsumedMarkAppliesToEveryRead() {
        // Shielded (5), platform-address (4) and identity (0) locks each have
        // their own read path.
        for (fundingType, read) in [
            (5, { (lookup: ShieldedTxLookup, hex: String) in lookup.info(forTxidHex: hex) }),
            (4, { (lookup: ShieldedTxLookup, hex: String) in lookup.platformFundingInfo(forTxidHex: hex) }),
            (0, { (lookup: ShieldedTxLookup, hex: String) in lookup.identityFundingInfo(forTxidHex: hex) }),
        ] {
            let lookup = ShieldedTxLookup()
            lookup.store([txidHex: info(status: 1, fundingType: fundingType)])
            lookup.markConsumed(txidWire: txidWire)

            XCTAssertEqual(read(lookup, txidHex.uppercased())?.statusRaw, 4, "type \(fundingType)")
            XCTAssertEqual(lookup.allEntries().first?.info.statusRaw, 4, "type \(fundingType)")
        }
    }

    @MainActor
    func testChangesArePublishedOnlyWhenWhatReadsReportChanges() {
        let lookup = ShieldedTxLookup()
        let posts = PostCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .shieldedTxLookupDidChange, object: nil, queue: nil
        ) { _ in posts.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        lookup.store([txidHex: info(status: 2)])
        XCTAssertEqual(posts.count, 1, "a new snapshot")
        lookup.store([txidHex: info(status: 2)])
        XCTAssertEqual(posts.count, 1, "the same snapshot again")

        lookup.markConsumed(txidWire: txidWire)
        XCTAssertEqual(posts.count, 2, "a new mark")
        lookup.markConsumed(txidWire: txidWire)
        XCTAssertEqual(posts.count, 2, "the same mark again")
    }
}
