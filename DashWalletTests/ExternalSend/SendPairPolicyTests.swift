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

/// The one pair policy (ADR-0038, ADR-0041): for every source and destination type it answers the route or the
/// unavailable reason, the starting source (AC-10, AC-14) and the Confirm warnings (AC-16, AC-17, AC-18).
final class SendPairPolicyTests: XCTestCase {
    private let ownID = "own-current-identity-id"
    private let otherID = "someone-elses-identity-id"

    private struct PairCase {
        let name: String
        let source: SendSource
        let destination: Destination
        let expected: SendPairDecision

        init(_ name: String, _ source: SendSource, _ destination: Destination, _ expected: SendPairDecision) {
            self.name = name
            self.source = source
            self.destination = destination
            self.expected = expected
        }
    }


    private var facts: SendPairFacts { SendPairFacts(ownIdentityID: ownID) }

    private func destination(_ kind: Destination.Kind, text: String = "dest", script: Bool = false) -> Destination {
        Destination(type: kind, text: text, isScriptForm: script)
    }

    private func decide(_ source: SendSource, _ destination: Destination) -> SendPairDecision {
        SendPairPolicy.decide(source: source, destination: destination, facts: facts)
    }

    // MARK: - AC-06: every source x destination pair

    func testAllSixteenPairsGiveARouteOrAReason() {
        let core = destination(.coreAddress)
        let shielded = destination(.shieldedAddress)
        let platform = destination(.platformAddress)
        let ownIdentity = destination(.identityID, text: ownID)
        let otherIdentity = destination(.identityID, text: otherID)

        let table: [PairCase] = [
            PairCase("core -> core", .core, core, .route(.coreToCore)),
            PairCase("core -> shielded", .core, shielded, .route(.coreToShielded)),
            PairCase("core -> platform", .core, platform, .route(.coreToPlatform)),
            PairCase("core -> own identity (top-up)", .core, ownIdentity, .route(.coreToIdentity)),
            PairCase("core -> other identity", .core, otherIdentity, .unavailable(.coreToOtherIdentity)),

            PairCase("shielded -> core", .shielded, core, .route(.shieldedToCore)),
            PairCase("shielded -> shielded", .shielded, shielded, .route(.shieldedToShielded)),
            PairCase("shielded -> platform", .shielded, platform, .route(.shieldedToPlatform)),
            PairCase("shielded -> own identity", .shielded, ownIdentity, .route(.shieldedToIdentity)),
            PairCase("shielded -> other identity", .shielded, otherIdentity, .route(.shieldedToIdentity)),

            PairCase("platform -> core", .platform, core, .route(.platformToCore)),
            PairCase("platform -> shielded", .platform, shielded, .route(.platformToShielded)),
            PairCase("platform -> platform", .platform, platform, .route(.platformToPlatform)),
            PairCase("platform -> own identity", .platform, ownIdentity, .route(.platformToIdentity)),
            PairCase("platform -> other identity", .platform, otherIdentity, .unavailable(.platformToOtherIdentity)),

            PairCase("identity -> core", .identity, core, .route(.identityToCore)),
            PairCase("identity -> shielded (ADR-0041)", .identity, shielded, .unavailable(.notSupportedYet)),
            PairCase("identity -> platform", .identity, platform, .route(.identityToPlatform)),
            PairCase("identity -> own identity", .identity, ownIdentity, .unavailable(.identityToOwnIdentity)),
            PairCase("identity -> other identity", .identity, otherIdentity, .route(.identityToIdentity))
        ]

        for row in table {
            XCTAssertEqual(decide(row.source, row.destination), row.expected, row.name)
        }
    }

    func testCoreToScriptFormPlatformAddressIsUnavailable() {
        let script = destination(.platformAddress, script: true)
        XCTAssertEqual(decide(.core, script), .unavailable(.coreToScriptFormPlatformAddress))
    }

    /// The Platform transfer's FFI takes only P2PKH outputs (`p2shNotSupported`); the unshield and the identity
    /// credit transfer hand the address to Rust as it is, which takes P2SH.
    func testScriptFormPlatformAddressIsPayableFromShieldedAndIdentityOnly() {
        let script = destination(.platformAddress, script: true)
        XCTAssertEqual(decide(.shielded, script), .route(.shieldedToPlatform))
        XCTAssertEqual(decide(.platform, script), .unavailable(.platformToScriptFormPlatformAddress))
        XCTAssertEqual(decide(.identity, script), .route(.identityToPlatform))
    }

    // MARK: - Payment requests are Core-only (BIP70 hands the signed Core transaction to the merchant)

