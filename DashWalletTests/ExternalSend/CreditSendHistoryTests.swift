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

/// Every completed Platform- or identity-source send has exactly one History row: Sent with its recipient when it
/// paid someone else, Internal Transfer when it paid the wallet's own address or identity. The app records the send
/// where it makes it (`CreditSendLedger.recording`); a sync-derived reading of the same send defers to that row.
final class CreditSendHistoryTests: XCTestCase {
    private struct Unrelated: Error {}

    private let walletId = Data(repeating: 0x5A, count: 32)
    private let otherWalletId = Data(repeating: 0x5B, count: 32)
    private let networkRaw: Int64 = 1
    private let sentAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let coreAddress = "yP8A3cbdxRtLRduy5mXDsBnJtMzHWs6ZXr"
    private let platformAddress = "tdash1krma5z0gmqlwsr8c7n8ac8c3g2xk9ns0ue2k9yh"
    private let identity = "8kSGh4JiXHrswkG5ckapT6zkJ3qrH1V9X2ELYrQo4Jdy"

    private var owner: CreditSendLedger.Owner { .init(walletId: walletId, networkRaw: networkRaw) }

    /// Runs `spend` through the ledger for this test's wallet, or for no wallet.
    @MainActor
    private func record(
        _ send: CreditSend, into dao: CreditSendActivityDAO, hasWallet: Bool = true, spend: () async throws -> Void
    ) async throws {
        let owner = hasWallet ? self.owner : nil
        try await CreditSendLedger.recording(send, owner: { owner }, dao: dao, now: { self.sentAt }, spend)
    }

    private func makeDAO(path: String? = nil) throws -> CreditSendActivityDAO {
        let connection = try path.map { try Connection($0) } ?? Connection(.inMemory)
        try AddCreditSendActivityTable().migrateDatabase(connection)
        return CreditSendActivityDAO(connection: { connection })
    }

    private func send(
        _ source: CreditSendSource, _ kind: CreditSendDestinationKind, amountDuffs: UInt64 = 1_000_000
    ) -> CreditSend {
        let destination: String
        switch kind {
        case .core: destination = coreAddress
        case .platform: destination = platformAddress
        case .identity: destination = identity
        }
        return CreditSend(source: source, destinationKind: kind, destination: destination, amountDuffs: amountDuffs)
    }

    private var everyRoute: [CreditSend] {
        [send(.platform, .core), send(.platform, .platform), send(.platform, .identity),
         send(.identity, .core), send(.identity, .platform), send(.identity, .identity)]
    }

    // MARK: - The ledger

    @MainActor
    func testACompletedSendOfEveryRouteRecordsOneSentRow() async throws {
        for route in everyRoute {
            let dao = try makeDAO()
            try await record(route, into: dao) {}
            let records = dao.records(walletId: walletId, networkRaw: networkRaw)
            XCTAssertEqual(records.count, 1, "\(route)")
            XCTAssertEqual(records.first?.send, route)
            XCTAssertEqual(records.first?.status, .sent)
            XCTAssertEqual(records.first?.sentAt, sentAt)
        }
    }

    @MainActor
    func testAnUnconfirmedSendIsRecordedPendingAndTheErrorRethrown() async throws {
        let unconfirmed: [Error] = [
            SDKError.stateTransitionResultUnconfirmed("test"),
            PlatformWalletError.transactionBroadcastUnconfirmed("test"),
            PlatformWalletError.shieldedSpendUnconfirmed("test"),
        ]
        for error in unconfirmed {
            let dao = try makeDAO()
            do {
                try await record(send(.identity, .identity), into: dao) { throw error }
                XCTFail("rethrows")
            } catch {}
            XCTAssertEqual(dao.records(walletId: walletId, networkRaw: networkRaw).map(\.status), [.pending])
        }
    }

    @MainActor
    func testARefusedSendRecordsNothing() async throws {
        let dao = try makeDAO()
        do {
            try await record(send(.platform, .core), into: dao) { throw Unrelated() }
            XCTFail("rethrows")
        } catch is Unrelated {}
        XCTAssertTrue(dao.records(walletId: walletId, networkRaw: networkRaw).isEmpty)
    }

