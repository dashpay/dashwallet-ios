//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

@testable import dashpay
import SQLite
import SwiftDashSDK
import SwiftData
import XCTest

/// AC-21b (ADR-0077): a rise of the Current identity's balance that the wallet's own operations do not explain is one
/// Received row with the unexplained amount; the wallet's own credits to the identity never are.
@MainActor
final class IdentityCreditActivityTests: XCTestCase {
    private let walletId = Data(repeating: 0x5A, count: 32)
    private let otherWalletId = Data(repeating: 0x5B, count: 32)
    private let identityId = Data(repeating: 0x21, count: 32)
    private let networkRaw: Int64 = 1
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let creditsPerDuff: UInt64 = 1_000

    private func makeDAO() throws -> IdentityCreditActivityDAO {
        let connection = try Connection(.inMemory)
        try AddIdentityCreditActivityTables().migrateDatabase(connection)
        return IdentityCreditActivityDAO(connection: { connection })
    }

    private func makeLedger() throws -> CreditSendActivityDAO {
        let connection = try Connection(.inMemory)
        try AddCreditSendActivityTable().migrateDatabase(connection)
        return CreditSendActivityDAO(connection: { connection })
    }

    @discardableResult
    private func observe(
        _ duffs: UInt64, own: [IdentityOwnCredit] = [], walletId: Data? = nil, networkRaw: Int64? = nil,
        at date: Date? = nil, generation: UInt64? = nil, dao: IdentityCreditActivityDAO
    ) -> IdentityCreditActivityRecorder.Outcome {
        // The traces the wallet holds; the recorder asks for those written after a date, as the store does.
        IdentityCreditActivityRecorder.observe(
            balanceCredits: duffs * creditsPerDuff, identityId: identityId, walletId: walletId ?? self.walletId,
            networkRaw: networkRaw ?? self.networkRaw, readStart: date ?? now,
            generation: generation ?? dao.generation, ownCredits: { after in own.filter { $0.date > after } },
            dao: dao)
    }

    private func rows(_ dao: IdentityCreditActivityDAO, walletId: Data? = nil) -> [Int64] {
        dao.activities(walletId: walletId ?? self.walletId, networkRaw: networkRaw).map(\.amountDuffs)
    }

    private func own(_ key: String, _ duffs: Int64, at date: Date, pending: Bool = false) -> IdentityOwnCredit {
        IdentityOwnCredit(key: key, amountDuffs: duffs, date: date, isPending: pending)
    }

    private func minutes(_ value: Double) -> Date { now.addingTimeInterval(value * 60) }

    // MARK: - Recorder

    func testTheFirstReadSeedsTheBaselineWithoutARow() throws {
        let dao = try makeDAO()
        XCTAssertEqual(observe(5_000, dao: dao), .seeded, "a standing balance is not something received today")
        XCTAssertEqual(rows(dao), [])
        XCTAssertEqual(dao.baseline(walletId: walletId, networkRaw: networkRaw, identityId: identityId), 5_000)
    }

    func testARiseNoOwnOperationExplainsIsOneReceivedRowWithTheAmountAndTheBalanceAfter() throws {
        let dao = try makeDAO()
        observe(5_000, at: minutes(-1), dao: dao)
        XCTAssertEqual(observe(6_042, dao: dao), .received(duffs: 1_042))
        let record = try XCTUnwrap(dao.activities(walletId: walletId, networkRaw: networkRaw).first)
        XCTAssertEqual(record.amountDuffs, 1_042)
        XCTAssertEqual(record.balanceAfterDuffs, 6_042)
        XCTAssertEqual(record.identityId, identityId)
        XCTAssertEqual(record.observedAt, now)
        XCTAssertEqual(observe(6_042, at: minutes(1), dao: dao), .unchanged, "the same balance read again adds nothing")
        XCTAssertEqual(rows(dao), [1_042])
    }