    private var paymentRequestDestinations: [(String, Destination)] {
        [
            ("payment-request kind", destination(.paymentRequest, text: "")),
            ("core address with a request URL",
             Destination(type: .coreAddress, text: "dest",
                         paymentRequestURL: URL(string: "https://merchant.example/pr")))
        ]
    }

    func testPaymentRequestIsPayableFromCore() {
        for (name, dest) in paymentRequestDestinations {
            XCTAssertEqual(decide(.core, dest), .route(.coreToCore), name)
        }
    }

    func testPaymentRequestIsUnavailableFromShieldedPlatformAndIdentity() {
        for (name, dest) in paymentRequestDestinations {
            for source in [SendSource.shielded, .platform, .identity] {
                XCTAssertEqual(decide(source, dest), .unavailable(.paymentRequestCoreOnly), "\(name) from \(source)")
            }
        }
    }

    func testCoreAddressWithoutRequestURLStaysPayableFromEverySource() {
        XCTAssertEqual(decide(.shielded, destination(.coreAddress)), .route(.shieldedToCore))
    }

    func testPaymentRequestStartsFromCoreEvenWithoutACoreBalance() {
        for (name, dest) in paymentRequestDestinations {
            XCTAssertEqual(start(dest, balances(0, 5, 5)).source, .core, name)
            let pinned = start(dest, balances(0, 5, 5), pinned: .shielded)
            XCTAssertEqual(pinned.source, .core, name)
            XCTAssertTrue(pinned.sourceChanged, name)
        }
    }

    func testCoreToKeyFormPlatformAddressIsAllowed() {
        XCTAssertEqual(decide(.core, destination(.platformAddress, script: false)), .route(.coreToPlatform))
    }

    func testAnotherIdentityOfTheSameWalletCountsAsSomeoneElses() {
        // Not the Current identity, even if the wallet owns it: Core cannot pay it.
        let sibling = destination(.identityID, text: "second-identity-of-this-wallet")
        XCTAssertEqual(decide(.core, sibling), .unavailable(.coreToOtherIdentity))
        XCTAssertEqual(decide(.platform, sibling), .unavailable(.platformToOtherIdentity))
    }

    /// At the pinned SDK the top-up from Platform addresses refuses an identity the wallet does not manage
    /// (`IdentityNotFound`), so only the holder's own Current identity is payable from Platform.
    func testPlatformPaysOnlyTheOwnCurrentIdentity() {
        XCTAssertEqual(decide(.platform, destination(.identityID, text: ownID)), .route(.platformToIdentity))
        XCTAssertEqual(decide(.platform, destination(.identityID, text: otherID)),
                       .unavailable(.platformToOtherIdentity))
        XCTAssertEqual(UnavailableReason.platformToOtherIdentity.localizedMessage,
                       "Platform can't pay someone else's identity yet")
    }

    func testWithoutACurrentIdentityEveryIdentityIDIsSomeoneElses() {
        let noOwn = SendPairFacts(ownIdentityID: nil)
        let dest = destination(.identityID, text: ownID)
        XCTAssertEqual(SendPairPolicy.decide(source: .core, destination: dest, facts: noOwn),
                       .unavailable(.coreToOtherIdentity))
        XCTAssertEqual(SendPairPolicy.decide(source: .platform, destination: dest, facts: noOwn),
                       .unavailable(.platformToOtherIdentity))
        XCTAssertEqual(SendPairPolicy.decide(source: .identity, destination: dest, facts: noOwn),
                       .route(.identityToIdentity))
    }

    func testIdentityToShieldedStaysUnavailableForEveryShieldedAddress() {
        // ADR-0041: no call site, whatever the SDK can do.
        for text in ["a", "b", "own-current-identity-id"] {
            XCTAssertEqual(decide(.identity, destination(.shieldedAddress, text: text)),
                           .unavailable(.notSupportedYet), text)
        }
    }

    func testUnavailableReasonsAreDistinctAndCarryText() {
        let reasons: [UnavailableReason] = [.coreToOtherIdentity, .coreToScriptFormPlatformAddress,
                                            .platformToScriptFormPlatformAddress, .identityToOwnIdentity,
                                            .notSupportedYet, .paymentRequestCoreOnly, .platformToOtherIdentity]
        XCTAssertEqual(Set(reasons).count, 7)
        XCTAssertEqual(Set(reasons.map(\.localizedMessage)).count, 7)
        for reason in reasons {
            XCTAssertFalse(reason.localizedMessage.isEmpty, "\(reason)")
        }
    }

    // MARK: - AC-10: starting source

