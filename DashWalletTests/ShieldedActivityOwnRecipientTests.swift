//
//  ShieldedActivityOwnRecipientTests.swift
//  DashWalletTests
//

@testable import dashpay
import SwiftDashSDK
import SwiftData
import XCTest

#if targetEnvironment(simulator)
/// A shielded Sent row is own funds when its entry id also produced a
/// Received row, or when the SDK predicate says the recipient is one of the
/// wallet's own shielded addresses (default or fresh). Recipients are random
/// bytes, never a real wallet's address.
@MainActor
final class ShieldedActivityOwnRecipientTests: XCTestCase {
    private static let walletId = Data(repeating: 0x71, count: 32)
    private static let sentKind = ShieldedActivityItem.Kind.sent.rawValue
    private static let receivedKind = ShieldedActivityItem.Kind.received.rawValue

    private let container: ModelContainer = {
        do {
            return try ShieldedWithdrawalHistoryFixture.makeContainer()
        } catch {
            fatalError("in-memory container: \(error)")
        }
    }()

    private static func randomRecipient() -> Data {
        Data((0..<43).map { _ in UInt8.random(in: 0...255) })
    }

    private func insert(id: UInt8, kind: Int, account: UInt32 = 0, counterparty: Data) throws {
        container.mainContext.insert(PersistentShieldedActivity(
            walletId: Self.walletId, accountIndex: account, entryId: Data(repeating: id, count: 32),
            kindTag: kind, direction: kind == Self.sentKind ? 1 : 0, status: 1, amount: 1_000, fee: 10,
            hasFee: true, blockHeight: 1, hasBlockHeight: true, createdAtMs: 1_800_000_000_000,
            identityId: Data(), counterparty: counterparty, memo: Data(), noteCmxs: Data(),
            spentNullifiers: Data()))
        try container.mainContext.save()
    }

    private func items(
        predicate: @escaping (UInt32, Data) -> Bool?
    ) -> [ShieldedActivityItem] {
        items(ownRecipients: { recipients in
            recipients.filter { predicate($0.account, $0.raw43) == true }
        })
    }

    private func items(
        ownRecipients: @escaping (Set<SwiftDashSDKWalletSource.ShieldedRecipient>)
            -> Set<SwiftDashSDKWalletSource.ShieldedRecipient>
    ) -> [ShieldedActivityItem] {
        SwiftDashSDKWalletSource.fetchShieldedActivity(
            container: container, walletId: Self.walletId,
            ownShieldedRecipients: ownRecipients,
            withdrawalStore: ShieldedWithdrawalStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard))
    }

    func testPredicateTrueMeansOwnFunds() throws {
        try insert(id: 1, kind: Self.sentKind, counterparty: Self.randomRecipient())
        let item = try XCTUnwrap(items { _, _ in true }.first)
        XCTAssertNotNil(item.destinationAddress)
        XCTAssertFalse(item.isExternalDestination)
    }

    func testPredicateFalseMeansExternalRecipient() throws {
        try insert(id: 1, kind: Self.sentKind, counterparty: Self.randomRecipient())
        let item = try XCTUnwrap(items { _, _ in false }.first)
        XCTAssertTrue(item.isExternalDestination)
    }

    func testPredicateNilMeansExternalRecipient() throws {
        try insert(id: 1, kind: Self.sentKind, counterparty: Self.randomRecipient())
        let item = try XCTUnwrap(items { _, _ in nil }.first)
        XCTAssertTrue(item.isExternalDestination)
    }

    func testPredicateGetsTheRowsAccountAndRecipient() throws {
        let recipient = Self.randomRecipient()
        try insert(id: 1, kind: Self.sentKind, account: 3, counterparty: recipient)
        var calls: [(UInt32, Data)] = []
        _ = items { account, raw in calls.append((account, raw)); return true }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, 3)
        XCTAssertEqual(calls.first?.1, recipient)
    }

    func testSendMatchedByEntryIdIsOwnWithoutAskingThePredicate() throws {
        let recipient = Self.randomRecipient()
        try insert(id: 1, kind: Self.sentKind, counterparty: recipient)
        try insert(id: 1, kind: Self.receivedKind, account: 1, counterparty: Data())
        var calls = 0
        let sent = items { _, _ in calls += 1; return false }
            .filter { $0.kind == .sent }
        XCTAssertFalse(try XCTUnwrap(sent.first).isExternalDestination)
        XCTAssertEqual(calls, 0)
    }

    func testOneQueryPerFetchWithEachDistinctRecipientOnce() throws {
        // The SDK answers on the main thread: a fetch asks once, for every
        // distinct unmatched recipient together, however many rows share it.
        let own = Self.randomRecipient()
        let foreign = Self.randomRecipient()
        try insert(id: 1, kind: Self.sentKind, counterparty: own)
        try insert(id: 2, kind: Self.sentKind, counterparty: own)
        try insert(id: 3, kind: Self.sentKind, counterparty: own)
        try insert(id: 4, kind: Self.sentKind, counterparty: foreign)
        try insert(id: 5, kind: Self.sentKind, account: 2, counterparty: own)
        var queries: [Set<SwiftDashSDKWalletSource.ShieldedRecipient>] = []
        let result = items(ownRecipients: { recipients in
            queries.append(recipients)
            return recipients.filter { $0.raw43 == own }
        })
        XCTAssertEqual(queries.count, 1)
        XCTAssertEqual(queries.first, [
            .init(account: 0, raw43: own),
            .init(account: 0, raw43: foreign),
            .init(account: 2, raw43: own),
        ])
        XCTAssertEqual(result.filter { !$0.isExternalDestination }.count, 4)
        XCTAssertEqual(result.filter { $0.isExternalDestination }.count, 1)
    }

    func testNoQueryWhenEverySendIsMatchedByEntryId() throws {
        try insert(id: 1, kind: Self.sentKind, counterparty: Self.randomRecipient())
        try insert(id: 1, kind: Self.receivedKind, account: 1, counterparty: Data())
        var queries = 0
        _ = items(ownRecipients: { _ in queries += 1; return [] })
        XCTAssertEqual(queries, 0)
    }

    func testUnpairedSendsAreAllClassifiedByThePredicate() throws {
        // Live, other-device and restore-scan rows reach the reader alike:
        // a Sent row with no paired Received row.
        let own = Self.randomRecipient()
        let foreign = Self.randomRecipient()
        try insert(id: 1, kind: Self.sentKind, counterparty: own)
        try insert(id: 2, kind: Self.sentKind, counterparty: own)
        try insert(id: 3, kind: Self.sentKind, counterparty: foreign)
        let result = items { _, raw in raw == own }
        XCTAssertEqual(result.filter { !$0.isExternalDestination }.count, 2)
        XCTAssertEqual(result.filter { $0.isExternalDestination }.count, 1)
    }
}
#endif
