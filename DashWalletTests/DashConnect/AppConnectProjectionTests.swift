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
        _ id: UInt32, data: UInt8? = nil, bound: AppConnect.StoredBound? = .singleContract(app), expiresAt: UInt64? = now + 1000,
        budget: UInt64? = 1000
    ) -> Key {
        Key(id: id, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: data ?? UInt8(truncatingIfNeeded: id), count: 20), readOnly: false, bound: bound,
            totalBudget: budget, expiresAt: expiresAt)
    }

    private static func encryptionKey(_ id: UInt32) -> Key {
        Key(id: id, purpose: .encryption, securityLevel: .medium, keyType: .ecdsaSecp256k1,
            data: Data(repeating: UInt8(id), count: 33), readOnly: false, bound: .singleContract(app),
            totalBudget: nil, expiresAt: nil)
    }

    /// The key as Platform shows it once its update landed.
    private static func onPlatform(
        _ key: Key, disabledAt: UInt64? = nil, boundKnown: Bool = true, data: Data? = nil,
        limits: (totalBudget: UInt64?, expiresAt: UInt64?)? = nil
    ) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType,
            data: data ?? key.data, readOnly: key.readOnly, bound: boundKnown ? key.bound : nil,
            boundKnown: boundKnown, totalBudget: limits.map(\.totalBudget) ?? key.totalBudget,
            expiresAt: limits.map(\.expiresAt) ?? key.expiresAt, disabledAt: disabledAt)
    }

    private static func intent(
        _ keys: [Key], app: Data = app, identity: Data = identity, published: Bool = false, createdAt: TimeInterval = 0,
        refusal: AppConnect.ConsensusRefusal? = nil, removedAt: Date? = nil, label: String = "App", url: String = ""
    ) -> Intent {
        var intent = Intent(
            id: UUID(), identityId: identity, appId: app, appLabel: label, appUrl: url, requestHash: Data(repeating: 0xEE, count: 20),
            connectionId: nil, keys: keys, sentEncryptionKeyIds: [], disables: [],
            response: AppConnect.ResponseValues(appEphemeralPubKeyHash: "ee", walletEphemeralPubKey: "02", encryptedPayload: "00"),
            responseDocumentId: published ? Data(repeating: 0xDD, count: 32) : nil, responseRemoved: !published, createdAt: Date(timeIntervalSince1970: createdAt), closedAt: nil)
        intent.refusal = refusal
        intent.removedAt = removedAt
        return intent
    }

    private static func snapshot(
        _ keys: [AppConnect.PlatformKey], identity: Data = identity, revision: UInt64 = 5, time: UInt64? = now
    ) -> Snapshot {
        Snapshot(identityId: identity, revision: revision, keys: keys, platformTime: time)
    }

    // MARK: What a connection gave

    func testTheAccessOfAConnectionIsWhatItsIntentsAdded() {
        let profile = Self.authKey(11, bound: .documentType(contractId: Self.dashPay, name: "profile"))
        var group = Self.intent([Self.authKey(12, bound: .contractGroup(Self.appGroup), expiresAt: Self.now + 5000)])
        group.administeredGroupIds = [Self.appGroup]
        let access = ConnectionAccess(intents: [Self.intent([Self.authKey(10), profile, Self.encryptionKey(13)]), group])

        XCTAssertEqual(access?.keys.map(\.bound), [.singleContract(Self.app), profile.bound!, .contractGroup(Self.appGroup)])
        XCTAssertEqual(access?.keys.map(\.isAdministered), [false, false, true])
        XCTAssertEqual(access?.budgetLimit, 3000, "three keys of 1000, each spent apart")
        XCTAssertEqual(access?.hasUnlimitedKey, false)
        XCTAssertEqual(access?.expiresAt, Date(timeIntervalSince1970: TimeInterval(Self.now + 5000) / 1000))
        XCTAssertEqual(access?.receivesMessages, true, "an encryption key it added")
        XCTAssertNil(ConnectionAccess(intents: [Self.intent([Self.encryptionKey(13)])]), "no auth key, nothing to show")
    }

    func testAConnectionReceivesMessagesWhenItsResponseCarriesAnEncryptionKey() {
        let added = ConnectionAccess(intents: [Self.intent([Self.authKey(10)])])
        XCTAssertEqual(added?.receivesMessages, false)
        var sent = Self.intent([Self.authKey(10)])
        sent = Intent(
            id: sent.id, identityId: sent.identityId, appId: sent.appId, appLabel: sent.appLabel, appUrl: sent.appUrl,
            requestHash: sent.requestHash, connectionId: nil, keys: sent.keys, sentEncryptionKeyIds: [3], disables: [],
            response: sent.response, responseDocumentId: nil, responseRemoved: true, createdAt: sent.createdAt, closedAt: nil)
        XCTAssertEqual(ConnectionAccess(intents: [sent])?.receivesMessages, true, "the identity's key, sent again")
    }

    func testEachAuthKeyIsListedOnceWithWhatIsLeftOfItsBudget() {
        let profile = Self.authKey(11, bound: .documentType(contractId: Self.dashPay, name: "profile"))
        let first = Self.intent([Self.authKey(10), profile, Self.encryptionKey(13)])
        let snapshot = Self.snapshot([Self.onPlatform(Self.authKey(10)), Self.onPlatform(profile)])
        let funding = KeyFunding.of(
            intents: [first, Self.intent([Self.authKey(10)])], snapshot: snapshot, remaining: [10: 400, 11: nil])
        XCTAssertEqual(funding, [
            KeyFunding(isProfileKey: false, totalBudget: 1000, remaining: 400),
            KeyFunding(isProfileKey: true, totalBudget: 1000, remaining: nil),
        ])
    }

    /// A connection gives what its keys on Platform give: a disabled or
    /// taken key gives nothing, even in an intent with a live key, and a
    /// key that landed gives its limits as Platform holds them now, which an
    /// authorized limits update may have raised.
    func testAConnectionGivesWhatItsKeysOnPlatformGive() {
        let app = Self.authKey(10)
        let profile = Self.authKey(11, bound: .documentType(contractId: Self.dashPay, name: "profile"))
        let taken = Self.authKey(12, bound: .contractGroup(Self.appGroup))
        let intent = Self.intent([app, profile, taken])
        let snapshot = Self.snapshot([
            Self.onPlatform(app, limits: (2000, Self.now + 9000)),
            Self.onPlatform(profile, disabledAt: Self.now - 10),
            Self.onPlatform(taken, data: Data(repeating: 0x77, count: 20)),
        ])

        let access = ConnectionAccess(intents: [intent], snapshot: snapshot)
        XCTAssertEqual(access?.keys.map(\.bound), [.singleContract(Self.app)], "not the disabled profile key nor the taken id")
        XCTAssertEqual(access?.keys.first?.totalBudget, 2000, "the budget Platform holds now")
        XCTAssertEqual(access?.expiresAt, Date(timeIntervalSince1970: TimeInterval(Self.now + 9000) / 1000))
        XCTAssertEqual(
            KeyFunding.of(intents: [intent], snapshot: snapshot, remaining: [10: 1500, 11: 900]),
            [KeyFunding(isProfileKey: false, totalBudget: 2000, remaining: 1500)],
            "no funding line for the disabled key")
        let unlimited = Self.snapshot([Self.onPlatform(app, limits: (nil, Self.now + 9000))])
        XCTAssertEqual(ConnectionAccess(intents: [intent], snapshot: unlimited)?.hasUnlimitedKey, true, "no limit now")
    }

    /// Keys that have not landed show the terms the wallet submitted while
    /// the update may still land, and nothing once another key landed in
    /// their place.
    func testKeysThatHaveNotLandedShowTheSubmittedTermsWhileTheyMayLand() {
        let confirming = Self.intent([Self.authKey(10), Self.authKey(11, bound: .contractGroup(Self.appGroup))])
        let access = ConnectionAccess(intents: [confirming], snapshot: Self.snapshot([]))
        XCTAssertEqual(access?.keys.count, 2)
        XCTAssertEqual(access?.keys.first?.totalBudget, 1000)
        XCTAssertNil(ConnectionAccess(intents: [Self.intent([Self.authKey(10)])], snapshot: Self.snapshot([
            Self.onPlatform(Self.authKey(10), data: Data(repeating: 0x77, count: 20)),
        ])), "its id is taken: it can never land")
    }

    /// Platform counts each key's budget apart, so what an app may spend at
    /// most is their sum, not the largest one; a key named twice counts once.
    func testTheFundingLimitIsTheSumOfTheKeysBudgets() {
        let first = Self.authKey(10, budget: 500)
        let second = Self.authKey(11, bound: .contractGroup(Self.appGroup), budget: 500)
        let access = ConnectionAccess(intents: [Self.intent([first, second]), Self.intent([first])])
        XCTAssertEqual(access?.budgetLimit, 1000)
        XCTAssertEqual(access?.hasUnlimitedKey, false)
    }

    func testAnIntentWrittenBeforeItNotedAdministeredGroupsIsStillRead() throws {
        var intent = Self.intent([Self.authKey(12, bound: .contractGroup(Self.appGroup))])
        intent.administeredGroupIds = [Self.appGroup]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        json.removeValue(forKey: "administeredGroupIds")
        let read = try JSONDecoder().decode(Intent.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(read.administeredGroupIds)
        XCTAssertFalse(read.isAdministered(.contractGroup(Self.appGroup)), "not known, so not said")
    }

    // MARK: The Disconnected list (ADR 0013)

    /// A Disconnected row is listed with what the intents its last
    /// disconnect marked gave the app, and when that disconnect ran; an
    /// earlier marked connection and an unmarked intent do not count.
    func testADisconnectedEntryReadsTheIntentsTheLastDisconnectMarked() {
        var earlier = Self.intent([Self.authKey(10)], createdAt: 100)
        earlier.disconnectedAt = Date(timeIntervalSince1970: 200)
        var last = Self.intent([Self.authKey(11, bound: .contractGroup(Self.appGroup))], createdAt: 300)
        last.disconnectedAt = Date(timeIntervalSince1970: 400)
        let unmarked = Self.intent([Self.authKey(12)], createdAt: 350)
        let other = { () -> Intent in
            var other = Self.intent([Self.authKey(13)], app: Data(repeating: 0xB2, count: 32), createdAt: 500)
            other.disconnectedAt = Date(timeIntervalSince1970: 600)
            return other
        }()
        let row = DAppConnection(
            id: Self.app.toBase58String(), name: "App", url: "app.example", status: .disconnected,
            updatedAt: Date(timeIntervalSince1970: 1))

        let entry = PlatformDashConnectDataSource.disconnectedEntry(of: row, intents: [earlier, last, unmarked, other])

        XCTAssertEqual(entry.disconnectedAt, Date(timeIntervalSince1970: 400))
        XCTAssertEqual(entry.connectedAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(entry.access?.keys.map(\.bound), [.contractGroup(Self.appGroup)])
        XCTAssertEqual(entry.identityId, Self.identity.toBase58String())
    }

    // MARK: The disconnect mark (T35)

    /// T35 (G1): an open intent a disconnect ran on, whose id the fence now
    /// holds, is Disconnected; with no mark it is Never landed.
    func testAnOpenIntentADisconnectRanOnWhoseIdAnotherKeyHoldsIsDisconnected() {
        let a = Self.authKey(10)
        var intent = Self.intent([a])
        let fenced = Self.snapshot([Self.onPlatform(a, disabledAt: Self.now - 1, data: Data(repeating: 0xF0, count: 20))])
        XCTAssertEqual(AppConnect.status(of: intent, in: fenced), .neverLanded)
        intent.disconnectedAt = Date(timeIntervalSince1970: 1)
        XCTAssertEqual(AppConnect.status(of: intent, in: fenced), .disconnected)
    }

    /// T35 (G5): an intent stored before `disconnectedAt` existed still loads,
    /// with no mark; a marked one round-trips.
    func testAnIntentStoredWithoutTheDisconnectMarkLoadsAndAMarkedOneRoundTrips() throws {
        var intent = Self.intent([Self.authKey(10)])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        json.removeValue(forKey: "disconnectedAt")
        let older = try JSONDecoder().decode(Intent.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(older.disconnectedAt)
        XCTAssertEqual(older.id, intent.id)
        intent.disconnectedAt = Date(timeIntervalSince1970: 1_773_132_300)
        XCTAssertEqual(try JSONDecoder().decode(Intent.self, from: JSONEncoder().encode(intent)), intent)
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

    // AC-13: the card is on the tab of the app's latest connection, so a new
    // approval still Confirming shows over an earlier Active one.
    func testAnAppShowsTheStatusOfItsLatestConnection() {
        let old = Self.intent([Self.authKey(10)], createdAt: 1)
        let new = Self.intent([Self.authKey(11)], createdAt: 2)
        let projection = AppConnect.project(
            [Self.snapshot([Self.onPlatform(Self.authKey(10))])], intents: [old, new])
        XCTAssertEqual(projection.connections.count, 1)
        XCTAssertEqual(projection.connections[0].status, .confirming)
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

    func testAProfileKeyNoIntentNamesOnAnIdentityWithNothingElseToDisconnectIsADashPayRow() {
        let profile = Self.authKey(20, bound: .documentType(contractId: Self.dashPay, name: "profile"))
        let off = Self.authKey(21, bound: .singleContract(Self.otherApp))
        let snapshot = Self.snapshot([Self.onPlatform(profile), Self.onPlatform(off, disabledAt: 1)])
        let projection = AppConnect.project([snapshot], intents: [])
        XCTAssertEqual(projection.connections.map(\.appId), [Self.dashPay], "no other disconnect would turn it off")
        XCTAssertEqual(projection.connections.first?.unrecordedKeyIds, [Self.identity: [20]])
        XCTAssertEqual(AppConnect.disconnectPlan(appId: Self.dashPay, snapshot: snapshot, intents: [], owners: [:]).disable, [20])
    }

    func testAProfileKeyNoIntentNamesNextToADisconnectedAppIsADashPayRow() {
        let profile = Self.authKey(20, bound: .documentType(contractId: Self.dashPay, name: "profile"))
        var gone = Self.intent([Self.authKey(10)], published: true)
        gone.closedAt = Date(timeIntervalSince1970: 1)
        let snapshot = Self.snapshot([Self.onPlatform(Self.authKey(10), disabledAt: 1), Self.onPlatform(profile)])
        let projection = AppConnect.project([snapshot], intents: [gone])
        XCTAssertEqual(Set(projection.connections.map(\.appId)), [Self.app, Self.dashPay])
    }

    func testAProfileKeyNoIntentNamesIsNotShownOnAnotherAppsRowEither() {
        let profile = Self.authKey(20, bound: .documentType(contractId: Self.dashPay, name: "profile"))
        let snapshot = Self.snapshot([Self.onPlatform(Self.authKey(10)), Self.onPlatform(profile)])
        let projection = AppConnect.project([snapshot], intents: [Self.intent([Self.authKey(10)])])
        XCTAssertEqual(projection.connections.map(\.appId), [Self.app])
        XCTAssertEqual(projection.connections[0].unrecordedKeyIds, [:])
    }

    func testAKeyAStoreCannotBindIsNotGuessedToBeAnApps() {
        let unknown = Self.onPlatform(Self.authKey(20), boundKnown: false)
        XCTAssertEqual(AppConnect.project([Self.snapshot([unknown])], intents: []).connections, [])
    }

    // MARK: Every status (AC-14, AC-19)

    private static let refusal = AppConnect.ConsensusRefusal(code: 10_212, at: Date(timeIntervalSince1970: 1_773_132_300))
    private static let removedAt = Date(timeIntervalSince1970: 1_773_218_700)

    private static func closed(_ intent: Intent) -> Intent {
        var closed = intent
        closed.closedAt = Date(timeIntervalSince1970: 5)
        return closed
    }

    /// `intent` as a Disconnect leaves one it closed: closed and marked.
    private static func disconnected(_ intent: Intent) -> Intent {
        var disconnected = closed(intent)
        disconnected.disconnectedAt = disconnected.closedAt
        return disconnected
    }

    /// The projected connection of `Self.app` from one read of `Self.identity`.
    private static func connection(
        _ intents: [Intent], _ keys: [AppConnect.PlatformKey], time: UInt64? = now
    ) -> AppConnect.ProjectedConnection? {
        AppConnect.project([snapshot(keys, time: time)], intents: intents).connections.first { $0.appId == app }
    }

    func testEveryStatusIsProjectedFromTheKeysAndTheIntent() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let expired = Self.authKey(10, expiresAt: Self.now - 1)
        let cases: [(String, Intent, [AppConnect.PlatformKey], AppConnect.IntentStatus, Bool)] = [
            ("Active", Self.intent([a, b], published: true), [Self.onPlatform(a)], .active(expiresAt: Self.now + 1000), false),
            ("Confirming", Self.intent([a, b]), [], .confirming, false),
            ("Not delivered", Self.intent([a, b]), [Self.onPlatform(a)], .active(expiresAt: Self.now + 1000), true),
            ("Refused", Self.intent([a, b], refusal: Self.refusal), [], .refused, false),
            ("Expired", Self.intent([expired, b], published: true), [Self.onPlatform(expired), Self.onPlatform(b, disabledAt: 1)], .expired, false),
            ("Disconnected", Self.closed(Self.intent([a, b], published: true)), [Self.onPlatform(a, disabledAt: 1), Self.onPlatform(b, disabledAt: 1)], .disconnected, false),
        ]
        for (name, intent, keys, status, undelivered) in cases {
            let projected = Self.connection([intent], keys)
            XCTAssertEqual(projected?.status, status, name)
            XCTAssertEqual(projected?.isUndelivered, undelivered, name)
        }
    }

    func testMixedKeysOfOneIntentFollowTheAC14Precedence() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let aExpired = Self.authKey(10, expiresAt: Self.now - 1)
        let plain = Self.intent([a, b])
        let expiredIntent = Self.intent([aExpired, b])
        let refused = Self.intent([a, b], refusal: Self.refusal)
        let cases: [(String, Intent, [AppConnect.PlatformKey], AppConnect.IntentStatus)] = [
            ("one live, one off: Active", plain, [Self.onPlatform(a), Self.onPlatform(b, disabledAt: 1)], .active(expiresAt: Self.now + 1000)),
            ("one live, one expired: Active", expiredIntent, [Self.onPlatform(aExpired), Self.onPlatform(b)], .active(expiresAt: Self.now + 1000)),
            ("one expired, one off: Expired, not Disconnected", expiredIntent, [Self.onPlatform(aExpired), Self.onPlatform(b, disabledAt: 1)], .expired),
            ("every key off: Disconnected", plain, [Self.onPlatform(a, disabledAt: 1), Self.onPlatform(b, disabledAt: 1)], .disconnected),
            ("a refusal and a live key: the live key wins", refused, [Self.onPlatform(a)], .active(expiresAt: Self.now + 1000)),
            ("a refusal and both keys live: Active", refused, [Self.onPlatform(a), Self.onPlatform(b)], .active(expiresAt: Self.now + 1000)),
            ("a refusal and no key on Platform: Refused", refused, [], .refused),
        ]
        for (name, intent, keys, expected) in cases {
            XCTAssertEqual(AppConnect.status(of: intent, in: Self.snapshot(keys)), expected, name)
            XCTAssertEqual(Self.connection([intent], keys)?.status, expected, name)
        }
    }

    func testAMixOfLiveAndOffKeysWithNoPublishedResponseIsNotDelivered() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let projected = Self.connection([Self.intent([a, b])], [Self.onPlatform(a), Self.onPlatform(b, disabledAt: 1)])
        XCTAssertEqual(projected?.status, .active(expiresAt: Self.now + 1000))
        XCTAssertEqual(projected?.isUndelivered, true)
    }

    // MARK: Expiry by block time (AC-14)

    func testAKeyIsExpiredFromItsExpiryOnByBlockTime() {
        let key = Self.authKey(10, expiresAt: Self.now)
        let intent = Self.intent([key])
        XCTAssertEqual(Self.connection([intent], [Self.onPlatform(key)])?.status, .expired, "expiry <= block time")
        XCTAssertEqual(
            Self.connection([intent], [Self.onPlatform(key)], time: Self.now - 1)?.status, .active(expiresAt: Self.now),
            "one millisecond before")
    }

    func testAKeyPastItsExpiryByThePhoneClockButNotByBlockTimeIsNotExpired() {
        let key = Self.authKey(10, expiresAt: 1_000_000)
        let projected = Self.connection([Self.intent([key])], [Self.onPlatform(key)], time: 500_000)
        XCTAssertEqual(projected?.status, .active(expiresAt: 1_000_000))
    }

    func testAKeyPastItsExpiryByBlockTimeButNotByThePhoneClockIsExpired() {
        let phone = UInt64(Date().timeIntervalSince1970 * 1000)
        let key = Self.authKey(10, expiresAt: phone + 3_600_000)
        let projected = Self.connection([Self.intent([key])], [Self.onPlatform(key)], time: phone + 7_200_000)
        XCTAssertEqual(projected?.status, .expired)
    }

    func testWithoutPlatformTimeNoConnectionIsExpired() {
        let key = Self.authKey(10, expiresAt: 1)
        let projected = Self.connection([Self.intent([key])], [Self.onPlatform(key)], time: nil)
        XCTAssertEqual(projected?.status, .active(expiresAt: 1))
    }

    // MARK: Refused (AC-14, AC-20b)

    func testARefusalAloneMakesTheConnectionRefused() {
        let refused = Self.intent([Self.authKey(10)], refusal: Self.refusal)
        let projected = Self.connection([refused], [])
        XCTAssertEqual(projected?.status, .refused)
        XCTAssertEqual(projected?.intents.first?.refusal, Self.refusal, "the reason stays on the intent")
    }

    func testAnIntentWithoutARefusalAndNoKeyIsConfirmingNotRefused() {
        XCTAssertEqual(Self.connection([Self.intent([Self.authKey(10)])], [])?.status, .confirming)
    }

    func testARemovedRefusedIntentHasNoRow() {
        let removed = Self.intent([Self.authKey(10)], refusal: Self.refusal, removedAt: Self.removedAt)
        XCTAssertEqual(AppConnect.project([Self.snapshot([])], intents: [removed]).connections, [])
    }

    func testAnIntentWithRemovedAtNeverYieldsADisconnectedEntry() {
        let key = Self.authKey(10)
        let gone = Self.closed(Self.intent([key], removedAt: Self.removedAt))
        XCTAssertEqual(AppConnect.project([Self.snapshot([Self.onPlatform(key, disabledAt: 1)])], intents: [gone]).connections, [])
    }

    // MARK: Recording a refusal and Remove (AC-20b, ADR 0012)

    func testRecordingARefusalOnAnIntentListsItsConnectionAsRefused() {
        let intent = Self.intent([Self.authKey(10), Self.authKey(11)])
        let other = Self.intent([Self.authKey(20)], app: Self.otherApp)
        XCTAssertEqual(Self.connection([intent, other], [])?.status, .confirming)

        let recorded = AppConnect.recordRefusal(Self.refusal, on: intent.id, in: [intent, other])

        XCTAssertEqual(recorded.first { $0.id == intent.id }?.refusal, Self.refusal)
        XCTAssertNil(recorded.first { $0.id == other.id }?.refusal, "only the named intent")
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(Self.connection(recorded, [])?.status, .refused)
    }

    func testRecordingARefusalNamingNoIntentChangesNothing() {
        let intent = Self.intent([Self.authKey(10)])
        XCTAssertEqual(AppConnect.recordRefusal(Self.refusal, on: UUID(), in: [intent]), [intent])
    }

    func testWithoutARecordedRefusalTheConnectionStaysConfirming() {
        let intent = Self.intent([Self.authKey(10)])
        XCTAssertEqual(Self.connection([intent], [])?.status, .confirming)
        XCTAssertNil(intent.refusal)
    }

    func testRemovingARefusedConnectionSetsRemovedAtOnItsRefusedIntentsAndHidesTheRow() throws {
        let refused = Self.intent([Self.authKey(10)], refusal: Self.refusal)
        let other = Self.intent([Self.authKey(20)], app: Self.otherApp)

        let removed = try XCTUnwrap(AppConnect.removing(
            appId: Self.app, intents: [refused, other], snapshots: [Self.snapshot([])], at: Self.removedAt))

        XCTAssertEqual(removed.first { $0.id == refused.id }?.removedAt, Self.removedAt)
        XCTAssertEqual(removed.first { $0.id == refused.id }?.refusal, Self.refusal, "the reason stays")
        XCTAssertNil(removed.first { $0.id == other.id }?.removedAt)
        XCTAssertNil(Self.connection(removed, []), "the row is hidden")
    }

    func testRemovingRefusesAConnectionThatIsNotRefused() {
        let a = Self.authKey(10)
        let cases: [(String, [Intent], [AppConnect.PlatformKey])] = [
            ("Confirming", [Self.intent([a])], []),
            ("Active", [Self.intent([a], published: true, refusal: Self.refusal)], [Self.onPlatform(a)]),
            ("Disconnected", [Self.closed(Self.intent([a], published: true))], [Self.onPlatform(a, disabledAt: 1)]),
            ("no intent of the app", [Self.intent([a], app: Self.otherApp)], []),
        ]
        for (name, intents, keys) in cases {
            XCTAssertNil(
                AppConnect.removing(appId: Self.app, intents: intents, snapshots: [Self.snapshot(keys)], at: Self.removedAt), name)
        }
    }

    func testRemovingALiveKeyIsRefusedEvenWhenTheRefusalIsRecorded() {
        // The live key wins over the recorded refusal (AC-14), so Remove, which
        // writes nothing to Platform, must not hide it.
        let a = Self.authKey(10)
        let intent = Self.intent([a], refusal: Self.refusal)
        XCTAssertNil(AppConnect.removing(
            appId: Self.app, intents: [intent], snapshots: [Self.snapshot([Self.onPlatform(a)])], at: Self.removedAt))
    }

    func testRemovingARefusedConnectionLeavesAnEarlierConnectionOfTheAppOnItsOwnTab() throws {
        let (earlier, earlierKeys) = disconnectedEarlier()
        let refused = Self.intent([Self.authKey(30)], createdAt: 2, refusal: Self.refusal)
        XCTAssertEqual(Self.connection([earlier, refused], earlierKeys)?.status, .refused)

        let removed = try XCTUnwrap(AppConnect.removing(
            appId: Self.app, intents: [earlier, refused], snapshots: [Self.snapshot(earlierKeys)], at: Self.removedAt))

        XCTAssertNil(removed.first { $0.id == earlier.id }?.removedAt, "the earlier connection is not removed")
        XCTAssertEqual(Self.connection(removed, earlierKeys)?.status, .disconnected, "it is not moved to Disconnected either")
        XCTAssertEqual(Self.connection(removed, earlierKeys)?.intents.map(\.id), [earlier.id])
    }

    // MARK: The Disconnected entry and its give-way rules (AC-19)

    private func disconnectedEarlier() -> (Intent, [AppConnect.PlatformKey]) {
        let old = Self.authKey(10)
        return (Self.closed(Self.intent([old], published: true, createdAt: 1)), [Self.onPlatform(old, disabledAt: 1)])
    }

    func testADisconnectedEntryNeedsEveryKeyOffNotJustClosedAt() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let closed = Self.closed(Self.intent([a, b], published: true))
        XCTAssertEqual(
            Self.connection([closed], [Self.onPlatform(a, disabledAt: 1), Self.onPlatform(b)])?.status,
            .active(expiresAt: Self.now + 1000))
        XCTAssertEqual(
            Self.connection([closed], [Self.onPlatform(a, disabledAt: 1), Self.onPlatform(b, disabledAt: 1)])?.status,
            .disconnected)
    }

    func testKeysGivenOnAnotherDeviceThenTurnedOffMakeNoDisconnectedEntry() {
        let stray = Self.onPlatform(Self.authKey(20), disabledAt: 1)
        XCTAssertEqual(AppConnect.project([Self.snapshot([stray])], intents: []).connections, [])
    }

    func testTheDisconnectedEntryGivesWayToANewerConnectionThatIsConfirmingNotDeliveredActiveOrExpired() {
        let (earlier, off) = disconnectedEarlier()
        let new = Self.authKey(11)
        let newExpired = Self.authKey(12, expiresAt: Self.now - 1)
        let cases: [(String, Intent, [AppConnect.PlatformKey], AppConnect.IntentStatus, Bool)] = [
            ("Confirming", Self.intent([new], createdAt: 2), [], .confirming, false),
            ("Not delivered", Self.intent([new], createdAt: 2), [Self.onPlatform(new)], .active(expiresAt: Self.now + 1000), true),
            ("Active", Self.intent([new], published: true, createdAt: 2), [Self.onPlatform(new)], .active(expiresAt: Self.now + 1000), false),
            ("Expired", Self.intent([newExpired], published: true, createdAt: 2), [Self.onPlatform(newExpired)], .expired, false),
        ]
        for (name, newer, keys, status, undelivered) in cases {
            let projected = Self.connection([earlier, newer], off + keys)
            XCTAssertEqual(projected?.status, status, name)
            XCTAssertEqual(projected?.isUndelivered, undelivered, name)
            XCTAssertEqual(AppConnect.project([Self.snapshot(off + keys)], intents: [earlier, newer]).connections.count, 1, "one card per app: \(name)")
        }
    }

    func testARemovedRefusedAttemptAfterADisconnectedOneLeavesTheDisconnectedEntry() {
        let (earlier, off) = disconnectedEarlier()
        let removed = Self.intent([Self.authKey(11)], createdAt: 2, refusal: Self.refusal, removedAt: Self.removedAt)
        let projection = AppConnect.project([Self.snapshot(off)], intents: [earlier, removed])
        XCTAssertEqual(projection.connections.map(\.status), [.disconnected])
    }

    func testAnUnremovedRefusedAttemptAfterADisconnectedOneIsShownRefused() {
        let (earlier, off) = disconnectedEarlier()
        let refused = Self.intent([Self.authKey(11)], createdAt: 2, refusal: Self.refusal)
        XCTAssertEqual(Self.connection([earlier, refused], off)?.status, .refused)
    }

    // T22 (R10): rewritten from `testARefusedAttemptDoesNotHideAnEarlierConnectionTheUserCanActOn`, which pinned
    // the old "most actionable status wins" rule (older Active + newer Refused showed Active). The card follows the
    // app's latest intent (AC-13), so the Refused attempt shows and can be Removed (AC-20b).
    func testTheCardFollowsTheLatestIntentOfTheApp() {
        let live = Self.authKey(10)
        let expired = Self.authKey(12, expiresAt: Self.now - 1)
        let activeThenRefused = [
            Self.intent([live], published: true, createdAt: 1),
            Self.intent([Self.authKey(11)], createdAt: 2, refusal: Self.refusal),
        ]
        let expiredThenRefused = [
            Self.intent([expired], published: true, createdAt: 1),
            Self.intent([Self.authKey(11)], createdAt: 2, refusal: Self.refusal),
        ]
        let refusedThenActive = [
            Self.intent([Self.authKey(11)], createdAt: 1, refusal: Self.refusal),
            Self.intent([live], published: true, createdAt: 2),
        ]
        let cases: [(String, [Intent], [AppConnect.PlatformKey], AppConnect.IntentStatus)] = [
            ("older Active, newer Refused", activeThenRefused, [Self.onPlatform(live)], .refused),
            ("older Active, newer Refused (input order reversed)", activeThenRefused.reversed(), [Self.onPlatform(live)], .refused),
            ("older Expired, newer Refused", expiredThenRefused, [Self.onPlatform(expired)], .refused),
            ("older Refused, newer Active", refusedThenActive, [Self.onPlatform(live)], .active(expiresAt: Self.now + 1000)),
        ]
        for (name, intents, keys, expected) in cases {
            XCTAssertEqual(Self.connection(intents, keys)?.status, expected, name)
            XCTAssertEqual(AppConnect.project([Self.snapshot(keys)], intents: intents).connections.count, 1, "one card: \(name)")
        }
    }

    // T30 (F1): a newer intent with no access left of its own (Never landed, Disconnected) does not hide the
    // older Active connection whose keys are live (AC-13, AC-14, AC-16).
    func testANewerIntentWithNoAccessLeftDoesNotHideAnOlderActiveConnection() {
        let live = Self.authKey(10)
        let older = Self.intent([live], published: true, createdAt: 1)
        let active = AppConnect.IntentStatus.active(expiresAt: Self.now + 1000)

        // Never landed: unclosed, and its key id is held by another key.
        let lost = Self.authKey(11)
        let holder = AppConnect.PlatformKey(
            id: 11, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: lost.data, readOnly: false, bound: .singleContract(Self.otherApp), boundKnown: true,
            totalBudget: 1000, expiresAt: Self.now + 1000, disabledAt: nil)
        let neverLanded = Self.intent([lost], createdAt: 2)
        let neverLandedKeys = [Self.onPlatform(live), holder]
        XCTAssertEqual(AppConnect.status(of: neverLanded, in: Self.snapshot(neverLandedKeys)), .neverLanded)
        XCTAssertEqual(Self.connection([older, neverLanded], neverLandedKeys)?.status, active, "older Active, newer Never landed")

        // Disconnected: closed, its own key off.
        let gone = Self.authKey(12)
        let disconnected = Self.closed(Self.intent([gone], published: true, createdAt: 2))
        let disconnectedKeys = [Self.onPlatform(live), Self.onPlatform(gone, disabledAt: 1)]
        XCTAssertEqual(Self.connection([older, disconnected], disconnectedKeys)?.status, active, "older Active, newer Disconnected")

        // The existing decision stays: a newer Confirming is what the card shows.
        let confirming = Self.intent([Self.authKey(13)], createdAt: 2)
        XCTAssertEqual(Self.connection([older, confirming], [Self.onPlatform(live)])?.status, .confirming, "older Active, newer Confirming")
    }

    // T30 (F5): the not-delivered fact follows the newest Active intent, not "every Active intent" (AC-18).
    func testTheNotDeliveredFactFollowsTheNewestActiveIntent() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let keys = [Self.onPlatform(a), Self.onPlatform(b)]
        let olderDelivered = Self.intent([a], published: true, createdAt: 1)
        let newerUndelivered = Self.intent([b], published: false, createdAt: 2)
        XCTAssertEqual(Self.connection([olderDelivered, newerUndelivered], keys)?.isUndelivered, true, "newest without a response")
        let olderUndelivered = Self.intent([a], published: false, createdAt: 1)
        let newerDelivered = Self.intent([b], published: true, createdAt: 2)
        XCTAssertEqual(Self.connection([olderUndelivered, newerDelivered], keys)?.isUndelivered, false, "newest with a response")
    }

    func testRemovingTheLatestRefusedAttemptShowsTheEarlierActiveConnectionAgain() throws {
        let live = Self.authKey(10)
        let earlier = Self.intent([live], published: true, createdAt: 1)
        let refused = Self.intent([Self.authKey(11)], createdAt: 2, refusal: Self.refusal)
        let keys = [Self.onPlatform(live)]
        XCTAssertEqual(Self.connection([earlier, refused], keys)?.status, .refused)
        let removed = try XCTUnwrap(AppConnect.removing(
            appId: Self.app, intents: [earlier, refused], snapshots: [Self.snapshot(keys)], at: Self.removedAt))
        XCTAssertEqual(Self.connection(removed, keys)?.status, .active(expiresAt: Self.now + 1000))
    }

    // MARK: T22 R4: Confirming, then disconnected

    /// The wallet's fence key as Platform shows it under `key`'s id: another key, no expiry, no contract bound.
    private static func fence(_ key: Key) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: key.id, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: 0x99, count: 20), readOnly: false, bound: nil, boundKnown: true,
            totalBudget: 1, expiresAt: nil, disabledAt: nil)
    }

    func testAConfirmingConnectionThatWasDisconnectedProjectsAsDisconnected() {
        // Disconnect fenced the missing key id: the id is now held by the wallet's fence key and the intent is closed.
        let a = Self.authKey(10)
        let fence = Self.fence(a)
        let confirming = Self.intent([a], createdAt: 1)
        XCTAssertEqual(Self.connection([confirming], [])?.status, .confirming)

        let disconnected = Self.disconnected(confirming)
        XCTAssertEqual(Self.connection([disconnected], [fence])?.status, .disconnected)
    }

    func testAFencedClosedIntentWithANewerIntentGivesWayToIt() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let fence = Self.fence(a)
        let closed = Self.closed(Self.intent([a], createdAt: 1))
        let newer = Self.intent([b], published: true, createdAt: 2)
        XCTAssertEqual(Self.connection([closed, newer], [fence, Self.onPlatform(b)])?.status, .active(expiresAt: Self.now + 1000))
    }

    // MARK: T22 R1: rows() of every status

    func testRowsShowEveryIntentStatus() {
        let a = Self.authKey(10)
        let expired = Self.authKey(10, expiresAt: Self.now - 1)
        let fence = Self.fence(a)
        let cases: [(String, Intent, [AppConnect.PlatformKey], ConnectionStatus?)] = [
            ("Active", Self.intent([a], published: true), [Self.onPlatform(a)], .active),
            ("Not delivered", Self.intent([a]), [Self.onPlatform(a)], .undelivered),
            ("Confirming", Self.intent([a]), [], .confirming),
            ("Expired", Self.intent([expired], published: true), [Self.onPlatform(expired)], .expired),
            ("Refused", Self.intent([a], refusal: Self.refusal), [], .refused),
            ("Disconnected", Self.closed(Self.intent([a], published: true)), [Self.onPlatform(a, disabledAt: 1)], .disconnected),
            ("Never landed", Self.intent([a]), [fence], nil),
        ]
        for (name, intent, keys, expected) in cases {
            let projection = AppConnect.project([Self.snapshot(keys)], intents: [intent])
            let rows = PlatformDashConnectDataSource.rows(
                [], after: projection, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 2))
            XCTAssertEqual(rows.map(\.status), expected.map { [$0] } ?? [], name)
        }
    }

    func testAFencedConfirmingConnectionHasADisconnectedRow() {
        let a = Self.authKey(10)
        let fence = Self.fence(a)
        let projection = AppConnect.project([Self.snapshot([fence])], intents: [Self.disconnected(Self.intent([a]))])
        let rows = PlatformDashConnectDataSource.rows(
            [], after: projection, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(rows.map(\.status), [.disconnected])
    }

    /// T36 (G2, AC-19): a closed Disconnected A keeps its row when a newer
    /// open intent C never landed (another key holds its id): the row is
    /// read off the intents the card follows, not the newest one, and so
    /// are its name and website (T40, H2, AC-13).
    func testADisconnectedRowStaysUnderANewerIntentThatNeverLanded() {
        let a = Self.authKey(10), c = Self.authKey(11)
        let disconnected = Self.closed(Self.intent(
            [a], published: true, createdAt: 1, label: "Yappr iOS", url: "https://ios.yappr.example"))
        let neverLanded = Self.intent([c], createdAt: 2, label: "Yappr web", url: "https://web.yappr.example")
        let projection = AppConnect.project(
            [Self.snapshot([Self.onPlatform(a, disabledAt: 1), Self.fence(c)])], intents: [disconnected, neverLanded])
        XCTAssertEqual(projection.connections.first?.status, .disconnected)
        XCTAssertEqual(projection.connections.first?.followedIntents.map(\.id), [disconnected.id])
        let rows = PlatformDashConnectDataSource.rows(
            [], after: projection, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(rows.map(\.status), [.disconnected])
        XCTAssertEqual(rows.first?.name, "Yappr iOS", "the name recorded with the disconnected connection")
        XCTAssertEqual(rows.first?.url, "https://ios.yappr.example")
    }

    /// T44 (J3, AC-13, AC-19): a newer intent C whose id another key took
    /// (Never landed) is closed by a disconnect without the mark; it reads
    /// Never landed still, so the connection follows the closed, marked A:
    /// its name, website and status are A's.
    func testAClosedUnmarkedIntentAnotherKeyTookTheIdOfReadsNeverLandedAndDoesNotNameTheDisconnectedEntry() {
        let a = Self.authKey(10), c = Self.authKey(11)
        var disconnected = Self.closed(Self.intent(
            [a], published: true, createdAt: 1, label: "Yappr iOS", url: "https://ios.yappr.example"))
        disconnected.disconnectedAt = Date(timeIntervalSince1970: 5)
        let neverLanded = Self.closed(Self.intent(
            [c], createdAt: 2, label: "Yappr web", url: "https://web.yappr.example"))
        let snapshot = Self.snapshot([Self.onPlatform(a, disabledAt: 1), Self.fence(c)])
        XCTAssertEqual(AppConnect.status(of: neverLanded, in: snapshot), .neverLanded, "closed without the mark it never landed")
        let projection = AppConnect.project([snapshot], intents: [disconnected, neverLanded])
        XCTAssertEqual(projection.connections.first?.followedIntents.first?.id, disconnected.id)
        XCTAssertEqual(projection.connections.first?.status, .disconnected)
        let rows = PlatformDashConnectDataSource.rows(
            [], after: projection, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(rows.first?.name, "Yappr iOS")
        XCTAssertEqual(rows.first?.url, "https://ios.yappr.example")
    }

    // MARK: T22 R8: a refused intent is never fenced

    func testARefusedIntentIsNeverFencedByADisconnectPlan() {
        let refused = Self.intent([Self.authKey(10)], refusal: Self.refusal)
        let pending = Self.intent([Self.authKey(11)])
        let plan = AppConnect.recordedDisconnectPlan(appId: Self.app, snapshot: Self.snapshot([]), intents: [refused, pending])
        XCTAssertEqual(plan.fence, [11], "only the update that may still land is fenced")
        XCTAssertEqual(
            AppConnect.recordedDisconnectPlan(appId: Self.app, snapshot: Self.snapshot([]), intents: [refused]).fence, [])
        XCTAssertEqual(
            AppConnect.disconnectPlan(appId: Self.app, snapshot: Self.snapshot([]), intents: [refused], owners: [:]).fence, [])
    }

    // MARK: First connection of an App ID (AC-03, T16)

    func testTheFirstConnectionFactCountsEveryStatusButRefused() {
        let a = Self.authKey(10)
        let expired = Self.authKey(10, expiresAt: Self.now - 1)
        let cases: [(String, [Intent], [AppConnect.PlatformKey], Bool)] = [
            ("no intent", [], [], false),
            ("Confirming", [Self.intent([a])], [], true),
            ("Active", [Self.intent([a], published: true)], [Self.onPlatform(a)], true),
            ("Not delivered", [Self.intent([a])], [Self.onPlatform(a)], true),
            ("Expired", [Self.intent([expired], published: true)], [Self.onPlatform(expired)], true),
            ("Disconnected", [Self.closed(Self.intent([a], published: true))], [Self.onPlatform(a, disabledAt: 1)], true),
            ("Refused", [Self.intent([a], refusal: Self.refusal)], [], false),
            ("a removed Refused", [Self.intent([a], refusal: Self.refusal, removedAt: Self.removedAt)], [], false),
            ("a refusal next to a live key", [Self.intent([a], refusal: Self.refusal)], [Self.onPlatform(a)], true),
        ]
        for (name, intents, keys, expected) in cases {
            let projection = AppConnect.project([Self.snapshot(keys)], intents: intents)
            XCTAssertEqual(projection.hasConnectionOtherThanRefused(appId: Self.app), expected, name)
        }
    }

    func testARefusedAttemptNextToADisconnectedOneStillCountsAsAFirstConnectionHistory() {
        let (earlier, off) = disconnectedEarlier()
        let refused = Self.intent([Self.authKey(11)], createdAt: 2, refusal: Self.refusal)
        let projection = AppConnect.project([Self.snapshot(off)], intents: [earlier, refused])
        XCTAssertTrue(projection.hasConnectionOtherThanRefused(appId: Self.app), "the project() status says Refused, the history says otherwise")
    }

    func testTheFirstConnectionFactIsPerAppId() {
        let refused = Self.intent([Self.authKey(10)], refusal: Self.refusal)
        let other = Self.intent([Self.authKey(11, bound: .singleContract(Self.otherApp))], app: Self.otherApp)
        let projection = AppConnect.project([Self.snapshot([])], intents: [refused, other])
        XCTAssertFalse(projection.hasConnectionOtherThanRefused(appId: Self.app))
        XCTAssertTrue(projection.hasConnectionOtherThanRefused(appId: Self.otherApp))
    }

    func testAKeyNoIntentNamesCountsAsAConnectionForTheFirstConnectionFact() {
        let stray = Self.onPlatform(Self.authKey(20))
        let projection = AppConnect.project([Self.snapshot([stray])], intents: [])
        XCTAssertTrue(projection.hasConnectionOtherThanRefused(appId: Self.app))
    }

    // MARK: Snapshots

    func testAReadBehindOneAlreadySeenIsDropped() {
        let newest = Self.snapshot([], revision: 7)
        XCTAssertFalse(Self.snapshot([], revision: 6).mayReplace(newest))
        XCTAssertTrue(Self.snapshot([], revision: 7).mayReplace(newest))
        XCTAssertTrue(Self.snapshot([], revision: 1).mayReplace(nil))
        XCTAssertTrue(Self.snapshot([], identity: Self.otherIdentity, revision: 1).mayReplace(newest))
    }

    /// A raise of a key's limits keeps the revision: a later read of the
    /// same revision with the limits from before it, or without a key, or
    /// with a turned-off key on again, is behind the one already seen.
    func testAReadOfTheSameRevisionBehindTheLimitsAlreadySeenIsDropped() {
        let raised = Self.onPlatform(Self.authKey(10, expiresAt: Self.now + 2000))
        let newest = Self.snapshot([raised], revision: 7)
        let earlier = Self.onPlatform(Self.authKey(10, expiresAt: Self.now + 1000))
        let lowerBudget = AppConnect.PlatformKey(
            id: raised.id, purpose: raised.purpose, securityLevel: raised.securityLevel, keyType: raised.keyType,
            data: raised.data, readOnly: raised.readOnly, bound: raised.bound, boundKnown: raised.boundKnown,
            totalBudget: 500, expiresAt: raised.expiresAt, disabledAt: nil)
        XCTAssertFalse(Self.snapshot([earlier], revision: 7).mayReplace(newest), "an earlier expiry")
        XCTAssertFalse(Self.snapshot([lowerBudget], revision: 7).mayReplace(newest), "a lower budget")
        XCTAssertFalse(Self.snapshot([], revision: 7).mayReplace(newest), "a key missing")
        let off = Self.snapshot([Self.onPlatform(Self.authKey(10, expiresAt: Self.now + 2000), disabledAt: Self.now)], revision: 8)
        XCTAssertTrue(off.mayReplace(newest))
        XCTAssertFalse(Self.snapshot([raised], revision: 8).mayReplace(off), "a turned-off key on again")
        let higher = Self.onPlatform(Self.authKey(10, expiresAt: Self.now + 3000))
        XCTAssertTrue(Self.snapshot([higher, Self.onPlatform(Self.authKey(11))], revision: 7).mayReplace(newest))
    }

    /// A read whose proof is older than one already seen keeps the later
    /// block time: a key already seen expired is not Active again, unless
    /// the read shows its expiry raised.
    func testAnOlderProofDoesNotReviveAnExpiredConnection() throws {
        let key = Self.onPlatform(Self.authKey(10, expiresAt: Self.now + 1000))
        let expiredRead = Self.snapshot([key], revision: 7, time: Self.now + 2000)
        let older = try XCTUnwrap(Self.snapshot([key], revision: 7, time: Self.now).admitted(after: expiredRead))
        XCTAssertEqual(older.platformTime, Self.now + 2000)
        XCTAssertEqual(AppConnect.presence(of: Self.authKey(10, expiresAt: Self.now + 1000), in: older), .expired)
        let untimed = try XCTUnwrap(Self.snapshot([key], revision: 7, time: nil).admitted(after: expiredRead))
        XCTAssertEqual(untimed.platformTime, Self.now + 2000)

        let extended = Self.onPlatform(Self.authKey(10, expiresAt: Self.now + 5000))
        let renewed = try XCTUnwrap(Self.snapshot([extended], revision: 7, time: Self.now + 2100).admitted(after: expiredRead))
        XCTAssertEqual(renewed.platformTime, Self.now + 2100)
        XCTAssertEqual(AppConnect.presence(of: Self.authKey(10, expiresAt: Self.now + 5000), in: renewed), .live)

        XCTAssertNil(Self.snapshot([key], revision: 6, time: Self.now + 3000).admitted(after: expiredRead))
        XCTAssertEqual(Self.snapshot([key], revision: 1).admitted(after: nil), Self.snapshot([key], revision: 1))
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
            appId: Self.app, snapshot: snapshot, intents: [landed, waiting, dead], owners: [:])
        // 14 is another key on the id the dead intent named: bound to the
        // app and named by no record, so it goes too (AC-16).
        XCTAssertEqual(plan.disable, [10, 11, 14])
        XCTAssertEqual(plan.fence, [12])
        XCTAssertEqual(plan.deleteResponses, [landed.id])
    }

    func testAPartlyLandedIntentIsFencedOnlyWhileAKeyIsMissing() {
        let intent = Self.intent([Self.authKey(10), Self.authKey(11)])
        let plan = AppConnect.disconnectPlan(
            appId: Self.app, snapshot: Self.snapshot([Self.onPlatform(Self.authKey(10))]), intents: [intent], owners: [:])
        XCTAssertEqual(plan.disable, [10])
        XCTAssertEqual(plan.fence, [11])
    }

    // MARK: Disconnect without asking (AC-16, AC-16b, AC-18)

    private static let profileBound = AppConnect.StoredBound.documentType(contractId: dashPay, name: "profile")

    func testOneDisconnectTurnsOffRecordedUnrecordedAndUnattributedProfileKeysWithNoFlag() {
        let intent = Self.intent([Self.authKey(10)])
        let otherApps = Self.intent([Self.authKey(11, bound: .singleContract(Self.otherApp))], app: Self.otherApp)
        let snapshot = Self.snapshot([
            Self.onPlatform(Self.authKey(10)),
            Self.onPlatform(Self.authKey(20)),
            Self.onPlatform(Self.authKey(30, bound: Self.profileBound)),
            Self.onPlatform(Self.authKey(11, bound: .singleContract(Self.otherApp))),
            Self.onPlatform(Self.authKey(21), disabledAt: 1),
        ])
        let plan = AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent, otherApps], owners: [:])
        XCTAssertEqual(plan.disable, [30, 10, 20], "the unattributed profile key first, then recorded and live unrecorded; not the other app's")
    }

    func testAnUnattributedProfileKeyGoesWithTheDisconnectOfAnyApp() {
        let snapshot = Self.snapshot([
            Self.onPlatform(Self.authKey(10)), Self.onPlatform(Self.authKey(30, bound: Self.profileBound)),
        ])
        let mine = Self.intent([Self.authKey(10)])
        let theirs = Self.intent([Self.authKey(11, bound: .singleContract(Self.otherApp))], app: Self.otherApp)
        XCTAssertEqual(
            AppConnect.disconnectPlan(appId: Self.otherApp, snapshot: snapshot, intents: [mine, theirs], owners: [:]).disable, [30])
    }

    func testAProfileKeyAnIntentNamesIsNotTakenAsUnattributed() {
        let named = Self.authKey(30, bound: Self.profileBound)
        let theirs = Self.intent([named], app: Self.otherApp)
        let snapshot = Self.snapshot([Self.onPlatform(named)])
        XCTAssertEqual(AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [theirs], owners: [:]).disable, [])
    }

    func testKeysWhoseBoundTheStoreDoesNotHoldAreNotTurnedOffAndAreReportedAsNotChecked() {
        let intent = Self.intent([Self.authKey(10)])
        let snapshot = Self.snapshot([
            Self.onPlatform(Self.authKey(10)), Self.onPlatform(Self.authKey(20), boundKnown: false),
        ])
        XCTAssertEqual(AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], owners: [:]).disable, [10])
        XCTAssertEqual(AppConnect.project([snapshot], intents: [intent]).unplacedKeyIds, [Self.identity: [20]])
    }

    func testTwentyThreeKeysGoInThreeUpdatesOfAtMostTen() {
        let recorded = (100 ..< 112).map { Self.authKey($0) }
        let intent = Self.intent(recorded)
        let unrecorded = (200 ..< 208).map { Self.authKey($0) }
        let profile = (300 ..< 303).map { Self.authKey($0, bound: Self.profileBound) }
        let snapshot = Self.snapshot((recorded + unrecorded + profile).map { Self.onPlatform($0) })
        let plan = AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], owners: [:])
        XCTAssertEqual(plan.disable.count, 23)
        let updates = plan.updates
        XCTAssertEqual(updates.count, 3)
        XCTAssertTrue(updates.allSatisfy { $0.disable.count <= 10 })
        XCTAssertEqual(updates.flatMap(\.disable), plan.disable, "every key once, none dropped")
    }

    func testAnUpdateAddsAtMostSixFencesAndTurnsOffAtMostTenKeys() {
        let plan = AppConnect.DisconnectPlan(disable: [1, 2, 3], fence: Array(40 ..< 47))
        let updates = plan.updates
        XCTAssertEqual(updates.count, 2)
        XCTAssertTrue(updates.allSatisfy { $0.fence.count <= 6 && $0.disable.count <= 10 })
        XCTAssertEqual(updates.flatMap(\.fence), plan.fence)
        XCTAssertEqual(updates.flatMap(\.disable), plan.disable)
    }

    func testAnUpdateFailingMidBatchStopsAndNamesWhatIsStillLive() async {
        let plan = AppConnect.DisconnectPlan(disable: (1 ... 23).map { UInt32($0) })
        var sent = 0
        let progress = await AppConnect.submit(plan) { _ in
            sent += 1
            if sent == 2 { throw NSError(domain: "test", code: 1) }
        }
        XCTAssertEqual(sent, 2, "nothing is sent after the failure")
        XCTAssertTrue(progress.stopped)
        XCTAssertEqual(progress.turnedOff, (1 ... 10).map { UInt32($0) })
        XCTAssertEqual(progress.stillLive, (11 ... 23).map { UInt32($0) })
    }

    func testAnUninterruptedSubmitLeavesNothingLive() async {
        let plan = AppConnect.DisconnectPlan(disable: (1 ... 23).map { UInt32($0) })
        let progress = await AppConnect.submit(plan) { _ in }
        XCTAssertFalse(progress.stopped)
        XCTAssertEqual(progress.turnedOff, plan.disable)
        XCTAssertEqual(progress.stillLive, [])
    }

    func testADisconnectLeavesOtherAppsAndOtherIdentitiesAlone() {
        let mine = Self.intent([Self.authKey(10)])
        let otherApps = Self.intent([Self.authKey(11)], app: Self.otherApp)
        let otherIdentity = Self.intent([Self.authKey(12)], identity: Self.otherIdentity)
        let snapshot = Self.snapshot([Self.onPlatform(Self.authKey(10)), Self.onPlatform(Self.authKey(11))])
        let plan = AppConnect.disconnectPlan(
            appId: Self.app, snapshot: snapshot, intents: [mine, otherApps, otherIdentity], owners: [:])
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

    func testAnIntentWrittenBeforeRefusalAndRemovedAtDecodesWithBothNil() throws {
        var row = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.intent([Self.authKey(10)]))) as? [String: Any])
        row.removeValue(forKey: "refusal")
        row.removeValue(forKey: "removedAt")

        let decoded = try JSONDecoder().decode(Intent.self, from: JSONSerialization.data(withJSONObject: row))

        XCTAssertNil(decoded.refusal)
        XCTAssertNil(decoded.removedAt)
    }

    // MARK: Intent store

    private func intentStore(_ scope: @escaping () -> String?) -> (UserDefaultsAppConnectIntentStore, UserDefaults) {
        let suite = "AppConnectProjectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (UserDefaultsAppConnectIntentStore(defaults: defaults, network: .testnet, scopeKeyProvider: scope), defaults)
    }

    func testAnIntentWithARefusalAndRemovedAtRoundTripsThroughTheStore() throws {
        let (store, _) = intentStore { "scope" }
        let refusal = AppConnect.ConsensusRefusal(code: 10_212, at: Date(timeIntervalSince1970: 1_773_132_300))
        let removedAt = Date(timeIntervalSince1970: 1_773_218_700)
        let refused = Self.intent([Self.authKey(6)], refusal: refusal, removedAt: removedAt)
        let plain = Self.intent([Self.authKey(7)])

        store.save([refused, plain])

        let loaded = store.load()
        XCTAssertEqual(loaded, [refused, plain])
        let back = try XCTUnwrap(loaded.first { $0.id == refused.id })
        XCTAssertEqual(back.refusal, refusal)
        XCTAssertEqual(back.removedAt, removedAt)
        let other = try XCTUnwrap(loaded.first { $0.id == plain.id })
        XCTAssertNil(other.refusal)
        XCTAssertNil(other.removedAt)
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

    func testAConnectionWhoseKeysAreAllExpiredShowsAsExpired() {
        let key = Self.authKey(10, expiresAt: Self.now - 1)
        let projection = AppConnect.project(
            [Self.snapshot([Self.onPlatform(key)])], intents: [Self.intent([key], published: true)])
        XCTAssertEqual(
            PlatformDashConnectDataSource.rows([], after: projection, of: Self.identity, intents: [], at: Date(timeIntervalSince1970: 2)).map(\.status),
            [.expired])
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
    /// intent was turned off, never landed or there is no intent at all: it
    /// is Confirming, not Active. Once every key is placed, the row goes.
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
            XCTAssertEqual(rows(keys + [unplaced]).map(\.status), [.confirming], name)
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
                AppConnect.disconnectPlan(appId: app, snapshot: snapshot, intents: [mine, theirs], owners: [:]).disable,
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
                AppConnect.disconnectPlan(appId: app, snapshot: Self.snapshot([stray]), intents: [mine, gone], owners: [:]).disable,
                [20], "a disconnect of either app turns it off")
        }
    }

    func testALiveKeyOfAnIntentWithATakenIdStaysActionable() {
        let a = Self.authKey(10), b = Self.authKey(11)
        let intent = Self.intent([a, b])
        let snapshot = Self.snapshot([Self.onPlatform(a), Self.onPlatform(b, data: Data(repeating: 9, count: 20))])
        let projection = AppConnect.project([snapshot], intents: [intent])
        XCTAssertEqual(projection.connections.first?.status, .active(expiresAt: Self.now + 1000), "the app keeps a row")
        let plan = AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], owners: [:])
        // 11 is another key on the id the intent named, bound to the app and
        // named by no record: it is turned off as an unrecorded key (AC-16).
        XCTAssertEqual(plan.disable, [10, 11])
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
            AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], owners: [:]).disable,
            [10, 11], "11 holds the intent's id with other data: an unrecorded key of the app (AC-16)")
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

    /// A disconnect here closes this identity's intent; the access another
    /// identity of the wallet still has keeps the row, and its Disconnect.
    func testAClosedIntentHereDoesNotShowDisconnectedWhileAnotherIdentityHasAccess() {
        let me = Self.identity.toBase58String(), other = Self.otherIdentity.toBase58String()
        var closed = Self.intent([Self.authKey(10)])
        closed.closedAt = Date(timeIntervalSince1970: 1)
        let projection = AppConnect.project([Self.snapshot([Self.onPlatform(Self.authKey(10), disabledAt: 1)])], intents: [closed])
        let at = Date(timeIntervalSince1970: 2)
        func row(seenOn: Set<String>) -> DAppConnection {
            DAppConnection(
                id: Self.app.toBase58String(), name: "App", url: "", status: .active,
                updatedAt: Date(timeIntervalSince1970: 1), seenOn: seenOn)
        }

        let held = PlatformDashConnectDataSource.rows(
            [row(seenOn: [me])], after: projection, of: Self.identity,
            intents: [Self.intent([Self.authKey(10)], identity: Self.otherIdentity)], at: at)
        XCTAssertEqual(held.map(\.status), [.active], "another identity's open intent holds it")

        let seen = PlatformDashConnectDataSource.rows(
            [row(seenOn: [me, other])], after: projection, of: Self.identity, intents: [], at: at)
        XCTAssertEqual(seen.map(\.status), [.active], "live keys seen on another identity hold it")
        XCTAssertEqual(seen.first?.seenOn, [other])

        let alone = PlatformDashConnectDataSource.rows(
            [row(seenOn: [me])], after: projection, of: Self.identity, intents: [], at: at)
        XCTAssertEqual(alone.map(\.status), [.disconnected], "with no access elsewhere it is Disconnected")
    }

    /// An app whose intents here are all closed, renewed through keys no
    /// intent names: a key of unknown bound on the read may be the app's,
    /// so its row stays Confirming, with its Disconnect, not Disconnected.
    func testAClosedIntentHereIsConfirmingWhileTheReadHasAKeyOfUnknownBound() {
        var closed = Self.intent([Self.authKey(10)])
        closed.closedAt = Date(timeIntervalSince1970: 1)
        let unknown = Self.onPlatform(Self.authKey(20, bound: nil), boundKnown: false)
        let off = Self.onPlatform(Self.authKey(10), disabledAt: 1)
        let row = DAppConnection(
            id: Self.app.toBase58String(), name: "App", url: "", status: .active,
            updatedAt: Date(timeIntervalSince1970: 1), seenOn: [Self.identity.toBase58String()])
        let at = Date(timeIntervalSince1970: 2)

        let held = PlatformDashConnectDataSource.rows(
            [row], after: AppConnect.project([Self.snapshot([off, unknown])], intents: [closed]),
            of: Self.identity, intents: [], at: at)
        XCTAssertEqual(held.map(\.status), [.confirming])

        let placed = PlatformDashConnectDataSource.rows(
            [row], after: AppConnect.project([Self.snapshot([off])], intents: [closed]),
            of: Self.identity, intents: [], at: at)
        XCTAssertEqual(placed.map(\.status), [.disconnected], "once every key is placed it is Disconnected")
    }

    /// A sign-in that beat its fence shows the app's key under the fenced
    /// id: the result counts it once, from the plan's fence, not again as a
    /// key the read after the update found.
    func testAKeyUnderAFencedIdIsNotFoundAgainAfterTheUpdate() {
        let plan = AppConnect.DisconnectPlan(disable: [10], fence: [7])
        let remaining = AppConnect.DisconnectPlan(disable: [7, 30])
        XCTAssertEqual(PlatformDashConnectDataSource.keysFoundAfter(plan: plan, remaining: remaining, fenceIds: []), 1)
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
            AppConnect.disconnectPlan(appId: Self.app, snapshot: snapshot, intents: [intent], owners: [:]).fence,
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

    // MARK: Fifth review round

    func testUnrecordedKeysAllPastTheirExpiryShowExpiredAndAreStillTurnedOff() {
        let expired = Self.onPlatform(Self.authKey(20, bound: .singleContract(Self.otherApp), expiresAt: Self.now - 1))
        let snapshot = Self.snapshot([expired])
        let projection = AppConnect.project([snapshot], intents: [])
        XCTAssertEqual(projection.connections.map(\.status), [.expired])
        XCTAssertEqual(AppConnect.disconnectPlan(appId: Self.otherApp, snapshot: snapshot, intents: [], owners: [:]).disable, [20])
    }

    func testUnrecordedKeysWithOneLiveShowActive() {
        let expired = Self.onPlatform(Self.authKey(20, bound: .singleContract(Self.otherApp), expiresAt: Self.now - 1))
        let live = Self.onPlatform(Self.authKey(21, bound: .singleContract(Self.otherApp)))
        let projection = AppConnect.project([Self.snapshot([expired, live])], intents: [])
        XCTAssertEqual(projection.connections.map(\.status), [.active(expiresAt: nil)])
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

    /// A disconnect of X turns off its intent keys and the unrecorded keys
    /// attributed to it by owner, and sorts every other key that may be X's
    /// into what the result reports.
    func testADisconnectTurnsOffTheKeysAttributedByOwnerAndReportsTheRest() {
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
            /// disable, notChecked, notAttributable
            let expected: [[UInt32]]
            init(_ name: String, _ keys: [AppConnect.PlatformKey], _ intents: [Intent], _ owners: [Data: Data], _ expected: [[UInt32]]) {
                (self.name, self.keys, self.intents, self.owners, self.expected) = (name, keys, intents, owners, expected)
            }
        }
        let cases: [Case] = [
            Case("AC-01 sibling contract", [Self.onPlatform(own), onY()], [x], match, [[10, 20], [], []]),
            Case("AC-01 document type", [Self.onPlatform(own), onY(.documentType(contractId: Self.sibling, name: "note"))], [x], match,
                 [[10, 20], [], []]),
            Case("AC-02 contract group", [Self.onPlatform(own), onY(.contractGroup(Self.siblingGroup))], [x],
                 [Self.siblingGroup: Self.ownerX, Self.app: Self.ownerX], [[10, 20], [], []]),
            Case("AC-04 owner unread", [Self.onPlatform(own), onY()], [x], [Self.app: Self.ownerX], [[10], [20], []]),
            Case("AC-06 another owner", [Self.onPlatform(own), onY()], [x], [Self.sibling: Self.ownerW, Self.app: Self.ownerX], [[10], [], []]),
            Case("AC-07 two apps of one owner", [Self.onPlatform(own), onY()], [x, z], match.merging([Self.otherApp: Self.ownerX]) { a, _ in a },
                 [[10], [], [20]]),
            Case("AC-11 unplaced key", [Self.onPlatform(own), onY(boundKnown: false)], [x], match, [[10], [20], []]),
            Case("AC-12 another app's owner unknown", [Self.onPlatform(own), onY()], [x, z], match, [[10], [20], []]),
            Case("a sibling key no longer live", [Self.onPlatform(own), onY(disabledAt: 1)], [x], match, [[10], [], []]),
            Case("only unknown owners still turn off the app's keys", [Self.onPlatform(own), onY()], [x], [:], [[10], [20], []]),
            Case("AC-09 system contract of the app's owner", [Self.onPlatform(own), onY(.singleContract(Self.withdrawals))], [x],
                 [Self.withdrawals: Self.ownerX, Self.app: Self.ownerX], [[10], [], []]),
        ]
        for c in cases {
            let plan = AppConnect.disconnectPlan(appId: Self.app, snapshot: Self.snapshot(c.keys), intents: c.intents, owners: c.owners)
            XCTAssertEqual([plan.disable, plan.notChecked, plan.notAttributable], c.expected, c.name)
        }
    }

    /// A row whose app has no intent on the identity is the contract the
    /// user named: its disconnect turns off every key placed on that
    /// contract, whatever owner has been read since the row was shown.
    func testADisconnectOfARowWithoutAnIntentTurnsOffItsKeysWhateverTheirOwner() {
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
            let expected: [UInt32]
            init(_ name: String, _ keys: [AppConnect.PlatformKey], _ intents: [Intent], _ owners: [Data: Data], _ expected: [UInt32]) {
                (self.name, self.keys, self.intents, self.owners, self.expected) = (name, keys, intents, owners, expected)
            }
        }
        let cases: [Case] = [
            Case("owner unread when shown, read now", [Self.onPlatform(own), onY], [x], match, [20]),
            Case("owner still unread", [Self.onPlatform(own), onY], [x], [Self.app: Self.ownerX], [20]),
            Case("another owner", [Self.onPlatform(own), onY], [x], [Self.sibling: Self.ownerW, Self.app: Self.ownerX], [20]),
            Case("no intent here (AC-10)", [onY, onY2], [], [:], [20]),
        ]
        for c in cases {
            let plan = AppConnect.disconnectPlan(appId: Self.sibling, snapshot: Self.snapshot(c.keys), intents: c.intents, owners: c.owners)
            XCTAssertEqual(plan.disable, c.expected, c.name)
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