    private func balances(_ core: UInt64, _ shielded: UInt64, _ platform: UInt64) -> SendBalances {
        SendBalances(core: core, shielded: shielded, platform: platform)
    }

    private func start(_ dest: Destination, _ balances: SendBalances, pinned: SendSource? = nil) -> StartingSource {
        SendPairPolicy.startingSource(destination: dest, balances: balances, pinned: pinned, facts: facts)
    }

    func testBalanceOfIdentityIsNilNotZero() {
        let all = balances(1, 2, 3)
        XCTAssertEqual(all.balance(of: .core), 1)
        XCTAssertEqual(all.balance(of: .shielded), 2)
        XCTAssertEqual(all.balance(of: .platform), 3)
        XCTAssertNil(all.balance(of: .identity))
    }

    func testStartingSourceFollowsCoreShieldedPlatformOrder() {
        let dest = destination(.shieldedAddress)
        XCTAssertEqual(start(dest, balances(1, 1, 1)).source, .core)
        XCTAssertEqual(start(dest, balances(0, 1, 1)).source, .shielded)
        XCTAssertEqual(start(dest, balances(0, 0, 1)).source, .platform)
    }

    func testStartingSourceSkipsASourceThatCannotPayTheDestination() {
        // Core and Platform hold the most but cannot pay someone else's Identity ID.
        let dest = destination(.identityID, text: otherID)
        XCTAssertEqual(start(dest, balances(9, 0, 5)).source, .shielded)
        XCTAssertEqual(start(dest, balances(9, 3, 5)).source, .shielded)
        XCTAssertEqual(start(destination(.identityID, text: ownID), balances(0, 0, 5)).source, .platform)
    }

    /// Only Shielded among the auto-picked sources can pay a script-form Platform address.
    func testStartingSourceSkipsCoreAndPlatformForAScriptFormPlatformAddress() {
        let dest = destination(.platformAddress, script: true)
        XCTAssertEqual(start(dest, balances(9, 0, 0)).source, .shielded)
        XCTAssertEqual(start(dest, balances(9, 0, 4)).source, .shielded)
        XCTAssertEqual(start(dest, balances(9, 3, 4)).source, .shielded)
    }

    func testStartingSourceNeverPicksIdentity() {
        for kind in [Destination.Kind.coreAddress, .shieldedAddress, .platformAddress, .identityID] {
            for b in [balances(0, 0, 0), balances(1, 0, 0), balances(0, 1, 0), balances(0, 0, 1), balances(5, 5, 5)] {
                XCTAssertNotEqual(start(destination(kind, text: otherID), b).source, .identity, "\(kind) \(b)")
            }
        }
    }

    func testNoBalanceAnywherePicksTheFirstSourceThatCanPay() {
        let zero = balances(0, 0, 0)
        XCTAssertEqual(start(destination(.coreAddress), zero).source, .core)
        XCTAssertEqual(start(destination(.shieldedAddress), zero).source, .core)
        XCTAssertEqual(start(destination(.identityID, text: ownID), zero).source, .core)
        // Core cannot pay these, so the first that can is Shielded, at 0.
        XCTAssertEqual(start(destination(.identityID, text: otherID), zero).source, .shielded)
        XCTAssertEqual(start(destination(.platformAddress, script: true), zero).source, .shielded)
    }

    func testStartingSourceWithoutPinIsNeverFlaggedAsChanged() {
        XCTAssertFalse(start(destination(.coreAddress), balances(1, 1, 1)).sourceChanged)
    }

    // MARK: - AC-14: pinned source

    func testPinnedSourceThatCanPayIsKept() {
        let dest = destination(.coreAddress)
        let result = start(dest, balances(1, 9, 9), pinned: .platform)
        XCTAssertEqual(result.source, .platform)
        XCTAssertFalse(result.sourceChanged)
    }

    func testPinnedCoreWithSomeoneElsesIdentityIDIsReplacedAndFlagged() {
        let dest = destination(.identityID, text: otherID)
        let result = start(dest, balances(9, 2, 5), pinned: .core)
        XCTAssertEqual(result.source, .shielded)
        XCTAssertTrue(result.sourceChanged)
        XCTAssertNotEqual(result.source, .identity)
    }

    func testPinnedPlatformWithSomeoneElsesIdentityIDIsReplacedAndFlagged() {
        let result = start(destination(.identityID, text: otherID), balances(0, 2, 9), pinned: .platform)
        XCTAssertEqual(result.source, .shielded)
        XCTAssertTrue(result.sourceChanged)
    }

