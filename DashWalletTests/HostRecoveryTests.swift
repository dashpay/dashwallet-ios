//
//  HostRecoveryTests.swift
//  DashWalletTests
//
//  `SwiftDashSDKHost`'s stage-4/4 restore flow and reset preflight over
//  in-memory collaborators: the wallet rows, the keychain material, the
//  active-wallet registry and the CoinJoin flag are stand-ins; the control
//  flow, the on-disk recovery marker and reset intent, and the failure
//  classification are production.
//

import XCTest
import SwiftDashSDK
@testable import dashpay

/// A wallet row of the in-memory store.
struct TestWalletRow: SwiftDashSDKWalletRow, Equatable {
    let walletId: Data
}

/// The rows every "launch" reads and writes: shared between the stores of
/// successive hosts, as the SwiftData store is between launches.
@MainActor
final class PersistedWalletRows {
    var rows: [Data: TestWalletRow] = [:]
    /// One wallet creation the store refuses, like a failed SwiftData write.
    var failingMnemonic: String?
    var createAttempts: [String] = []
    var shutdowns = 0
}

@MainActor
final class InMemoryWalletRowStore: SwiftDashSDKWalletRowStore {
    private let persisted: PersistedWalletRows
    private(set) var wallets: [Data: TestWalletRow] = [:]

    init(persisted: PersistedWalletRows) {
        self.persisted = persisted
    }

    var firstWallet: TestWalletRow? {
        wallets.min { $0.key.lexicographicallyPrecedes($1.key) }?.value
    }

    func loadFromPersistor() async throws -> [TestWalletRow] {
        wallets = persisted.rows
        return Array(wallets.values)
    }

    func createWallet(
        mnemonic: String, network: Network, name: String?, createDefaultAccounts: Bool, birthHeight: UInt32?
    ) throws -> TestWalletRow {
        persisted.createAttempts.append(mnemonic)
        if mnemonic == persisted.failingMnemonic { throw NSError(domain: "InjectedWrite", code: 1) }
        let wallet = TestWalletRow(walletId: Data(mnemonic.utf8))
        wallets[wallet.walletId] = wallet
        persisted.rows[wallet.walletId] = wallet
        return wallet
    }

    func deleteWallet(walletId: Data) throws {
        wallets[walletId] = nil
        persisted.rows[walletId] = nil
    }

    @discardableResult
    func shutdown() async -> PlatformWalletShutdownMetrics {
        persisted.shutdowns += 1
        return PlatformWalletShutdownMetrics(steps: [], totalMilliseconds: 0, ranOffMainThread: true)
    }
}

/// Keychain material whose reads can be scripted to fail or to carry
/// malformed entries. Flags are set on the test's actor before the read.
final class ScriptedWalletMaterial: SwiftDashSDKWalletMaterialReading, @unchecked Sendable {
    var unreadableKeychain = false
    var invalidMaterial = false
    var nulMaterial = false

    func strictlyPersistedMnemonics() throws -> [(walletId: Data, mnemonic: String)] {
        if unreadableKeychain { throw WalletStorageError.keychainError(-25291) } // errSecNotAvailable
        if nulMaterial { return [(walletId: Data("wallet-a".utf8), mnemonic: "wallet-a\u{0}trailing bytes")] }
        return ["wallet-a", "wallet-b"].map { (walletId: Data($0.utf8), mnemonic: $0) }
    }

    func persistedSDKWalletNetworks(in entries: [(walletId: Data, mnemonic: String)]) throws -> Set<Network> {
        // Production resolves ids through SwiftDashSDKStoredWalletNetworkResolver,
        // whose refusal is this error.
        if invalidMaterial { throw SwiftDashSDKWalletDeletionError.unrecognizedWalletNetwork }
        return [.mainnet]
    }

    func recoverablePersistedMnemonics(
        _ entries: [(walletId: Data, mnemonic: String)], for network: Network
    ) -> [(walletId: Data, mnemonic: String)] {
        entries
    }
}

@MainActor
final class InMemoryActiveWalletRegistry: SwiftDashSDKActiveWalletRegistry {
    var active: [WalletEnvironment.NetworkKind: Data] = [:]

