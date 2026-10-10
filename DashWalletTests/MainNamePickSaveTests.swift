import Foundation
import SwiftData
import SwiftDashSDK
import XCTest
#if canImport(dashwallet)
@testable import dashwallet
#elseif canImport(dashpay)
@testable import dashpay
#endif

/// Picking a main username on the Identities screen: the pick is written
/// to `PersistentIdentity.mainDpnsName`, and a failed save must leave the
/// identity and a waiting create-username promotion as they were.
@MainActor
final class MainNamePickSaveTests: XCTestCase {
    private struct SaveFailed: Error {}

    private let identityId = Data(repeating: 0x5A, count: 32)
    private let otherIdentityId = Data(repeating: 0x5B, count: 32)
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    /// In-memory store without CloudKit: the test host carries iCloud
    /// entitlements, and the default configuration then rejects the SDK
    /// models (`loadIssueModelContainer`).
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(DashModelContainer.modelTypes),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    /// The slot `DWCurrentUserIdentityInfo.promoteToMainName` leaves behind.
    private func pendingKey(_ id: Data) -> String {
        "DWPendingMainDpnsName." + id.map { String(format: "%02x", $0) }.joined()
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
        for id in [identityId, otherIdentityId] {
            UserDefaults.standard.removeObject(forKey: pendingKey(id))
        }
    }

    private func addIdentity(to container: ModelContainer, id: Data, mainDpnsName: String?) throws -> PersistentIdentity {
        let identity = PersistentIdentity(identityId: id, mainDpnsName: mainDpnsName, network: .testnet)
        identity.lastUpdated = stamp
        container.mainContext.insert(identity)
        try container.mainContext.save()
        return identity
    }

    func testFailedSaveRestoresThePickAndKeepsThePendingPromotion() throws {
        let container = try makeContainer()
        let identity = try addIdentity(to: container, id: identityId, mainDpnsName: "Alice")
        UserDefaults.standard.set("Carol", forKey: pendingKey(identityId))

        XCTAssertThrowsError(
            try IdentitiesViewModel.persistMainName("Bob", on: identity, save: { throw SaveFailed() })
        ) { XCTAssertTrue($0 is SaveFailed) }

        XCTAssertEqual(identity.mainDpnsName, "Alice")
        XCTAssertEqual(identity.lastUpdated, stamp)
        XCTAssertEqual(UserDefaults.standard.string(forKey: pendingKey(identityId)), "Carol")
    }

    func testRetryAfterAFailedSaveStoresThePickAndDropsThePendingPromotion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let identity = try addIdentity(to: container, id: identityId, mainDpnsName: "Alice")
        let other = try addIdentity(to: container, id: otherIdentityId, mainDpnsName: "Dave")
        UserDefaults.standard.set("Carol", forKey: pendingKey(identityId))
        UserDefaults.standard.set("Erin", forKey: pendingKey(otherIdentityId))

        XCTAssertThrowsError(
            try IdentitiesViewModel.persistMainName("Bob", on: identity, save: { throw SaveFailed() }))
        try IdentitiesViewModel.persistMainName("Bob", on: identity, save: context.save)

        // A second context sees only what was saved.
        let stored = PersistentIdentity.fetch(in: ModelContext(container), identityId: identityId)
        XCTAssertEqual(stored?.mainDpnsName, "Bob")
        XCTAssertGreaterThan(identity.lastUpdated, stamp)
        XCTAssertNil(UserDefaults.standard.string(forKey: pendingKey(identityId)))

        XCTAssertEqual(other.mainDpnsName, "Dave")
        XCTAssertEqual(other.lastUpdated, stamp)
        XCTAssertEqual(UserDefaults.standard.string(forKey: pendingKey(otherIdentityId)), "Erin")
    }
}
