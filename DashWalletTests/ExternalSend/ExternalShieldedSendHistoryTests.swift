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
import SwiftDashSDK
import XCTest

private final class QuietDetailModel: TxDetailModel {
    override func resolveSwapExplorerLink(completion: @escaping () -> Void) {}
    override func observeSwapOrderPlaceholder(onChange: @escaping () -> Void) {}
}

/// A Core → Shielded asset lock pays someone else's Shielded address, moves the wallet's own funds, or pays an address
/// whose owner cannot be told now; History tells the three apart. A payment reads "Sent" only once Platform consumed
/// the lock, and its amount is named as what was locked. The decision is made once, in
/// `ShieldedTxLookup.resolvingRecipients`; the home row and the details read it through `Transaction`.
final class ExternalShieldedSendHistoryTests: XCTestCase {
    private typealias Info = ShieldedTxLookup.ShieldedLockInfo

    private let txidWire = Data((0..<32).map { UInt8(0x60 + $0) })
    private let walletId = Data(repeating: 1, count: 32)
    private let recipient = Data(repeating: 7, count: 43)
    private let amount: UInt64 = 25_000_000

    private var txidHex: String { Transaction.displayHex(txidWire).lowercased() }
    private var recipientAddress: String? { Bech32m.shieldedDisplayAddress(raw43: recipient, mainnet: false) }

    private func lock(recipient: Data?, fundingType: Int = 5,
                      status: Int = AssetLockRecoveryService.consumedStatus) -> Info {
        Info(amountDuffs: amount, statusRaw: status, vout: 0,
             fundingTypeRaw: fundingType, walletId: walletId, drainOperation: nil, recipientRaw43: recipient)
    }

    @MainActor
    private func resolved(_ info: Info, isOwn: Bool?) -> Info {
        let map = ShieldedTxLookup.resolvingRecipients(of: [txidHex: info], mainnet: false) { _, _ in isOwn }
        XCTAssertEqual(map.count, 1)
        return map[txidHex] ?? info
    }

