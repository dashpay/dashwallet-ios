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

        _ = try await first.approveLogin(MockDashConnectDataSource.sampleLoginRequest)

        let second = MockDashConnectDataSource(store: store)

        XCTAssertEqual(second.connectionsSnapshot.count, 1)
        XCTAssertEqual(second.connectionsSnapshot.first?.id, "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F")
        XCTAssertEqual(second.connectionsSnapshot.first?.status, .approved)
    }

    func testRemovePersistsAcrossFreshMockInstances() async throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let first = MockDashConnectDataSource(store: store)
        _ = try await first.approveLogin(MockDashConnectDataSource.sampleLoginRequest)

        await first.remove(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F")

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

        await first.disconnect(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F")

        let second = MockDashConnectDataSource(store: store)
        XCTAssertEqual(second.connectionsSnapshot.count, 1)
        XCTAssertEqual(second.connectionsSnapshot.first?.id, "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F")
        XCTAssertEqual(second.connectionsSnapshot.first?.status, .approved)
    }

    private func makeStore(network: DashConnectNetwork, walletIdHex: String?) -> UserDefaultsDashConnectStore {
        UserDefaultsDashConnectStore(
            defaults: defaults,
            network: network,
            walletIdHexProvider: { walletIdHex }
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
