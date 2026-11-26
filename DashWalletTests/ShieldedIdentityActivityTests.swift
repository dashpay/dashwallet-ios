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

/// The Shielded activity kinds the SDK records for an identity — a top-up from the pool (9) and an identity's
/// credits shielded (8) — read as a send to someone else or as an Internal Transfer, never as the unknown
/// "Shielded Spend" a restored residual gets.
final class ShieldedIdentityActivityTests: XCTestCase {
    private let identityId = Data(repeating: 9, count: 32)
    private let recipient = "EeEuq3recipient"

    private func row(
        kind: ShieldedActivityItem.Kind, direction: ShieldedActivityItem.Direction
    ) -> PersistentShieldedActivity {
        PersistentShieldedActivity(
            walletId: Data(repeating: 1, count: 32), accountIndex: 0, entryId: Data(repeating: 2, count: 32),
            kindTag: kind.rawValue, direction: direction.rawValue, status: 1, amount: 10_000_000, fee: 0,
            hasFee: false, blockHeight: 0, hasBlockHeight: false, createdAtMs: 1_800_000_000_000,
            identityId: kind == .identityTopUp ? identityId : Data(), counterparty: Data(), memo: Data(),
            noteCmxs: Data(), spentNullifiers: Data())
    }

    func testATopUpOfSomeoneElsesIdentityFromShieldedIsSent() {
        let item = ShieldedActivityItem(row: row(kind: .identityTopUp, direction: .outgoing),
                                        destinationAddress: recipient, isExternalDestination: true)
        XCTAssertEqual(item.kind, .identityTopUp)
        XCTAssertEqual(item.title, String(localized: "Sent", comment: ""))
        XCTAssertEqual(item.detailsText, ShieldedActivityItem.shortAddress(recipient))
        XCTAssertFalse(item.isInternalMove)
        XCTAssertEqual(item.signedDashAmount, -10_000)
        XCTAssertEqual(item.secondarySystemIcon, "arrow.up")
    }

    func testATopUpOfTheWalletsOwnIdentityFromShieldedIsAnInternalTransfer() {
        let item = ShieldedActivityItem(row: row(kind: .identityTopUp, direction: .outgoing),
                                        destinationAddress: recipient, isExternalDestination: false)
        XCTAssertEqual(item.title, String(localized: "Internal Transfer", comment: ""))
        XCTAssertEqual(item.detailsText, String(localized: "Shielded → Identity", comment: ""))
        XCTAssertTrue(item.isInternalMove)
        XCTAssertEqual(item.signedDashAmount, 10_000)
    }

    func testIdentityCreditsShieldedToSomeoneElseAreSentWhateverThePoolDirection() {
        for direction in [ShieldedActivityItem.Direction.incoming, .outgoing] {
            let item = ShieldedActivityItem(row: row(kind: .shieldFromIdentity, direction: direction),
                                            destinationAddress: recipient, isExternalDestination: true)
            XCTAssertEqual(item.title, String(localized: "Sent", comment: ""), "\(direction)")
            XCTAssertEqual(item.signedDashAmount, -10_000, "\(direction)")
        }
    }

    func testIdentityCreditsShieldedToTheWalletsOwnBalanceAreAnInternalTransfer() {
        let item = ShieldedActivityItem(row: row(kind: .shieldFromIdentity, direction: .incoming))
        XCTAssertEqual(item.title, String(localized: "Internal Transfer", comment: ""))
        XCTAssertEqual(item.detailsText, String(localized: "Identity → Shielded", comment: ""))
        XCTAssertTrue(item.isInternalMove)
    }

    func testOnlyAnUnknownKindIsAShieldedSpend() {
        let unknown = PersistentShieldedActivity(
            walletId: Data(), accountIndex: 0, entryId: Data(repeating: 3, count: 32), kindTag: 42, direction: 1,
            status: 1, amount: 1_000, fee: 0, hasFee: false, blockHeight: 0, hasBlockHeight: false, createdAtMs: 0,
            identityId: Data(), counterparty: Data(), memo: Data(), noteCmxs: Data(), spentNullifiers: Data())
        XCTAssertEqual(ShieldedActivityItem(row: unknown).kind, .shieldedSpend)
    }
}