    func testAFallMovesTheBaselineSilentlyAndTheNextRiseCountsFromIt() throws {
        let dao = try makeDAO()
        observe(5_000, at: minutes(-2), dao: dao)
        XCTAssertEqual(observe(3_000, at: minutes(-1), dao: dao), .unchanged, "an own spend has its own row")
        XCTAssertEqual(observe(3_500, dao: dao), .received(duffs: 500))
        XCTAssertEqual(rows(dao), [500])
    }

    func testAnOwnCreditBetweenTheTwoReadsHidesTheRise() throws {
        let dao = try makeDAO()
        observe(5_000, at: minutes(-10), dao: dao)
        // A lock's value exceeds the credits Platform grants by the processing fee.
        XCTAssertEqual(observe(5_990, own: [own("lock:aa:0", 1_000, at: minutes(-5))], dao: dao), .unchanged)
        XCTAssertEqual(rows(dao), [])
    }

    func testARiseAboveTheOwnCreditsRecordsOnlyTheRemainder() throws {
        let dao = try makeDAO()
        observe(5_000, at: minutes(-10), dao: dao)
        let own = [own("ledger:op1", 1_000, at: minutes(-5)), own("shielded:0:ab", 500, at: minutes(-3))]
        XCTAssertEqual(observe(8_000, own: own, dao: dao), .received(duffs: 1_500),
                       "someone else's credits read together with the wallet's own")
        XCTAssertEqual(rows(dao), [1_500])
    }

    func testAnOwnCreditCountsForOneReadOnlyEvenWhenItsTraceIsReDated() throws {
        // The SDK stamps its rows again on every write: a counted trace dated after the next read stays counted.
        let dao = try makeDAO()
        observe(5_000, at: minutes(-10), dao: dao)
        XCTAssertEqual(observe(6_000, own: [own("lock:aa:0", 1_000, at: minutes(-5))], at: minutes(-1), dao: dao),
                       .unchanged)
        XCTAssertEqual(observe(7_000, own: [own("lock:aa:0", 1_000, at: minutes(-0.5))], dao: dao),
                       .received(duffs: 1_000))
    }

    func testATraceWrittenDuringTheReadCountsForTheNextOne() throws {
        let dao = try makeDAO()
        observe(5_000, at: minutes(-10), dao: dao)
        let topUp = own("lock:aa:0", 1_000, at: minutes(-4))
        // The read started before the top-up and its answer does not hold it yet.
        XCTAssertEqual(observe(5_000, own: [topUp], at: minutes(-5), dao: dao), .unchanged)
        XCTAssertEqual(observe(6_000, own: [topUp], dao: dao), .unchanged, "the top-up lands in the next read")
        XCTAssertEqual(rows(dao), [])
    }

    func testAnOwnCreditAlreadyInTheSeededBalanceDoesNotHideALaterPayment() throws {
        let dao = try makeDAO()
        let topUp = own("lock:aa:0", 1_000, at: minutes(-30))
        XCTAssertEqual(observe(6_000, own: [topUp], at: minutes(-20), dao: dao), .seeded)
        XCTAssertEqual(observe(6_800, own: [topUp], dao: dao), .received(duffs: 800))
    }

    func testAnOwnCreditOutweighedByASpendDoesNotHideALaterPayment() throws {
        let dao = try makeDAO()
        let topUp = own("lock:aa:0", 1_000, at: minutes(-15))
        observe(5_000, at: minutes(-20), dao: dao)
        XCTAssertEqual(observe(4_500, own: [topUp], at: minutes(-10), dao: dao), .unchanged,
                       "a top-up of 1 000 and a spend of 1 500")
        XCTAssertEqual(observe(5_300, own: [topUp], dao: dao), .received(duffs: 800))
    }

    func testAnUnconfirmedSendExplainsTheFirstRiseAfterItOnly() throws {
        // Submitted, its result unknown: its credit may come after the next read.
        let dao = try makeDAO()
        let pending = own("ledger:op", 1_000, at: minutes(-30), pending: true)
        observe(5_000, at: minutes(-40), dao: dao)
        XCTAssertEqual(observe(5_000, own: [pending], at: minutes(-20), dao: dao), .unchanged)
        XCTAssertFalse(dao.isClaimed(walletId: walletId, networkRaw: networkRaw, key: pending.key))
        XCTAssertEqual(observe(6_000, own: [pending], at: minutes(-10), dao: dao), .unchanged, "it executed")
        XCTAssertEqual(observe(7_000, own: [pending], dao: dao), .received(duffs: 1_000))
    }