    func testPinnedCoreWithScriptFormPlatformAddressIsReplacedAndFlagged() {
        let dest = destination(.platformAddress, script: true)
        let result = start(dest, balances(9, 2, 0), pinned: .core)
        XCTAssertEqual(result.source, .shielded)
        XCTAssertTrue(result.sourceChanged)
    }

    func testPinnedSourceWithZeroBalanceThatCanPayIsKept() {
        let result = start(destination(.coreAddress), balances(5, 0, 0), pinned: .shielded)
        XCTAssertEqual(result.source, .shielded)
        XCTAssertFalse(result.sourceChanged)
    }

    // MARK: - AC-16, AC-17: Confirm warnings per pair

    private func warnings(_ source: SendSource, _ dest: Destination, isMax: Bool = false) -> [ConfirmWarning] {
        SendPairPolicy.warnings(source: source, destination: dest, isMax: isMax)
    }

    private var allAvailablePairs: [(SendSource, Destination)] {
        [
            (.core, destination(.coreAddress)), (.core, destination(.shieldedAddress)),
            (.core, destination(.platformAddress)), (.core, destination(.identityID, text: ownID)),
            (.shielded, destination(.coreAddress)), (.shielded, destination(.shieldedAddress)),
            (.shielded, destination(.platformAddress)), (.shielded, destination(.identityID, text: otherID)),
            (.platform, destination(.coreAddress)), (.platform, destination(.shieldedAddress)),
            (.platform, destination(.platformAddress)), (.platform, destination(.identityID, text: ownID)),
            (.identity, destination(.coreAddress)), (.identity, destination(.platformAddress)),
            (.identity, destination(.identityID, text: otherID))
        ]
    }

    func testNoPairListsAWithdrawalDelayNotice() {
        for (source, dest) in allAvailablePairs {
            let label = "\(source) -> \(dest.type)"
            XCTAssertFalse(warnings(source, dest).contains { "\($0)" == "withdrawalDelay" }, label)
            XCTAssertFalse(warnings(source, dest, isMax: true).contains { "\($0)" == "withdrawalDelay" },
                           "\(label) Max")
        }
    }

    func testShieldedPublicWarningIsListedForExactlyShieldedToNonShielded() {
        for (source, dest) in allAvailablePairs {
            let expected = source == .shielded && dest.type != .shieldedAddress
            XCTAssertEqual(warnings(source, dest).contains(.shieldedMadePublic), expected, "\(source) -> \(dest.type)")
        }
    }

    func testShieldedToShieldedHasNoPublicWarning() {
        let list = warnings(.shielded, destination(.shieldedAddress))
        XCTAssertFalse(list.contains(.shieldedMadePublic))
    }

    /// Owner review O7: Shielded → Core says "not instant" in place of Processing time, then the public notice.
    func testShieldedToCoreListsExactlyNotInstantAndPublic() {
        XCTAssertEqual(warnings(.shielded, destination(.coreAddress)), [.shieldedNotInstant, .shieldedMadePublic])
        XCTAssertEqual(warnings(.shielded, destination(.coreAddress), isMax: true),
                       [.shieldedNotInstant, .shieldedMadePublic])
    }

    func testNotInstantOnExactlyShieldedToCore() {
        for (source, dest) in allAvailablePairs {
            let expected = source == .shielded && dest.type == .coreAddress
            XCTAssertEqual(warnings(source, dest).contains(.shieldedNotInstant), expected, "\(source) -> \(dest.type)")
        }
    }

    // MARK: - AC-18: the current Send's warnings keep exactly their conditions
    //
    // Source of the conditions: Pay/SendScreen.swift (confirm sheet) infoTitle/infoBody, lines 1552-1590, and
    // SendViewModel.Route (lines 34-50: the 8 routes among Core, Shielded and Platform). The sheet shows ONE card,
    // chosen in this priority: Core drain (Core -> Shielded Max, `coreShieldedDrain != nil`), then Shielded -> Core
    // and Platform -> Core ("Processing time"; the Platform one has a full-balance variant, `isFullPlatformWithdrawal`,
    // SendViewModel.swift:1416), else the wrong-address reminder. So the legacy warnings are mutually exclusive
    // (wrong-address vs processing/emptying). The wrong-address card is the `default:` branch, so it also applies to
    // pairs the old Send never had; those get no other legacy warning.

    private let legacy: Set<ConfirmWarning> = [
        .wrongAddressReminder, .processingTime, .fullPlatformWithdrawal, .emptyingCoreBalance
    ]

    private func legacyWarnings(_ source: SendSource, _ dest: Destination, isMax: Bool = false) -> Set<ConfirmWarning> {
        Set(warnings(source, dest, isMax: isMax)).intersection(legacy)
    }