    func activeWalletId(for network: WalletEnvironment.NetworkKind) -> Data? { active[network] }

    func setActiveWalletId(_ id: Data?, for network: WalletEnvironment.NetworkKind) { active[network] = id }
}

@MainActor
final class RecordingCoinJoinRecovery: CoinJoinRecoveryFlagResetting {
    /// Scopes whose wide-scan flag the host re-armed, in order.
    var resetScopes: [String] = []

    func resetRecoveryFlag(scope: String) { resetScopes.append(scope) }
}

@MainActor
final class RecordingRestoreSyncGate: InitialRestoreSyncGating {
    /// The scopes the host armed the initial-restore-sync gate for, in order.
    var armedScopes: [String] = []

    func armInitialRestoreSyncGate(scope: String) { armedScopes.append(scope) }
}

@MainActor
final class HostRecoveryTests: XCTestCase {
    private var directory: URL!
    private var roots: WalletLocalStoreRoots!
    private var persisted: PersistedWalletRows!
    private var material: ScriptedWalletMaterial!
    private var registry: InMemoryActiveWalletRegistry!
    private var coinJoin: RecordingCoinJoinRecovery!
    private var restoreSyncGate: RecordingRestoreSyncGate!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        roots = WalletLocalStoreRoots(documents: directory)
        // The recovery marker sits beside the store, in a directory the
        // runtime build creates before the restore.
        try FileManager.default.createDirectory(
            at: roots.platform.appendingPathComponent("mainnet", isDirectory: true),
            withIntermediateDirectories: true)
        persisted = PersistedWalletRows()
        material = ScriptedWalletMaterial()
        registry = InMemoryActiveWalletRegistry()
        coinJoin = RecordingCoinJoinRecovery()
        restoreSyncGate = RecordingRestoreSyncGate()
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// A host over the test collaborators: a fresh one per launch.
    private func makeHost() -> SwiftDashSDKHost {
        let roots = roots!
        return SwiftDashSDKHost(collaborators: .init(
            material: material,
            registry: registry,
            coinJoinRecovery: coinJoin,
            restoreSyncGate: restoreSyncGate,
            localStoreRoots: { roots }))
    }

    /// One launch: `host` (or a fresh one) restores through a fresh store
    /// over the persisted rows, with no devnet provisioning.
    private func start(_ host: SwiftDashSDKHost? = nil) async throws -> TestWalletRow {
        try await (host ?? makeHost()).restoreWallet(
            in: InMemoryWalletRowStore(persisted: persisted), network: .mainnet) { nil }
    }

    private func localStoreRecovery() -> WalletLocalStoreRecovery {
        WalletLocalStoreRecovery(directory: roots.platform.appendingPathComponent("mainnet", isDirectory: true))
    }

    private func resetIntent() -> WalletLocalStoreResetIntent {
        WalletLocalStoreResetIntent(directory: roots.resetIntents)
    }

    func testRecreatingWalletRowsReArmsTheWideCoinJoinScanForTheNetwork() async throws {
        // An empty store, however it came to be empty (interrupted reset, a
        // flag write that never reached disk, a reinstall), recreates rows
        // from the keychain and must re-arm the one-time wide scan.
        _ = try await start()
        XCTAssertEqual(coinJoin.resetScopes, ["mainnet"])
        // A resumed partial recovery passes through the same branch.
        persisted.rows = [:]
        persisted.failingMnemonic = "wallet-b"
        do { _ = try await start() } catch {}
        persisted.failingMnemonic = nil
        _ = try await start()
        XCTAssertEqual(coinJoin.resetScopes, ["mainnet", "mainnet", "mainnet"])
    }

