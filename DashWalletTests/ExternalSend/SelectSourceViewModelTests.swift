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

/// The Select source sheet's ViewModel (SCR-05; AC-05, AC-06, AC-07): only the edges are faked (the per-source
/// balances, the Current identity); the pair policy and the ViewModel are the real ones.
@MainActor
final class SelectSourceViewModelTests: XCTestCase {
    private typealias Row = SelectSourceViewModel.Row

    // MARK: - Fixtures

    private let ownID = "OwnIdentityIDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    private let otherID = "OtherIdentityIDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    private let identityCredits: UInt64 = 5_000_000_000

    private func destination(_ type: Destination.Kind, text: String = "dest",
                             isScriptForm: Bool = false) -> Destination {
        Destination(type: type, text: text, isScriptForm: isScriptForm)
    }

    // MARK: - Fakes

    private final class FakeBalances: ExternalSendBalanceReading {
        /// A source missing from the table is unreadable (nil). Identity is in credits, the rest in duffs.
        var table: [SendSource: UInt64] = [:]

        func spendableBalance(of source: SendSource) async -> UInt64? {
            table[source]
        }
    }

    private final class FakeIdentity: CurrentIdentityReading {
        var current: SelectSourceIdentity?

        func currentIdentity() async -> SelectSourceIdentity? {
            current
        }
    }

    /// 1 DASH = 50 units of the local currency; the text is a plain marker, not the app's formatter.
    private final class FakeConverter: SendAmountConverting {
        var rate: Decimal? = 50

        func fiat(forDuffs duffs: UInt64) -> Decimal? {
            rate.map { Decimal(duffs) / 100_000_000 * $0 }
        }

        func duffs(forFiat fiat: Decimal) -> UInt64? {
            nil
        }

        func fiatText(forDuffs duffs: UInt64) -> String? {
            fiat(forDuffs: duffs).map { "$\($0)" }
        }
    }

    private let balances = FakeBalances()
    private let identity = FakeIdentity()
    private let converter = FakeConverter()
    private var picked: [SendSource] = []

    override func setUp() {
        super.setUp()
        balances.table = [.core: 300_000_000, .shielded: 200_000_000, .platform: 100_000_000,
                          .identity: identityCredits]
        identity.current = SelectSourceIdentity(id: ownID, username: "alice")
    }

    private func makeVM(_ destination: Destination, selected: SendSource = .core) async -> SelectSourceViewModel {
        let vm = SelectSourceViewModel(destination: destination, selected: selected, balances: balances,
                                       currentIdentity: identity, converter: converter)
        vm.onPick = { [unowned self] source in picked.append(source) }
        await vm.load()
        return vm
    }

    private func row(_ source: SendSource, in vm: SelectSourceViewModel) throws -> Row {
        try XCTUnwrap(vm.rows.first { $0.source == source }, "no \(source) row")
    }

    // MARK: - AC-05: every source, in order, with its balance

    func testListsCoreShieldedPlatformIdentityInThatOrder() async {
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertEqual(vm.rows.map(\.source), [.core, .shielded, .platform, .identity])
    }

    func testEachRowCarriesItsBalanceInDuffs() async throws {
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertEqual(try row(.core, in: vm).balanceDuffs, 300_000_000)
        XCTAssertEqual(try row(.shielded, in: vm).balanceDuffs, 200_000_000)
        XCTAssertEqual(try row(.platform, in: vm).balanceDuffs, 100_000_000)
    }

    func testIdentityRowShowsItsCreditsAsTheirDashValue() async throws {
        let vm = await makeVM(destination(.coreAddress))
        let expected = AmountRules.dashValue(of: identityCredits)
        XCTAssertGreaterThan(expected, 0)
        XCTAssertNotEqual(expected, identityCredits, "credits are not duffs")
        XCTAssertEqual(try row(.identity, in: vm).balanceDuffs, expected)
    }

    func testBalanceTextIsTheAppsDashFormatterOnTheDuffs() async throws {
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertEqual(try row(.core, in: vm).balanceText, UInt64(300_000_000).formattedDashAmount)
        XCTAssertEqual(try row(.identity, in: vm).balanceText,
                       AmountRules.dashValue(of: identityCredits).formattedDashAmount)
    }

    func testEachRowShowsItsBalanceInFiatThroughTheSameConverter() async throws {
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertEqual(try row(.core, in: vm).balanceFiatText, converter.fiatText(forDuffs: 300_000_000))
        XCTAssertEqual(try row(.shielded, in: vm).balanceFiatText, converter.fiatText(forDuffs: 200_000_000))
        XCTAssertEqual(try row(.identity, in: vm).balanceFiatText,
                       converter.fiatText(forDuffs: AmountRules.dashValue(of: identityCredits)))
        XCTAssertNotNil(try row(.core, in: vm).balanceFiatText)
    }

