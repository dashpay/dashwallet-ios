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

/// The amount rules of the Send screen: Max on Identity with the DashPay reserve, the balance check for every source
/// and the DASH value of credits (AC-08, AC-09). Amounts, balances and fees are in the source's own unit: duffs for
/// Core, Shielded and Platform, credits for Identity.
final class AmountRulesTests: XCTestCase {
    private let reserve = IdentityCreditBalance.lowBalance
    private let fee: UInt64 = 5_000
    private let nonIdentitySources: [SendSource] = [.core, .shielded, .platform]

    private struct CheckRow {
        let name: String
        let amount: UInt64
        let expected: AmountCheck

        init(_ name: String, _ amount: UInt64, _ expected: AmountCheck) {
            self.name = name
            self.amount = amount
            self.expected = expected
        }
    }

    // MARK: - Max on Identity (AC-08, AC-09)
    // Max for Core, Shielded and Platform stays with the existing per-route services, not AmountRules.

    func testIdentityMaxIsCreditsMinusFeeMinusReserve() {
        let credits = reserve + 7_000_000_000
        XCTAssertEqual(AmountRules.identityMax(balanceCredits: credits, feeCredits: fee),
                       .amount(credits - fee - reserve))
    }

    func testIdentityMaxIsOneUnitWhenOneUnitIsLeftAboveTheReserve() {
        XCTAssertEqual(AmountRules.identityMax(balanceCredits: reserve + fee + 1, feeCredits: fee), .amount(1))
    }

    func testIdentityMaxDisabledWhenBalanceMinusFeeEqualsTheReserve() {
        XCTAssertEqual(AmountRules.identityMax(balanceCredits: reserve + fee, feeCredits: fee), .disabledReserveSpent)
    }

    func testIdentityMaxDisabledWhenBalanceMinusFeeIsBelowTheReserve() {
        XCTAssertEqual(AmountRules.identityMax(balanceCredits: reserve + fee - 1, feeCredits: fee),
                       .disabledReserveSpent)
        XCTAssertEqual(AmountRules.identityMax(balanceCredits: reserve, feeCredits: fee), .disabledReserveSpent)
    }

    func testIdentityMaxDisabledWhenCreditsDoNotCoverTheFee() {
        XCTAssertEqual(AmountRules.identityMax(balanceCredits: fee - 1, feeCredits: fee), .disabledReserveSpent)
        XCTAssertEqual(AmountRules.identityMax(balanceCredits: 0, feeCredits: fee), .disabledReserveSpent)
    }

    func testIdentityMaxLeavesExactlyTheReserveAndTheFee() {
        let credits = reserve + 3_000_000_000
        guard case let .amount(max) = AmountRules.identityMax(balanceCredits: credits, feeCredits: fee) else {
            return XCTFail("expected an amount")
        }
        XCTAssertEqual(credits - max - fee, reserve)
        XCTAssertEqual(AmountRules.check(amount: max, source: .identity, balance: credits, fee: fee), .ok,
                       "Max itself carries no reserve warning")
    }

    // MARK: - Balance check, table over sources (AC-08)

    func testCheckTableOverNonIdentitySources() {
        let balance: UInt64 = 250_000_000
        let limit = balance - fee
        let rows: [CheckRow] = [
            CheckRow("below balance minus fee", limit - 1, .ok),
            CheckRow("equal to balance minus fee", limit, .ok),
            CheckRow("balance minus fee plus one unit", limit + 1, .notEnough),
            CheckRow("the whole balance (fee not covered)", balance, .notEnough),
            CheckRow("above the balance", balance + 1, .notEnough)
        ]
        for source in nonIdentitySources {
            for row in rows {
                XCTAssertEqual(AmountRules.check(amount: row.amount, source: source, balance: balance, fee: fee),
                               row.expected, "\(source): \(row.name)")
            }
        }
    }

    func testCheckOnNonIdentitySourceNeverWarnsAboutTheReserve() {
        let balance = reserve / 2
        for source in nonIdentitySources {
            XCTAssertEqual(AmountRules.check(amount: balance - fee, source: source, balance: balance, fee: fee),
                           .ok, "\(source)")
        }
    }

    // MARK: - Balance check on Identity (AC-08, AC-09)

    func testIdentityCheckTable() {
        let credits = reserve + 7_000_000_000
        let limit = credits - fee
        let rows: [CheckRow] = [
            CheckRow("small amount, plenty left", 1_000_000_000, .ok),
            CheckRow("leaves exactly the reserve", limit - reserve, .ok),
            CheckRow("leaves one unit less than the reserve", limit - reserve + 1, .okWithReserveWarning),
            CheckRow("equal to balance minus fee", limit, .okWithReserveWarning),
            CheckRow("balance minus fee plus one unit", limit + 1, .notEnough),
            CheckRow("above the balance", credits + 1, .notEnough)
        ]
        for row in rows {
            XCTAssertEqual(AmountRules.check(amount: row.amount, source: .identity, balance: credits, fee: fee),
                           row.expected, row.name)
        }
    }

    func testIdentityTypedAmountStillAllowedWithWarningWhenMaxIsDisabled() {
        let credits = reserve + fee - 1
        XCTAssertEqual(AmountRules.identityMax(balanceCredits: credits, feeCredits: fee), .disabledReserveSpent)
        XCTAssertEqual(AmountRules.check(amount: 1, source: .identity, balance: credits, fee: fee),
                       .okWithReserveWarning)
        XCTAssertEqual(AmountRules.check(amount: credits - fee, source: .identity, balance: credits, fee: fee),
                       .okWithReserveWarning)
        XCTAssertEqual(AmountRules.check(amount: credits - fee + 1, source: .identity, balance: credits, fee: fee),
                       .notEnough)
    }

    func testIdentityCheckIsNotEnoughWhenCreditsDoNotCoverTheFee() {
        XCTAssertEqual(AmountRules.check(amount: 1, source: .identity, balance: fee - 1, fee: fee), .notEnough)
        XCTAssertEqual(AmountRules.check(amount: 1, source: .core, balance: fee - 1, fee: fee), .notEnough)
    }

    // MARK: - DASH value of credits (spec section 6.1)

    func testDashValueOfCreditsUsesTheExistingRateOf1000CreditsPerDuff() {
        XCTAssertEqual(AmountRules.dashValue(of: 0), 0)
        XCTAssertEqual(AmountRules.dashValue(of: 1_000), 1)
        XCTAssertEqual(AmountRules.dashValue(of: 100_000_000_000), 100_000_000, "1 DASH is 1e11 credits")
        XCTAssertEqual(AmountRules.dashValue(of: reserve), 1_000_000, "the reserve is 0.01 DASH")
    }

    func testDashValueOfCreditsAgreesWithTheExistingConversion() {
        for credits: UInt64 in [0, 999, 1_000, 123_456_789, reserve] {
            XCTAssertEqual(Int64(AmountRules.dashValue(of: credits)),
                           PlatformAddressActivityUnitPolicy.duffs(fromCredits: credits))
        }
    }

    func testDashValueOfCreditsRoundsDownBelowOneDuff() {
        XCTAssertEqual(AmountRules.dashValue(of: 999), 0)
        XCTAssertEqual(AmountRules.dashValue(of: 1_999), 1)
    }
}