    func testPendingResetIntentReconcilesKeychainAgainstSurvivingRows() async throws {
        // A WAL-only interruption: wallet A survives in the main database,
        // wallet B's rows were lost with the WAL, no recovery marker exists.
        let a = Data("wallet-a".utf8)
        persisted.rows[a] = TestWalletRow(walletId: a)
        registry.active[.mainnet] = Data("wallet-b".utf8)
        let host = makeHost()
        try resetIntent().record(scopes: ["mainnet"])

        let resolved = try await start(host)

        XCTAssertEqual(persisted.createAttempts, ["wallet-b"], "Only the missing wallet is recreated")
        XCTAssertEqual(persisted.rows.count, 2)
        XCTAssertEqual(resolved.walletId, Data("wallet-b".utf8), "The active wallet is not replaced by the survivor")
        XCTAssertFalse(try localStoreRecovery().isPending())
        XCTAssertTrue(resetIntent().isPending(scope: "mainnet"), "The intent outlives the start, until the scan completes")
        XCTAssertEqual(coinJoin.resetScopes, ["mainnet"])
        // A later start with every wallet present changes nothing.
        persisted.createAttempts = []
        _ = try await start()
        XCTAssertTrue(persisted.createAttempts.isEmpty)
    }

    func testHealthyStoreKeepsTheCompletedWideScanFlag() async throws {
        let id = Data("wallet-a".utf8)
        persisted.rows[id] = TestWalletRow(walletId: id)
        _ = try await start()
        XCTAssertEqual(coinJoin.resetScopes, [])
    }

    // MARK: - Initial restore sync gate (ios#1227)

    func testRecreatingWalletRowsArmsTheInitialRestoreSyncGate() async throws {
        // Rows recreated from the keychain scan from the import floor, so
        // Core spends must stay blocked until that historical scan is done,
        // exactly as after a phrase restore.
        _ = try await start()
        XCTAssertEqual(restoreSyncGate.armedScopes, ["mainnet"])
    }

    func testHealthyStoreDoesNotArmTheInitialRestoreSyncGate() async throws {
        // A normal launch over persisted rows is a foreground catch-up and
        // must not delay a payment.
        for mnemonic in ["wallet-a", "wallet-b"] {
            let id = Data(mnemonic.utf8)
            persisted.rows[id] = TestWalletRow(walletId: id)
        }
        _ = try await start()
        XCTAssertEqual(restoreSyncGate.armedScopes, [])
    }

    func testFailedRecoveryDoesNotArmTheGateUntilAWalletOpens() async throws {
        persisted.failingMnemonic = "wallet-b"
        do {
            _ = try await start()
            XCTFail("One restored wallet must not mask another's failure")
        } catch {}
        XCTAssertEqual(restoreSyncGate.armedScopes, [])
        persisted.failingMnemonic = nil
        _ = try await start()
        XCTAssertEqual(restoreSyncGate.armedScopes, ["mainnet"])
    }

    private func pendingChainStoreRebuilds() -> [Data]? {
        SPVChainStoreRebuild.pendingWalletIds(scope: "mainnet", directory: roots.chainStoreRebuilds)
    }

    func testRecreatedWalletsArmTheChainStoreRebuildAndAFailedCreateKeepsIt() async throws {
        // Wallet B's create throws; the SDK may have landed its rows first,
        // so its marker stays with wallet A's.
        persisted.failingMnemonic = "wallet-b"
        do { _ = try await start() } catch {}
        XCTAssertEqual(pendingChainStoreRebuilds(), [Data("wallet-a".utf8), Data("wallet-b".utf8)])
    }

    func testSurvivingWalletIsNotArmedByARecoveryOfAnother() async throws {
        let a = Data("wallet-a".utf8)
        persisted.rows[a] = TestWalletRow(walletId: a)
        try resetIntent().record(scopes: ["mainnet"])
        _ = try await start()
        XCTAssertEqual(pendingChainStoreRebuilds(), [Data("wallet-b".utf8)])
    }

    func testRecoveryStillOpensTheWalletWhenTheMarkerCannotBeWritten() async throws {
        // A file where the marker directory should be.
        try FileManager.default.createDirectory(
            at: roots.chainStoreRebuilds.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: roots.chainStoreRebuilds)
        let resolved = try await start()
        XCTAssertEqual(persisted.createAttempts, ["wallet-a", "wallet-b"])
        XCTAssertEqual(persisted.rows.count, 2)
        XCTAssertNotNil(persisted.rows[resolved.walletId])
        XCTAssertFalse(try localStoreRecovery().isPending())
        XCTAssertNil(pendingChainStoreRebuilds())
    }

