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

    /// The plan of a disconnect whose question listed every unrecorded key
    /// it offered, as the user confirms it.
    private static func planTurningOffOffered(appId: Data, snapshot: Snapshot, intents: [Intent]) -> AppConnect.DisconnectPlan {
        let asked = AppConnect.disconnectPlan(appId: appId, snapshot: snapshot, intents: intents, owners: [:], listedUnrecordedKeyIds: nil)
        return AppConnect.disconnectPlan(
            appId: appId, snapshot: snapshot, intents: intents, owners: [:], listedUnrecordedKeyIds: Set(asked.offeredUnrecorded))
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
            Self.planTurningOffOffered(appId: Self.dashPay, snapshot: snapshot, intents: []).disable,
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
            appId: Self.app, snapshot: snapshot, intents: [landed, waiting, dead], owners: [:], listedUnrecordedKeyIds: nil)
        XCTAssertEqual(plan.disable, [10, 11])
        XCTAssertEqual(plan.fence, [12])
        XCTAssertEqual(plan.deleteResponses, [landed.id])
    }

    func testAPartlyLandedIntentIsFencedOnlyWhileAKeyIsMissing() {
        let intent = Self.intent([Self.authKey(10), Self.authKey(11)])
        let plan = AppConnect.disconnectPlan(
            appId: Self.app, snapshot: Self.snapshot([Self.onPlatform(Self.authKey(10))]), intents: [intent],
            owners: [:], listedUnrecordedKeyIds: nil)
        XCTAssertEqual(plan.disable, [10])
        XCTAssertEqual(plan.fence, [11])
    }

    func testUnrecordedAppKeysAreTurnedOffOnlyWhenTheUserSaysSo() {
        let intent = Self.intent([Self.authKey(10)])
        let stray = Self.onPlatform(Self.authKey(20))
        let snapshot = Self.snapshot([Self.onPlatform(Self.authKey(10)), stray])
        XCTAssertEqual(
            AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], owners: [:], listedUnrecordedKeyIds: nil).disable,
            [10])
        XCTAssertEqual(
            Self.planTurningOffOffered(appId: Self.app, snapshot: snapshot, intents: [intent]).disable,
            [10, 20])
    }

    func testADisconnectLeavesOtherAppsAndOtherIdentitiesAlone() {
        let mine = Self.intent([Self.authKey(10)])
        let otherApps = Self.intent([Self.authKey(11)], app: Self.otherApp)
        let otherIdentity = Self.intent([Self.authKey(12)], identity: Self.otherIdentity)
        let snapshot = Self.snapshot([Self.onPlatform(Self.authKey(10)), Self.onPlatform(Self.authKey(11))])
        let plan = AppConnect.disconnectPlan(
            appId: Self.app, snapshot: snapshot, intents: [mine, otherApps, otherIdentity], owners: [:], listedUnrecordedKeyIds: nil)
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
                Self.planTurningOffOffered(appId: app, snapshot: snapshot, intents: [mine, theirs]).disable,
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
                Self.planTurningOffOffered(appId: app, snapshot: Self.snapshot([stray]), intents: [mine, gone]).disable,
                [20], "a disconnect of either app turns it off")
        }
    }

    func testALiveKeyOfAnIntentWithATakenIdStaysActionable() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let intent = Self.intent([a, b])
        let snapshot = Self.snapshot([Self.onPlatform(a), Self.onPlatform(b, data: Data(repeating: 9, count: 20))])
        let projection = AppConnect.project([snapshot], intents: [intent])
        XCTAssertEqual(projection.connections.first?.status, .active(expiresAt: Self.now + 1000), "the app keeps a row")
        let plan = AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], owners: [:], listedUnrecordedKeyIds: nil)
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
            AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], owners: [:], listedUnrecordedKeyIds: nil).disable,
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
            AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], owners: [:], listedUnrecordedKeyIds: nil).fence,
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

    // MARK: Owners

    private static let sibling = Data(repeating: 0xC1, count: 32)
    private static let siblingGroup = Data(repeating: 0xC2, count: 32)
    private static let withdrawals = Data.identifier(fromBase58: "4fJLR2GYTPFdomuTVvNy3VRrvWgvkKPzqehEBpNf2nk6")!

    /// The owners asked about are those of the apps with an intent on the
    /// identity and of the bounds of unrecorded keys no intent names by
    /// contract, never of a system contract.
    func testTheOwnersNeededAreTheAppsHereAndTheBoundsOfUnrecordedKeysNoIntentNames() {
        let own = Self.authKey(10)
        let x = Self.intent([own])
        let z = Self.intent([Self.authKey(11, bound: .singleContract(Self.sibling))], app: Self.otherApp)
        let elsewhere = Self.intent([Self.authKey(12, bound: .singleContract(Self.sibling))], identity: Self.otherIdentity)
        func stray(_ bound: AppConnect.StoredBound, boundKnown: Bool = true, expiresAt: UInt64? = AppConnectProjectionTests.now + 1000) -> AppConnect.PlatformKey {
            Self.onPlatform(Self.authKey(20, bound: bound, expiresAt: expiresAt), boundKnown: boundKnown)
        }
        struct Case {
            let name: String
            let keys: [AppConnect.PlatformKey]
            let intents: [Intent]
            let expected: Set<Data>
            init(_ name: String, _ keys: [AppConnect.PlatformKey], _ intents: [Intent], _ expected: Set<Data>) {
                (self.name, self.keys, self.intents, self.expected) = (name, keys, intents, expected)
            }
        }
        let cases: [Case] = [
            Case("a key on a sibling contract", [Self.onPlatform(own), stray(.singleContract(Self.sibling))], [x], [Self.app, Self.sibling]),
            Case("a key on a contract an intent of another app here names", [stray(.singleContract(Self.sibling))], [x, z], []),
            Case("a key on a contract only an intent on another identity names", [stray(.singleContract(Self.sibling))], [x, elsewhere], []),
            Case("a key on a document type of a sibling", [stray(.documentType(contractId: Self.sibling, name: "note"))], [x], [Self.app, Self.sibling]),
            Case("a key on a contract group", [stray(.contractGroup(Self.siblingGroup))], [x], [Self.app, Self.siblingGroup]),
            Case("a DashPay profile key", [stray(.documentType(contractId: Self.dashPay, name: "profile"))], [x], []),
            Case("a key on another system contract", [stray(.singleContract(Self.withdrawals))], [x], []),
            Case("a key whose bound the store does not hold", [stray(.singleContract(Self.sibling), boundKnown: false)], [x], []),
            Case("a key not in an App Connect shape", [stray(.singleContract(Self.sibling), expiresAt: nil)], [x], []),
            Case("no unrecorded key", [Self.onPlatform(own)], [x], []),
            Case("a key on the contract of an app whose intent is on another identity", [stray(.singleContract(Self.app))], [Self.intent([own], identity: Self.otherIdentity)], []),
            Case("an app with an intent only on another identity", [stray(.singleContract(Self.sibling))], [Self.intent([own], identity: Self.otherIdentity)], []),
            Case("no intent at all", [stray(.singleContract(Self.sibling))], [], []),
        ]
        for c in cases {
            XCTAssertEqual(AppConnect.ownerIdsNeeded(snapshot: Self.snapshot(c.keys), intents: c.intents), c.expected, c.name)
        }
    }

    private static let ownerX = Data(repeating: 0x0A, count: 32)
    private static let ownerW = Data(repeating: 0x0B, count: 32)
    private static let sibling2 = Data(repeating: 0xC3, count: 32)

    /// The one owner rule: a key joins app X only on a known match no other
    /// app here shares, and an unknown owner is never a match or a mismatch.
    func testTheOwnerRuleAttributesOnlyOnAKnownMatchNoOtherAppShares() {
        let x = Self.app, z = Self.otherApp, y = Self.sibling, system = AppConnect.systemContractOwnerId
        struct Case {
            let name: String
            let owners: [Data: Data]
            let apps: Set<Data>
            let expected: AppConnect.OwnerOutcome
            init(_ name: String, _ owners: [Data: Data], _ apps: Set<Data>, _ expected: AppConnect.OwnerOutcome) {
                (self.name, self.owners, self.apps, self.expected) = (name, owners, apps, expected)
            }
        }
        let cases: [Case] = [
            Case("known match, no other app", [y: Self.ownerX, x: Self.ownerX], [x], .attributed),
            Case("known match, other app of another owner", [y: Self.ownerX, x: Self.ownerX, z: Self.ownerW], [x, z], .attributed),
            Case("known mismatch", [y: Self.ownerW, x: Self.ownerX], [x], .notThisApp),
            Case("bound owner unknown", [x: Self.ownerX], [x], .notChecked),
            Case("app owner unknown", [y: Self.ownerX], [x], .notChecked),
            Case("app owner unknown, bound of another known owner", [y: Self.ownerW], [x], .notChecked),
            Case("both unknown", [:], [x], .notChecked),
            Case("another app here has the same owner", [y: Self.ownerX, x: Self.ownerX, z: Self.ownerX], [x, z], .notAttributable),
            Case("another app here has an unknown owner", [y: Self.ownerX, x: Self.ownerX], [x, z], .notChecked),
            Case("bound owned by the system", [y: system, x: system], [x], .notThisApp),
            Case("bound owned by the system, app owner unknown", [y: system], [x], .notThisApp),
        ]
        for c in cases {
            XCTAssertEqual(AppConnect.ownerOutcome(of: y, for: x, among: c.apps, owners: c.owners), c.expected, c.name)
        }
    }

    /// An unrecorded key no intent names by contract shows on the row of the
    /// one app it is attributed to, and on its own contract's row otherwise.
    func testAnUnrecordedKeyShowsUnderTheAppItIsAttributedToAndOnItsOwnRowOtherwise() {
        let x = Self.intent([Self.authKey(10)])
        let z = Self.intent([Self.authKey(11, bound: .singleContract(Self.otherApp))], app: Self.otherApp)
        let onY = Self.onPlatform(Self.authKey(20, bound: .singleContract(Self.sibling)))
        let onYDoc = Self.onPlatform(Self.authKey(20, bound: .documentType(contractId: Self.sibling, name: "note")))
        let onGroup = Self.onPlatform(Self.authKey(20, bound: .contractGroup(Self.siblingGroup)))
        let onY2 = Self.onPlatform(Self.authKey(21, bound: .singleContract(Self.sibling2)))
        let onWithdrawals = Self.onPlatform(Self.authKey(20, bound: .singleContract(Self.withdrawals)))
        let match: [Data: Data] = [Self.sibling: Self.ownerX, Self.app: Self.ownerX]
        struct Case {
            let name: String
            let keys: [AppConnect.PlatformKey]
            let intents: [Intent]
            let owners: [Data: Data]
            let rows: [Data: [UInt32]]
            init(_ name: String, _ keys: [AppConnect.PlatformKey], _ intents: [Intent], _ owners: [Data: Data], _ rows: [Data: [UInt32]]) {
                (self.name, self.keys, self.intents, self.owners, self.rows) = (name, keys, intents, owners, rows)
            }
        }
        let cases: [Case] = [
            Case("no owners: as today", [onY], [x], [:], [Self.sibling: [20]]),
            Case("known match (AC-03)", [onY], [x], match, [Self.app: [20]]),
            Case("known match on a document type", [onYDoc], [x], match, [Self.app: [20]]),
            Case("known match on a contract group", [onGroup], [x], [Self.siblingGroup: Self.ownerX, Self.app: Self.ownerX], [Self.app: [20]]),
            Case("bound owner unknown (AC-05)", [onY], [x], [Self.app: Self.ownerX], [Self.sibling: [20]]),
            Case("known mismatch (AC-06)", [onY], [x], [Self.sibling: Self.ownerW, Self.app: Self.ownerX], [Self.sibling: [20]]),
            Case("two apps of one owner (AC-07)", [onY], [x, z], match.merging([Self.otherApp: Self.ownerX]) { a, _ in a }, [Self.sibling: [20]]),
            Case("another app's owner unknown (AC-12)", [onY], [x, z], match, [Self.sibling: [20]]),
            Case("other app of another owner", [onY], [x, z], match.merging([Self.otherApp: Self.ownerW]) { a, _ in a }, [Self.app: [20]]),
            Case("bound owned by the system (AC-09)", [onY], [x], [Self.sibling: AppConnect.systemContractOwnerId, Self.app: Self.ownerX], [Self.sibling: [20]]),
            Case("no intent of that owner (AC-10)", [onY, onY2], [], [Self.sibling: Self.ownerX, Self.sibling2: Self.ownerX], [Self.sibling: [20], Self.sibling2: [21]]),
            Case("system contract of the app's owner (AC-09)", [onWithdrawals], [x], [Self.withdrawals: Self.ownerX, Self.app: Self.ownerX], [:]),
        ]
        for c in cases {
            let projection = AppConnect.project([Self.snapshot(c.keys)], intents: c.intents, owners: c.owners)
            let rows = Dictionary(uniqueKeysWithValues: projection.connections.compactMap { row in
                row.unrecordedKeyIds[Self.identity].map { (row.appId, $0) }
            })
            XCTAssertEqual(rows, c.rows, c.name)
        }
    }

    /// A disconnect of X turns off only its intent keys and the unrecorded
    /// keys the question listed that are still X's, and sorts every other
    /// key that may be X's into what the result reports.
    func testADisconnectTurnsOffOnlyListedKeysStillTheAppsAndReportsTheRest() {
        let own = Self.authKey(10)
        let x = Self.intent([own]), z = Self.intent([Self.authKey(11, bound: .singleContract(Self.otherApp))], app: Self.otherApp)
        func onY(_ bound: AppConnect.StoredBound = .singleContract(AppConnectProjectionTests.sibling), disabledAt: UInt64? = nil, boundKnown: Bool = true) -> AppConnect.PlatformKey {
            Self.onPlatform(Self.authKey(20, bound: bound), disabledAt: disabledAt, boundKnown: boundKnown)
        }
        let match: [Data: Data] = [Self.sibling: Self.ownerX, Self.app: Self.ownerX]
        struct Case {
            let name: String
            let keys: [AppConnect.PlatformKey]
            let intents: [Intent]
            let owners: [Data: Data]
            let listed: Set<UInt32>?
            /// disable, offered, notChecked, notAttributable, leftAfterQuestion
            let expected: [[UInt32]]
            init(_ name: String, _ keys: [AppConnect.PlatformKey], _ intents: [Intent], _ owners: [Data: Data],
                 _ listed: Set<UInt32>?, _ expected: [[UInt32]]) {
                (self.name, self.keys, self.intents, self.owners, self.listed, self.expected) = (name, keys, intents, owners, listed, expected)
            }
        }
        let cases: [Case] = [
            Case("AC-01 question: offered, none turned off", [Self.onPlatform(own), onY()], [x], match, nil, [[10], [20], [], [], []]),
            Case("AC-01 confirmed", [Self.onPlatform(own), onY()], [x], match, [20], [[10, 20], [20], [], [], []]),
            Case("AC-01 document type", [Self.onPlatform(own), onY(.documentType(contractId: Self.sibling, name: "note"))], [x], match, [20],
                 [[10, 20], [20], [], [], []]),
            Case("AC-02 contract group", [Self.onPlatform(own), onY(.contractGroup(Self.siblingGroup))], [x],
                 [Self.siblingGroup: Self.ownerX, Self.app: Self.ownerX], [20], [[10, 20], [20], [], [], []]),
            Case("AC-04 owner unread", [Self.onPlatform(own), onY()], [x], [Self.app: Self.ownerX], nil, [[10], [], [20], [], []]),
            Case("AC-04 owner unread after the question listed it", [Self.onPlatform(own), onY()], [x], [Self.app: Self.ownerX], [20],
                 [[10], [], [20], [], []]),
            Case("AC-06 another owner", [Self.onPlatform(own), onY()], [x], [Self.sibling: Self.ownerW, Self.app: Self.ownerX], [20],
                 [[10], [], [], [], []]),
            Case("AC-07 two apps of one owner", [Self.onPlatform(own), onY()], [x, z], match.merging([Self.otherApp: Self.ownerX]) { a, _ in a }, nil,
                 [[10], [], [], [20], []]),
            Case("AC-08 attributed only after the question", [Self.onPlatform(own), onY()], [x], match, [], [[10], [20], [], [], [20]]),
            Case("AC-11 unplaced key", [Self.onPlatform(own), onY(boundKnown: false)], [x], match, [20], [[10], [], [20], [], []]),
            Case("AC-12 another app's owner unknown", [Self.onPlatform(own), onY()], [x, z], match, nil, [[10], [], [20], [], []]),
            Case("a listed key no longer live", [Self.onPlatform(own), onY(disabledAt: 1)], [x], match, [20], [[10], [], [], [], []]),
            Case("a listed id no key has", [Self.onPlatform(own)], [x], match, [20, 99], [[10], [], [], [], []]),
            Case("only unknown owners still turn off the app's keys", [Self.onPlatform(own), onY()], [x], [:], [20], [[10], [], [20], [], []]),
            Case("AC-09 system contract of the app's owner", [Self.onPlatform(own), onY(.singleContract(Self.withdrawals))], [x],
                 [Self.withdrawals: Self.ownerX, Self.app: Self.ownerX], [20], [[10], [], [], [], []]),
        ]
        for c in cases {
            let plan = AppConnect.disconnectPlan(
                appId: Self.app, snapshot: Self.snapshot(c.keys), intents: c.intents, owners: c.owners, listedUnrecordedKeyIds: c.listed)
            XCTAssertEqual(
                [plan.disable, plan.offeredUnrecorded, plan.notChecked, plan.notAttributable, plan.leftAfterQuestion], c.expected, c.name)
            XCTAssertTrue(Set(plan.disable).isSubset(of: Set(x.keys.map(\.id)).union(c.listed ?? [])), "\(c.name): nothing beyond the list")
        }
    }

    /// A row whose app has no intent on the identity is the contract the
    /// user named: its disconnect offers every key placed on that contract,
    /// whatever owner has been read since the row was shown, and turns off
    /// only the listed ones.
    func testADisconnectOfARowWithoutAnIntentOffersItsKeysWhateverTheirOwner() {
        let own = Self.authKey(10)
        let x = Self.intent([own])
        let onY = Self.onPlatform(Self.authKey(20, bound: .singleContract(Self.sibling)))
        let onY2 = Self.onPlatform(Self.authKey(21, bound: .singleContract(Self.sibling2)))
        let match: [Data: Data] = [Self.sibling: Self.ownerX, Self.app: Self.ownerX]
        struct Case {
            let name: String
            let keys: [AppConnect.PlatformKey]
            let intents: [Intent]
            let owners: [Data: Data]
            let listed: Set<UInt32>?
            /// disable, offered
            let expected: [[UInt32]]
            init(_ name: String, _ keys: [AppConnect.PlatformKey], _ intents: [Intent], _ owners: [Data: Data],
                 _ listed: Set<UInt32>?, _ expected: [[UInt32]]) {
                (self.name, self.keys, self.intents, self.owners, self.listed, self.expected) = (name, keys, intents, owners, listed, expected)
            }
        }
        let cases: [Case] = [
            Case("owner unread when shown, read now: question", [Self.onPlatform(own), onY], [x], match, nil, [[], [20]]),
            Case("owner unread when shown, read now: confirmed", [Self.onPlatform(own), onY], [x], match, [20], [[20], [20]]),
            Case("owner still unread", [Self.onPlatform(own), onY], [x], [Self.app: Self.ownerX], [20], [[20], [20]]),
            Case("another owner", [Self.onPlatform(own), onY], [x], [Self.sibling: Self.ownerW, Self.app: Self.ownerX], [20], [[20], [20]]),
            Case("no intent here (AC-10)", [onY, onY2], [], [:], [20], [[20], [20]]),
        ]
        for c in cases {
            let plan = AppConnect.disconnectPlan(
                appId: Self.sibling, snapshot: Self.snapshot(c.keys), intents: c.intents, owners: c.owners, listedUnrecordedKeyIds: c.listed)
            XCTAssertEqual([plan.disable, plan.offeredUnrecorded], c.expected, c.name)
        }
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
