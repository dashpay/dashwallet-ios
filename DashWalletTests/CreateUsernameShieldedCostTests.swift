//
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

import DashUIKit
import XCTest
@testable import dashpay

/// The Create Username cost row while Shielded is the chosen source: what
/// stops it, in the words and mark the form shows.
@MainActor
final class CreateUsernameShieldedCostTests: XCTestCase {
    private typealias Blocker = CreateUsernameViewModel.ShieldedCostBlocker

    func testStandardNameUsesSmallestDenomination() {
        XCTAssertEqual(ShieldedIdentityFundingReadiness.requiredCredits(forContestedName: false), 3_000_000_000)
        XCTAssertEqual(ShieldedIdentityFundingReadiness.requiredCredits(forContestedName: true), 25_000_000_000)
    }

    func testReadyStateBlocksNothing() {
        XCTAssertNil(CreateUsernameViewModel.shieldedCostBlocker(for: .ready, dashBalanceCovers: false))
    }

    func testRestingFundsReportWhenTheyAreReady() {
        let readyAt = Date(timeIntervalSinceNow: 600)
        XCTAssertEqual(
            CreateUsernameViewModel.shieldedCostBlocker(for: .maturing(readyAt: readyAt), dashBalanceCovers: true),
            .resting(readyAt: readyAt))
    }

    /// Readiness counts in credits; the form states duffs, rounded up so the
    /// stated amount is never short of what is missing.
    func testShortfallIsStatedInDuffsRoundedUp() {
        XCTAssertEqual(
            CreateUsernameViewModel.shieldedCostBlocker(
                for: .needsFunding(shortfallCredits: 5_000_000_001), dashBalanceCovers: false),
            .short(shortfallDuffs: 5_000_001, dashBalanceCovers: false))
    }

    func testPoolBelowMinimumIsItsOwnBlocker() {
        XCTAssertEqual(
            CreateUsernameViewModel.shieldedCostBlocker(for: .poolTooSmall(current: 120), dashBalanceCovers: false),
            .poolTooSmall(current: 120))
    }