    func testHealthyStoreArmsNoChainStoreRebuild() async throws {
        for name in ["wallet-a", "wallet-b"] {
            let id = Data(name.utf8)
            persisted.rows[id] = TestWalletRow(walletId: id)
        }
        _ = try await start()
        XCTAssertNil(pendingChainStoreRebuilds())
    }

    func testPartialRecoveryFailsThenNextLaunchCreatesOnlyMissingWallet() async throws {
        persisted.failingMnemonic = "wallet-b"
        let first = makeHost()
        do {
            _ = try await start(first)
            XCTFail("One restored wallet must not mask another's failure")
        } catch {}
        XCTAssertNil(first.wallet)
        XCTAssertEqual(persisted.rows.count, 1)
        XCTAssertEqual(persisted.shutdowns, 1)
        XCTAssertTrue(try localStoreRecovery().isPending())
        persisted.failingMnemonic = nil
        let nextLaunch = makeHost()
        _ = try await start(nextLaunch)
        XCTAssertEqual(persisted.rows.count, 2)
        XCTAssertEqual(persisted.createAttempts, ["wallet-a", "wallet-b", "wallet-b"])
        XCTAssertFalse(try localStoreRecovery().isPending())
    }

    func testUnreadableKeychainKeepsRecoveryPendingAndRetriesLater() async throws {
        material.unreadableKeychain = true
        let first = makeHost()
        do { _ = try await start(first); XCTFail("Expected strict read failure") } catch {}
        XCTAssertTrue(try localStoreRecovery().isPending())
        XCTAssertTrue(persisted.createAttempts.isEmpty)
        material.unreadableKeychain = false
        _ = try await start()
        XCTAssertEqual(persisted.rows.count, 2)
    }

    func testCrashAfterAllRowsBeforeMarkerRemovalDoesNotRecreateWallets() async throws {
        for name in ["wallet-a", "wallet-b"] {
            let id = Data(name.utf8)
            persisted.rows[id] = TestWalletRow(walletId: id)
        }
        let host = makeHost()
        try localStoreRecovery().begin()
        _ = try await start(host)
        XCTAssertTrue(persisted.createAttempts.isEmpty)
        XCTAssertFalse(try localStoreRecovery().isPending())
    }

    func testHealthyStoreDoesNotRequireReadingEveryMnemonic() async throws {
        let id = Data("wallet-a".utf8)
        persisted.rows[id] = TestWalletRow(walletId: id)
        material.unreadableKeychain = true
        _ = try await start()
        XCTAssertTrue(persisted.createAttempts.isEmpty)
    }

    /// `XCTAssertThrowsError` has no async form.
    private func preflightError(_ host: SwiftDashSDKHost) async -> Error? {
        do { try await host.validateLocalStoreReset(); return nil } catch { return error }
    }

    func testResetPreflightRejectsUnreadableOrMalformedRecoveryMaterial() async throws {
        material.unreadableKeychain = true
        let unreadable = await preflightError(makeHost())
        XCTAssertNotNil(unreadable)
        material.unreadableKeychain = false
        material.invalidMaterial = true
        let malformed = await preflightError(makeHost())
        XCTAssertNotNil(malformed)
        material.invalidMaterial = false
        // A valid phrase followed by an embedded NUL passes C-string validation
        // and id derivation but can never sign; it must not authorize deletion.
        material.nulMaterial = true
        let nul = await preflightError(makeHost())
        guard case SwiftDashSDKHost.HostError.invalidMnemonic? = nul else {
            return XCTFail("Expected invalidMnemonic, got \(String(describing: nul))")
        }
    }

    /// The card record the runtime shows for a failed start, or nil when the
    /// start succeeded or the error keeps its existing flow.
    private func startFailure() async -> WalletPreparationFailure? {
        do { _ = try await start(); return nil } catch {
            return SwiftDashSDKHost.preparationFailure(forStartError: error)
        }
    }

    func testUnreadableKeychainShowsTheKeysCardWithItsStatus() async throws {
        material.unreadableKeychain = true
        let failure = await startFailure()
        XCTAssertEqual(failure?.kind, .keychain)
        XCTAssertEqual(failure?.codes, ["Keychain:unreadable", "OSStatus:-25291"])
        XCTAssertEqual(failure?.canResetLocalData, false)
    }

