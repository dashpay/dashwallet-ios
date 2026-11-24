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

/// A Core → Shielded asset lock reads as "Sent" with the recipient's address in History when it pays someone else's
/// Shielded address, and as an Internal Transfer only when it moves the wallet's own funds. The decision is made once,
/// in `ShieldedTxLookup.resolvingRecipients`; the home row and the details read it through `Transaction`.
final class ExternalShieldedSendHistoryTests: XCTestCase {
    private typealias Info = ShieldedTxLookup.ShieldedLockInfo

    private let txidWire = Data((0..<32).map { UInt8(0x60 + $0) })
    private let walletId = Data(repeating: 1, count: 32)
    private let recipient = Data(repeating: 7, count: 43)
    private let amount: UInt64 = 25_000_000

    private var txidHex: String { Transaction.displayHex(txidWire).lowercased() }
    private var recipientAddress: String? { Bech32m.shieldedDisplayAddress(raw43: recipient, mainnet: false) }

    private func lock(recipient: Data?, fundingType: Int = 5) -> Info {
        Info(amountDuffs: amount, statusRaw: AssetLockRecoveryService.consumedStatus, vout: 0,
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
        XCTAssertNil(resolved(lock(recipient: recipient), isOwn: true).externalRecipientAddress)
    }

    @MainActor
    func testAnExternalRecipientIsASendWithItsAddress() {
        let info = resolved(lock(recipient: recipient), isOwn: false)
        XCTAssertEqual(info.externalRecipientAddress, recipientAddress)
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
    func testAnUndecidedOwnerStaysAnInternalTransfer() {
        XCTAssertNil(resolved(lock(recipient: recipient), isOwn: nil).externalRecipientAddress)
    }

    @MainActor
    func testOnlyAShieldedLockIsResolved() {
        XCTAssertNil(resolved(lock(recipient: recipient, fundingType: 4), isOwn: false).externalRecipientAddress)
    }

    /// The consumed overlay rebuilds the entry: it keeps the recipient.
    @MainActor
    func testAConsumedMarkKeepsTheRecipient() {
        let lookup = ShieldedTxLookup()
        lookup.store([txidHex: resolved(lock(recipient: recipient), isOwn: false)])
        lookup.markConsumed(txidWire: txidWire)
        XCTAssertEqual(lookup.info(forTxidHex: txidHex)?.externalRecipientAddress, recipientAddress)
    }

    // MARK: - Transaction

    @MainActor
    func testTheTransactionOfAnExternalSendReadsAsSent() {
        withLock(resolved(lock(recipient: recipient), isOwn: false)) { tx in
            XCTAssertEqual(tx.externalShieldedRecipient, recipientAddress)
            XCTAssertNil(tx.internalTransferRoute)
            XCTAssertEqual(tx.direction, .sent)
            XCTAssertEqual(tx.stateTitle, NSLocalizedString("Sent", comment: ""))
            XCTAssertEqual(tx.signedDashAmount, -Int64(amount))
        }
    }

    @MainActor
    func testTheTransactionOfAnOwnTransferStaysAnInternalTransfer() {
        for info in [resolved(lock(recipient: recipient), isOwn: true), lock(recipient: nil)] {
            withLock(info) { tx in
                XCTAssertNil(tx.externalShieldedRecipient)
                XCTAssertEqual(tx.internalTransferRoute, .coreToShielded)
                XCTAssertEqual(tx.direction, .moved)
                XCTAssertEqual(tx.stateTitle, NSLocalizedString("Internal Transfer", comment: ""))
                XCTAssertEqual(tx.signedDashAmount, Int64(amount))
            }
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
                           NSLocalizedString("Transparent → Shielded", comment: ""))
            XCTAssertNotNil(HomeTransactionRoute.symbols(of: tx))
        }
    }

    // MARK: - Details

    private func toRow(of model: TxDetailModel) -> String? {
        model.shieldedInfo().first { $0.title == NSLocalizedString("To", comment: "") }?.plainDetail
    }

    @MainActor
    func testTheDetailsOfAnExternalSendNameTheRecipient() {
        withLock(resolved(lock(recipient: recipient), isOwn: false)) { tx in
            let model = QuietDetailModel(transaction: tx)
            XCTAssertEqual(model.title, NSLocalizedString("Amount Sent", comment: ""))
            XCTAssertEqual(toRow(of: model), recipientAddress)
        }
    }

    @MainActor
    func testTheDetailsOfAnOwnTransferNameTheShieldedBalance() {
        withLock(lock(recipient: nil)) { tx in
            let model = QuietDetailModel(transaction: tx)
            XCTAssertEqual(model.title, NSLocalizedString("Internal Transfer", comment: ""))
            XCTAssertEqual(toRow(of: model), NSLocalizedString("Shielded balance", comment: ""))
        }
    }
}
