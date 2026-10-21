import XCTest
@testable import dashpay

final class SPVChainStoreRebuildTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SPVChainStoreRebuildTests-markers-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func walletId(_ byte: UInt8) -> Data {
        Data(repeating: byte, count: 32)
    }

    func testNothingIsPendingUntilAnImportArmsIt() {
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory))
    }

    func testImportArmsOnlyItsOwnScope() throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1)])
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", directory: directory))
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "testnet-sakura", directory: directory))
    }

    func testSecondImportJoinsThePendingRebuildAndARepeatAddsNothing() throws {
        XCTAssertTrue(try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", directory: directory))
        XCTAssertTrue(try SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "mainnet", directory: directory))
        XCTAssertFalse(try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", directory: directory))

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", directory: directory),
            [walletId(0xA1), walletId(0xB2)])
    }

    func testFinishDropsOnlyTheRebuiltWalletsAndKeepsOnesArmedMeanwhile() throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", directory: directory)
        try SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "mainnet", directory: directory)

        SPVChainStoreRebuild.finish(walletIds: [walletId(0xA1)], scope: "mainnet", directory: directory)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", directory: directory),
            [walletId(0xB2)])

        SPVChainStoreRebuild.finish(walletIds: [walletId(0xB2)], scope: "mainnet", directory: directory)
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", directory: directory))
    }

    func testFinishOfAWalletThatIsNotPendingChangesNothing() throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)

        SPVChainStoreRebuild.finish(walletIds: [walletId(0xEE)], scope: "testnet", directory: directory)
        SPVChainStoreRebuild.finish(walletIds: [walletId(0xA1)], scope: "mainnet", directory: directory)

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1)])
    }

    func testClearAllDropsEveryScope() throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", directory: directory)
        try SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "devnet-sakura", directory: directory)

        SPVChainStoreRebuild.clearAll(directory: directory)

        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", directory: directory))
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "devnet-sakura", directory: directory))
    }

    func testArmedMarkerIsAFileOnDiskBeforeArmReturns() throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xC3), scope: "testnet", directory: directory)

        let marker = directory.appendingPathComponent("testnet").appendingPathComponent(String(repeating: "c3", count: 32))
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testArmThrowsWhenTheMarkerCannotBeWritten() throws {
        // A file where the marker directory should be.
        try Data([0]).write(to: directory)

        XCTAssertThrowsError(try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory))
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory))
    }

    func testArmingAPendingWalletAgainStillSucceeds() throws {
        XCTAssertTrue(try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory))
        XCTAssertFalse(try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory))

        // After a clear the same wallet arms from nothing, directories included.
        SPVChainStoreRebuild.clearAll(directory: directory)
        XCTAssertTrue(try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory))
    }

    func testAMarkerWrittenButNotFlushedStaysPending() throws {
        // The marker root sits in a directory that can be traversed and
        // written but not opened for the last flush — not for root.
        try XCTSkipIf(getuid() == 0)
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("SPVChainStoreRebuildTests-noflush-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: parent.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
            try? FileManager.default.removeItem(at: parent)
        }
        let root = parent.appendingPathComponent("ChainStoreRebuilds", isDirectory: true)

        XCTAssertThrowsError(try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: root))

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: root),
            [walletId(0xA1)])
    }

    func testUnrelatedFilesInAScopeDirectoryAreNotWalletIds() throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)
        try Data().write(to: directory.appendingPathComponent("testnet/.DS_Store"))

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1)])
    }

    // MARK: - Applying a pending rebuild

    @MainActor
    func testApplyRewindsThenClearsAndReturnsOnlyLoadedWallets() async throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)
        try SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "testnet", directory: directory)
        var steps: [String] = []

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            directory: directory,
            isLoaded: { $0 == self.walletId(0xA1) },
            rewind: { walletId in
                XCTAssertEqual(walletId, self.walletId(0xA1))
                steps.append("rewind")
                return true
            },
            clearStore: {
                steps.append("clear")
                return true
            })

        XCTAssertEqual(applied, [walletId(0xA1)])
        XCTAssertEqual(steps, ["rewind", "clear"])
        // Consumed by the caller, after the start, and only for what was applied.
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1), walletId(0xB2)])
        SPVChainStoreRebuild.finish(walletIds: applied, scope: "testnet", directory: directory)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xB2)])
    }

    @MainActor
    func testApplyTouchesNothingWhenNoPendingWalletIsLoaded() async throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)
        var steps: [String] = []

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            directory: directory,
            isLoaded: { _ in false },
            rewind: { _ in
                steps.append("rewind")
                return true
            },
            clearStore: {
                steps.append("clear")
                return true
            })

        XCTAssertEqual(applied, [])
        XCTAssertEqual(steps, [])
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1)])
    }

    @MainActor
    func testApplyDoesNothingWhenNothingIsPending() async {
        var steps: [String] = []

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            directory: directory,
            isLoaded: { _ in true },
            rewind: { _ in
                steps.append("rewind")
                return true
            },
            clearStore: {
                steps.append("clear")
                return true
            })

        XCTAssertEqual(applied, [])
        XCTAssertEqual(steps, [])
    }

    @MainActor
    func testFailedRewindLeavesTheStoreAndTheMarker() async throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)
        var cleared = false

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            directory: directory,
            isLoaded: { _ in true },
            rewind: { _ in false },
            clearStore: {
                cleared = true
                return true
            })

        XCTAssertEqual(applied, [])
        XCTAssertFalse(cleared)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1)])
    }

    @MainActor
    func testOneFailedRewindDoesNotHoldBackTheOtherWallets() async throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)
        try SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "testnet", directory: directory)
        var cleared = false

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            directory: directory,
            isLoaded: { _ in true },
            rewind: { $0 == self.walletId(0xB2) },
            clearStore: {
                cleared = true
                return true
            })

        XCTAssertEqual(applied, [walletId(0xB2)])
        XCTAssertTrue(cleared)
        SPVChainStoreRebuild.finish(walletIds: applied, scope: "testnet", directory: directory)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1)])
    }

    @MainActor
    func testRefusedClearKeepsTheMarkerForTheNextStart() async throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            directory: directory,
            isLoaded: { _ in true },
            rewind: { _ in true },
            clearStore: { false })

        XCTAssertEqual(applied, [])
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1)])
    }

    // MARK: - Consuming the marker and lowering checkpoints

    private struct Failure: Error {}

    private final class Row {
        var syncedHeight: UInt32
        init(_ syncedHeight: UInt32) { self.syncedHeight = syncedHeight }
    }

    func testAFailedStartKeepsTheAppliedWalletsPending() throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)

        XCTAssertThrowsError(try SPVChainStoreRebuild.finish(
            walletIds: [walletId(0xA1)], scope: "testnet", directory: directory,
            afterStarting: { throw Failure() }))

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1)])
    }

    func testASuccessfulStartConsumesOnlyTheAppliedWallets() throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)
        try SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "testnet", directory: directory)
        var pendingDuringStart: [Data]?

        SPVChainStoreRebuild.finish(
            walletIds: [walletId(0xA1)], scope: "testnet", directory: directory,
            afterStarting: {
                pendingDuringStart = SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: self.directory)
            })

        XCTAssertEqual(pendingDuringStart, [walletId(0xA1), walletId(0xB2)])
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xB2)])
    }

    func testAStartWithNothingAppliedLeavesTheMarkerAlone() throws {
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)
        var started = false

        SPVChainStoreRebuild.finish(
            walletIds: [], scope: "testnet", directory: directory, afterStarting: { started = true })

        XCTAssertTrue(started)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1)])
    }

    func testLowerCheckpointsNeverRaisesARow() throws {
        let rows = [Row(1_500_000), Row(100), Row(200_000)]
        var saved: [[UInt32]] = []

        try SPVChainStoreRebuild.lowerCheckpoints(
            of: rows, to: 200_000, checkpoint: \.syncedHeight, save: { saved.append(rows.map(\.syncedHeight)) })

        // One save, of the lowered values.
        XCTAssertEqual(saved, [[200_000, 100, 200_000]])
        XCTAssertEqual(rows.map(\.syncedHeight), [200_000, 100, 200_000])
    }

    func testAFailedSavePutsTheCheckpointsBack() {
        let rows = [Row(1_500_000), Row(100)]

        XCTAssertThrowsError(try SPVChainStoreRebuild.lowerCheckpoints(
            of: rows, to: 0, checkpoint: \.syncedHeight, save: { throw Failure() }))

        XCTAssertEqual(rows.map(\.syncedHeight), [1_500_000, 100])
    }

    // MARK: - Emptying the store

    private func makeScratchDirectory() throws -> URL {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("SPVChainStoreRebuildTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        return scratch
    }

    private func makeStore(in scratch: URL, scope: String = "testnet") throws -> URL {
        let store = scratch.appendingPathComponent("SPV/\(scope)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: store.appendingPathComponent("headers", isDirectory: true),
            withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: store.appendingPathComponent("headers/segment_0000.dat"))
        return store
    }

    func testEmptyStoreLeavesAnEmptyDirectoryAndNoMovedCopy() throws {
        let scratch = try makeScratchDirectory()
        let store = try makeStore(in: scratch)
        let trash = scratch.appendingPathComponent("trash", isDirectory: true)

        try SPVChainStoreRebuild.emptyStore(at: store, movingInto: trash)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), [])
    }

    func testEmptyStoreSweepsACopyAnInterruptedClearLeftBehind() throws {
        let scratch = try makeScratchDirectory()
        let store = try makeStore(in: scratch)
        let trash = scratch.appendingPathComponent("trash", isDirectory: true)
        let leftover = trash.appendingPathComponent("earlier", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        let neighbour = scratch.appendingPathComponent("unrelated.tmp")
        try Data([9]).write(to: neighbour)

        try SPVChainStoreRebuild.emptyStore(at: store, movingInto: trash)

        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighbour.path))
    }

    func testEmptyStoreThatCannotMoveLeavesTheStoreWhole() throws {
        let scratch = try makeScratchDirectory()
        let store = try makeStore(in: scratch)
        let trash = scratch.appendingPathComponent("trash", isDirectory: true)
        // A read-only parent refuses the rename itself — not for root.
        try XCTSkipIf(getuid() == 0)
        let parent = store.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
        }

        XCTAssertThrowsError(try SPVChainStoreRebuild.emptyStore(at: store, movingInto: trash))

        XCTAssertEqual(
            try Data(contentsOf: store.appendingPathComponent("headers/segment_0000.dat")),
            Data([1, 2, 3]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), [])
    }

    func testEmptyStoreThatCannotCreateItsTrashLeavesTheStoreWhole() throws {
        let scratch = try makeScratchDirectory()
        let store = try makeStore(in: scratch)
        // A file where the trash's parent should be: nothing can be moved in.
        let blocker = scratch.appendingPathComponent("blocker")
        try Data([0]).write(to: blocker)
        let trash = blocker.appendingPathComponent("trash", isDirectory: true)

        XCTAssertThrowsError(try SPVChainStoreRebuild.emptyStore(at: store, movingInto: trash))

        XCTAssertEqual(
            try Data(contentsOf: store.appendingPathComponent("headers/segment_0000.dat")),
            Data([1, 2, 3]))
    }

    func testEmptyStoreReplacesAFileSittingAtTheTrashPath() throws {
        let scratch = try makeScratchDirectory()
        let store = try makeStore(in: scratch)
        let trash = scratch.appendingPathComponent("trash")
        try Data([0]).write(to: trash)

        try SPVChainStoreRebuild.emptyStore(at: store, movingInto: trash)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), [])
    }

    // MARK: - A scope whose SPV stop failed

    func testAFailedStopClosesOnlyItsOwnScope() {
        var gate = SPVChainStoreRebuild.StoreClearGate()
        XCTAssertTrue(gate.allowsClearing(scope: "testnet"))

        gate.recordFailedStop(scope: "testnet")

        XCTAssertFalse(gate.allowsClearing(scope: "testnet"))
        XCTAssertTrue(gate.allowsClearing(scope: "mainnet"))
        XCTAssertTrue(gate.allowsClearing(scope: "testnet-sakura"))
    }

    /// A rebuild whose store clear goes through the gate, the step the
    /// coordinator's clear runs.
    @MainActor
    private func rebuild(scope: String, store: URL, trash: URL, gate: SPVChainStoreRebuild.StoreClearGate) async -> [Data] {
        await SPVChainStoreRebuild.apply(
            scope: scope,
            directory: directory,
            isLoaded: { _ in true },
            rewind: { _ in true },
            clearStore: {
                (try? await gate.clear(scope: scope) {
                    try SPVChainStoreRebuild.emptyStore(at: store, movingInto: trash)
                }) ?? false
            })
    }

    @MainActor
    func testTheGateRunsAClearOnlyForAScopeWhoseStopDidNotFail() async {
        var gate = SPVChainStoreRebuild.StoreClearGate()
        gate.recordFailedStop(scope: "testnet")
        var cleared: [String] = []

        let testnet = await gate.clear(scope: "testnet") { cleared.append("testnet") }
        let mainnet = await gate.clear(scope: "mainnet") { cleared.append("mainnet") }

        XCTAssertFalse(testnet)
        XCTAssertTrue(mainnet)
        XCTAssertEqual(cleared, ["mainnet"])
    }

    @MainActor
    func testTheGatePassesOnAClearsError() async {
        let gate = SPVChainStoreRebuild.StoreClearGate()

        do {
            _ = try await gate.clear(scope: "testnet") { throw Failure() }
            XCTFail("the clear's error was swallowed")
        } catch {}
    }

    @MainActor
    func testAFailedStopKeepsItsScopesStoreAndMarkerWhileAnotherScopeRebuilds() async throws {
        let scratch = try makeScratchDirectory()
        let testnetStore = try makeStore(in: scratch)
        let mainnetStore = try makeStore(in: scratch, scope: "mainnet")
        let trash = scratch.appendingPathComponent("trash", isDirectory: true)
        try SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", directory: directory)
        try SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "mainnet", directory: directory)
        var gate = SPVChainStoreRebuild.StoreClearGate()
        gate.recordFailedStop(scope: "testnet")

        let testnet = await rebuild(scope: "testnet", store: testnetStore, trash: trash, gate: gate)
        let mainnet = await rebuild(scope: "mainnet", store: mainnetStore, trash: trash, gate: gate)

        // Nothing applied on the failed-stop scope: the store is whole and
        // the start that follows consumes nothing.
        XCTAssertEqual(testnet, [])
        XCTAssertEqual(
            try Data(contentsOf: testnetStore.appendingPathComponent("headers/segment_0000.dat")),
            Data([1, 2, 3]))
        SPVChainStoreRebuild.finish(walletIds: testnet, scope: "testnet", directory: directory)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", directory: directory),
            [walletId(0xA1)])

        XCTAssertEqual(mainnet, [walletId(0xB2)])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: mainnetStore.path), [])
        SPVChainStoreRebuild.finish(walletIds: mainnet, scope: "mainnet", directory: directory)
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", directory: directory))
    }

    func testEmptyStoreCreatesAMissingStoreDirectory() throws {
        let scratch = try makeScratchDirectory()
        let store = scratch.appendingPathComponent("SPV/testnet", isDirectory: true)
        let trash = scratch.appendingPathComponent("trash", isDirectory: true)

        try SPVChainStoreRebuild.emptyStore(at: store, movingInto: trash)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.path), [])
    }
}