    func testWithoutARateTheRowHasNoFiatText() async throws {
        converter.rate = nil
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertNil(try row(.core, in: vm).balanceFiatText)
        XCTAssertNotNil(try row(.core, in: vm).balanceText)
    }

    func testZeroBalanceTextIsTheFormattedZero() async throws {
        balances.table = [.core: 0, .shielded: 0, .platform: 0, .identity: 0]
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertEqual(try row(.core, in: vm).balanceText, UInt64(0).formattedDashAmount)
    }

    func testAvailableRowsAreSelectableAndCarryNoReason() async throws {
        let vm = await makeVM(destination(.coreAddress))
        for source in SendSource.allCases {
            let r = try row(source, in: vm)
            XCTAssertTrue(r.isSelectable, "\(source)")
            XCTAssertNil(r.unavailableReason, "\(source)")
            XCTAssertNil(r.reasonText, "\(source)")
        }
    }

    // MARK: - current selection

    func testOnlyTheCurrentSelectionIsMarked() async {
        let vm = await makeVM(destination(.coreAddress), selected: .platform)
        XCTAssertEqual(vm.selected, .platform)
        XCTAssertEqual(vm.rows.filter(\.isSelected).map(\.source), [.platform])
    }

    func testPickingAnAvailableRowReportsItAndMovesTheMark() async {
        let vm = await makeVM(destination(.coreAddress), selected: .core)
        vm.select(.shielded)
        XCTAssertEqual(picked, [.shielded])
        XCTAssertEqual(vm.selected, .shielded)
        XCTAssertEqual(vm.rows.filter(\.isSelected).map(\.source), [.shielded])
    }

    func testPickingTheIdentityRowReportsIt() async {
        let vm = await makeVM(destination(.coreAddress))
        vm.select(.identity)
        XCTAssertEqual(picked, [.identity])
    }

    // MARK: - AC-06: unavailable pairs are shown with the policy's reason and cannot be picked

    private func assertUnavailable(_ source: SendSource, _ reason: UnavailableReason, _ text: String,
                                   in vm: SelectSourceViewModel, file: StaticString = #filePath,
                                   line: UInt = #line) throws {
        let r = try row(source, in: vm)
        XCTAssertEqual(r.unavailableReason, reason, file: file, line: line)
        XCTAssertEqual(r.reasonText, reason.localizedMessage, file: file, line: line)
        XCTAssertEqual(r.reasonText, text, file: file, line: line)
        XCTAssertFalse(r.isSelectable, file: file, line: line)
        XCTAssertFalse(r.isSelected, file: file, line: line)
    }

    func testCoreToSomeoneElsesIdentityIDIsUnavailableButListedWithItsBalance() async throws {
        let vm = await makeVM(destination(.identityID, text: otherID), selected: .shielded)
        try assertUnavailable(.core, .coreToOtherIdentity, "Core can't pay someone else's identity", in: vm)
        XCTAssertEqual(try row(.core, in: vm).balanceDuffs, 300_000_000, "dimmed, not hidden")
        XCTAssertEqual(vm.rows.count, 4)
    }

    func testCoreToOwnIdentityIsAvailableAndIdentityToItselfIsNot() async throws {
        let vm = await makeVM(destination(.identityID, text: ownID), selected: .core)
        XCTAssertTrue(try row(.core, in: vm).isSelectable)
        try assertUnavailable(.identity, .identityToOwnIdentity, "Identity can't top up itself", in: vm)
    }

    func testCoreAndPlatformToScriptFormPlatformAddressAreUnavailable() async throws {
        let vm = await makeVM(destination(.platformAddress, isScriptForm: true), selected: .shielded)
        try assertUnavailable(.core, .coreToScriptFormPlatformAddress,
                              "Core can't pay this kind of Platform address", in: vm)
        try assertUnavailable(.platform, .platformToScriptFormPlatformAddress,
                              "Platform can't pay this kind of Platform address", in: vm)
        XCTAssertTrue(try row(.shielded, in: vm).isSelectable)
        XCTAssertTrue(try row(.identity, in: vm).isSelectable)
    }

