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

/// Every asset lock that records whom it pays reads by whose the recipient is, as a Core → Shielded send already
/// does: a Core → Identity top-up (type 2) and a Core → Platform payment (type 4) to someone else read as "Sent" with
/// the recipient, an own recipient keeps the own-transfer reading, and one whose owner cannot be told now is named
/// neither.
final class ExternalAssetLockSendHistoryTests: XCTestCase {
    private typealias Info = ShieldedTxLookup.ShieldedLockInfo

    private let txidWire = Data((0..<32).map { UInt8(0x90 + $0) })
    private let walletId = Data(repeating: 1, count: 32)
    private let identityId = Data(repeating: 9, count: 32)
    private static let platformStorage = Data([0]) + Data(repeating: 0xEE, count: 20)
    private let amount: UInt64 = 1_050_500

    private var txidHex: String { Transaction.displayHex(txidWire).lowercased() }
    private var identityAddress: String { ScriptAddressCodec.base58Encode(identityId) }
    private var platformAddress: String {
        Bech32m.bech32mPayload(fromStorageBytes: Self.platformStorage)
            .flatMap { Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: false), data: $0) } ?? ""
    }

    private func identityLock(_ identity: Data?, fundingType: Int = 2,
                              status: Int = AssetLockRecoveryService.consumedStatus) -> Info {
        Info(amountDuffs: amount, statusRaw: status, vout: 0,
             fundingTypeRaw: fundingType, walletId: walletId, drainOperation: nil, identityRecipient: identity)
    }

    private func platformLock(recorded: Bool, status: Int = AssetLockRecoveryService.consumedStatus) -> Info {
        Info(amountDuffs: amount, statusRaw: status, vout: 0,
             fundingTypeRaw: 4, walletId: walletId, drainOperation: nil, hasPlatformAddressRecipients: recorded)
    }

    /// `isOwn` answers for the identity and the Platform address alike; `platform` is what the lock's recorded
    /// Platform recipients read as (nil: unreadable now).
    @MainActor
    private func resolved(
        _ info: Info, isOwn: Bool?, platform: [Data]? = [ExternalAssetLockSendHistoryTests.platformStorage]
    ) -> Info {
        let recipients = platform
        let map = ShieldedTxLookup.resolvingIdentityAndPlatformRecipients(
            of: [txidHex: info], mainnet: false,
            isOwnIdentity: { _, _ in isOwn },
            platformRecipients: { _, _ in recipients },
            isOwnPlatformAddress: { _, _ in isOwn })
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
    func testAnIdentityRecipientIsOwnExternalOrUndecided() {
        XCTAssertEqual(resolved(identityLock(identityId), isOwn: true).recipient, .own)
        XCTAssertEqual(resolved(identityLock(identityId), isOwn: false).recipient,
                       .external(address: identityAddress))
        XCTAssertEqual(resolved(identityLock(identityId), isOwn: nil).recipient,
                       .undecided(address: identityAddress))
    }

    @MainActor
    func testAPlatformRecipientIsOwnExternalOrUndecided() {
        XCTAssertEqual(resolved(platformLock(recorded: true), isOwn: true).recipient, .own)
        XCTAssertEqual(resolved(platformLock(recorded: true), isOwn: false).recipient,
                       .external(address: platformAddress))
        XCTAssertEqual(resolved(platformLock(recorded: true), isOwn: nil).recipient,
                       .undecided(address: platformAddress))
    }

    @MainActor
    func testALockThatRecordedNoRecipientKeepsNoAnswer() {
        XCTAssertNil(resolved(identityLock(nil), isOwn: false).recipient)
        XCTAssertNil(resolved(identityLock(identityId, fundingType: 1), isOwn: false).recipient, "a bound top-up")
        XCTAssertNil(resolved(platformLock(recorded: false), isOwn: false).recipient)
        XCTAssertNil(resolved(platformLock(recorded: true), isOwn: false, platform: []).recipient)
        XCTAssertNil(resolved(platformLock(recorded: true), isOwn: false, platform: nil).recipient,
                     "recipients that cannot be read now")
    }

    // MARK: - Transaction: every reader takes the same fact

    @MainActor
    func testAPaymentToSomeoneElseReadsAsSent() {
        for (info, address) in [(resolved(identityLock(identityId), isOwn: false), identityAddress),
                                (resolved(platformLock(recorded: true), isOwn: false), platformAddress)] {
            withLock(info) { tx in
                XCTAssertEqual(tx.assetLockRecipientAddress, address)
                XCTAssertNil(tx.internalTransferRoute)
                XCTAssertEqual(tx.direction, .sent)
                XCTAssertEqual(tx.stateTitle, String(localized: "Sent", comment: ""))
                XCTAssertEqual(tx.signedDashAmount, -Int64(amount))
                XCTAssertEqual(tx.defaultTaxCategory, .transferOut)
                XCTAssertEqual(HomeTransactionRoute.details(of: tx), ShieldedActivityItem.shortAddress(address))
            }
        }
    }

    /// Platform credits the recipient when it consumes the lock: until then the payment is sending.
    @MainActor
    func testAPaymentWhoseLockIsNotConsumedReadsAsSending() {
        for info in [identityLock(identityId, status: 2), platformLock(recorded: true, status: 2)] {
            withLock(resolved(info, isOwn: false)) { tx in
                XCTAssertEqual(tx.direction, .sent)
                XCTAssertEqual(tx.stateTitle, String(localized: "Sending", comment: ""))
            }
        }
    }

    /// An owner that cannot be told now is named neither a payment nor an own transfer.
    @MainActor
    func testAnUndecidedIdentityOrPlatformRecipientIsNamedNeither() {
        withLock(resolved(identityLock(identityId), isOwn: nil)) { tx in
            XCTAssertEqual(tx.assetLockRecipientAddress, identityAddress)
            XCTAssertNil(tx.internalTransferRoute)
            XCTAssertEqual(tx.stateTitle, String(localized: "Identity transfer", comment: ""))
        }
        withLock(resolved(platformLock(recorded: true), isOwn: nil)) { tx in
            XCTAssertEqual(tx.assetLockRecipientAddress, platformAddress)
            XCTAssertNil(tx.internalTransferRoute)
            XCTAssertEqual(tx.stateTitle, String(localized: "Platform transfer", comment: ""))
        }
    }

    @MainActor
    func testOwnFundingsKeepTheirReading() {
        for info in [resolved(identityLock(identityId), isOwn: true),
                     resolved(identityLock(identityId, fundingType: 1), isOwn: false)] {
            withLock(info) { tx in
                XCTAssertNil(tx.assetLockRecipientAddress)
                XCTAssertEqual(tx.internalTransferRoute, .coreToIdentity)
                XCTAssertEqual(tx.stateTitle, String(localized: "Identity top-up", comment: ""))
            }
        }
        for info in [resolved(platformLock(recorded: true), isOwn: true), platformLock(recorded: false)] {
            withLock(info) { tx in
                XCTAssertNil(tx.assetLockRecipientAddress)
                XCTAssertEqual(tx.internalTransferRoute, .coreToPlatform)
                XCTAssertEqual(tx.defaultTaxCategory, .internalTransfer)
            }
        }
    }
}
