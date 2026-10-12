import XCTest
#if canImport(dashpay)
@testable import dashpay
#elseif canImport(dashwallet)
@testable import dashwallet
#else
@testable import WalletPreparationHarness
#endif

final class SPVChainStoreRebuildTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "SPVChainStoreRebuildTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func walletId(_ byte: UInt8) -> Data {
        Data(repeating: byte, count: 32)
    }

    func testNothingIsPendingUntilAnImportArmsIt() {
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults))
    }

    func testImportArmsOnlyItsOwnScope() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", defaults: defaults))
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "testnet-sakura", defaults: defaults))
    }

    func testSecondImportJoinsThePendingRebuildAndARepeatAddsNothing() {
        XCTAssertTrue(SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", defaults: defaults))
        XCTAssertTrue(SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "mainnet", defaults: defaults))
        XCTAssertFalse(SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", defaults: defaults))

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", defaults: defaults),
            [walletId(0xA1), walletId(0xB2)])
    }

    func testFinishDropsOnlyTheRebuiltWalletsAndKeepsOnesArmedMeanwhile() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", defaults: defaults)
        SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "mainnet", defaults: defaults)

        SPVChainStoreRebuild.finish(walletIds: [walletId(0xA1)], scope: "mainnet", defaults: defaults)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", defaults: defaults),
            [walletId(0xB2)])

        SPVChainStoreRebuild.finish(walletIds: [walletId(0xB2)], scope: "mainnet", defaults: defaults)
        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", defaults: defaults))
    }

    func testFinishOfAWalletThatIsNotPendingChangesNothing() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)

        SPVChainStoreRebuild.finish(walletIds: [walletId(0xEE)], scope: "testnet", defaults: defaults)
        SPVChainStoreRebuild.finish(walletIds: [walletId(0xA1)], scope: "mainnet", defaults: defaults)

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
    }

    func testClearFinishesOneScopeAndLeavesTheOther() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "mainnet", defaults: defaults)
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)

        SPVChainStoreRebuild.clear(scope: "mainnet", defaults: defaults)

        XCTAssertNil(SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", defaults: defaults))
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
    }

    func testPendingRebuildSurvivesANewDefaultsInstance() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xC3), scope: "testnet", defaults: defaults)

        let reopened = UserDefaults(suiteName: suiteName)!
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: reopened),
            [walletId(0xC3)])
    }

    // MARK: - Applying a pending rebuild

    @MainActor
    func testApplyRewindsThenClearsAndReturnsOnlyLoadedWallets() async {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)
        SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "testnet", defaults: defaults)
        var steps: [String] = []

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            defaults: defaults,
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
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1), walletId(0xB2)])
        SPVChainStoreRebuild.finish(walletIds: applied, scope: "testnet", defaults: defaults)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xB2)])
    }

    @MainActor
    func testApplyTouchesNothingWhenNoPendingWalletIsLoaded() async {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)
        var steps: [String] = []

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            defaults: defaults,
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
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
    }

    @MainActor
    func testApplyDoesNothingWhenNothingIsPending() async {
        var steps: [String] = []

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            defaults: defaults,
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
    func testFailedRewindLeavesTheStoreAndTheMarker() async {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)
        var cleared = false

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            defaults: defaults,
            isLoaded: { _ in true },
            rewind: { _ in false },
            clearStore: {
                cleared = true
                return true
            })

        XCTAssertEqual(applied, [])
        XCTAssertFalse(cleared)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
    }

    @MainActor
    func testOneFailedRewindDoesNotHoldBackTheOtherWallets() async {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)
        SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "testnet", defaults: defaults)
        var cleared = false

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            defaults: defaults,
            isLoaded: { _ in true },
            rewind: { $0 == self.walletId(0xB2) },
            clearStore: {
                cleared = true
                return true
            })

        XCTAssertEqual(applied, [walletId(0xB2)])
        XCTAssertTrue(cleared)
        SPVChainStoreRebuild.finish(walletIds: applied, scope: "testnet", defaults: defaults)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
    }

    @MainActor
    func testRefusedClearKeepsTheMarkerForTheNextStart() async {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)

        let applied = await SPVChainStoreRebuild.apply(
            scope: "testnet",
            defaults: defaults,
            isLoaded: { _ in true },
            rewind: { _ in true },
            clearStore: { false })

        XCTAssertEqual(applied, [])
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
    }

    // MARK: - Consuming the marker and lowering checkpoints

    private struct Failure: Error {}

    private final class Row {
        var syncedHeight: UInt32
        init(_ syncedHeight: UInt32) { self.syncedHeight = syncedHeight }
    }

    func testAFailedStartKeepsTheAppliedWalletsPending() {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)

        XCTAssertThrowsError(try SPVChainStoreRebuild.finish(
            walletIds: [walletId(0xA1)], scope: "testnet", defaults: defaults,
            afterStarting: { throw Failure() }))

        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xA1)])
    }

    func testASuccessfulStartConsumesOnlyTheAppliedWallets() throws {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)
        SPVChainStoreRebuild.arm(walletId: walletId(0xB2), scope: "testnet", defaults: defaults)
        var pendingDuringStart: [Data]?

        try SPVChainStoreRebuild.finish(
            walletIds: [walletId(0xA1)], scope: "testnet", defaults: defaults,
            afterStarting: {
                pendingDuringStart = SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: self.defaults)
            })

        XCTAssertEqual(pendingDuringStart, [walletId(0xA1), walletId(0xB2)])
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
            [walletId(0xB2)])
    }

    func testAStartWithNothingAppliedLeavesTheMarkerAlone() throws {
        SPVChainStoreRebuild.arm(walletId: walletId(0xA1), scope: "testnet", defaults: defaults)
        var started = false

        try SPVChainStoreRebuild.finish(
            walletIds: [], scope: "testnet", defaults: defaults, afterStarting: { started = true })

        XCTAssertTrue(started)
        XCTAssertEqual(
            SPVChainStoreRebuild.pendingWalletIds(scope: "testnet", defaults: defaults),
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

    private func makeStore(in scratch: URL) throws -> URL {
        let store = scratch.appendingPathComponent("SPV/testnet", isDirectory: true)
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

    func testEmptyStoreCreatesAMissingStoreDirectory() throws {
        let scratch = try makeScratchDirectory()
        let store = scratch.appendingPathComponent("SPV/testnet", isDirectory: true)
        let trash = scratch.appendingPathComponent("trash", isDirectory: true)

        try SPVChainStoreRebuild.emptyStore(at: store, movingInto: trash)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.path), [])
    }
}
