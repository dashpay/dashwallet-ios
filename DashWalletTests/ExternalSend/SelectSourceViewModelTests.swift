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

/// The Select source sheet's ViewModel (SCR-05; AC-05, AC-06, AC-07): only the edge is faked (the Current
/// identity); the pair policy and the ViewModel are the real ones.
@MainActor
final class SelectSourceViewModelTests: XCTestCase {
    private typealias Row = SelectSourceViewModel.Row

    // MARK: - Fixtures

    private let ownID = "OwnIdentityIDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    private let otherID = "OtherIdentityIDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    private func destination(_ type: Destination.Kind, text: String = "dest",
                             isScriptForm: Bool = false) -> Destination {
        Destination(type: type, text: text, isScriptForm: isScriptForm)
    }

    // MARK: - Fakes

    private final class FakeIdentity: CurrentIdentityReading {
        var current: SelectSourceIdentity?

        func currentIdentity() async -> SelectSourceIdentity? {
            current
        }
    }

    private let identity = FakeIdentity()
    private var picked: [SendSource] = []

    override func setUp() {
        super.setUp()
        identity.current = SelectSourceIdentity(id: ownID, username: "alice")
    }

    private func makeVM(_ destination: Destination, selected: SendSource = .core) async -> SelectSourceViewModel {
        let vm = SelectSourceViewModel(destination: destination, selected: selected, currentIdentity: identity)
        vm.onPick = { [unowned self] source in picked.append(source) }
        await vm.load()
        return vm
    }

    private func row(_ source: SendSource, in vm: SelectSourceViewModel) throws -> Row {
        try XCTUnwrap(vm.rows.first { $0.source == source }, "no \(source) row")
    }

    // MARK: - AC-05: every source, in order, icon and name only (owner review O5)

    func testListsCoreShieldedPlatformIdentityInThatOrder() async {
        let vm = await makeVM(destination(.coreAddress))
        XCTAssertEqual(vm.rows.map(\.source), [.core, .shielded, .platform, .identity])
    }

    func testRowsCarryNoBalanceForDisplay() async throws {
        let vm = await makeVM(destination(.coreAddress))
        for source in SendSource.allCases {
            let labels = Mirror(reflecting: try row(source, in: vm)).children.compactMap(\.label)
            XCTAssertFalse(labels.contains { $0.lowercased().contains("balance") }, "\(source): \(labels)")
        }
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
        vm.tap(.shielded)
        XCTAssertEqual(picked, [.shielded])
        XCTAssertNil(vm.toastMessage, "a pick shows no Toast")
        XCTAssertEqual(vm.selected, .shielded)
        XCTAssertEqual(vm.rows.filter(\.isSelected).map(\.source), [.shielded])
    }

    func testPickingTheIdentityRowReportsIt() async {
        let vm = await makeVM(destination(.coreAddress))
        vm.tap(.identity)
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

    func testCoreToSomeoneElsesIdentityIDIsUnavailableButListed() async throws {
        let vm = await makeVM(destination(.identityID, text: otherID), selected: .shielded)
        try assertUnavailable(.core, .coreToOtherIdentity, "Core can't pay someone else's identity", in: vm)
        XCTAssertEqual(vm.rows.count, 4, "dimmed, not hidden")
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
        vm.tap(.identity)
        XCTAssertEqual(vm.toastMessage, "Identity can't pay a Shielded address yet")
        XCTAssertTrue(picked.isEmpty)
        XCTAssertEqual(vm.selected, .core)
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

    func testTappingAnUnavailableRowShowsItsReasonAndChangesNothing() async throws {
        let vm = await makeVM(destination(.identityID, text: otherID), selected: .shielded)
        XCTAssertNil(vm.toastMessage)
        vm.tap(.core)
        XCTAssertEqual(vm.toastMessage, "Core can't pay someone else's identity")
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
        vm.tap(.identity)
        XCTAssertTrue(picked.isEmpty)
        XCTAssertNil(vm.toastMessage, "no row, no reason")
        XCTAssertEqual(vm.selected, .core)
    }

    // MARK: - the Toast

    func testAnotherUnavailableTapReplacesTheReason() async {
        let vm = await makeVM(destination(.platformAddress, isScriptForm: true), selected: .shielded)
        vm.tap(.core)
        vm.tap(.platform)
        XCTAssertEqual(vm.toastMessage, "Platform can't pay this kind of Platform address")
        XCTAssertTrue(picked.isEmpty)
        XCTAssertEqual(vm.selected, .shielded)
    }

    func testDismissingTheToastClearsTheReason() async {
        let vm = await makeVM(destination(.shieldedAddress), selected: .core)
        vm.tap(.identity)
        vm.dismissToast()
        XCTAssertNil(vm.toastMessage)
    }
}