    func testAnUnconfirmedSendOlderThanTheWindowExplainsNothing() throws {
        let dao = try makeDAO()
        let window = IdentityCreditActivityRecorder.pendingWindow
        observe(5_000, at: now.addingTimeInterval(-window - 600), dao: dao)
        let pending = own("ledger:op", 1_000, at: now.addingTimeInterval(-window - 60), pending: true)
        XCTAssertEqual(observe(6_000, own: [pending], dao: dao), .received(duffs: 1_000))
    }

    func testOwnCreditsAreAskedForFromThePreviousReadOfTheIdentity() throws {
        // The Current identity switched away and back: its top-ups made in between are still its own.
        let dao = try makeDAO()
        let dayAgo = now.addingTimeInterval(-24 * 60 * 60)
        observe(5_000, at: dayAgo, dao: dao)
        var asked: Date?
        let outcome = IdentityCreditActivityRecorder.observe(
            balanceCredits: 6_000 * creditsPerDuff, identityId: identityId, walletId: walletId, networkRaw: networkRaw,
            readStart: now, generation: dao.generation,
            ownCredits: { after in
                asked = after
                return [IdentityOwnCredit(key: "lock:aa:0", amountDuffs: 1_000, date: dayAgo.addingTimeInterval(60))]
            },
            dao: dao)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(asked, dayAgo)
    }

    func testAReadAnsweredAfterTheHistoryWasDeletedWritesNothing() throws {
        let dao = try makeDAO()
        observe(5_000, at: minutes(-2), dao: dao)
        let before = dao.generation
        try dao.delete(walletId: walletId)
        XCTAssertEqual(observe(6_000, generation: before, dao: dao), .dropped)
        XCTAssertNil(dao.baseline(walletId: walletId, networkRaw: networkRaw, identityId: identityId))
        XCTAssertEqual(rows(dao), [])
    }

    func testAFailedWriteKeepsTheBaselineSoTheNextReadSeesTheRiseAgain() throws {
        let connection = try Connection(.inMemory)
        try AddIdentityCreditActivityTables().migrateDatabase(connection)
        let dao = IdentityCreditActivityDAO(connection: { connection })
        observe(5_000, at: minutes(-1), dao: dao)
        try connection.run(IdentityCreditActivitySchema.activity.drop())

        XCTAssertEqual(observe(6_000, dao: dao), .failed)
        XCTAssertEqual(dao.baseline(walletId: walletId, networkRaw: networkRaw, identityId: identityId), 5_000,
                       "the row and the baseline are written together or not at all")

        try AddIdentityCreditActivityTables().migrateDatabase(connection)
        XCTAssertEqual(observe(6_000, at: minutes(1), dao: dao), .received(duffs: 1_000))
    }

    func testRowsAndBaselinesBelongToOneWalletAndNetwork() throws {
        let dao = try makeDAO()
        observe(5_000, at: minutes(-1), dao: dao)
        observe(6_000, dao: dao)
        XCTAssertEqual(observe(9_000, walletId: otherWalletId, dao: dao), .seeded,
                       "another wallet has its own baseline")
        XCTAssertEqual(observe(9_000, networkRaw: 2, dao: dao), .seeded, "another network has its own baseline")
        XCTAssertEqual(rows(dao), [1_000])
        XCTAssertEqual(rows(dao, walletId: otherWalletId), [])
        XCTAssertEqual(dao.activities(walletId: walletId, networkRaw: 2), [])
    }

