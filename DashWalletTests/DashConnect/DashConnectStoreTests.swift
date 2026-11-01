import XCTest
@testable import dashpay

final class DashConnectStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DashConnectStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRoundTripPreservesConnections() {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let connections = [
            sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .approved, updatedAt: Date(timeIntervalSince1970: 10)),
            sampleConnection(id: "7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234", name: "DashGet", url: "dashget.app", status: .active, updatedAt: Date(timeIntervalSince1970: 20)),
            sampleConnection(id: "AaC695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNgA9Z", name: "PayKit", url: "paykit.dev", status: .approved, updatedAt: Date(timeIntervalSince1970: 30)),
        ]

        store.save(connections)

        XCTAssertEqual(store.load(), connections)
    }

    func testRoundTripKeepsWhichLoginMadeAConnection() {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        var oneQR = sampleConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .active,
            updatedAt: Date(timeIntervalSince1970: 10))
        oneQR.loginKind = .oneQR
        let twoQR = sampleConnection(
            id: "7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234", status: .active,
            updatedAt: Date(timeIntervalSince1970: 20))

        store.save([oneQR, twoQR])

        XCTAssertEqual(store.load().map(\.loginKind), [.oneQR, .twoQR])
    }

    func testUnknownStatusDropsOnlyThatRow() throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let payload: [[String: Any]] = [
            [
                "contractId": "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
                "label": "Yappr",
                "url": "yap.pr",
                "status": "approved",
                "updatedAt": 1_773_132_300_000
            ],
            [
                "contractId": "7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234",
                "label": "DashGet",
                "url": "dashget.app",
                "status": "mystery",
                "updatedAt": 1_773_218_700_000
            ],
        ]

        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: try XCTUnwrap(store.storageKey))

        XCTAssertEqual(
            store.load(),
            [sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .approved, updatedAt: Date(timeIntervalSince1970: 1_773_132_300))]
        )
    }

    func testMalformedRowIsDropped() throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let payload: [[String: Any]] = [
            [
                "contractId": "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
                "label": "Yappr",
                "url": "yap.pr",
                "status": "approved",
                "updatedAt": 1_773_132_300_000
            ],
            [
                "label": "Broken",
                "url": "broken.app",
                "status": "approved",
                "updatedAt": 1_773_132_300_000
            ],
        ]

        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: try XCTUnwrap(store.storageKey))

        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(store.load().first?.id, "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F")
    }

    func testLegacyDisconnectedStatusIsDropped() throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let payload: [[String: Any]] = [[
            "contractId": "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
            "label": "Yappr",
            "url": "yap.pr",
            "status": "disconnected",
            "updatedAt": 1_773_132_300_000
        ]]

        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: try XCTUnwrap(store.storageKey))

        XCTAssertEqual(store.load(), [])
    }

    func testEmptyStoreLoadsAsEmptyArray() {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        XCTAssertEqual(store.load(), [])
    }

    func testSavingEmptyArrayClearsStore() throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        store.save([sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .approved, updatedAt: Date(timeIntervalSince1970: 10))])

        store.save([])

        XCTAssertNil(defaults.data(forKey: try XCTUnwrap(store.storageKey)))
        XCTAssertEqual(store.load(), [])
    }

    func testNetworksAreIsolated() throws {
        let testnetStore = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let mainnetStore = makeStore(network: .mainnet, walletIdHex: "wallet-a")
        let testnetConnection = sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .approved, updatedAt: Date(timeIntervalSince1970: 10))
        let mainnetConnection = sampleConnection(id: "7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234", status: .active, updatedAt: Date(timeIntervalSince1970: 20))

        testnetStore.save([testnetConnection])
        mainnetStore.save([mainnetConnection])

        XCTAssertEqual(testnetStore.load(), [testnetConnection])
        XCTAssertEqual(mainnetStore.load(), [mainnetConnection])
        XCTAssertNotEqual(testnetStore.storageKey, mainnetStore.storageKey)
        XCTAssertTrue(try XCTUnwrap(testnetStore.storageKey).contains(".t."))
        XCTAssertTrue(try XCTUnwrap(mainnetStore.storageKey).contains(".m."))
    }

    func testWalletIdsAreIsolated() {
        let walletAStore = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let walletBStore = makeStore(network: .testnet, walletIdHex: "wallet-b")
        let walletAConnection = sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .approved, updatedAt: Date(timeIntervalSince1970: 10))

        walletAStore.save([walletAConnection])

        XCTAssertEqual(walletAStore.load(), [walletAConnection])
        XCTAssertEqual(walletBStore.load(), [])
        XCTAssertNotEqual(walletAStore.storageKey, walletBStore.storageKey)
    }

    func testApproveLoginPersistsAcrossFreshMockInstances() async throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let first = MockDashConnectDataSource(store: store)

        _ = try await first.approveLogin(
            MockDashConnectDataSource.sampleLoginRequest, consent: MockDashConnectDataSource.sampleRequest)

        let second = MockDashConnectDataSource(store: store)

        XCTAssertEqual(second.connectionsSnapshot.count, 1)
        XCTAssertEqual(second.connectionsSnapshot.first?.id, "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F")
        XCTAssertEqual(second.connectionsSnapshot.first?.status, .approved)
    }

    func testRemovePersistsAcrossFreshMockInstances() async throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let first = MockDashConnectDataSource(store: store)
        _ = try await first.approveLogin(
            MockDashConnectDataSource.sampleLoginRequest, consent: MockDashConnectDataSource.sampleRequest)

        await first.remove(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", scope: nil)

        let second = MockDashConnectDataSource(store: store)
        XCTAssertEqual(second.connectionsSnapshot, [])
    }

    func testDisconnectPersistsApprovedStatusAcrossFreshMockInstances() async throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let first = MockDashConnectDataSource(
            initial: [
                sampleConnection(
                    id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
                    status: .active,
                    updatedAt: Date(timeIntervalSince1970: 10)
                )
            ],
            store: store
        )

        try await first.disconnect(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", scope: nil)

        let second = MockDashConnectDataSource(store: store)
        XCTAssertEqual(second.connectionsSnapshot.count, 1)
        XCTAssertEqual(second.connectionsSnapshot.first?.id, "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F")
        XCTAssertEqual(second.connectionsSnapshot.first?.status, .approved)
    }

    func testMainnetAndTestnetKeysAreUnchanged() {
        XCTAssertEqual(makeStore(network: .testnet, walletIdHex: "wallet-a").storageKey,
                       "dashconnect.connections.v1.t.wallet-a")
        XCTAssertEqual(makeStore(network: .mainnet, walletIdHex: "wallet-a").storageKey,
                       "dashconnect.connections.v1.m.wallet-a")
    }

    func testEachConfiguredDevnetKeepsItsOwnConnections() {
        let devnetA = makeStore(network: .devnet, walletIdHex: "wallet-a", devnetName: "moutai")
        let devnetB = makeStore(network: .devnet, walletIdHex: "wallet-a", devnetName: "paloma")
        let connection = sampleConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
            status: .approved,
            updatedAt: Date(timeIntervalSince1970: 10))

        devnetA.save([connection])

        XCTAssertEqual(devnetA.load(), [connection])
        XCTAssertEqual(devnetB.load(), [])
        XCTAssertNotEqual(devnetA.storageKey, devnetB.storageKey)
    }

    func testAPinnedStoreStaysWithItsWalletAndDevnetWhenTheActiveOnesChange() {
        var walletIdHex: String? = "wallet-a"
        var devnetName: String? = "moutai"
        let store = UserDefaultsDashConnectStore(
            defaults: defaults,
            network: .devnet,
            walletIdHexProvider: { walletIdHex },
            devnetNameProvider: { devnetName }
        )
        let connection = sampleConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
            status: .active,
            updatedAt: Date(timeIntervalSince1970: 10))

        let pinned = store.pinnedStore(toWalletIdHex: "wallet-a")
        XCTAssertEqual(pinned.storageKey, store.storageKey)

        walletIdHex = "wallet-b"
        devnetName = "paloma"
        pinned.save([connection])

        XCTAssertNotEqual(pinned.storageKey, store.storageKey)
        XCTAssertEqual(pinned.load(), [connection])
        XCTAssertEqual(store.load(), [], "the wallet that became active got none of the rows")
        walletIdHex = "wallet-a"
        devnetName = "moutai"
        XCTAssertEqual(store.load(), [connection])
    }

    func testAPinnedStoreNamesTheWalletItWasGivenNotTheActiveOne() {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-b")

        XCTAssertEqual(store.pinnedStore(toWalletIdHex: "wallet-a").storageKey, "dashconnect.connections.v1.t.wallet-a")
    }

    func testUnnamedDevnetStoresNothing() {
        let store = makeStore(network: .devnet, walletIdHex: "wallet-a", devnetName: nil)
        store.save([sampleConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
            status: .approved,
            updatedAt: Date(timeIntervalSince1970: 10))])

        XCTAssertNil(store.storageKey)
        XCTAssertEqual(store.load(), [])
    }

    // MARK: Disconnected history

    private func historyEntry(_ id: String, at seconds: TimeInterval = 10) -> DisconnectedConnection {
        DisconnectedConnection(
            id: id, name: "Yappr", url: "yap.pr", identityId: "identity", username: "alice",
            disconnectedAt: Date(timeIntervalSince1970: seconds), access: nil)
    }

    func testHistoryKeepsOneEntryPerAppAndForgetsAnAppConnectedAgain() {
        let history = UserDefaultsDashConnectHistoryStore(
            defaults: defaults, scope: makeStore(network: .testnet, walletIdHex: "wallet-a"))
        history.record(historyEntry("app-1", at: 10))
        history.record(historyEntry("app-2", at: 20))
        history.record(historyEntry("app-1", at: 30))
        XCTAssertEqual(history.load()?.map(\.id).sorted(), ["app-1", "app-2"])
        XCTAssertEqual(history.load()?.first { $0.id == "app-1" }?.disconnectedAt, Date(timeIntervalSince1970: 30))

        history.remove(appId: "app-1")
        XCTAssertEqual(history.load()?.map(\.id), ["app-2"])
    }

    func testHistoryIsScopedLikeTheRows() {
        let walletA = UserDefaultsDashConnectHistoryStore(
            defaults: defaults, scope: makeStore(network: .testnet, walletIdHex: "wallet-a"))
        walletA.record(historyEntry("app-1"))
        let walletB = walletA.pinned(toWalletIdHex: "wallet-b")
        let otherNetwork = UserDefaultsDashConnectHistoryStore(
            defaults: defaults, scope: makeStore(network: .devnet, walletIdHex: "wallet-a"))
        XCTAssertEqual(walletB.load(), [])
        XCTAssertEqual(otherNetwork.load(), [])
        XCTAssertEqual(walletA.pinned(toWalletIdHex: "wallet-a").load()?.map(\.id), ["app-1"])
        // The rows of the same wallet are not touched.
        XCTAssertEqual(makeStore(network: .testnet, walletIdHex: "wallet-a").load(), [])
    }

    func testUnreadableHistoryIsUnknownAndNotOverwritten() throws {
        let scope = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let history = UserDefaultsDashConnectHistoryStore(defaults: defaults, scope: scope)
        let key = try XCTUnwrap(scope.scopedKey(prefix: "dashconnect.history.v1"))
        defaults.set(Data("not json".utf8), forKey: key)
        XCTAssertNil(history.load())
        XCTAssertFalse(history.record(historyEntry("app-1")), "the caller is told nothing was recorded")
        XCTAssertEqual(defaults.data(forKey: key), Data("not json".utf8), "what cannot be read is not written over")
    }

    func testAHistoryEntryThisBuildCannotReadLeavesTheOthers() throws {
        let scope = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let history = UserDefaultsDashConnectHistoryStore(defaults: defaults, scope: scope)
        history.record(historyEntry("app-1"))
        let key = try XCTUnwrap(scope.scopedKey(prefix: "dashconnect.history.v1"))
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(defaults.data(forKey: key))) as? [Any])
        rows.append(["id": "app-2", "name": 7])
        defaults.set(try JSONSerialization.data(withJSONObject: rows), forKey: key)
        XCTAssertEqual(history.load()?.map(\.id), ["app-1"])

        history.record(historyEntry("app-3"))
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(defaults.data(forKey: key))) as? [Any])
        XCTAssertEqual(written.count, 3, "the entry this build cannot read is written back")
        XCTAssertEqual(history.load()?.map(\.id).sorted(), ["app-1", "app-3"])
    }

    func testOneHistoryEntryPerAppTheLatest() throws {
        let scope = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let history = UserDefaultsDashConnectHistoryStore(defaults: defaults, scope: scope)
        let key = try XCTUnwrap(scope.scopedKey(prefix: "dashconnect.history.v1"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let rows = try [historyEntry("app-1", at: 10), historyEntry("app-1", at: 30), historyEntry("app-2", at: 20)]
            .map { try JSONSerialization.jsonObject(with: encoder.encode($0)) }
        defaults.set(try JSONSerialization.data(withJSONObject: rows), forKey: key)
        let loaded = try XCTUnwrap(history.load())
        XCTAssertEqual(loaded.map(\.id).sorted(), ["app-1", "app-2"])
        XCTAssertEqual(loaded.first { $0.id == "app-1" }?.disconnectedAt, Date(timeIntervalSince1970: 30))
    }

    func testRecordingAnAppReplacesItsEntryThisBuildCannotRead() throws {
        let scope = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let history = UserDefaultsDashConnectHistoryStore(defaults: defaults, scope: scope)
        let key = try XCTUnwrap(scope.scopedKey(prefix: "dashconnect.history.v1"))
        defaults.set(try JSONSerialization.data(withJSONObject: [["id": "app-1", "name": 7], ["id": "app-2", "name": 7]]),
                     forKey: key)
        history.record(historyEntry("app-1"))
        var written = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(defaults.data(forKey: key))) as? [Any])
        XCTAssertEqual(written.count, 2, "app-1's unreadable entry is replaced, app-2's is kept")
        history.remove(appId: "app-2")
        written = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(defaults.data(forKey: key))) as? [Any])
        XCTAssertEqual(written.count, 1, "a removed app's unreadable entry goes too")
    }

    func testDeletingAWalletClearsItsHistoryOnEveryNetwork() {
        let testnet = UserDefaultsDashConnectHistoryStore(
            defaults: defaults, scope: makeStore(network: .testnet, walletIdHex: "abcd"))
        let devnet = UserDefaultsDashConnectHistoryStore(
            defaults: defaults, scope: makeStore(network: .devnet, walletIdHex: "abcd"))
        let other = UserDefaultsDashConnectHistoryStore(
            defaults: defaults, scope: makeStore(network: .testnet, walletIdHex: "ef01"))
        testnet.record(historyEntry("app-1"))
        devnet.record(historyEntry("app-1"))
        other.record(historyEntry("app-1"))
        UserDefaultsDashConnectHistoryStore.clear(walletIdHex: "abcd", defaults: defaults)
        XCTAssertEqual(testnet.load(), [])
        XCTAssertEqual(devnet.load(), [])
        XCTAssertEqual(other.load()?.map(\.id), ["app-1"], "another wallet's history stays")
    }

    func testNoWalletMeansNoHistory() {
        let history = UserDefaultsDashConnectHistoryStore(
            defaults: defaults, scope: makeStore(network: .testnet, walletIdHex: nil))
        history.record(historyEntry("app-1"))
        XCTAssertEqual(history.load(), [])
    }

    private func makeStore(
        network: DashConnectNetwork,
        walletIdHex: String?,
        devnetName: String? = "moutai"
    ) -> UserDefaultsDashConnectStore {
        UserDefaultsDashConnectStore(
            defaults: defaults,
            network: network,
            walletIdHexProvider: { walletIdHex },
            devnetNameProvider: { devnetName }
        )
    }

    private func sampleConnection(
        id: String,
        name: String = "Yappr",
        url: String = "yap.pr",
        status: ConnectionStatus,
        updatedAt: Date
    ) -> DAppConnection {
        DAppConnection(id: id, name: name, url: url, status: status, updatedAt: updatedAt)
    }
}
