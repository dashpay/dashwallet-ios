//
//  IdentityTopUpEventTests.swift
//  DashWalletTests
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

import SwiftDashSDK
import XCTest
@testable import dashpay

/// A top-up from this wallet announces the credits it added, so the Identity
/// option on Receive raises no Receipt for it (AC-06, ADR-0034).
@MainActor
final class IdentityTopUpEventTests: XCTestCase {
    private let walletId = Data(repeating: 1, count: 32)
    private let identityId = Data(repeating: 2, count: 32)

    private enum Refused: Error { case byPlatform }

    private let center = NotificationCenter()
    private let inFlight = IdentityTopUpsInFlight()
    private var events: [IdentityTopUpDidComplete] = []
    private var token: NSObjectProtocol?

    override func setUp() {
        token = center.addObserver(forName: IdentityTopUpDidComplete.name, object: nil, queue: nil) { [weak self] in
            if let event = IdentityTopUpDidComplete(notification: $0) { self?.events.append(event) }
        }
    }

    override func tearDown() {
        if let token { center.removeObserver(token) }
    }

    private func announced(balanceAfter: UInt64?, suppliedCredits: UInt64) -> [IdentityTopUpDidComplete] {
        IdentityTopUpDidComplete.announce(
            balanceAfter: balanceAfter,
            suppliedCredits: suppliedCredits,
            walletId: walletId,
            network: .testnet,
            identityId: identityId,
            center: center)
        return events
    }

    private func announcing(_ topUp: () async throws -> UInt64) async rethrows -> UInt64 {
        try await IdentityTopUpDidComplete.announcing(
            walletId: walletId, network: .testnet, identityId: identityId,
            suppliedCredits: 1_000_000_000, center: center, inFlight: inFlight, topUp)
    }

    private var key: IdentityTopUpsInFlight.Key {
        .init(walletId: walletId, network: .testnet, identityId: identityId)
    }

    /// The event carries the transition's own balance and what it was handed,
    /// not a delta over the whole top-up: a spend from elsewhere during it
    /// would cut that delta (review-2026-11-11-r1 S1).
    func testSuccessfulTopUpPostsOneEventWithItsBalanceAndSuppliedCredits() {
        let events = announced(balanceAfter: 2_958_500_000, suppliedCredits: 1_000_000_000)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.balanceAfter, 2_958_500_000)
        XCTAssertEqual(events.first?.suppliedCredits, 1_000_000_000)
        XCTAssertEqual(events.first?.identityId, identityId)
        XCTAssertEqual(events.first?.walletId, walletId)
        XCTAssertEqual(events.first?.network, .testnet)
    }

    func testCancelledOrFailedTopUpPostsNothing() {
        XCTAssertTrue(announced(balanceAfter: nil, suppliedCredits: 1_000_000_000).isEmpty)
    }

    // MARK: The credits each funding source hands to the identity

    /// The Shielded route unshields the whole amount but claims it into the
    /// identity less the fee headroom, which stays at the wallet's Platform
    /// address. Announcing the whole amount would let the watcher absorb up to
    /// the headroom of a Payer's credits with no Receipt.
    func testShieldedTopUpSuppliesTheAmountLessTheFeeHeadroom() {
        let amountDuffs: UInt64 = 5_000_000
        let credits = amountDuffs * PlatformPaymentIdentityFundingPolicy.creditsPerDuff
        XCTAssertEqual(
            IdentityTopUpViewModel.suppliedCredits(amountDuffs: amountDuffs, source: .shielded),
            credits - PlatformPaymentIdentityFundingPolicy.feeHeadroomCredits)
    }

    func testPlatformAndTransparentTopUpsSupplyTheWholeAmount() {
        let amountDuffs: UInt64 = 5_000_000
        let credits = amountDuffs * PlatformPaymentIdentityFundingPolicy.creditsPerDuff
        XCTAssertEqual(IdentityTopUpViewModel.suppliedCredits(amountDuffs: amountDuffs, source: .platform), credits)
        XCTAssertEqual(IdentityTopUpViewModel.suppliedCredits(amountDuffs: amountDuffs, source: .transparent), credits)
    }

    // MARK: The coordinator's top-ups (registration shortfall, name purchase)

    func testATopUpThatReturnsAnnouncesItsBalanceAndPassesItOn() async throws {
        let after = try await announcing { 2_958_500_000 }
        XCTAssertEqual(after, 2_958_500_000)
        XCTAssertEqual(events.map(\.balanceAfter), [2_958_500_000])
        XCTAssertEqual(events.first?.identityId, identityId)
    }

    func testATopUpThatThrowsAnnouncesNothing() async {
        do {
            _ = try await announcing { throw Refused.byPlatform }
            XCTFail("The refusal must reach the caller")
        } catch {
            XCTAssertEqual(error as? Refused, .byPlatform)
        }
        XCTAssertTrue(events.isEmpty)
    }

    /// The watch holds its Receipt while the top-up runs (review-2026-11-10-r3 Q1).
    func testATopUpIsInFlightOnlyWhileItRuns() async throws {
        var runningDuringTopUp = false
        _ = try await announcing {
            runningDuringTopUp = inFlight.contains(key)
            return 2_958_500_000
        }
        XCTAssertTrue(runningDuringTopUp)
        XCTAssertFalse(inFlight.contains(key))
    }

    func testATopUpThatThrowsIsNoLongerInFlight() async {
        _ = try? await announcing { throw Refused.byPlatform }
        XCTAssertFalse(inFlight.contains(key))
    }

    func testTwoTopUpsOfOneIdentityStayInFlightUntilBothEnd() {
        inFlight.begin(key)
        inFlight.begin(key)
        inFlight.end(key)
        XCTAssertTrue(inFlight.contains(key))
        inFlight.end(key)
        XCTAssertFalse(inFlight.contains(key))
    }

    func testANotificationOfAnotherNameIsNotAnEvent() {
        XCTAssertNil(IdentityTopUpDidComplete(notification: Notification(name: .init("Other"))))
    }
}