    func testRemovingAWalletDeletesItsRowsBaselineAndClaimsOnly() throws {
        let dao = try makeDAO()
        observe(5_000, at: minutes(-2), dao: dao)
        observe(5_500, own: [own("ledger:a", 1_000, at: minutes(-1.5))], at: minutes(-1), dao: dao)
        XCTAssertTrue(dao.isClaimed(walletId: walletId, networkRaw: networkRaw, key: "ledger:a"))
        observe(6_000, dao: dao)
        observe(5_000, walletId: otherWalletId, at: minutes(-1), dao: dao)
        observe(5_200, walletId: otherWalletId, dao: dao)

        try dao.delete(walletId: walletId)

        XCTAssertEqual(rows(dao), [])
        XCTAssertNil(dao.baseline(walletId: walletId, networkRaw: networkRaw, identityId: identityId))
        XCTAssertFalse(dao.isClaimed(walletId: walletId, networkRaw: networkRaw, key: "ledger:a"))
        XCTAssertEqual(rows(dao, walletId: otherWalletId), [200])
        XCTAssertEqual(observe(7_000, at: minutes(1), dao: dao), .seeded, "a restored wallet starts from its balance")

        try dao.deleteAll()
        XCTAssertEqual(rows(dao, walletId: otherWalletId), [])
        XCTAssertNil(dao.baseline(walletId: otherWalletId, networkRaw: networkRaw, identityId: identityId))
    }

    func testAReceivedRowPostsTheHistoryReloadSignal() throws {
        let dao = try makeDAO()
        observe(5_000, at: minutes(-1), dao: dao)
        let posted = expectation(forNotification: .identityCreditActivityRecorded, object: nil)
        observe(5_100, dao: dao)
        wait(for: [posted], timeout: 1)
    }

    // MARK: - Own credits from the wallet's traces

    private func makeContainer(identityIndex: UInt32 = 3) throws -> ModelContainer {
        let container = try DashModelContainer.inMemoryWithoutCloudKit()
        let wallet = PersistentWallet(walletId: walletId, network: .testnet)
        let identity = PersistentIdentity(identityId: identityId, network: .testnet, identityIndex: identityIndex)
        container.mainContext.insert(wallet)
        container.mainContext.insert(identity)
        identity.wallet = wallet
        try container.mainContext.save()
        return container
    }

    private func lock(
        _ outPoint: String, type: Int = 1, index: Int32 = 3, status: Int = 4, duffs: Int64 = 1_000,
        walletId: Data? = nil, updatedAt: Date? = nil
    ) -> PersistentAssetLock {
        let lock = PersistentAssetLock(
            outPointHex: outPoint, walletId: walletId ?? self.walletId, transactionBytes: Data(),
            fundingTypeRaw: type, identityIndexRaw: index, amountDuffs: duffs, statusRaw: status)
        lock.updatedAt = updatedAt ?? now
        return lock
    }

    private func shielded(
        _ entry: UInt8, kind: Int = 9, status: Int = 1, credits: UInt64 = 500_000, identity: Data? = nil,
        confirmedAt date: Date? = nil
    ) -> PersistentShieldedActivity {
        let row = PersistentShieldedActivity(
            walletId: walletId, accountIndex: 0, entryId: Data(repeating: entry, count: 32), kindTag: kind,
            direction: 1, status: status, amount: credits, fee: 0, hasFee: false, blockHeight: 0,
            hasBlockHeight: false, createdAtMs: UInt64(after.addingTimeInterval(-3600).timeIntervalSince1970 * 1000),
            identityId: identity ?? identityId, counterparty: Data(), memo: Data(), noteCmxs: Data(),
            spentNullifiers: Data())
        row.lastUpdated = date ?? now
        return row
    }

    /// The previous read: traces up to it are in its balance.
    private var after: Date { now.addingTimeInterval(-600) }

    private func ownCredits(container: ModelContainer, ledger: CreditSendActivityDAO) -> [String: Int64] {
        let credits = IdentityCreditActivityRecorder.ownCredits(
            identityId: identityId, walletId: walletId, networkRaw: networkRaw, after: after,
            container: container, creditSends: ledger)
        return Dictionary(uniqueKeysWithValues: credits.map { ($0.key, $0.amountDuffs) })
    }

