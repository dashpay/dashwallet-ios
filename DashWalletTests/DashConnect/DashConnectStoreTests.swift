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
            sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .confirming, updatedAt: Date(timeIntervalSince1970: 10)),
            sampleConnection(id: "7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234", name: "DashGet", url: "dashget.app", status: .active, updatedAt: Date(timeIntervalSince1970: 20)),
            sampleConnection(id: "AaC695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNgA9Z", name: "PayKit", url: "paykit.dev", status: .confirming, updatedAt: Date(timeIntervalSince1970: 30)),
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
                "status": "confirming",
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
            [sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .confirming, updatedAt: Date(timeIntervalSince1970: 1_773_132_300))]
        )
    }

    func testWhereAccessWasSeenRoundTripsAndAnOlderRowReadsWithNone() throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let row = DAppConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", name: "Yappr", url: "yap.pr", status: .active,
            updatedAt: Date(timeIntervalSince1970: 10), seenOn: ["identity-a"])
        store.save([row])
        XCTAssertEqual(store.load().first?.seenOn, ["identity-a"])

        let older: [[String: Any]] = [
            ["contractId": "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", "label": "Yappr", "url": "yap.pr",
             "status": "active", "updatedAt": 1_773_132_300_000],
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: older), forKey: try XCTUnwrap(store.storageKey))
        XCTAssertEqual(store.load().map(\.seenOn), [[]])
    }

    func testARowOfTheRemovedApprovedStatusIsDroppedAndTheOthersKept() throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let payload: [[String: Any]] = [
            ["contractId": "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", "label": "Yappr", "url": "yap.pr",
             "status": "approved", "updatedAt": 1_773_132_300_000],
            ["contractId": "7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234", "label": "DashGet", "url": "dashget.app",
             "status": "active", "updatedAt": 1_773_218_700_000],
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: try XCTUnwrap(store.storageKey))

        XCTAssertEqual(store.load().map(\.id), ["7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234"])
    }

    func testMalformedRowIsDropped() throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let payload: [[String: Any]] = [
            [
                "contractId": "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
                "label": "Yappr",
                "url": "yap.pr",
                "status": "confirming",
                "updatedAt": 1_773_132_300_000
            ],
            [
                "label": "Broken",
                "url": "broken.app",
                "status": "confirming",
                "updatedAt": 1_773_132_300_000
            ],
        ]

        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: try XCTUnwrap(store.storageKey))

        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(store.load().first?.id, "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F")
    }

    func testARowWithEachNewStatusRoundTrips() {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let connections = [
            sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .refused, updatedAt: Date(timeIntervalSince1970: 10)),
            sampleConnection(id: "7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234", status: .expired, updatedAt: Date(timeIntervalSince1970: 20)),
            sampleConnection(id: "AaC695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNgA9Z", status: .disconnected, updatedAt: Date(timeIntervalSince1970: 30)),
        ]

        store.save(connections)

        XCTAssertEqual(store.load(), connections)
        XCTAssertEqual(store.load().map(\.status), [.refused, .expired, .disconnected])
    }

    func testStoredRowsOfTheNewStatusesDecodeFromTheirRawValues() throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let ids = [
            "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", "7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234",
            "AaC695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNgA9Z",
        ]
        let payload: [[String: Any]] = zip(ids, ["refused", "expired", "disconnected"]).map { id, status in
            ["contractId": id, "label": "App", "url": "app.example.test", "status": status,
             "updatedAt": 1_773_132_300_000]
        }
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: try XCTUnwrap(store.storageKey))

        XCTAssertEqual(store.load().map(\.status), [.refused, .expired, .disconnected])
    }

    func testEmptyStoreLoadsAsEmptyArray() {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        XCTAssertEqual(store.load(), [])
    }

    func testSavingEmptyArrayClearsStore() throws {
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a")
        store.save([sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .confirming, updatedAt: Date(timeIntervalSince1970: 10))])

        store.save([])

        XCTAssertNil(defaults.data(forKey: try XCTUnwrap(store.storageKey)))
        XCTAssertEqual(store.load(), [])
    }

    func testNetworksAreIsolated() throws {
        let testnetStore = makeStore(network: .testnet, walletIdHex: "wallet-a")
        let mainnetStore = makeStore(network: .mainnet, walletIdHex: "wallet-a")
        let testnetConnection = sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .confirming, updatedAt: Date(timeIntervalSince1970: 10))
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
        let walletAConnection = sampleConnection(id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .confirming, updatedAt: Date(timeIntervalSince1970: 10))

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
        XCTAssertEqual(second.connectionsSnapshot.first?.status, .active)
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

    func testDisconnectRemovesTheRowAcrossFreshMockInstances() async throws {
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
        XCTAssertEqual(second.connectionsSnapshot, [])
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
            status: .confirming,
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
            status: .confirming,
            updatedAt: Date(timeIntervalSince1970: 10))])

        XCTAssertNil(store.storageKey)
        XCTAssertEqual(store.load(), [])
    }

    /// Every save is announced under the key it wrote, the last row's
    /// removal too; a store with nowhere to write announces nothing.
    func testASaveIsAnnouncedUnderItsKey() {
        let center = NotificationCenter()
        let keys = AnnouncedKeys()
        let observer = center.addObserver(
            forName: UserDefaultsDashConnectStore.didSaveNotification, object: nil, queue: nil
        ) { keys.append($0.userInfo?[UserDefaultsDashConnectStore.scopeKeyUserInfoKey] as? String) }
        defer { center.removeObserver(observer) }
        let store = makeStore(network: .testnet, walletIdHex: "wallet-a", notificationCenter: center)
        let row = sampleConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", status: .active,
            updatedAt: Date(timeIntervalSince1970: 10))

        store.save([row])
        store.save([])
        XCTAssertEqual(keys.all, [store.scopeKey, store.scopeKey])

        let pinned = store.pinned(toWalletIdHex: "wallet-b")
        pinned.save([row])
        XCTAssertEqual(keys.all.last, pinned.scopeKey, "a pinned store announces on the same center")

        makeStore(network: .testnet, walletIdHex: nil, notificationCenter: center).save([row])
        makeStore(network: .devnet, walletIdHex: "wallet-a", devnetName: nil, notificationCenter: center).save([row])
        XCTAssertEqual(keys.all.count, 3, "nowhere to write, nothing announced")
    }

    // MARK: - Wallet wipe (AC-19)

    private let wipedWalletHex = String(repeating: "a1", count: 32)
    private let keptWalletHex = String(repeating: "b2", count: 32)

    /// Writes the three key families a wallet has on one network scope - row
    /// cache, intents, legacy grants - and returns their keys.
    @discardableResult
    private func seedDashConnectKeys(
        in defaults: UserDefaults,
        network: DashConnectNetwork,
        devnetName: String? = nil,
        walletIdHex: String
    ) throws -> [String] {
        let store = UserDefaultsDashConnectStore(
            defaults: defaults,
            network: network,
            walletIdHexProvider: { walletIdHex },
            devnetNameProvider: { devnetName })
        let rowCacheKey = try XCTUnwrap(store.storageKey)
        let keys = [
            rowCacheKey,
            "\(rowCacheKey).app-connect-intents.v1",
            "\(rowCacheKey).app-connect-responses.v1",
        ]
        for key in keys {
            defaults.set(Data("[]".utf8), forKey: key)
        }
        return keys
    }

    func testRemoveAllClearsEveryNetworkOfTheWalletAndKeepsTheOther() throws {
        var wiped: [String] = []
        var kept: [String] = []
        for (network, devnetName) in [(DashConnectNetwork.mainnet, String?.none),
                                      (.testnet, nil),
                                      (.devnet, "devnet-a.b")] {
            wiped += try seedDashConnectKeys(
                in: defaults, network: network, devnetName: devnetName, walletIdHex: wipedWalletHex)
            kept += try seedDashConnectKeys(
                in: defaults, network: network, devnetName: devnetName, walletIdHex: keptWalletHex)
        }
        XCTAssertEqual(wiped.count, 9)

        DashConnectStores.removeAll(walletIdHex: wipedWalletHex, in: defaults)

        for key in wiped {
            XCTAssertNil(defaults.object(forKey: key), "\(key) must be removed with its wallet")
        }
        for key in kept {
            XCTAssertNotNil(defaults.object(forKey: key), "\(key) belongs to the other wallet")
        }
    }

    func testRemoveAllMatchesTheWalletSegmentNotADevnetNameHoldingAHex() throws {
        // Devnet names that hold a wallet id, with and without dots: the
        // wallet segment is what follows the network segment.
        let nameHoldingKeptHex = "x.\(keptWalletHex)"
        let nameHoldingWipedHex = wipedWalletHex
        let wipedOnNameHoldingKeptHex = try seedDashConnectKeys(
            in: defaults, network: .devnet, devnetName: nameHoldingKeptHex, walletIdHex: wipedWalletHex)
        let keptOnNameHoldingWipedHex = try seedDashConnectKeys(
            in: defaults, network: .devnet, devnetName: nameHoldingWipedHex, walletIdHex: keptWalletHex)
        let keptOnNameHoldingKeptHex = try seedDashConnectKeys(
            in: defaults, network: .devnet, devnetName: nameHoldingKeptHex, walletIdHex: keptWalletHex)

        DashConnectStores.removeAll(walletIdHex: wipedWalletHex, in: defaults)

        for key in wipedOnNameHoldingKeptHex {
            XCTAssertNil(defaults.object(forKey: key), "\(key) has the wiped wallet as its wallet segment")
        }
        for key in keptOnNameHoldingWipedHex + keptOnNameHoldingKeptHex {
            XCTAssertNotNil(defaults.object(forKey: key), "\(key) has the other wallet as its wallet segment")
        }

        // The mirror: wiping the other wallet leaves what the first wipe
        // left, apart from that wallet's own keys.
        DashConnectStores.removeAll(walletIdHex: keptWalletHex, in: defaults)
        for key in keptOnNameHoldingWipedHex + keptOnNameHoldingKeptHex {
            XCTAssertNil(defaults.object(forKey: key))
        }
    }

    func testRemoveAllLeavesUnrelatedKeys() throws {
        let unrelated = [
            "DashConnect.keptSharedProfileKeysRemoved",
            "crowdnode.\(wipedWalletHex)",
            "unrelated.dashconnect.connections.v1.m.\(wipedWalletHex)",
            "dashconnect.connections.v1.m",
        ]
        for key in unrelated {
            defaults.set("kept", forKey: key)
        }
        try seedDashConnectKeys(in: defaults, network: .mainnet, walletIdHex: wipedWalletHex)

        DashConnectStores.removeAll(walletIdHex: wipedWalletHex, in: defaults)

        for key in unrelated {
            XCTAssertEqual(defaults.string(forKey: key), "kept", "\(key) is not a DashConnect key of the wallet")
        }
    }

    /// The per-wallet deletion path (`deleteWalletFromSDK`, shared by the
    /// Wallets screen's Remove and the full wipe's loop) runs on
    /// `UserDefaults.standard`; the wipe's other app-state stores are not
    /// injectable, so this seeds `.standard` under a random wallet id.
    @MainActor
    func testWalletDeletionPathClearsDashConnectKeysOfThatWallet() throws {
        let walletId = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let otherWalletId = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let standard = UserDefaults.standard
        let wiped = try seedDashConnectKeys(
            in: standard, network: .testnet, walletIdHex: walletId.hexEncodedString())
        let kept = try seedDashConnectKeys(
            in: standard, network: .testnet, walletIdHex: otherWalletId.hexEncodedString())
        defer { (wiped + kept).forEach { standard.removeObject(forKey: $0) } }

        try SwiftDashSDKWalletWiper.deleteWalletFromSDK(
            walletId,
            deleteWallet: { _ in },
            scope: "testnet")

        for key in wiped {
            XCTAssertNil(standard.object(forKey: key), "\(key) must go with the wallet")
        }
        for key in kept {
            XCTAssertNotNil(standard.object(forKey: key), "\(key) belongs to another wallet")
        }
    }

    /// The full wipe goes on after another devnet scope's deletion fails,
    /// and the wallet's DashConnect records serve every scope: its deletion
    /// of the configured scope leaves them to the wipe's commit point, which
    /// runs only once every deletion succeeded.
    @MainActor
    func testTheFullWipesDeletionLeavesDashConnectKeysToItsCommitPoint() throws {
        let walletId = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let standard = UserDefaults.standard
        let kept = try seedDashConnectKeys(
            in: standard, network: .devnet, devnetName: "moutai", walletIdHex: walletId.hexEncodedString())
        defer { kept.forEach { standard.removeObject(forKey: $0) } }

        try SwiftDashSDKWalletWiper.deleteWalletFromSDK(
            walletId,
            deleteWallet: { _ in },
            leavesDashConnectToWipe: true,
            scope: "devnet-b")

        for key in kept {
            XCTAssertNotNil(standard.object(forKey: key), "\(key) may still serve a scope whose deletion failed")
        }
    }

    func testRemoveAllWalletsClearsEveryDashConnectKeyIncludingOrphansAndKeepsOthers() throws {
        let current = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).hexEncodedString()
        let orphan = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).hexEncodedString()
        var dashConnectKeys = try seedDashConnectKeys(in: defaults, network: .testnet, walletIdHex: current)
        dashConnectKeys += try seedDashConnectKeys(in: defaults, network: .mainnet, walletIdHex: orphan)
        dashConnectKeys += try seedDashConnectKeys(
            in: defaults, network: .devnet, devnetName: "moutai", walletIdHex: orphan)
        let unrelated = "dashconnect.unrelated.\(UUID().uuidString)"
        defaults.set("keep", forKey: unrelated)

        DashConnectStores.removeAllWallets(in: defaults)

        for key in dashConnectKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) must go on a full wipe")
        }
        let leftovers = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(UserDefaultsDashConnectStore.keyPrefix) }
        XCTAssertTrue(leftovers.isEmpty, "no key under the prefix may survive: \(leftovers)")
        XCTAssertEqual(defaults.string(forKey: unrelated), "keep")
    }

    private func makeStore(
        network: DashConnectNetwork,
        walletIdHex: String?,
        devnetName: String? = "moutai",
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> UserDefaultsDashConnectStore {
        UserDefaultsDashConnectStore(
            defaults: defaults,
            network: network,
            walletIdHexProvider: { walletIdHex },
            devnetNameProvider: { devnetName },
            notificationCenter: notificationCenter
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

/// The keys announced to a test's observer, which may be called on any
/// thread.
private final class AnnouncedKeys: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String?] = []

    var all: [String?] { lock.withLock { keys } }

    func append(_ key: String?) { lock.withLock { keys.append(key) } }
}
