import Foundation
import XCTest
@testable import dashpay
@testable import SwiftDashSDK

/// The App Connect projection: intents against one read of the identity
/// (`AppConnectProjection.swift`).
final class AppConnectProjectionTests: XCTestCase {
    private typealias Key = AppConnect.IntendedKey
    private typealias Intent = AppConnect.ConnectionIntent
    private typealias Snapshot = AppConnect.IdentitySnapshot

    private static let identity = Data(repeating: 0x01, count: 32)
    private static let otherIdentity = Data(repeating: 0x02, count: 32)
    private static let app = Data(repeating: 0xA1, count: 32)
    private static let otherApp = Data(repeating: 0xA2, count: 32)
    private static let appGroup = Data(repeating: 0xB1, count: 32)
    private static let dashPay = Data.identifier(fromBase58: AppConnect.dashPayContractId)!
    private static let now: UInt64 = 1_800_000_000_000

    private static func authKey(
        _ id: UInt32, data: UInt8? = nil, bound: AppConnect.StoredBound? = .singleContract(app), expiresAt: UInt64? = now + 1000
    ) -> Key {
        Key(id: id, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: data ?? UInt8(truncatingIfNeeded: id), count: 20), readOnly: false, bound: bound,
            totalBudget: 1000, expiresAt: expiresAt)
    }

    private static func encryptionKey(_ id: UInt32) -> Key {
        Key(id: id, purpose: .encryption, securityLevel: .medium, keyType: .ecdsaSecp256k1,
            data: Data(repeating: UInt8(id), count: 33), readOnly: false, bound: .singleContract(app),
            totalBudget: nil, expiresAt: nil)
    }

    /// The key as Platform shows it once its update landed.
    private static func onPlatform(
        _ key: Key, disabledAt: UInt64? = nil, boundKnown: Bool = true, data: Data? = nil
    ) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType,
            data: data ?? key.data, readOnly: key.readOnly, bound: boundKnown ? key.bound : nil,
            boundKnown: boundKnown, totalBudget: key.totalBudget, expiresAt: key.expiresAt, disabledAt: disabledAt)
    }

    private static func intent(
        _ keys: [Key], app: Data = app, identity: Data = identity, published: Bool = false, createdAt: TimeInterval = 0
    ) -> Intent {
        Intent(
            id: UUID(), identityId: identity, appId: app, appLabel: "App", appUrl: "", requestHash: Data(repeating: 0xEE, count: 20),
            connectionId: nil, keys: keys, sentEncryptionKeyIds: [], disables: [],
            response: AppConnect.ResponseValues(appEphemeralPubKeyHash: "ee", walletEphemeralPubKey: "02", encryptedPayload: "00"),
            responseDocumentId: published ? Data(repeating: 0xDD, count: 32) : nil, responseRemoved: !published, createdAt: Date(timeIntervalSince1970: createdAt), closedAt: nil)
    }

    private static func snapshot(
        _ keys: [AppConnect.PlatformKey], identity: Data = identity, revision: UInt64 = 5, time: UInt64? = now
    ) -> Snapshot {
        Snapshot(identityId: identity, revision: revision, keys: keys, platformTime: time)
    }

    // MARK: Status of one intent

    func testStatusOfAnIntentFollowsItsAuthKeysOnPlatform() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let intent = Self.intent([a, b, Self.encryptionKey(12)])
        let expired = Self.authKey(10, expiresAt: Self.now - 1)
        let cases: [(String, [AppConnect.PlatformKey], AppConnect.IntentStatus)] = [
            ("nothing there yet", [], .confirming),
            ("all there", [Self.onPlatform(a), Self.onPlatform(b)], .active(expiresAt: Self.now + 1000)),
            ("one there, one missing", [Self.onPlatform(a)], .active(expiresAt: Self.now + 1000)),
            ("one id taken by another key", [Self.onPlatform(a, data: Data(repeating: 9, count: 20))], .neverLanded),
            ("a live key wins over a taken id", [Self.onPlatform(a), Self.onPlatform(b, data: Data(repeating: 9, count: 20))], .active(expiresAt: Self.now + 1000)),
            ("all off", [Self.onPlatform(a, disabledAt: 1), Self.onPlatform(b, disabledAt: 1)], .disconnected),
            ("one off, one missing", [Self.onPlatform(a, disabledAt: 1)], .confirming),
            ("expired by Platform time", [Self.onPlatform(expired), Self.onPlatform(b, disabledAt: 1)], .expired),
        ]
        for (name, keys, expected) in cases {
            XCTAssertEqual(AppConnect.status(of: intent, in: Self.snapshot(keys)), expected, name)
        }
    }

    func testAKeyIsNeverJudgedExpiredWithoutPlatformTime() {
        let key = Self.authKey(10, expiresAt: 1)
        let intent = Self.intent([key])
        XCTAssertEqual(
            AppConnect.status(of: intent, in: Self.snapshot([Self.onPlatform(key)], time: nil)),
            .active(expiresAt: 1))
    }

    func testABoundTheStoreDoesNotKnowYetDoesNotMakeTheKeyAnother() {
        let key = Self.authKey(10)
        let intent = Self.intent([key])
        XCTAssertEqual(
            AppConnect.status(of: intent, in: Self.snapshot([Self.onPlatform(key, boundKnown: false)])),
            .active(expiresAt: Self.now + 1000))
    }

    func testAKnownOtherBoundMeansTheIdIsHeldByAnotherKey() {
        let key = Self.authKey(10)
        var other = Self.onPlatform(Self.authKey(10, bound: .singleContract(Self.otherApp)))
        other = AppConnect.PlatformKey(
            id: other.id, purpose: other.purpose, securityLevel: other.securityLevel, keyType: other.keyType,
            data: key.data, readOnly: false, bound: other.bound, boundKnown: true,
            totalBudget: other.totalBudget, expiresAt: other.expiresAt, disabledAt: nil)
        XCTAssertEqual(AppConnect.status(of: Self.intent([key]), in: Self.snapshot([other])), .neverLanded)
    }

    func testChangedLimitsAreTheSameKey() {
        let key = Self.authKey(10)
        let raised = AppConnect.PlatformKey(
            id: 10, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160, data: key.data,
            readOnly: false, bound: key.bound, boundKnown: true, totalBudget: 5000, expiresAt: Self.now + 9000,
            disabledAt: nil)
        XCTAssertEqual(AppConnect.status(of: Self.intent([key]), in: Self.snapshot([raised])), .active(expiresAt: Self.now + 9000))
    }

    // MARK: Projection

    func testAnAppShowsTheStatusTheUserCanActOnFirst() {
        let old = Self.intent([Self.authKey(10)], createdAt: 1)
        let new = Self.intent([Self.authKey(11)], createdAt: 2)
        let projection = AppConnect.project(
            [Self.snapshot([Self.onPlatform(Self.authKey(10))])], intents: [old, new])
        XCTAssertEqual(projection.connections.count, 1)
        XCTAssertEqual(projection.connections[0].status, .active(expiresAt: Self.now + 1000))
        XCTAssertEqual(projection.connections[0].intents.map(\.id), [new.id, old.id])
    }

    func testIntentsOnSeveralIdentitiesMakeOneConnection() {
        let first = Self.intent([Self.authKey(10)])
        let second = Self.intent([Self.authKey(10)], identity: Self.otherIdentity)
        let projection = AppConnect.project(
            [Self.snapshot([]), Self.snapshot([Self.onPlatform(Self.authKey(10))], identity: Self.otherIdentity)],
            intents: [first, second])
        XCTAssertEqual(projection.connections.map(\.status), [.active(expiresAt: Self.now + 1000)])
    }

    func testALiveAppKeyNoIntentNamesIsShownUnderItsApp() {
        let group = Self.authKey(10, bound: .contractGroup(Self.appGroup))
        let intent = Self.intent([group])
        let stray = Self.onPlatform(Self.authKey(20, bound: .contractGroup(Self.appGroup)))
        let projection = AppConnect.project([Self.snapshot([Self.onPlatform(group, disabledAt: 1), stray])], intents: [intent])
        XCTAssertEqual(projection.connections.count, 1)
        XCTAssertEqual(projection.connections[0].appId, Self.app)
        XCTAssertEqual(projection.connections[0].unrecordedKeyIds, [Self.identity: [20]])
        XCTAssertEqual(projection.connections[0].status, .active(expiresAt: nil))
    }

    func testALiveKeyOfAnAppWithNoIntentMakesItsOwnConnection() {
        let stray = Self.onPlatform(Self.authKey(20, bound: .singleContract(Self.otherApp)))
        let projection = AppConnect.project([Self.snapshot([stray])], intents: [])
        XCTAssertEqual(projection.connections.map(\.appId), [Self.otherApp])
        XCTAssertEqual(projection.connections[0].unrecordedKeyIds, [Self.identity: [20]])
    }

    func testAProfileKeyNoIntentNamesStandsAsAConnectionOfItsOwnAndADisabledOneIsNotShown() {
        let profile = Self.authKey(20, bound: .documentType(contractId: Self.dashPay, name: "profile"))
        let off = Self.authKey(21, bound: .singleContract(Self.otherApp))
        let snapshot = Self.snapshot([Self.onPlatform(profile), Self.onPlatform(off, disabledAt: 1)])
        let projection = AppConnect.project([snapshot], intents: [])
        XCTAssertEqual(projection.connections.map(\.appId), [Self.dashPay], "it can be turned off with no other row left")
        XCTAssertEqual(projection.connections.first?.unrecordedKeyIds, [Self.identity: [20]])
        XCTAssertEqual(projection.unrecordedProfileKeyIds, [Self.identity: [20]])
        XCTAssertEqual(
            AppConnect.disconnectPlan(appId: Self.dashPay, snapshot: snapshot, intents: [], includeUnrecorded: true).disable,
            [20])
    }

    func testAKeyAStoreCannotBindIsNotGuessedToBeAnApps() {
        let unknown = Self.onPlatform(Self.authKey(20), boundKnown: false)
        XCTAssertEqual(AppConnect.project([Self.snapshot([unknown])], intents: []).connections, [])
    }

    // MARK: Snapshots

    func testAReadBehindOneAlreadySeenIsDropped() {
        let newest = Self.snapshot([], revision: 7)
        XCTAssertFalse(Self.snapshot([], revision: 6).mayReplace(newest))
        XCTAssertTrue(Self.snapshot([], revision: 7).mayReplace(newest))
        XCTAssertTrue(Self.snapshot([], revision: 1).mayReplace(nil))
        XCTAssertTrue(Self.snapshot([], identity: Self.otherIdentity, revision: 1).mayReplace(newest))
    }

    // MARK: Key ids

    func testNewIdsSkipEveryIdAnIntentMayStillLandOn() {
        let pending = Self.intent([Self.authKey(14), Self.encryptionKey(15)])
        let elsewhere = Self.intent([Self.authKey(40)], identity: Self.otherIdentity)
        let ids = AppConnect.newKeyIds(
            count: 2, snapshot: Self.snapshot([Self.onPlatform(Self.authKey(3))]), intents: [pending, elsewhere])
        XCTAssertEqual(ids, [16, 17])
    }

    func testNewIdsTakeTheLowestFreeOnesOnceTheTopIsReached() {
        let top = Self.onPlatform(Self.authKey(UInt32.max - 1))
        XCTAssertEqual(AppConnect.newKeyIds(count: 1, snapshot: Self.snapshot([top]), intents: []), [UInt32.max])
        let low = [Self.onPlatform(Self.authKey(0)), top]
        let pending = Self.intent([Self.authKey(1)])
        XCTAssertEqual(AppConnect.newKeyIds(count: 2, snapshot: Self.snapshot(low), intents: [pending]), [2, 3])
    }

    // MARK: Disconnect

    func testADisconnectTurnsOffWhatIsThereAndFencesWhatMayStillLand() {
        let landed = Self.intent([Self.authKey(10), Self.authKey(11)], published: true)
        let waiting = Self.intent([Self.authKey(12), Self.authKey(13)])
        let dead = Self.intent([Self.authKey(14)])
        let expired = Self.authKey(11, expiresAt: Self.now - 1)
        let snapshot = Self.snapshot([
            Self.onPlatform(Self.authKey(10)), Self.onPlatform(expired),
            Self.onPlatform(Self.authKey(14), data: Data(repeating: 9, count: 20)),
        ])
        let plan = AppConnect.disconnectPlan(
            appId: Self.app, snapshot: snapshot, intents: [landed, waiting, dead], includeUnrecorded: false)
        XCTAssertEqual(plan.disable, [10, 11])
        XCTAssertEqual(plan.fence, [12])
        XCTAssertEqual(plan.deleteResponses, [landed.id])
    }

    func testAPartlyLandedIntentIsFencedOnlyWhileAKeyIsMissing() {
        let intent = Self.intent([Self.authKey(10), Self.authKey(11)])
        let plan = AppConnect.disconnectPlan(
            appId: Self.app, snapshot: Self.snapshot([Self.onPlatform(Self.authKey(10))]), intents: [intent],
            includeUnrecorded: false)
        XCTAssertEqual(plan.disable, [10])
        XCTAssertEqual(plan.fence, [11])
    }

    func testUnrecordedAppKeysAreTurnedOffOnlyWhenTheUserSaysSo() {
        let intent = Self.intent([Self.authKey(10)])
        let stray = Self.onPlatform(Self.authKey(20))
        let snapshot = Self.snapshot([Self.onPlatform(Self.authKey(10)), stray])
        XCTAssertEqual(
            AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], includeUnrecorded: false).disable,
            [10])
        XCTAssertEqual(
            AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], includeUnrecorded: true).disable,
            [10, 20])
    }

    func testADisconnectLeavesOtherAppsAndOtherIdentitiesAlone() {
        let mine = Self.intent([Self.authKey(10)])
        let otherApps = Self.intent([Self.authKey(11)], app: Self.otherApp)
        let otherIdentity = Self.intent([Self.authKey(12)], identity: Self.otherIdentity)
        let snapshot = Self.snapshot([Self.onPlatform(Self.authKey(10)), Self.onPlatform(Self.authKey(11))])
        let plan = AppConnect.disconnectPlan(
            appId: Self.app, snapshot: snapshot, intents: [mine, otherApps, otherIdentity], includeUnrecorded: false)
        XCTAssertEqual(plan, AppConnect.DisconnectPlan(disable: [10]))
    }

    // MARK: Store

    func testAnIntentRoundTripsThroughJSON() throws {
        let intent = Self.intent([
            Self.authKey(10, bound: .documentType(contractId: Self.dashPay, name: "profile")),
            Self.authKey(11, bound: .contractGroup(Self.appGroup)), Self.encryptionKey(12),
        ])
        let decoded = try JSONDecoder().decode(Intent.self, from: JSONEncoder().encode(intent))
        XCTAssertEqual(decoded, intent)
    }

    // MARK: Intent store

    private func intentStore(_ scope: @escaping () -> String?) -> (UserDefaultsAppConnectIntentStore, UserDefaults) {
        let suite = "AppConnectProjectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (UserDefaultsAppConnectIntentStore(defaults: defaults, network: .testnet, scopeKeyProvider: scope), defaults)
    }

    func testAPinnedHandedInScopeDoesNotFollowItsProvider() {
        var scope: String? = "scope-a"
        let (store, _) = intentStore { scope }
        let intent = Self.intent([Self.authKey(6)])

        let pinned = store.pinned(toWalletIdHex: "wallet-a")
        scope = "scope-b"
        pinned.save([intent])

        XCTAssertEqual(store.load(), [])
        scope = "scope-a"
        XCTAssertEqual(store.load(), [intent])
    }

    func testARowThisBuildCannotReadIsKeptAndCountsForItsIdentity() throws {
        let (store, defaults) = intentStore { "scope" }
        let intent = Self.intent([Self.authKey(6)])
        store.save([intent])
        let key = "scope.app-connect-intents.v1"
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: key))) as? [Any])
        rows.append(["identityId": Self.identity.base64EncodedString(), "future": true])
        defaults.set(try JSONSerialization.data(withJSONObject: rows), forKey: key)

        XCTAssertEqual(store.load(), [intent])
        XCTAssertTrue(store.hasUnreadableRows(identityId: Self.identity))
        XCTAssertFalse(store.hasUnreadableRows(identityId: Self.otherIdentity))
        store.save([])
        XCTAssertTrue(store.hasUnreadableRows(identityId: Self.identity), "an unreadable row is never dropped")
    }

    func testAStoredValueThatIsNotARowListIsNeverReplaced() {
        let (store, defaults) = intentStore { "scope" }
        defaults.set("not a list", forKey: "scope.app-connect-intents.v1")
        XCTAssertFalse(store.canPersist)
        store.save([Self.intent([Self.authKey(6)])])
        XCTAssertEqual(defaults.string(forKey: "scope.app-connect-intents.v1"), "not a list")
    }

    // MARK: Rows

    func testRowsFollowTheProjection() {
        let gone = DAppConnection(
            id: Self.otherApp.toBase58String(), name: "Gone", url: "", status: .active,
            updatedAt: Date(timeIntervalSince1970: 1))
        let confirming = Self.intent([Self.authKey(10)])
        let projection = AppConnect.project([Self.snapshot([])], intents: [confirming])
        let rows = PlatformDashConnectDataSource.rows(
            [gone], after: projection, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(rows.map(\.id), [Self.app.toBase58String()])
        XCTAssertEqual(rows.last?.status, .confirming)
        XCTAssertEqual(rows.last?.name, "App")
    }

    func testAConnectionWhoseResponseWasNeverPublishedShowsAsNotDelivered() {
        let key = Self.authKey(10)
        let snapshot = Self.snapshot([Self.onPlatform(key)])
        let undelivered = AppConnect.project([snapshot], intents: [Self.intent([key])])
        XCTAssertEqual(undelivered.connections.first?.isUndelivered, true)
        XCTAssertEqual(
            PlatformDashConnectDataSource.rows([], after: undelivered, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 2)).map(\.status),
            [.undelivered])
        let delivered = AppConnect.project([snapshot], intents: [Self.intent([key], published: true)])
        XCTAssertEqual(delivered.connections.first?.isUndelivered, false)
        XCTAssertEqual(
            PlatformDashConnectDataSource.rows([], after: delivered, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 2)).map(\.status),
            [.active])
        let restored = AppConnect.project([Self.snapshot([Self.onPlatform(key)])], intents: [])
        XCTAssertEqual(restored.connections.first?.isUndelivered, false, "keys no intent names are not judged undelivered")
    }

    func testAccessSeenOnAnotherIdentityKeepsTheRowUntilThatIdentityIsReadAgain() {
        let stray = Self.onPlatform(Self.authKey(20))
        let onA = AppConnect.project([Self.snapshot([stray])], intents: [])
        let rowsA = PlatformDashConnectDataSource.rows([], after: onA, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(rowsA.first?.seenOn, [Self.identity.toBase58String()])
        let onB = AppConnect.project([Self.snapshot([], identity: Self.otherIdentity)], intents: [])
        let rowsB = PlatformDashConnectDataSource.rows(rowsA, after: onB, of: Self.otherIdentity, intents: [], at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(rowsB.map(\.id), [Self.app.toBase58String()], "B's read says nothing of A")
        XCTAssertEqual(rowsB.first?.status, .active)
        let againA = AppConnect.project([Self.snapshot([Self.onPlatform(Self.authKey(20), disabledAt: 1)])], intents: [])
        XCTAssertEqual(
            PlatformDashConnectDataSource.rows(rowsB, after: againA, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 3)),
            [], "A read again shows the key off")
    }

    func testARowAnotherIdentityHoldsKeepsWhatOtherIdentitiesSaw() {
        let a = Self.identity.toBase58String(), b = Self.otherIdentity.toBase58String()
        let row = DAppConnection(
            id: Self.app.toBase58String(), name: "App", url: "", status: .active,
            updatedAt: Date(timeIntervalSince1970: 1), seenOn: [a, b])
        let elsewhere = Self.intent([Self.authKey(10)], identity: Self.otherIdentity)
        let rows = PlatformDashConnectDataSource.rows(
            [row], after: AppConnect.project([Self.snapshot([])], intents: []), of: Self.identity, intents: [elsewhere],
            at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(rows.map(\.seenOn), [[b]], "only the identity read now is dropped")
    }

    func testAnAppConnectRowHeldByAnotherIdentityStays() {
        let row = DAppConnection(
            id: Self.otherApp.toBase58String(), name: "Elsewhere", url: "", status: .active,
            updatedAt: Date(timeIntervalSince1970: 1))
        let elsewhere = Self.intent([Self.authKey(10)], app: Self.otherApp, identity: Self.otherIdentity)
        let rows = PlatformDashConnectDataSource.rows(
            [row], after: AppConnect.project([Self.snapshot([])], intents: []), of: Self.identity, intents: [elsewhere],
            at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(rows, [row])
    }

    /// While the read has a key of unknown bound, no row goes, whether its
    /// intent was turned off, never landed or there is no intent at all; once
    /// every key is placed, the row goes.
    func testNoRowGoesWhileAKeyHasAnUnknownBound() {
        let key = Self.authKey(10)
        let row = DAppConnection(
            id: Self.app.toBase58String(), name: "App", url: "", status: .active,
            updatedAt: Date(timeIntervalSince1970: 1))
        let unplaced = Self.onPlatform(Self.authKey(20, bound: .singleContract(Self.otherApp)), boundKnown: false)
        let off = Self.onPlatform(key, disabledAt: 1)
        let taken = Self.onPlatform(Self.authKey(10, data: 9, bound: .singleContract(Self.otherApp)))
        let cases: [(String, [AppConnect.PlatformKey], [Intent], AppConnect.IntentStatus?)] = [
            ("turned off", [off], [Self.intent([key])], .disconnected),
            ("never landed", [taken], [Self.intent([key])], .neverLanded),
            ("no intent", [], [], nil),
        ]
        for (name, keys, intents, status) in cases {
            let rows = { (keys: [AppConnect.PlatformKey]) in
                let projection = AppConnect.project([Self.snapshot(keys)], intents: intents)
                XCTAssertEqual(projection.connections.first { $0.appId == Self.app }?.status, status, name)
                return PlatformDashConnectDataSource.rows(
                    [row], after: projection, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 2))
                    .filter { $0.id == row.id }
            }
            XCTAssertEqual(rows(keys + [unplaced]), [row], name)
            XCTAssertEqual(rows(keys), [], name)
        }
    }

    // MARK: Retry

    private static func plan(
        budget: UInt64? = 1000, expiresAt: UInt64 = now + 1000, critical: Bool = false,
        encryption: [AppConnectRequest.EncryptionBinding] = [], connectionId: Data? = nil
    ) -> AppConnect.GrantPlan {
        let binding = AppConnectRequest.AuthBinding(
            kind: .singleContract, securityLevel: critical ? .critical : .high, id: app,
            totalBudget: budget, expiresAt: expiresAt, documentTypeName: nil)
        return AppConnect.GrantPlan(
            appId: app, appEphemeralPubKeyHash: Data(repeating: 0xEE, count: 20),
            auth: [AppConnect.AuthGrant(bindingIndex: 0, binding: binding, totalBudget: budget, expiresAt: expiresAt)],
            encryption: encryption.enumerated().map { AppConnect.EncryptionGrant(bindingIndex: $0.offset, binding: $0.element) },
            connectionId: connectionId, identityHint: nil, createdAt: 0, callbackHost: nil)
    }

    // MARK: Fence

    func testAFenceKeyIsTheSameOnEveryTryAndDiffersPerId() {
        let first = AppConnect.fenceKeyLeaf(identityId: Self.identity, keyId: 7)
        XCTAssertEqual(first, AppConnect.fenceKeyLeaf(identityId: Self.identity, keyId: 7))
        XCTAssertNotEqual(first, AppConnect.fenceKeyLeaf(identityId: Self.identity, keyId: 8))
        XCTAssertNotEqual(first, AppConnect.fenceKeyLeaf(identityId: Self.otherIdentity, keyId: 7))
        let key = AppConnect.fenceKey(keyId: 7, publicKeyHash160: Data(repeating: 1, count: 20))
        XCTAssertEqual(key.keyId, 7)
        XCTAssertEqual(key.purpose, .authentication)
        XCTAssertNil(key.contractBounds)
    }

    func testAnIntendedKeyIsSubmittedExactlyAsRecorded() {
        let key = Self.authKey(10, bound: .documentType(contractId: Self.dashPay, name: "profile"))
        let submitted = AppConnect.identityPubkey(of: key)
        XCTAssertEqual(submitted.keyId, 10)
        XCTAssertEqual(submitted.pubkeyBytes, key.data)
        XCTAssertEqual(submitted.contractBounds, .singleContractDocumentType(id: Self.dashPay, documentTypeName: "profile"))
        XCTAssertEqual(submitted.totalBudget, key.totalBudget)
        XCTAssertEqual(submitted.expiresAt, key.expiresAt)
    }

    // MARK: Review fixes

    func testAnUnrecordedKeyOnAContractSeveralAppsBindIsOfferedWithEachOfThem() {
        let shared = Data(repeating: 0xC1, count: 32)
        let mine = Self.intent([Self.authKey(10, bound: .singleContract(shared))])
        let theirs = Self.intent([Self.authKey(11, bound: .singleContract(shared))], app: Self.otherApp)
        let stray = Self.onPlatform(Self.authKey(20, bound: .singleContract(shared)))
        let snapshot = Self.snapshot([stray])
        let projection = AppConnect.project([snapshot], intents: [mine, theirs])
        for app in [Self.app, Self.otherApp] {
            XCTAssertEqual(projection.connections.first { $0.appId == app }?.unrecordedKeyIds[Self.identity], [20])
            XCTAssertEqual(
                AppConnect.disconnectPlan(appId: app, snapshot: snapshot, intents: [mine, theirs], includeUnrecorded: true).disable,
                [20])
        }
    }

    func testAnUnrecordedKeyOnASharedContractGoesWithTheDisconnectOfAnyAppBindingIt() {
        let shared = Data(repeating: 0xC1, count: 32)
        let mine = Self.intent([Self.authKey(10, bound: .singleContract(shared))])
        var gone = Self.intent([Self.authKey(11, bound: .singleContract(shared))], app: Self.otherApp)
        gone.closedAt = Date(timeIntervalSince1970: 5)
        let stray = Self.onPlatform(Self.authKey(20, bound: .singleContract(shared)))
        let projection = AppConnect.project([Self.snapshot([stray])], intents: [mine, gone])
        for app in [Self.app, Self.otherApp] {
            XCTAssertEqual(projection.connections.first { $0.appId == app }?.unrecordedKeyIds[Self.identity], [20])
        }
        for app in [Self.app, Self.otherApp] {
            XCTAssertEqual(
                AppConnect.disconnectPlan(appId: app, snapshot: Self.snapshot([stray]), intents: [mine, gone], includeUnrecorded: true).disable,
                [20], "a disconnect of either app turns it off")
        }
    }

    func testALiveKeyOfAnIntentWithATakenIdStaysActionable() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let intent = Self.intent([a, b])
        let snapshot = Self.snapshot([Self.onPlatform(a), Self.onPlatform(b, data: Data(repeating: 9, count: 20))])
        let projection = AppConnect.project([snapshot], intents: [intent])
        XCTAssertEqual(projection.connections.first?.status, .active(expiresAt: Self.now + 1000), "the app keeps a row")
        let plan = AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], includeUnrecorded: false)
        XCTAssertEqual(plan.disable, [10])
        XCTAssertEqual(plan.fence, [])
    }

    func testAResponseIsNotReleasedForALandedKeyGivenMoreThanApproved() {
        let key = Self.authKey(10)
        let intent = Self.intent([key])
        let raised = AppConnect.PlatformKey(
            id: 10, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160, data: key.data,
            readOnly: false, bound: key.bound, boundKnown: true, totalBudget: 5000, expiresAt: Self.now + 1000,
            disabledAt: nil)
        XCTAssertTrue(AppConnect.landedKeysWithinPlan(intent, Self.plan(), in: Self.snapshot([])))
        XCTAssertTrue(AppConnect.landedKeysWithinPlan(intent, Self.plan(), in: Self.snapshot([Self.onPlatform(key)])))
        XCTAssertFalse(AppConnect.landedKeysWithinPlan(intent, Self.plan(), in: Self.snapshot([raised])))
        let longer = AppConnect.PlatformKey(
            id: 10, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160, data: key.data,
            readOnly: false, bound: key.bound, boundKnown: true, totalBudget: 1000, expiresAt: Self.now + 9000,
            disabledAt: nil)
        XCTAssertFalse(AppConnect.landedKeysWithinPlan(intent, Self.plan(), in: Self.snapshot([longer])))
        let lowered = AppConnect.PlatformKey(
            id: 10, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160, data: key.data,
            readOnly: false, bound: key.bound, boundKnown: true, totalBudget: 500, expiresAt: Self.now + 1000,
            disabledAt: nil)
        XCTAssertTrue(AppConnect.landedKeysWithinPlan(intent, Self.plan(), in: Self.snapshot([lowered])), "less than approved")
        let uncapped = AppConnect.PlatformKey(
            id: 10, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160, data: key.data,
            readOnly: false, bound: key.bound, boundKnown: true, totalBudget: nil, expiresAt: Self.now + 1000,
            disabledAt: nil)
        XCTAssertFalse(AppConnect.landedKeysWithinPlan(intent, Self.plan(), in: Self.snapshot([uncapped])), "no cap is more")
        XCTAssertTrue(AppConnect.landedKeysWithinPlan(intent, Self.plan(budget: nil), in: Self.snapshot([uncapped])))
    }

    func testAnExpiredKeyOfAnIntentWithATakenIdKeepsTheConnection() {
        let a = Self.authKey(10, expiresAt: Self.now - 1), b = Self.authKey(11)
        let intent = Self.intent([a, b])
        let snapshot = Self.snapshot([Self.onPlatform(a), Self.onPlatform(b, data: Data(repeating: 9, count: 20))])
        XCTAssertEqual(AppConnect.status(of: intent, in: snapshot), .expired)
        XCTAssertEqual(
            AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], includeUnrecorded: false).disable,
            [10])
        let off = Self.snapshot([Self.onPlatform(a, disabledAt: 1), Self.onPlatform(b, data: Data(repeating: 9, count: 20))])
        XCTAssertEqual(AppConnect.status(of: intent, in: off), .neverLanded, "nothing enabled is left")
    }

    func testAnIntentHasLandedOnlyOnceTheKeysItTurnsOffAreOff() {
        let key = Self.authKey(10), earlier = Self.authKey(5)
        var intent = Self.intent([key])
        intent = Intent(
            id: intent.id, identityId: intent.identityId, appId: intent.appId, appLabel: intent.appLabel,
            appUrl: intent.appUrl, requestHash: intent.requestHash, connectionId: nil, keys: intent.keys,
            sentEncryptionKeyIds: [], disables: [5], response: intent.response, responseDocumentId: nil,
            responseRemoved: true, createdAt: intent.createdAt, closedAt: nil)
        let addedElsewhere = Self.snapshot([Self.onPlatform(key), Self.onPlatform(earlier)])
        XCTAssertFalse(AppConnect.hasLanded(intent, in: addedElsewhere), "the earlier key is still on")
        XCTAssertEqual(AppConnect.outstandingDisables(of: intent, in: addedElsewhere), [5])
        XCTAssertTrue(AppConnect.hasLanded(
            intent, in: Self.snapshot([Self.onPlatform(key), Self.onPlatform(earlier, disabledAt: 1)])))
        XCTAssertFalse(AppConnect.hasLanded(intent, in: Self.snapshot([Self.onPlatform(earlier, disabledAt: 1)])))
    }

    func testAResponseIsReleasedOnlyWhileEveryAuthKeyCanSign() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let intent = Self.intent([a, b])
        XCTAssertTrue(AppConnect.authKeysUsable(intent, in: Self.snapshot([Self.onPlatform(a)])), "one may still land")
        XCTAssertFalse(
            AppConnect.authKeysUsable(intent, in: Self.snapshot([Self.onPlatform(a), Self.onPlatform(b, disabledAt: 1)])),
            "one of two is off")
        let expired = Self.authKey(11, expiresAt: Self.now - 1)
        XCTAssertFalse(AppConnect.authKeysUsable(Self.intent([a, expired]), in: Self.snapshot([Self.onPlatform(expired)])))
    }

    func testTheResponsesEncryptionKeysAreListedByPurpose() {
        let added = Self.encryptionKey(12)
        var intent = Self.intent([Self.authKey(10), added])
        intent = Intent(
            id: intent.id, identityId: intent.identityId, appId: intent.appId, appLabel: intent.appLabel,
            appUrl: intent.appUrl, requestHash: intent.requestHash, connectionId: nil, keys: intent.keys,
            sentEncryptionKeyIds: [7], disables: [], response: intent.response,
            responseDocumentId: nil, responseRemoved: true, createdAt: intent.createdAt, closedAt: nil)
        let decryption = AppConnect.PlatformKey(
            id: 7, purpose: .decryption, securityLevel: .medium, keyType: .ecdsaSecp256k1, data: Data(repeating: 7, count: 33),
            readOnly: false, bound: .singleContract(Self.app), boundKnown: true, totalBudget: nil, expiresAt: nil, disabledAt: nil)
        typealias Expected = AppConnect.ExpectedCurrentKey
        XCTAssertEqual(
            AppConnect.expectedCurrentEncryptionKeys(of: intent, in: Self.snapshot([decryption, Self.onPlatform(added)])),
            [.encryption: [Expected(id: 12, data: added.data, mayBeNone: false)], .decryption: [Expected(id: 7, data: decryption.data, mayBeNone: false)]])
        XCTAssertEqual(
            AppConnect.expectedCurrentEncryptionKeys(of: intent, in: Self.snapshot([decryption])),
            [.encryption: [Expected(id: 12, data: added.data, mayBeNone: true)], .decryption: [Expected(id: 7, data: decryption.data, mayBeNone: false)]])
        XCTAssertEqual(
            AppConnect.expectedCurrentEncryptionKeys(
                of: intent, in: Self.snapshot([decryption, Self.onPlatform(added, data: Data(repeating: 9, count: 33))])),
            [.decryption: [Expected(id: 7, data: decryption.data, mayBeNone: false)]], "another key under its id is not asked about")

        let toRegister = Expected(id: 12, data: added.data, mayBeNone: true)
        let resent = Expected(id: 7, data: decryption.data, mayBeNone: false)
        let ours = AppConnect.CurrentContractKey(keyId: 12, keyType: nil, data: added.data, isDisabled: false)
        let other = AppConnect.CurrentContractKey(keyId: 5, keyType: nil, data: Data(repeating: 5, count: 33), isDisabled: false)
        let disabledOther = AppConnect.CurrentContractKey(keyId: 5, keyType: nil, data: Data(repeating: 5, count: 33), isDisabled: true)
        let sameIdOtherKey = AppConnect.CurrentContractKey(keyId: 12, keyType: nil, data: Data(repeating: 9, count: 33), isDisabled: false)
        let resentOff = AppConnect.CurrentContractKey(keyId: 7, keyType: nil, data: decryption.data, isDisabled: true)
        XCTAssertEqual(AppConnect.check(nil, against: toRegister), .matches, "none current yet")
        XCTAssertEqual(AppConnect.check(ours, against: toRegister), .matches, "it landed and the identity read was behind")
        XCTAssertEqual(AppConnect.check(other, against: toRegister), .differs, "another key became current")
        XCTAssertEqual(AppConnect.check(disabledOther, against: toRegister), .differs, "a disabled current key is still a current key")
        XCTAssertEqual(AppConnect.check(sameIdOtherKey, against: toRegister), .differs, "another key under its id")
        XCTAssertEqual(AppConnect.check(nil, against: resent), .notYet, "the node that answered may be behind")
        XCTAssertEqual(AppConnect.check(resentOff, against: resent), .differs)
    }

    func testAResponseIsResentOnlyWhileItsEncryptionKeysCanBeUsed() {
        let added = Self.encryptionKey(12)
        let intent = Self.intent([Self.authKey(10), added])
        XCTAssertTrue(AppConnect.encryptionKeysUsable(intent, in: Self.snapshot([])), "not landed yet")
        XCTAssertTrue(AppConnect.encryptionKeysUsable(intent, in: Self.snapshot([Self.onPlatform(added)])))
        XCTAssertFalse(
            AppConnect.encryptionKeysUsable(intent, in: Self.snapshot([Self.onPlatform(added, disabledAt: 1)])),
            "an encryption key it adds was turned off")
    }

    func testARowAnotherIdentityHoldsStaysAfterThisOneDisconnected() {
        let row = DAppConnection(
            id: Self.app.toBase58String(), name: "App", url: "", status: .active,
            updatedAt: Date(timeIntervalSince1970: 1))
        let closed = Self.intent([Self.authKey(10)])
        let projection = AppConnect.project([Self.snapshot([Self.onPlatform(Self.authKey(10), disabledAt: 1)])], intents: [closed])
        let elsewhere = Self.intent([Self.authKey(10)], identity: Self.otherIdentity)
        let rows = PlatformDashConnectDataSource.rows(
            [row], after: projection, of: Self.identity, intents: [elsewhere], at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(rows, [row])
    }

    func testAFenceKeyCanSpendOneCreditAndNeverExpires() {
        let key = AppConnect.fenceKey(keyId: 7, publicKeyHash160: Data(repeating: 1, count: 20))
        XCTAssertEqual(key.totalBudget, 1)
        XCTAssertNil(key.expiresAt)
    }

    // MARK: Second review round

    func testAnIdHeldByAnotherKeyEndsTheUpdateEvenWhenItIsTheEncryptionKey() {
        let auth = Self.authKey(20)
        let encryption = Self.encryptionKey(21)
        let intent = Self.intent([auth, encryption])
        var other = Self.onPlatform(encryption)
        other = AppConnect.PlatformKey(
            id: 21, purpose: .encryption, securityLevel: .medium, keyType: .ecdsaSecp256k1,
            data: Data(repeating: 0x77, count: 33), readOnly: false, bound: other.bound, boundKnown: true,
            totalBudget: nil, expiresAt: nil, disabledAt: nil)
        let snapshot = Self.snapshot([other])
        XCTAssertEqual(AppConnect.status(of: intent, in: snapshot), .neverLanded)
        XCTAssertEqual(
            AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], includeUnrecorded: false).fence,
            [])
    }

    func testAKeyAtTheLastIdLeavesTheLowestFreeIds() {
        let last = Self.onPlatform(Self.authKey(UInt32.max))
        XCTAssertEqual(AppConnect.newKeyIds(count: 2, snapshot: Self.snapshot([last]), intents: []), [0, 1])
    }

    // MARK: Third review round

    func testAnAppWhoseIntentsAreOnlyOnAnotherIdentityHasNoConnectionInThisRead() {
        let elsewhere = Self.intent([Self.authKey(10)], identity: Self.otherIdentity)
        XCTAssertEqual(AppConnect.project([Self.snapshot([])], intents: [elsewhere]).connections, [])
    }

    func testOnlyKeysInAnAppConnectShapeOnAnAppsContractCountAsUnrecorded() {
        let full = AppConnect.PlatformKey(
            id: 20, purpose: .authentication, securityLevel: .high, keyType: .ecdsaSecp256k1,
            data: Data(repeating: 2, count: 33), readOnly: false, bound: .singleContract(Self.otherApp), boundKnown: true,
            totalBudget: nil, expiresAt: nil, disabledAt: nil)
        let master = Self.onPlatform(Key(
            id: 21, purpose: .authentication, securityLevel: .master, keyType: .ecdsaHash160,
            data: Data(repeating: 3, count: 20), readOnly: false, bound: .singleContract(Self.otherApp),
            totalBudget: nil, expiresAt: nil))
        let system = Self.onPlatform(Self.authKey(22, bound: .singleContract(Data.identifier(fromBase58: AppConnect.contractId)!)))
        XCTAssertEqual(AppConnect.project([Self.snapshot([full, master, system])], intents: []).connections, [])
    }

    // MARK: Fourth review round

    func testAProtocolTimestampAboveTheSignedRangeIsReadUnsigned() {
        let far: UInt64 = 1 << 63 + 5
        let info = ManagedIdentity.IdentityPublicKeyInfo(
            keyId: 4, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160, readOnly: false,
            disabledAt: nil, data: Data(repeating: 4, count: 20), totalBudget: nil, expiresAt: Int64(bitPattern: far))
        XCTAssertEqual(AppConnect.platformKey(info, binding: nil).expiresAt, far)
    }

    func testAKeyWithoutAnExpiryIsNoAppConnectKey() {
        let forever = Self.onPlatform(Self.authKey(20, bound: .singleContract(Self.otherApp), expiresAt: nil))
        XCTAssertEqual(AppConnect.project([Self.snapshot([forever])], intents: []).connections, [])
    }

    func testAKeyWhoseBoundIsNotKnownYetIsReportedNotGuessed() {
        let unplaced = Self.onPlatform(Self.authKey(20), boundKnown: false)
        let projection = AppConnect.project([Self.snapshot([unplaced])], intents: [])
        XCTAssertEqual(projection.connections, [])
        XCTAssertEqual(projection.unplacedKeyIds, [Self.identity: [20]])
    }

    func testAnIdAnotherKeyHoldsIsThatKeysNotTheIntents() {
        let mine = Self.intent([Self.authKey(7)])
        let theirs = Self.onPlatform(Self.authKey(7, data: 0x99, bound: .singleContract(Self.otherApp)))
        let projection = AppConnect.project([Self.snapshot([theirs])], intents: [mine])
        XCTAssertEqual(projection.connections.first { $0.appId == Self.otherApp }?.unrecordedKeyIds, [Self.identity: [7]])
    }

    /// The app's keys are disabled after the other keys, so an update that
    /// fails part way leaves an app key live while another key is: the app's
    /// row stays, and its retry reaches the keys left (ADR-0031).
    func testADisconnectDisablesTheAppsKeysAfterTheOtherKeys() {
        // One app key below ten profile keys: in id order the first update
        // would take the app key and nine profile keys.
        let order = AppConnect.disableOrder(appKeyIds: [3], otherKeyIds: Array(4 ... 13))
        XCTAssertEqual(order, Array(4 ... 13) + [3])
        let batches = stride(from: 0, to: order.count, by: AppConnect.maxKeysDisabledPerUpdate).map {
            Array(order[$0 ..< min($0 + AppConnect.maxKeysDisabledPerUpdate, order.count)])
        }
        XCTAssertEqual(batches.first, Array(4 ... 13), "the first update takes only the other keys")
        // Whichever update fails, while another key is still live so is an
        // app key.
        for failed in batches.indices {
            let off = Set(batches[..<failed].joined())
            if !Set(4 ... 13).isSubset(of: off) {
                XCTAssertFalse(off.contains(3))
            }
        }
        // Each part in id order; a key in both lists goes with the app's.
        XCTAssertEqual(
            AppConnect.disableOrder(appKeyIds: [20, 2, 9], otherKeyIds: [7, 5, 9]),
            [5, 7, 2, 9, 20], "a key in both is the app's")
        XCTAssertEqual(AppConnect.disableOrder(appKeyIds: [4, 1], otherKeyIds: []), [1, 4])
        XCTAssertEqual(AppConnect.disableOrder(appKeyIds: [], otherKeyIds: [6, 2]), [2, 6])
    }

    /// A response whose delete failed stays on a closed intent: the next
    /// signed operation on the identity picks it up, whichever app it is for.
    func testAClosedIntentWhoseResponseWasNotDeletedIsLeftForTheNextSignedOperation() {
        var left = Self.intent([Self.authKey(10)], published: true)
        left.closedAt = Date(timeIntervalSince1970: 1)
        var deleted = Self.intent([Self.authKey(11)], published: true)
        deleted.closedAt = Date(timeIntervalSince1970: 1)
        deleted.responseRemoved = true
        let open = Self.intent([Self.authKey(12)], published: true)
        var otherIdentity = Self.intent([Self.authKey(13)], identity: Self.otherIdentity, published: true)
        otherIdentity.closedAt = Date(timeIntervalSince1970: 1)
        var otherApp = Self.intent([Self.authKey(14, bound: .singleContract(Self.otherApp))], app: Self.otherApp, published: true)
        otherApp.closedAt = Date(timeIntervalSince1970: 1)

        let ids = AppConnect.responsesLeft(identityId: Self.identity, intents: [left, deleted, open, otherIdentity, otherApp])

        XCTAssertEqual(Set(ids), [left.id, otherApp.id], "closed and not removed, on this identity, of any app")
    }

    /// A key on the identity whose bound the store does not hold may be
    /// bound elsewhere: the update is not taken as landed until it does, so
    /// the response is not published. The row still counts the key as live.
    func testAKeyWithAnUnknownBoundIsNotTakenAsLanded() {
        let key = Self.authKey(10)
        let intent = Self.intent([key])
        let unknown = Self.snapshot([Self.onPlatform(key, boundKnown: false)])
        XCTAssertFalse(AppConnect.hasLanded(intent, in: unknown))
        XCTAssertEqual(AppConnect.status(of: intent, in: unknown), .active(expiresAt: key.expiresAt))
        XCTAssertTrue(AppConnect.hasLanded(intent, in: Self.snapshot([Self.onPlatform(key)])))
    }
}