    func testWrongAddressReminderIsTheDefaultForEveryPairExceptWithdrawalsToCoreAndTheCoreDrain() {
        for (source, dest) in allAvailablePairs {
            let isWithdrawalToCore = dest.type == .coreAddress && source != .core
            let label = "\(source) -> \(dest.type)"
            XCTAssertEqual(warnings(source, dest).contains(.wrongAddressReminder), !isWithdrawalToCore, label)
        }
    }

    func testWrongAddressReminderIsDroppedOnTheCoreDrainOnly() {
        let shielded = destination(.shieldedAddress)
        XCTAssertFalse(warnings(.core, shielded, isMax: true).contains(.wrongAddressReminder))
        XCTAssertTrue(warnings(.core, shielded).contains(.wrongAddressReminder))
        // Max to another destination is not the drain.
        XCTAssertTrue(warnings(.core, destination(.coreAddress), isMax: true).contains(.wrongAddressReminder))
    }

    /// Shielded → Core tells the delay with its "not instant" notice instead (owner review O7).
    func testProcessingTimeOnExactlyPlatformToCore() {
        for (source, dest) in allAvailablePairs {
            let expected = dest.type == .coreAddress && source == .platform
            XCTAssertEqual(warnings(source, dest).contains(.processingTime), expected, "\(source) -> \(dest.type)")
        }
    }

    func testWrongAddressAndProcessingTimeAreNeverListedTogether() {
        for (source, dest) in allAvailablePairs {
            let list = warnings(source, dest)
            let label = "\(source) -> \(dest.type)"
            XCTAssertFalse(list.contains(.wrongAddressReminder) && list.contains(.processingTime), label)
        }
    }

    func testIdentityToCoreListsNoWarning() {
        XCTAssertEqual(warnings(.identity, destination(.coreAddress)), [])
    }

    func testPlatformToCoreListsProcessingTimeAndAtMaxTheFullWithdrawal() {
        XCTAssertEqual(warnings(.platform, destination(.coreAddress)), [.processingTime])
        XCTAssertEqual(warnings(.platform, destination(.coreAddress), isMax: true),
                       [.processingTime, .fullPlatformWithdrawal])
    }

    func testNewPairsListNoLegacyWarningOtherThanTheDefaultReminder() {
        let newPairs: [(SendSource, Destination)] = allAvailablePairs.filter { source, dest in
            source == .identity || dest.type == .identityID || (source == .core && dest.type == .platformAddress)
        }
        XCTAssertFalse(newPairs.isEmpty)
        for (source, dest) in newPairs {
            let extra = legacyWarnings(source, dest, isMax: true).subtracting([.wrongAddressReminder])
            XCTAssertTrue(extra.isEmpty, "\(source) -> \(dest.type)")
        }
    }

    /// Max on Platform → Core withdraws the whole balance (the executor's `fullBalance`), though its amount is the
    /// balance less the fee.
    func testFullPlatformWithdrawalOnlyOnAMaxPlatformToCore() {
        let core = destination(.coreAddress)
        XCTAssertTrue(warnings(.platform, core, isMax: true).contains(.fullPlatformWithdrawal))
        XCTAssertTrue(warnings(.platform, core, isMax: true).contains(.processingTime))
        XCTAssertFalse(warnings(.platform, core).contains(.fullPlatformWithdrawal))
        for (source, dest) in allAvailablePairs where !(source == .platform && dest.type == .coreAddress) {
            let label = "\(source) -> \(dest.type)"
            XCTAssertFalse(warnings(source, dest, isMax: true).contains(.fullPlatformWithdrawal), label)
        }
    }

    /// Max on Core → Shielded drains the wallet (the executor's whole-wallet drain), though its amount is the balance
    /// less the fee.
    func testEmptyingCoreWarningOnlyOnAMaxCoreToShielded() {
        // The current Send's "Sends all eligible Transparent funds" is the Core -> Shielded drain only.
        let shielded = destination(.shieldedAddress)
        XCTAssertTrue(warnings(.core, shielded, isMax: true).contains(.emptyingCoreBalance))
        XCTAssertFalse(warnings(.core, shielded).contains(.emptyingCoreBalance))
        // Replaces the wrong-address card in the current Send.
        XCTAssertFalse(warnings(.core, shielded, isMax: true).contains(.wrongAddressReminder))
        for (source, dest) in allAvailablePairs where !(source == .core && dest.type == .shieldedAddress) {
            let label = "\(source) -> \(dest.type)"
            XCTAssertFalse(warnings(source, dest, isMax: true).contains(.emptyingCoreBalance), label)
        }
    }
}