    func testEveryOwnRouteToTheIdentityLeavesACreditAndNothingElseDoes() throws {
        let container = try makeContainer()
        let ledger = try makeLedger()
        let context = container.mainContext
        let tooOld = after // credited by the previous read: in its balance already

        // Core: a consumed top-up lock for the identity's index.
        context.insert(lock("aa:0"))
        context.insert(lock("ab:0", type: 2)) // a top-up of someone else's identity
        context.insert(lock("ac:0", index: 4)) // another identity of the wallet
        context.insert(lock("ad:0", status: 2)) // locked, not credited yet
        context.insert(lock("ae:0", type: 0)) // a registration
        context.insert(lock("af:0", walletId: otherWalletId))
        context.insert(lock("ag:0", updatedAt: tooOld))
        // Shielded: the pool's identity top-up for this identity.
        context.insert(shielded(0x01))
        context.insert(shielded(0x02, status: 2)) // failed
        context.insert(shielded(0x06, status: 0)) // pending: not credited yet
        context.insert(shielded(0x03, kind: 3)) // an ordinary shielded send
        context.insert(shielded(0x04, identity: Data(repeating: 0x22, count: 32)))
        context.insert(shielded(0x05, confirmedAt: tooOld))
        try context.save()

        // Platform or another identity: the ledger's send to this identity.
        let destination = identityId.toBase58String()
        func send(_ op: String, _ kind: CreditSendDestinationKind, _ to: String, status: CreditSendStatus = .sent,
                  at date: Date? = nil) {
            ledger.insert(
                CreditSend(source: .platform, destinationKind: kind, destination: to, amountDuffs: 700),
                operationId: op, walletId: walletId, networkRaw: networkRaw, status: status, sentAt: date ?? now)
        }
        send("op-sent", .identity, destination)
        send("op-pending", .identity, destination, status: .pending)
        send("op-other-identity", .identity, Data(repeating: 0x22, count: 32).toBase58String())
        send("op-platform", .platform, "tdash1krma5z0gmqlwsr8c7n8ac8c3g2xk9ns0ue2k9yh")
        send("op-old", .identity, destination, at: tooOld)

        let found = IdentityCreditActivityRecorder.ownCredits(
            identityId: identityId, walletId: walletId, networkRaw: networkRaw, after: after,
            container: container, creditSends: ledger)
        XCTAssertEqual(found.filter(\.isPending).map(\.key), ["ledger:op-pending"])
        XCTAssertEqual(ownCredits(container: container, ledger: ledger), [
            "lock:aa:0": 1_000,
            "ledger:op-sent": 700,
            "ledger:op-pending": 700,
            "shielded:0:" + String(repeating: "01", count: 32): 500,
        ])
    }

    func testAnIdentityOfAnotherWalletHasNoCoreCredits() throws {
        let container = try makeContainer()
        let identity = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<PersistentIdentity>()).first)
        let other = PersistentWallet(walletId: otherWalletId, network: .testnet)
        container.mainContext.insert(other)
        identity.wallet = other
        container.mainContext.insert(lock("aa:0"))
        try container.mainContext.save()
        XCTAssertEqual(ownCredits(container: container, ledger: try makeLedger()), [:])
    }

    // MARK: - History row

    func testTheRowReadsReceivedWithTheIdentityNameAndTheAmount() {
        let item = IdentityCreditActivityItem(
            record: IdentityCreditActivityRecord(
                id: 9, walletId: walletId, networkRaw: networkRaw, identityId: identityId, amountDuffs: 1_042,
                balanceAfterDuffs: 6_042, observedAt: now),
            identityName: "alice")
        XCTAssertEqual(item.title, String(localized: "Received", comment: ""))
        XCTAssertEqual(item.detailsText, "alice")
        XCTAssertEqual(item.signedDashAmount, 1_042)
        XCTAssertEqual(item.id, "identity-credit-9")
        XCTAssertEqual(TransactionListDataItem.identityCredit(item).date, now)
    }
}
