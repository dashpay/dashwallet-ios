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
import SwiftData
import SwiftDashSDK
@testable import dashpay

private struct RefreshNeverReachedItsRead: Error {}

/// Counts `shieldedTxLookupDidChange` posts; they arrive on the posting
/// (main) thread.
private final class PostCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// Snapshot loader whose first call is held until the test releases it;
/// later calls return `next` at once.
private final class HeldLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var held: CheckedContinuation<ShieldedTxLookup.SnapshotBuildResult, Never>?
    private var next: ShieldedTxLookup.SnapshotBuildResult?

    func setNext(_ result: ShieldedTxLookup.SnapshotBuildResult) {
        lock.withLock { next = result }
    }

    func load() async -> ShieldedTxLookup.SnapshotBuildResult {
        let isFirst = lock.withLock { () -> Bool in
            calls += 1
            return calls == 1
        }
        if isFirst {
            return await withCheckedContinuation { continuation in
                lock.withLock { held = continuation }
            }
        }
        // An unplanned read gets a failed snapshot, which `refresh` drops,
        // rather than trapping the test host.
        return lock.withLock { next } ?? ShieldedTxLookup.SnapshotBuildResult(
            map: nil, assetLockCount: 0, typesSeen: [], uncoveredTxids: [],
            errorDescription: "unexpected snapshot read", workerRanOffMain: true)
    }

    var isHolding: Bool { lock.withLock { held != nil } }

    func release(with result: ShieldedTxLookup.SnapshotBuildResult) {
        let continuation = lock.withLock { () -> CheckedContinuation<ShieldedTxLookup.SnapshotBuildResult, Never>? in
            defer { held = nil }
            return held
        }
        continuation?.resume(returning: result)
    }
}

/// The container `refresh` sees as active; tests swap it mid-refresh.
private final class ActiveContainer: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ModelContainer?

    init(_ container: ModelContainer) { value = container }

    var current: ModelContainer? { lock.withLock { value } }
    func set(_ container: ModelContainer) { lock.withLock { value = container } }
}

final class ShieldedTxLookupConsumedOverlayTests: XCTestCase {

    private typealias Info = ShieldedTxLookup.ShieldedLockInfo

    private let txidWire = Data((0..<32).map { UInt8($0) })
    private var txidHex: String { Transaction.displayHex(txidWire).lowercased() }

    private func snapshot(status: Int) -> ShieldedTxLookup.SnapshotBuildResult {
        ShieldedTxLookup.SnapshotBuildResult(
            map: [txidHex: info(status: status)],
            assetLockCount: 1,
            typesSeen: [5],
            uncoveredTxids: [],
            errorDescription: nil,
            workerRanOffMain: true)
    }

    /// Two in-memory containers, built once for the whole class: the tests
    /// use them only as the identity `refresh` compares, and each extra
    /// container over the app's models is process-wide state in the host.
    private static let containers: (ModelContainer, ModelContainer)? = {
        func make() -> ModelContainer? {
            try? ModelContainer(
                for: PersistentAssetLock.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
        guard let first = make(), let second = make() else { return nil }
        return (first, second)
    }()

    private func containers() throws -> (ModelContainer, ModelContainer) {
        try XCTUnwrap(Self.containers, "in-memory model containers")
    }

    /// Counts the changes `lookup` itself announces; other lookups (the host
    /// app's `shared` one) post with themselves as the object.
    private func countPosts(of lookup: ShieldedTxLookup) -> (PostCounter, NSObjectProtocol) {
        let posts = PostCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .shieldedTxLookupDidChange, object: lookup, queue: nil
        ) { _ in posts.increment() }
        return (posts, observer)
    }

    /// Waits until the loader holds the first snapshot read. A refresh that
    /// never gets there fails the test instead of leaving a later step
    /// waiting forever.
    private func waitUntilHolding(_ loader: HeldLoader) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !loader.isHolding, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard loader.isHolding else { throw RefreshNeverReachedItsRead() }
    }

    @MainActor
    func testASupersededRefreshNeitherReplacesNorAnnouncesTheWinningSnapshot() async throws {
        let (container, _) = try containers()
        let loader = HeldLoader()
        loader.setNext(snapshot(status: 4))
        let lookup = ShieldedTxLookup(source: .init(
            activeContainer: { container },
            buildSnapshot: { _ in await loader.load() }))
        let (posts, observer) = countPosts(of: lookup)
        defer { NotificationCenter.default.removeObserver(observer) }

        // Refresh A is held in its read while refresh B publishes.
        let refreshA = Task { await lookup.refresh(reason: "A") }
        try await waitUntilHolding(loader)
        await lookup.refresh(reason: "B")
        loader.release(with: snapshot(status: 2))
        await refreshA.value

        XCTAssertEqual(lookup.info(forTxidHex: txidHex)?.statusRaw, 4, "B's consumed snapshot stands")
        XCTAssertEqual(posts.count, 1, "only B's publication was announced")
    }

    @MainActor
    func testARefreshFromAReplacedContainerIsDropped() async throws {
        let (first, second) = try containers()
        let active = ActiveContainer(first)
        let loader = HeldLoader()
        let lookup = ShieldedTxLookup(source: .init(
            activeContainer: { active.current },
            buildSnapshot: { _ in await loader.load() }))
        let (posts, observer) = countPosts(of: lookup)
        defer { NotificationCenter.default.removeObserver(observer) }

        // No newer refresh runs: only the container check can drop this one.
        let refresh = Task { await lookup.refresh(reason: "old wallet") }
        try await waitUntilHolding(loader)
        active.set(second)
        loader.release(with: snapshot(status: 2))
        await refresh.value

        XCTAssertNil(lookup.info(forTxidHex: txidHex), "the old wallet's rows were not published")
        XCTAssertEqual(posts.count, 0)
    }

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
        let (posts, observer) = countPosts(of: lookup)
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