    /// Only a new identity is paid by the Shielded exit. Another source, or
    /// an identity the registration reuses with nothing to add, leaves the
    /// row to the price; one that needs a top-up says Shielded cannot do it.
    func testBlockerOnlyForShieldedFundingANewIdentity() {
        let maturing = ShieldedIdentityFundingReadiness.State.maturing(readyAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(
            CreateUsernameViewModel.shieldedCostBlocker(
                source: .shielded, identityTopUpDuffs: nil, readiness: maturing, dashBalanceCovers: false),
            .resting(readyAt: Date(timeIntervalSince1970: 0)))
        XCTAssertNil(CreateUsernameViewModel.shieldedCostBlocker(
            source: .core, identityTopUpDuffs: nil, readiness: maturing, dashBalanceCovers: false))
        XCTAssertNil(CreateUsernameViewModel.shieldedCostBlocker(
            source: .shielded, identityTopUpDuffs: 0, readiness: maturing, dashBalanceCovers: false))
        XCTAssertEqual(
            CreateUsernameViewModel.shieldedCostBlocker(
                source: .shielded, identityTopUpDuffs: 50_000, readiness: maturing, dashBalanceCovers: false),
            .cannotTopUp(topUpDuffs: 50_000))
        XCTAssertNil(CreateUsernameViewModel.shieldedCostBlocker(
            source: .shielded, identityTopUpDuffs: nil, readiness: nil, dashBalanceCovers: false))
    }

    func testRestingTodayNamesTheTimeWithoutAnError() {
        let now = Self.date(hour: 15, minute: 30)
        let readyAt = now.addingTimeInterval(10 * 60)
        let (text, state) = Blocker.resting(readyAt: readyAt).criterion(now: now, calendar: Self.calendar)
        XCTAssertEqual(text, "Your recently shielded Dash can be used for this username at \(Self.time(readyAt))")
        XCTAssertEqual(state, .pending)
    }

    func testRestingPastMidnightSaysTomorrow() {
        let now = Self.date(hour: 23, minute: 0)
        let readyAt = now.addingTimeInterval(3 * 60 * 60)
        let (text, state) = Blocker.resting(readyAt: readyAt).criterion(now: now, calendar: Self.calendar)
        XCTAssertEqual(text, "Your recently shielded Dash can be used for this username tomorrow at \(Self.time(readyAt))")
        XCTAssertEqual(state, .pending)
    }

    /// A clock that has already passed the ready time is not "tomorrow".
    func testRestingInThePastNamesTheTime() {
        let now = Self.date(hour: 0, minute: 5)
        let readyAt = now.addingTimeInterval(-10 * 60)
        let (text, _) = Blocker.resting(readyAt: readyAt).criterion(now: now, calendar: Self.calendar)
        XCTAssertEqual(text, "Your recently shielded Dash can be used for this username at \(Self.time(readyAt))")
    }

    func testShortfallOffersTheDashBalanceOnlyWhenItCovers() {
        let amount = UInt64(5_000_000).dashAmount.formattedDashAmountWithoutCurrencySymbol
        let covered = Blocker.short(shortfallDuffs: 5_000_000, dashBalanceCovers: true).criterion()
        let uncovered = Blocker.short(shortfallDuffs: 5_000_000, dashBalanceCovers: false).criterion()
        XCTAssertEqual(
            covered.text,
            "Add \(amount) Dash to your Shielded balance to create this username, or pay from your Dash balance")
        XCTAssertEqual(uncovered.text, "Add \(amount) Dash to your Shielded balance to create this username")
        XCTAssertEqual(covered.state, .failed)
        XCTAssertEqual(uncovered.state, .failed)
    }

    /// The row says what the registration would refuse with.
    func testTopUpSaysWhatTheRegistrationRefusesWith() {
        let (text, state) = Blocker.cannotTopUp(topUpDuffs: 50_000).criterion()
        XCTAssertEqual(
            text,
            DWIdentityRegistrationCoordinator.CoordinatorError.shieldedTopUpUnavailable(neededDuffs: 50_000).errorDescription)
        XCTAssertTrue(text.contains(UInt64(50_000).dashAmount.formattedDashAmountWithoutCurrencySymbol))
        XCTAssertEqual(state, .failed)
    }

    func testPoolBelowMinimumWaitsWithoutAnError() {
        let (text, state) = Blocker.poolTooSmall(current: 120).criterion()
        XCTAssertEqual(text, CreateUsernameViewModel.shieldedPoolTooSmallMessage(current: 120))
        XCTAssertTrue(text.contains("120 of the 250 notes"))
        XCTAssertEqual(state, .pending)
    }

    func testShieldedOnlyFundingNamesTheMatureBalance() {
        XCTAssertEqual(
            CreateUsernameViewModel.shieldedOnlyFunding(
                reusesIdentity: false, dashBalanceCovers: false, shieldedReady: true, matureCredits: 3_000_000_000),
            .standardOnly(matureDuffs: 3_000_000))
    }

    /// From the contested denomination Shielded pays for any name, so the
    /// sheet warns about no price, whatever the Dash balance holds.
    func testShieldedOnlyFundingCoversEveryNameFromTheContestedDenomination() {
        XCTAssertEqual(
            CreateUsernameViewModel.shieldedOnlyFunding(
                reusesIdentity: false, dashBalanceCovers: false, shieldedReady: true, matureCredits: 25_000_000_000),
            .everyName)
        XCTAssertEqual(
            CreateUsernameViewModel.shieldedOnlyFunding(
                reusesIdentity: false, dashBalanceCovers: true, shieldedReady: true, matureCredits: 25_000_000_000),
            .everyName)
        XCTAssertEqual(
            CreateUsernameViewModel.shieldedOnlyFunding(
                reusesIdentity: false, dashBalanceCovers: false, shieldedReady: true, matureCredits: 24_999_999_999),
            .standardOnly(matureDuffs: 24_999_999))
    }

    /// The Dash balance keeps its own line; Shielded that cannot pay yet
    /// says nothing here.
    func testShieldedOnlyFundingStepsAsideOtherwise() {
        XCTAssertNil(CreateUsernameViewModel.shieldedOnlyFunding(
            reusesIdentity: false, dashBalanceCovers: true, shieldedReady: true, matureCredits: 3_000_000_000))
        XCTAssertNil(CreateUsernameViewModel.shieldedOnlyFunding(
            reusesIdentity: false, dashBalanceCovers: false, shieldedReady: false, matureCredits: 3_000_000_000))
    }

    /// An existing identity is never funded from Shielded, so the sheet
    /// does not name Shielded as what pays.
    func testShieldedOnlyFundingSaysNothingForAnExistingIdentity() {
        XCTAssertNil(CreateUsernameViewModel.shieldedOnlyFunding(
            reusesIdentity: true, dashBalanceCovers: false, shieldedReady: true, matureCredits: 3_000_000_000))
        XCTAssertNil(CreateUsernameViewModel.shieldedOnlyFunding(
            reusesIdentity: true, dashBalanceCovers: false, shieldedReady: true, matureCredits: 25_000_000_000))
    }

    func testUnpayableTopUpIsOnlyAPositiveTopUp() {
        XCTAssertNil(CreateUsernameViewModel.shieldedUnpayableTopUp(identityTopUpDuffs: nil))
        XCTAssertNil(CreateUsernameViewModel.shieldedUnpayableTopUp(identityTopUpDuffs: 0))
        XCTAssertEqual(CreateUsernameViewModel.shieldedUnpayableTopUp(identityTopUpDuffs: 50_000), 50_000)
    }

    /// An existing identity that needs nothing passes with Shielded chosen,
    /// whatever Shielded's readiness; a new identity waits for it.
    func testShieldedPaysWhenNothingIsOwed() {
        XCTAssertTrue(CreateUsernameViewModel.shieldedPays(identityTopUpDuffs: 0, shieldedReady: false))
        XCTAssertFalse(CreateUsernameViewModel.shieldedPays(identityTopUpDuffs: nil, shieldedReady: false))
        XCTAssertTrue(CreateUsernameViewModel.shieldedPays(identityTopUpDuffs: nil, shieldedReady: true))
        XCTAssertFalse(CreateUsernameViewModel.shieldedPays(identityTopUpDuffs: 50_000, shieldedReady: false))
        // Ready notes do not top up an identity.
        XCTAssertFalse(CreateUsernameViewModel.shieldedPays(identityTopUpDuffs: 50_000, shieldedReady: true))
    }

    /// A cached resting state is evaluated again once its ready time comes.
    func testRestingStateGoesStaleAtItsReadyTime() {
        let now = Self.date(hour: 12, minute: 0)
        XCTAssertTrue(CreateUsernameViewModel.isPastReadyTime(.maturing(readyAt: now), now: now))
        XCTAssertTrue(CreateUsernameViewModel.isPastReadyTime(.maturing(readyAt: now.addingTimeInterval(-60)), now: now))
        XCTAssertFalse(CreateUsernameViewModel.isPastReadyTime(.maturing(readyAt: now.addingTimeInterval(60)), now: now))
        XCTAssertFalse(CreateUsernameViewModel.isPastReadyTime(.ready, now: now))
    }

    func testJoinNoteNamesTheMinimumWhenNothingPays() {
        XCTAssertEqual(
            CreateUsernameViewModel.joinBalanceNote(
                canProceed: false, transparentCoversEveryName: false, shieldedOnlyFunding: nil),
            .minimum)
    }

    /// A balance that covers every name leaves nothing to warn about, even
    /// with a standard name's worth in Shielded.
    func testJoinNoteIsSilentWhenTheDashBalanceCoversEveryName() {
        XCTAssertNil(CreateUsernameViewModel.joinBalanceNote(
            canProceed: true, transparentCoversEveryName: true, shieldedOnlyFunding: .standardOnly(matureDuffs: 3_000_000)))
        XCTAssertNil(CreateUsernameViewModel.joinBalanceNote(
            canProceed: true, transparentCoversEveryName: false, shieldedOnlyFunding: .everyName))
    }

    func testJoinNoteNamesWhicheverBalancePays() {
        XCTAssertEqual(
            CreateUsernameViewModel.joinBalanceNote(
                canProceed: true, transparentCoversEveryName: false, shieldedOnlyFunding: .standardOnly(matureDuffs: 3_000_000)),
            .shielded(matureDuffs: 3_000_000))
        XCTAssertEqual(
            CreateUsernameViewModel.joinBalanceNote(
                canProceed: true, transparentCoversEveryName: false, shieldedOnlyFunding: nil),
            .dashBalance)
    }

    private static func time(_ date: Date) -> String {
        DWDateFormatter.sharedInstance.timeOnly(from: date)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: hour, minute: minute))!
    }
}