    func testIdentityToAShieldedAddressIsUnavailable() async throws {
        let vm = await makeVM(destination(.shieldedAddress), selected: .core)
        try assertUnavailable(.identity, .notSupportedYet, "Identity can't pay a Shielded address yet", in: vm)
        XCTAssertTrue(try row(.core, in: vm).isSelectable)
        XCTAssertTrue(try row(.shielded, in: vm).isSelectable)
        XCTAssertTrue(try row(.platform, in: vm).isSelectable)
    }

    func testPaymentRequestAllowsOnlyCore() async throws {
        let vm = await makeVM(destination(.paymentRequest, text: ""), selected: .core)
        XCTAssertTrue(try row(.core, in: vm).isSelectable)
        for source in [SendSource.shielded, .platform, .identity] {
            try assertUnavailable(source, .paymentRequestCoreOnly,
                                  "A payment request can only be paid from Core", in: vm)
        }
    }

    func testTappingAnUnavailableRowChangesNothingAndReportsNothing() async throws {
        let vm = await makeVM(destination(.identityID, text: otherID), selected: .shielded)
        vm.select(.core)
        XCTAssertTrue(picked.isEmpty)
        XCTAssertEqual(vm.selected, .shielded)
        XCTAssertEqual(vm.rows.filter(\.isSelected).map(\.source), [.shielded])
        try assertUnavailable(.core, .coreToOtherIdentity, "Core can't pay someone else's identity", in: vm)
    }

    // MARK: - AC-07: Identity only with a Current identity that has a username

    func testNoCurrentIdentityOffersThreeRowsAndNoIdentity() async {
        identity.current = nil
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertEqual(vm.rows.map(\.source), [.core, .shielded, .platform])
    }

    func testCurrentIdentityWithoutAUsernameIsNotOffered() async {
        identity.current = SelectSourceIdentity(id: ownID, username: nil)
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertEqual(vm.rows.map(\.source), [.core, .shielded, .platform])
    }

    func testIdentityWithoutAUsernameStaysHiddenButItsIDStillMakesCoreToItARoute() async throws {
        identity.current = SelectSourceIdentity(id: ownID, username: nil)
        let vm = await makeVM(destination(.identityID, text: ownID))
        XCTAssertEqual(vm.rows.map(\.source), [.core, .shielded, .platform])
        XCTAssertTrue(try row(.core, in: vm).isSelectable, "own identity: a top-up, not 'someone else's'")
        XCTAssertNil(try row(.core, in: vm).unavailableReason)
    }

    func testCurrentIdentityWithAnEmptyUsernameIsNotOffered() async {
        identity.current = SelectSourceIdentity(id: ownID, username: "")
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertEqual(vm.rows.map(\.source), [.core, .shielded, .platform])
    }

    func testPickingIdentityWhenItIsNotOfferedReportsNothing() async {
        identity.current = nil
        let vm = await makeVM(destination(.coreAddress), selected: .core)
        vm.select(.identity)
        XCTAssertTrue(picked.isEmpty)
        XCTAssertEqual(vm.selected, .core)
    }

    // MARK: - zero and unreadable balances

    func testZeroBalancesAreListedAsZeroAndStaySelectable() async throws {
        balances.table = [.core: 0, .shielded: 0, .platform: 0, .identity: 0]
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertEqual(vm.rows.map(\.source), [.core, .shielded, .platform, .identity])
        for source in SendSource.allCases {
            let r = try row(source, in: vm)
            XCTAssertEqual(r.balanceDuffs, 0, "\(source)")
            XCTAssertTrue(r.isSelectable, "\(source)")
        }
        vm.select(.platform)
        XCTAssertEqual(picked, [.platform])
    }

    func testZeroBalanceDoesNotMakeAnUnavailablePairSelectable() async throws {
        balances.table = [.core: 0, .shielded: 0, .platform: 0, .identity: 0]
        let vm = await makeVM(destination(.shieldedAddress))
        try assertUnavailable(.identity, .notSupportedYet, "Identity can't pay a Shielded address yet", in: vm)
    }

    func testAnUnreadableBalanceStaysUnknownNotZero() async throws {
        balances.table = [.core: 300_000_000, .platform: 100_000_000, .identity: identityCredits]
        let vm = await makeVM(destination(.coreAddress))
        let shielded = try row(.shielded, in: vm)
        XCTAssertNil(shielded.balanceDuffs, "unreadable is nil, never a fabricated 0")
        XCTAssertNil(shielded.balanceText)
        XCTAssertTrue(shielded.isSelectable, "the row is still listed and pickable")
        XCTAssertEqual(try row(.core, in: vm).balanceDuffs, 300_000_000)
    }
}