    @MainActor
    func testWithoutAWalletNothingIsRecorded() async throws {
        let dao = try makeDAO()
        try await record(send(.platform, .platform), into: dao, hasWallet: false) {}
        XCTAssertTrue(dao.records(walletId: walletId, networkRaw: networkRaw).isEmpty)
    }

    // MARK: - The store

    func testAnOperationIsRecordedOnce() throws {
        let dao = try makeDAO()
        XCTAssertTrue(dao.insert(send(.platform, .core), operationId: "op", walletId: walletId, networkRaw: networkRaw,
                                 status: .sent, sentAt: sentAt))
        XCTAssertFalse(dao.insert(send(.platform, .core), operationId: "op", walletId: walletId,
                                  networkRaw: networkRaw, status: .pending, sentAt: sentAt))
        XCTAssertEqual(dao.records(walletId: walletId, networkRaw: networkRaw).map(\.status), [.sent])
    }

    func testRecordsSurviveAReopenedStore() throws {
        let path = NSTemporaryDirectory() + "credit-send-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try makeDAO(path: path).insert(send(.identity, .platform), operationId: "op", walletId: walletId,
                                       networkRaw: networkRaw, status: .pending, sentAt: sentAt)
        let reopened = try makeDAO(path: path)
        let records = reopened.records(walletId: walletId, networkRaw: networkRaw)
        XCTAssertEqual(records.map(\.send), [send(.identity, .platform)])
        XCTAssertEqual(records.map(\.status), [.pending])
        XCTAssertEqual(records.first?.sentAt, sentAt)
    }

    func testRecordsAreScopedByWalletAndNetwork() throws {
        let dao = try makeDAO()
        dao.insert(send(.platform, .core), operationId: "a", walletId: walletId, networkRaw: networkRaw,
                   status: .sent, sentAt: sentAt)
        dao.insert(send(.platform, .core), operationId: "b", walletId: otherWalletId, networkRaw: networkRaw,
                   status: .sent, sentAt: sentAt)
        dao.insert(send(.platform, .core), operationId: "c", walletId: walletId, networkRaw: 0,
                   status: .sent, sentAt: sentAt)
        XCTAssertEqual(dao.records(walletId: walletId, networkRaw: networkRaw).map(\.operationId), ["a"])
    }

    func testAWipeOfOneWalletKeepsTheOthers() throws {
        let dao = try makeDAO()
        dao.insert(send(.platform, .core), operationId: "a", walletId: walletId, networkRaw: networkRaw,
                   status: .sent, sentAt: sentAt)
        dao.insert(send(.identity, .core), operationId: "b", walletId: otherWalletId, networkRaw: networkRaw,
                   status: .sent, sentAt: sentAt)
        XCTAssertEqual(dao.withdrawalSource(toCoreAddress: coreAddress, walletId: walletId), .platform)

        dao.delete(walletId: walletId)
        XCTAssertTrue(dao.records(walletId: walletId, networkRaw: networkRaw).isEmpty)
        XCTAssertNil(dao.withdrawalSource(toCoreAddress: coreAddress, walletId: walletId), "the cache is cleared too")
        XCTAssertEqual(dao.withdrawalSource(toCoreAddress: coreAddress, walletId: otherWalletId), .identity)

        dao.deleteAll()
        XCTAssertTrue(dao.records(walletId: otherWalletId, networkRaw: networkRaw).isEmpty)
        XCTAssertNil(dao.withdrawalSource(toCoreAddress: coreAddress, walletId: otherWalletId))
    }

    func testOnlyAWithdrawalNamesACoreDestination() throws {
        let dao = try makeDAO()
        dao.insert(send(.identity, .platform), operationId: "a", walletId: walletId, networkRaw: networkRaw,
                   status: .sent, sentAt: sentAt)
        XCTAssertNil(dao.withdrawalSource(toCoreAddress: platformAddress, walletId: walletId))
        dao.insert(send(.identity, .core), operationId: "b", walletId: walletId, networkRaw: networkRaw,
                   status: .sent, sentAt: sentAt)
        XCTAssertEqual(dao.withdrawalSource(toCoreAddress: coreAddress, walletId: walletId), .identity)
    }

    // MARK: - A synced increase on an own Platform address

    func testAnIncreaseOnTheDestinationClaimsTheSendOnce() throws {
        let dao = try makeDAO()
        dao.insert(send(.platform, .platform, amountDuffs: 1_000_000), operationId: "a", walletId: walletId,
                   networkRaw: networkRaw, status: .pending, sentAt: sentAt)
        let since = sentAt.addingTimeInterval(-60)
        XCTAssertFalse(dao.claimIncrease(walletId: walletId, networkRaw: networkRaw, address: platformAddress,
                                         deltaDuffs: 1_000_001, since: since), "more than the send paid")
        XCTAssertFalse(dao.claimIncrease(walletId: walletId, networkRaw: networkRaw, address: "tdash1other",
                                         deltaDuffs: 1_000_000, since: since))
        XCTAssertFalse(dao.claimIncrease(walletId: walletId, networkRaw: networkRaw, address: platformAddress,
                                         deltaDuffs: 1_000_000, since: sentAt.addingTimeInterval(60)), "too old")
        XCTAssertTrue(dao.claimIncrease(walletId: walletId, networkRaw: networkRaw, address: platformAddress,
                                        deltaDuffs: 1_000_000, since: since))
        XCTAssertEqual(dao.records(walletId: walletId, networkRaw: networkRaw).map(\.status), [.sent],
                       "the increase proves the pending send executed")
        XCTAssertFalse(dao.claimIncrease(walletId: walletId, networkRaw: networkRaw, address: platformAddress,
                                         deltaDuffs: 1_000_000, since: since), "a second increase is a payment")
    }

    @MainActor
    func testTheRecorderShowsNoReceivedRowForAnOwnSend() throws {
        // A wallet id of its own: the recorder writes the app's activity store.
        let wallet = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let container = try ShieldedWithdrawalHistoryFixture.makeContainer()
        let dao = try makeDAO()
        let networkRaw = Int64(Network.testnet.rawValue)
        func observe(_ balance: UInt64) {
            PlatformAddressActivityRecorder.observe(
                addresses: [DerivedPlatformAddress(address: platformAddress, accountIndex: 0, addressIndex: 0,
                                                   isUsed: true, balance: balance)],
                walletId: wallet, network: .testnet, container: container, creditSends: dao)
        }
        let activity = { PlatformAddressActivityDAO.shared.activities(walletId: wallet, networkRaw: networkRaw) }
        observe(0)
        dao.insert(send(.identity, .platform, amountDuffs: 1_000), operationId: "a", walletId: wallet,
                   networkRaw: networkRaw, status: .sent, sentAt: Date())
        observe(1_000 * 1_000)
        XCTAssertTrue(activity().isEmpty, "the send's own row covers it")

        observe(3_000 * 1_000)
        XCTAssertEqual(activity().map(\.amountDuffs), [2_000], "an unrelated increase is still received")
    }

    // MARK: - History rows

    @MainActor
    private func receipt(amountDuffs: UInt64, in container: ModelContainer) throws -> Transaction {
        let tx = PersistentTransaction(txid: Data(repeating: 0x71, count: 32), transactionData: Data(), context: 2,
                                       blockHeight: 100, direction: 0, netAmount: Int64(amountDuffs),
                                       firstSeen: UInt64(sentAt.timeIntervalSince1970) + 60)
        let output = PersistentTxo(transaction: tx, vout: 0, amount: amountDuffs, address: coreAddress,
                                   scriptPubKey: Data([0x76]), height: 100)
        tx.outputs = [output]
        container.mainContext.insert(tx)
        container.mainContext.insert(output)
        try container.mainContext.save()
        return Transaction(persistentTransaction: tx)
    }

    private func record(_ send: CreditSend, status: CreditSendStatus = .sent) -> CreditSendRecord {
        CreditSendRecord(id: 7, operationId: "op", walletId: walletId, networkRaw: networkRaw, send: send,
                         status: status, sentAt: sentAt)
    }

    func testASendToSomeoneElseReadsSentAndNamesTheRecipient() {
        for route in everyRoute {
            let items = SwiftDashSDKWalletSource.creditSendItems(
                records: [record(route)], coreTransactions: []) { _ in false }
            XCTAssertEqual(items.count, 1)
            let item = items[0]
            XCTAssertEqual(item.title, NSLocalizedString("Sent", comment: ""))
            XCTAssertEqual(item.detailsText, ShieldedActivityItem.shortAddress(route.destination))
            XCTAssertEqual(item.destinationName, route.destination)
            XCTAssertEqual(item.signedDashAmount, -1_000_000)
            XCTAssertEqual(item.secondarySymbol, "arrow.up")
            XCTAssertNil(item.trailingStatusText)
        }
    }

    func testASendToTheWalletsOwnAccountReadsInternalTransfer() {
        for route in everyRoute {
            let item = SwiftDashSDKWalletSource.creditSendItems(
                records: [record(route)], coreTransactions: []) { _ in true }.first
            XCTAssertEqual(item?.title, NSLocalizedString("Internal Transfer", comment: ""))
            XCTAssertNil(item?.detailsText)
            XCTAssertEqual(item?.signedDashAmount, 1_000_000, "own funds moved: no sign")
            XCTAssertNotEqual(item?.secondarySymbol, "arrow.up")
        }
    }

    func testAPendingSendSaysPending() {
        let item = SwiftDashSDKWalletSource.creditSendItems(
            records: [record(send(.identity, .identity), status: .pending)], coreTransactions: []) { _ in false }.first
        XCTAssertEqual(item?.trailingStatusText, NSLocalizedString("Pending", comment: ""))
    }

    func testTheSourceIsNamed() {
        let platform = CreditSendActivityItem(record: record(send(.platform, .core)), isOwnDestination: false)
        let identity = CreditSendActivityItem(record: record(send(.identity, .core)), isOwnDestination: false)
        XCTAssertEqual(platform.sourceSymbol, "creditcard.fill")
        XCTAssertEqual(identity.sourceSymbol, "person.crop.circle.fill")
        XCTAssertNotEqual(platform.sourceName, identity.sourceName)
    }

    @MainActor
    func testAnOwnWithdrawalGivesWayToItsCorePayout() throws {
        let container = try ShieldedWithdrawalHistoryFixture.makeContainer()
        let payout = try receipt(amountDuffs: 1_000_000, in: container)
        for source in [CreditSendSource.platform, .identity] {
            let own = SwiftDashSDKWalletSource.creditSendItems(
                records: [record(send(source, .core))], coreTransactions: [payout]) { _ in true }
            XCTAssertTrue(own.isEmpty, "the payout is the send's one row")
            let pendingBeforePayout = SwiftDashSDKWalletSource.creditSendItems(
                records: [record(send(source, .core), status: .pending)], coreTransactions: []) { _ in true }
            XCTAssertEqual(pendingBeforePayout.count, 1, "until the payout arrives the record is the row")
        }
    }

    /// The payout of a recorded withdrawal reads as an Internal Transfer from its source, not as a Received.
    @MainActor
    func testThePayoutReadsAsAnInternalTransfer() throws {
        let network = WalletEnvironment.networkKind
        let previous = WalletEnvironment.activeWalletId(for: network)
        let wallet = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        WalletEnvironment.setActiveWalletId(wallet, for: network)
        defer {
            CreditSendActivityDAO.shared.delete(walletId: wallet)
            WalletEnvironment.setActiveWalletId(previous, for: network)
        }
        let container = try ShieldedWithdrawalHistoryFixture.makeContainer()
        let payout = try receipt(amountDuffs: 1_000_000, in: container)
        XCTAssertNil(payout.internalTransferRoute)
        XCTAssertEqual(payout.stateTitle, NSLocalizedString("Received", comment: ""))

        CreditSendActivityDAO.shared.insert(send(.identity, .core), operationId: UUID().uuidString, walletId: wallet,
                                            networkRaw: networkRaw, status: .sent, sentAt: sentAt)
        XCTAssertEqual(payout.creditWithdrawalSource, .identity)
        XCTAssertEqual(payout.internalTransferRoute, .identityToCore)
        XCTAssertEqual(payout.stateTitle, NSLocalizedString("Internal Transfer", comment: ""))
        XCTAssertEqual(HomeTransactionRoute.symbols(of: payout)?.source, "person.crop.circle.fill")
    }
}
