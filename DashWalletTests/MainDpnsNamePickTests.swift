import Foundation
import SwiftData
import SwiftDashSDK
import XCTest
#if canImport(dashwallet)
@testable import dashwallet
#elseif canImport(dashpay)
@testable import dashpay
#endif

/// The displayed-username pick kept in the app's own UserDefaults slot, so a
/// rewrite of the SDK column (`PersistentIdentity.mainDpnsName`) during
/// startup sync cannot lose it.
@MainActor
final class MainDpnsNamePickTests: XCTestCase {
    private let identityId = Data(repeating: 0x5A, count: 32)
    private let otherIdentityId = Data(repeating: 0x5B, count: 32)
    private let unrelatedKey = "MainDpnsNamePickTests.unrelated"

    /// In-memory store without CloudKit: the test host carries iCloud
    /// entitlements, and the default configuration then rejects the SDK
    /// models (`loadIssueModelContainer`).
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(DashModelContainer.modelTypes),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private var pickKeys: [String] {
        [identityId, otherIdentityId].flatMap { id -> [String] in
            let hex = id.map { String(format: "%02x", $0) }.joined()
            return ["DWMainDpnsName." + hex, "DWPendingMainDpnsName." + hex]
        }
    }

    override func setUp() {
        super.setUp()
        clearDefaults()
    }

    override func tearDown() {
        clearDefaults()
        super.tearDown()
    }

    private func clearDefaults() {
        for key in pickKeys + [unrelatedKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @discardableResult
    private func addIdentity(
        to container: ModelContainer,
        id: Data,
        mainDpnsName: String?,
        names: [(label: String, isOwned: Bool)]
    ) -> PersistentIdentity {
        let identity = PersistentIdentity(identityId: id, mainDpnsName: mainDpnsName, network: .testnet)
        container.mainContext.insert(identity)
        for name in names {
            let row = PersistentDPNSName(identity: identity, label: name.label)
            row.isOwned = name.isOwned
            container.mainContext.insert(row)
        }
        return identity
    }

    func testStoredPickRoundTripsAndClearsOnNilOrEmpty() throws {
        let container = try makeContainer()
        let identity = addIdentity(to: container, id: identityId, mainDpnsName: nil, names: [])

        DWCurrentUserIdentityInfo.setMainDpnsName("Alice", identityId: identityId)
        XCTAssertEqual(DWCurrentUserIdentityInfo.mainDpnsName(for: identity), "Alice")

        DWCurrentUserIdentityInfo.setMainDpnsName("", identityId: identityId)
        XCTAssertNil(DWCurrentUserIdentityInfo.mainDpnsName(for: identity))

        DWCurrentUserIdentityInfo.setMainDpnsName("Alice", identityId: identityId)
        DWCurrentUserIdentityInfo.setMainDpnsName(nil, identityId: identityId)
        XCTAssertNil(DWCurrentUserIdentityInfo.mainDpnsName(for: identity))
    }

    func testStoredPickWinsOverARewrittenSdkColumn() throws {
        let container = try makeContainer()
        let identity = addIdentity(
            to: container, id: identityId, mainDpnsName: "Alice",
            names: [("Alice", true), ("Bob", true)])
        DWCurrentUserIdentityInfo.setMainDpnsName("Alice", identityId: identityId)

        identity.mainDpnsName = "Bob" // what the SDK persister does on a partial snapshot

        XCTAssertEqual(DWCurrentUserIdentityInfo.mainDpnsName(for: identity), "Alice")
    }

    func testLegacyPickIsCapturedWhenTheStoreOpensAndSurvivesARewrite() throws {
        let container = try makeContainer()
        addIdentity(
            to: container, id: identityId, mainDpnsName: "Alice",
            names: [("Alice", true), ("Bob", true)])
        try container.mainContext.save()

        DWCurrentUserIdentityInfo.captureLegacyMainDpnsNames(in: container)

        let identity = try XCTUnwrap(PersistentIdentity.fetch(in: container.mainContext, identityId: identityId))
        identity.mainDpnsName = "Bob"
        XCTAssertEqual(DWCurrentUserIdentityInfo.mainDpnsName(for: identity), "Alice")
    }

    func testLegacyPickOfADepartedNameIsNotCaptured() throws {
        let container = try makeContainer()
        addIdentity(
            to: container, id: identityId, mainDpnsName: "Alice",
            names: [("Alice", false), ("Bob", true)])
        try container.mainContext.save()

        DWCurrentUserIdentityInfo.captureLegacyMainDpnsNames(in: container)

        XCTAssertNil(UserDefaults.standard.string(forKey: pickKeys[0]))
    }

    func testWipeRemovesStoredAndPendingPicksOnly() {
        DWCurrentUserIdentityInfo.setMainDpnsName("Alice", identityId: identityId)
        DWCurrentUserIdentityInfo.setMainDpnsName("Carol", identityId: otherIdentityId)
        UserDefaults.standard.set("Bob", forKey: pickKeys[1]) // pending promotion
        UserDefaults.standard.set("keep", forKey: unrelatedKey)

        DWCurrentUserIdentityInfo.resetPendingMainNamesForWipe()

        for key in pickKeys {
            XCTAssertNil(UserDefaults.standard.string(forKey: key), key)
        }
        XCTAssertEqual(UserDefaults.standard.string(forKey: unrelatedKey), "keep")
    }
}