    func testEveryKeychainStatusShowsTheKeysCardAndLeavesAutomaticPreparationOn() {
        // Transient statuses (the lock, securityd) are not told apart here;
        // the keys card leaves the automatic kicks on instead.
        typealias HostError = SwiftDashSDKHost.HostError
        for status: OSStatus in [-25308, -25291, -34018] {
            let failure = SwiftDashSDKHost.preparationFailure(
                forStartError: HostError.walletBootstrapFailed(WalletStorageError.keychainError(status)))
            XCTAssertEqual(failure?.codes, ["Keychain:unreadable", "OSStatus:\(status)"])
            let state = WalletLifecycleTransitionState()
            state.fail(.failedWalletOpen(failure!))
            XCTAssertTrue(state.allowsAutomaticWalletPreparation)
        }
        let store = WalletLifecycleTransitionState()
        store.fail(.failedWalletOpen(WalletPreparationFailure(error: NSError(domain: "SwiftData.SwiftDataError", code: 1))))
        XCTAssertFalse(store.allowsAutomaticWalletPreparation)
    }

    func testUnclassifiableMaterialShowsTheKeysCard() async throws {
        material.invalidMaterial = true
        let failure = await startFailure()
        XCTAssertEqual(failure?.kind, .keychain)
        XCTAssertEqual(failure?.codes, ["Keychain:unclassifiable"])
    }

    func testStoreWriteFailureWhileReplayingTheKeychainKeepsTheDatabaseCard() async throws {
        persisted.failingMnemonic = "wallet-a"
        let failure = await startFailure()
        XCTAssertEqual(failure?.kind, .database)
        XCTAssertEqual(failure?.codes, ["OtherError:1"])
        XCTAssertEqual(failure?.canResetLocalData, false)
    }

    func testOnlyKnownKeysCausesClassifyAsKeys() {
        typealias HostError = SwiftDashSDKHost.HostError
        let swiftData = NSError(domain: "SwiftData.SwiftDataError", code: 1)
        let store = SwiftDashSDKHost.preparationFailure(forStartError: HostError.modelContainerFailed(swiftData))
        XCTAssertEqual(store?.kind, .database)
        XCTAssertEqual(store?.canResetLocalData, true)
        // Keys readable, nothing eligible for the network: no card, the
        // existing flow (hasWallet routes that inventory to setup) stays.
        XCTAssertNil(SwiftDashSDKHost.preparationFailure(
            forStartError: HostError.walletBootstrapFailed(HostError.walletNotFound(.mainnet))))
        let mismatch = SwiftDashSDKHost.preparationFailure(
            forStartError: HostError.walletBootstrapFailed(HostError.mnemonicRoundTripMismatch))
        XCTAssertEqual(mismatch?.codes, ["Keychain:idMismatch"])
        let missing = SwiftDashSDKHost.preparationFailure(
            forStartError: HostError.walletBootstrapFailed(WalletStorageError.mnemonicNotFound))
        XCTAssertEqual(missing?.codes, ["Keychain:notFound"])
        let resolver = SwiftDashSDKHost.preparationFailure(
            forStartError: HostError.walletBootstrapFailed(SwiftDashSDKWalletDeletionError.unrecognizedWalletNetwork))
        XCTAssertEqual(resolver?.codes, ["Keychain:unclassifiable"])
        // The resolver constructs a wallet from the stored phrase; its refusal
        // of material that passed word validation is a keys failure too.
        for material in [KeyWalletError.invalidMnemonic("bad"), .invalidInput("bad")] {
            let construction = SwiftDashSDKHost.preparationFailure(
                forStartError: HostError.walletBootstrapFailed(material))
            XCTAssertEqual(construction?.codes, ["Keychain:unclassifiable"])
        }
        // Its other cases say nothing about the stored material.
        XCTAssertEqual(SwiftDashSDKHost.preparationFailure(
            forStartError: HostError.walletBootstrapFailed(KeyWalletError.invalidState("ffi")))?.kind, .database)
        XCTAssertNil(SwiftDashSDKHost.preparationFailure(forStartError: HostError.sdkInitFailed(swiftData)))
        XCTAssertNil(SwiftDashSDKHost.keysFailure(in: swiftData))
    }
}