    /// Runs `body` on the lock's funding transaction with `info` in the shared lookup that History and the details
    /// read, and puts the lookup back afterwards. The net-change view reads an asset lock as a move.
    @MainActor
    private func withLock(_ info: Info, _ body: (Transaction) -> Void) {
        let lookup = ShieldedTxLookup.shared
        let saved = Dictionary(uniqueKeysWithValues: lookup.allEntries().map { ($0.txidHex, $0.info) })
        defer { lookup.store(saved) }
        lookup.store([txidHex: info])
        body(Transaction(syntheticTxid: txidWire, directionRaw: 2, netAmount: -1_000, fee: 1_000, contextRaw: 3,
                         date: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    // MARK: - The choke point

    @MainActor
    func testAnOwnRecipientStaysAnInternalTransfer() {
        XCTAssertEqual(resolved(lock(recipient: recipient), isOwn: true).recipient, .own)
    }

    @MainActor
    func testAnExternalRecipientIsASendWithItsAddress() {
        let info = resolved(lock(recipient: recipient), isOwn: false)
        XCTAssertEqual(info.recipient, recipientAddress.map { .external(address: $0) })
        XCTAssertEqual(recipientAddress?.hasPrefix("tdash1"), true)
    }

    @MainActor
    func testALockWithoutARecordedRecipientStaysAnInternalTransfer() {
        var asked = false
        let map = ShieldedTxLookup.resolvingRecipients(of: [txidHex: lock(recipient: nil)], mainnet: false) { _, _ in
            asked = true
            return false
        }
        XCTAssertEqual(map[txidHex], lock(recipient: nil))
        XCTAssertFalse(asked, "nothing to ask about")
    }

    @MainActor
    func testAnUndecidedOwnerIsKeptApartFromBothReadings() {
        XCTAssertEqual(resolved(lock(recipient: recipient), isOwn: nil).recipient,
                       recipientAddress.map { .undecided(address: $0) })
    }

    @MainActor
    func testOnlyAShieldedLockIsResolved() {
        XCTAssertNil(resolved(lock(recipient: recipient, fundingType: 4), isOwn: false).recipient)
    }

    /// The consumed overlay rebuilds the entry: it keeps the recipient.
    @MainActor
    func testAConsumedMarkKeepsTheRecipient() {
        let lookup = ShieldedTxLookup()
        lookup.store([txidHex: resolved(lock(recipient: recipient), isOwn: false)])
        lookup.markConsumed(txidWire: txidWire)
        XCTAssertEqual(lookup.info(forTxidHex: txidHex)?.recipient, recipientAddress.map { .external(address: $0) })
    }

    // MARK: - Transaction

    @MainActor
    func testTheTransactionOfAnExternalSendReadsAsSent() {
        withLock(resolved(lock(recipient: recipient), isOwn: false)) { tx in
            XCTAssertEqual(tx.shieldedRecipientAddress, recipientAddress)
            XCTAssertNil(tx.internalTransferRoute)
            XCTAssertEqual(tx.direction, .sent)
            XCTAssertEqual(tx.stateTitle, String(localized: "Sent", comment: ""))
            XCTAssertEqual(tx.signedDashAmount, -Int64(amount))
        }
    }

    @MainActor
    func testTheTransactionOfAnOwnTransferStaysAnInternalTransfer() {
        for info in [resolved(lock(recipient: recipient), isOwn: true), lock(recipient: nil)] {
            withLock(info) { tx in
                XCTAssertNil(tx.shieldedRecipientAddress)
                XCTAssertEqual(tx.internalTransferRoute, .coreToShielded)
                XCTAssertEqual(tx.direction, .moved)
                XCTAssertEqual(tx.stateTitle, String(localized: "Internal Transfer", comment: ""))
                XCTAssertEqual(tx.signedDashAmount, Int64(amount))
            }
        }
    }

    /// Core confirms the lock before Platform credits the recipient: until Platform consumed it, the payment is
    /// sending, whatever Core's state.
    @MainActor
    func testAnExternalSendWhoseLockIsNotConsumedReadsAsSending() {
        for status in [1, 2, 3, 5] {
            withLock(resolved(lock(recipient: recipient, status: status), isOwn: false)) { tx in
                XCTAssertEqual(tx.direction, .sent, "\(status)")
                XCTAssertEqual(tx.stateTitle, String(localized: "Sending", comment: ""), "\(status)")
            }
        }
    }

    /// An owner that cannot be told now is named neither a payment nor an own transfer, with the recorded address;
    /// a later answer gives the reading it decides.
    @MainActor
    func testAnUndecidedOwnerShowsTheAddressNeutrallyUntilItIsDecided() {
        withLock(resolved(lock(recipient: recipient), isOwn: nil)) { tx in
            XCTAssertEqual(tx.shieldedRecipientAddress, recipientAddress)
            XCTAssertNil(tx.internalTransferRoute)
            XCTAssertEqual(tx.stateTitle, String(localized: "Shielded transfer", comment: ""))
            XCTAssertEqual(QuietDetailModel(transaction: tx).title, String(localized: "Amount locked", comment: ""))
        }
        withLock(resolved(lock(recipient: recipient), isOwn: false)) { tx in
            XCTAssertEqual(tx.stateTitle, String(localized: "Sent", comment: ""))
        }
        withLock(resolved(lock(recipient: recipient), isOwn: true)) { tx in
            XCTAssertEqual(tx.stateTitle, String(localized: "Internal Transfer", comment: ""))
        }
    }

    // MARK: - Home row

    @MainActor
    func testTheHomeRowOfAnExternalSendShowsTheShortRecipient() {
        withLock(resolved(lock(recipient: recipient), isOwn: false)) { tx in
            let address = recipientAddress ?? ""
            XCTAssertEqual(HomeTransactionRoute.details(of: tx),
                           String(address.prefix(6)) + "…" + String(address.suffix(6)))
            XCTAssertNil(HomeTransactionRoute.symbols(of: tx), "the sent icon, not the route pair")
        }
    }

    @MainActor
    func testTheHomeRowOfAnOwnTransferShowsTheRoute() {
        withLock(resolved(lock(recipient: recipient), isOwn: true)) { tx in
            XCTAssertEqual(HomeTransactionRoute.details(of: tx),
                           String(localized: "Transparent → Shielded", comment: ""))
            XCTAssertNotNil(HomeTransactionRoute.symbols(of: tx))
        }
    }

    // MARK: - Details

    private func toRow(of model: TxDetailModel) -> String? {
        model.shieldedInfo().first { $0.title == String(localized: "To", comment: "") }?.plainDetail
    }

    @MainActor
    func testTheDetailsOfAnExternalSendNameTheRecipient() {
        withLock(resolved(lock(recipient: recipient), isOwn: false)) { tx in
            let model = QuietDetailModel(transaction: tx)
            XCTAssertEqual(model.title, String(localized: "Amount locked", comment: ""),
                           "the lock carries the pool fee, so it is not what the recipient received")
            XCTAssertEqual(toRow(of: model), recipientAddress)
        }
    }

    @MainActor
    func testTheDetailsOfAnOwnTransferNameTheShieldedBalance() {
        withLock(lock(recipient: nil)) { tx in
            let model = QuietDetailModel(transaction: tx)
            XCTAssertEqual(model.title, String(localized: "Internal Transfer", comment: ""))
            XCTAssertEqual(toRow(of: model), String(localized: "Shielded balance", comment: ""))
        }
    }
}
