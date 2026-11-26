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
import XCTest

/// Every asset lock that pays someone else reads as "Sent" with the recipient in History — a Core → Identity top-up
/// of another identity (type 2) and a Core → Platform payment to another address (type 4) as a Core → Shielded send
/// already does — and only a lock that funds the wallet's own balance or identity reads as its own transfer.
final class ExternalAssetLockSendHistoryTests: XCTestCase {
    private typealias Info = ShieldedTxLookup.ShieldedLockInfo

    private let txidWire = Data((0..<32).map { UInt8(0x90 + $0) })
    private let walletId = Data(repeating: 1, count: 32)
    private let identityId = Data(repeating: 9, count: 32)
    private let platformRecipient = "tdash1krl9ddjez4lywvrwuemukn0memy3mh0teshyja0x"
    private let amount: UInt64 = 1_050_500

    private var txidHex: String { Transaction.displayHex(txidWire).lowercased() }

    private func identityLock(_ identity: Data?, fundingType: Int = 2) -> Info {
        Info(amountDuffs: amount, statusRaw: AssetLockRecoveryService.consumedStatus, vout: 0,
             fundingTypeRaw: fundingType, walletId: walletId, drainOperation: nil, identityRecipient: identity)
    }

    private func platformLock(recorded: Bool) -> Info {
        Info(amountDuffs: amount, statusRaw: AssetLockRecoveryService.consumedStatus, vout: 0,
             fundingTypeRaw: 4, walletId: walletId, drainOperation: nil, hasPlatformAddressRecipients: recorded)
    }

    @MainActor
    private func resolved(_ info: Info, ownIdentity: Bool?, platform: [String]? = nil) -> Info {
        let map = ShieldedTxLookup.resolvingIdentityAndPlatformRecipients(
            of: [txidHex: info], isOwnIdentity: { _, _ in ownIdentity }, platformRecipients: { _, _ in platform })
        return map[txidHex] ?? info
    }

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
    func testAnotherIdentityIsASendWithItsId() {
        XCTAssertEqual(resolved(identityLock(identityId), ownIdentity: false).externalRecipientAddress,
                       ScriptAddressCodec.base58Encode(identityId))
    }

    @MainActor
    func testAnOwnOrUndecidedOrUnrecordedIdentityStaysOwn() {
        XCTAssertNil(resolved(identityLock(identityId), ownIdentity: true).externalRecipientAddress)
        XCTAssertNil(resolved(identityLock(identityId), ownIdentity: nil).externalRecipientAddress)
        XCTAssertNil(resolved(identityLock(nil), ownIdentity: false).externalRecipientAddress)
    }

    @MainActor
    func testARecordedPlatformFundingIsASendWithItsAddress() {
        XCTAssertEqual(resolved(platformLock(recorded: true), ownIdentity: nil, platform: [platformRecipient])
            .externalRecipientAddress, platformRecipient)
    }

    @MainActor
    func testAnOwnOrUnreadablePlatformFundingStaysOwn() {
        XCTAssertNil(resolved(platformLock(recorded: false), ownIdentity: nil, platform: [platformRecipient])
            .externalRecipientAddress)
        XCTAssertNil(resolved(platformLock(recorded: true), ownIdentity: nil, platform: nil).externalRecipientAddress)
    }

    // MARK: - Transaction: every reader takes the same fact

    @MainActor
    func testATopUpOfAnotherIdentityReadsAsSent() {
        withLock(resolved(identityLock(identityId), ownIdentity: false)) { tx in
            XCTAssertEqual(tx.externalAssetLockRecipient, ScriptAddressCodec.base58Encode(identityId))
            XCTAssertNil(tx.internalTransferRoute)
            XCTAssertEqual(tx.direction, .sent)
            XCTAssertEqual(tx.stateTitle, NSLocalizedString("Sent", comment: ""))
            XCTAssertEqual(tx.signedDashAmount, -Int64(amount))
            XCTAssertEqual(tx.defaultTaxCategory, .transferOut)
        }
    }

    @MainActor
    func testAPaymentToAnotherPlatformAddressReadsAsSent() {
        withLock(resolved(platformLock(recorded: true), ownIdentity: nil, platform: [platformRecipient])) { tx in
            XCTAssertEqual(tx.externalAssetLockRecipient, platformRecipient)
            XCTAssertNil(tx.internalTransferRoute)
            XCTAssertEqual(tx.direction, .sent)
            XCTAssertEqual(tx.stateTitle, NSLocalizedString("Sent", comment: ""))
            XCTAssertEqual(tx.defaultTaxCategory, .transferOut)
        }
    }

    @MainActor
    func testOwnFundingsKeepTheirReading() {
        withLock(resolved(identityLock(identityId, fundingType: 1), ownIdentity: false)) { tx in
            XCTAssertEqual(tx.internalTransferRoute, .coreToIdentity)
            XCTAssertEqual(tx.stateTitle, NSLocalizedString("Identity top-up", comment: ""))
        }
        withLock(resolved(platformLock(recorded: false), ownIdentity: nil)) { tx in
            XCTAssertEqual(tx.internalTransferRoute, .coreToPlatform)
            XCTAssertEqual(tx.defaultTaxCategory, .internalTransfer)
        }
    }
}
