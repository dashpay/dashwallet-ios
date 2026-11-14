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

/// The Address screen's ViewModel (SCR-02; AC-02, AC-03, AC-13, AC-13b): only the edges are faked
/// (the pasteboard, the Identity ID lookup); the parser and the ViewModel are the real ones.
@MainActor
final class AddressViewModelTests: XCTestCase {
    private typealias Network = WalletEnvironment.NetworkKind

    // MARK: - Fixtures (real checksums, as in DestinationParserTests)

    private static let hash20 = Data((1 ... 20).map { UInt8($0) })
    private static let p2pkhScript = Data([0x76, 0xa9, 0x14] + hash20 + [0x88, 0xac])

    private func core(_ network: Network) -> String {
        let payment: PaymentNetwork = network == .mainnet ? .mainnet : .testnet
        return ScriptAddressCodec.address(forScript: Self.p2pkhScript, network: payment) ?? ""
    }

    private func identityID() -> String {
        ScriptAddressCodec.base58Encode(Data((1 ... 32).map { UInt8($0 * 3) })) ?? ""
    }

    private let network: Network = .testnet

    // MARK: - Fakes

    private final class FakePasteboard: ClipboardReading {
        var content: String?
        private(set) var readCount = 0

        func readString() -> String? {
            readCount += 1
            return content
        }
    }

    private final class FakeLookup: IdentityLooking {
        var results: [IdentityLookupResult] = []
        /// When true, `lookup` suspends until `resume(_:)`, so the `checking` state can be observed.
        var suspends = false
        private(set) var lookedUp: [(id: String, network: Network)] = []
        private var pending: CheckedContinuation<IdentityLookupResult, Never>?

        func lookup(id: String, network: Network) async -> IdentityLookupResult {
            lookedUp.append((id, network))
            if suspends {
                return await withCheckedContinuation { pending = $0 }
            }
            return results.isEmpty ? .couldNotCheck : results.removeFirst()
        }

        func resume(_ result: IdentityLookupResult) {
            pending?.resume(returning: result)
            pending = nil
        }

        var isWaiting: Bool { pending != nil }
    }

    private let pasteboard = FakePasteboard()
    private let lookup = FakeLookup()
    private var handed: [(Destination, IdentityRecipient?)] = []

    private func makeVM(network: Network? = nil) -> AddressViewModel {
        let vm = AddressViewModel(network: network ?? self.network, identityLookup: lookup, pasteboard: pasteboard)
        vm.onResolved = { [unowned self] destination, recipient in handed.append((destination, recipient)) }
        return vm
    }

    private func waitUntilLookupSuspended() async {
        for _ in 0 ..< 200 where !lookup.isWaiting { await Task.yield() }
        XCTAssertTrue(lookup.isWaiting, "the lookup was never started")
    }

    // MARK: - default / AC-03 (no clipboard read before the tap)

    func testDefaultStateReadsNoClipboardAndDisablesContinue() {
        pasteboard.content = core(network)
        let vm = makeVM()
        XCTAssertEqual(vm.state, .initial)
        XCTAssertEqual(vm.text, "")
        XCTAssertFalse(vm.canContinue)
        XCTAssertEqual(pasteboard.readCount, 0, "AC-03: nothing reads the clipboard before the tap")
    }

    func testTypingAndClearingNeverReadsTheClipboard() {
        pasteboard.content = core(network)
        let vm = makeVM()
        vm.setText("abc")
        vm.setText("")
        vm.clear()
        XCTAssertEqual(pasteboard.readCount, 0)
    }

    // MARK: - clipboard

    func testShowClipboardReadsOnceAndShowsTheDestinationFound() {
        let address = core(network)
        pasteboard.content = "pay me at \(address) thanks"
        let vm = makeVM()
        vm.showClipboard()
        XCTAssertEqual(pasteboard.readCount, 1, "exactly one read, inside the tap")
        guard case .clipboard(let found) = vm.state else { return XCTFail("expected .clipboard, got \(vm.state)") }
        XCTAssertEqual(found.type, .coreAddress)
        XCTAssertEqual(found.text, address)
        XCTAssertEqual(vm.text, "", "showing is not filling")
    }

    /// A request fetched for an empty field (a scanned or clipboard link) leaves the screen as it was: Continue
    /// never goes on for an empty field, and a clipboard suggestion stays.
    func testCheckingARequestFromAnEmptyFieldEndsInTheStateItStartedFrom() {
        let vm = makeVM()
        vm.beginChecking()
        XCTAssertEqual(vm.state, .checking)
        vm.endChecking()
        XCTAssertEqual(vm.state, .initial)
        XCTAssertFalse(vm.canContinue)

        pasteboard.content = "dash:?r=https://merchant.example/pay/1"
        vm.showClipboard()
        let suggestion = vm.state
        guard case .clipboard = suggestion else { return XCTFail("no clipboard suggestion: \(suggestion)") }
        vm.beginChecking()
        vm.endChecking()
        XCTAssertEqual(vm.state, suggestion)
        XCTAssertFalse(vm.canContinue)

        vm.setText(core(network))
        vm.beginChecking()
        vm.endChecking()
        XCTAssertEqual(vm.state, .entered, "a filled field can continue again")
    }

    func testTappingTheClipboardDestinationFillsTheField() {
        let address = core(network)
        pasteboard.content = address
        let vm = makeVM()
        vm.showClipboard()
        vm.fillFromClipboard()
        XCTAssertEqual(vm.text, address)
        XCTAssertEqual(vm.state, .entered)
        XCTAssertTrue(vm.canContinue)
    }

    func testClipboardPaymentLinkIsShownAndTappingItHandsItOnAtOnce() {
        pasteboard.content = "dash:?r=https%3A%2F%2Fmerchant.example%2Fpr"
        let vm = makeVM()
        vm.showClipboard()
        guard case .clipboard(let found) = vm.state else { return XCTFail("expected .clipboard, got \(vm.state)") }
        XCTAssertEqual(found.type, .paymentRequest)
        vm.fillFromClipboard()
        XCTAssertEqual(vm.text, "", "no empty address is put in the field")
        XCTAssertEqual(handed.count, 1)
        XCTAssertEqual(handed.first?.0, found)
        XCTAssertNil(handed.first?.1)
    }

    func testClipboardDashLinkWithAnAmountIsHandedOnWithItsAmount() {
        pasteboard.content = "dash:\(core(network))?amount=1.5"
        let vm = makeVM()
        vm.showClipboard()
        guard case .clipboard(let found) = vm.state else { return XCTFail("expected .clipboard, got \(vm.state)") }
        vm.fillFromClipboard()
        XCTAssertEqual(handed.count, 1, "a link keeps its fields, so it is handed on, not reduced to its address")
        XCTAssertEqual(handed.first?.0, found)
        XCTAssertEqual(handed.first?.0.amountDuffs, 150_000_000)
        XCTAssertNil(handed.first?.1)
    }

    func testClipboardWithNoDestinationFillsNothing() {
        pasteboard.content = "just some words"
        let vm = makeVM()
        vm.showClipboard()
        XCTAssertEqual(vm.state, .clipboardNone)
        XCTAssertEqual(vm.text, "")
        XCTAssertFalse(vm.canContinue)
    }

    func testEmptyClipboardIsClipboardNone() {
        pasteboard.content = nil
        let vm = makeVM()
        vm.showClipboard()
        XCTAssertEqual(vm.state, .clipboardNone)
        XCTAssertEqual(vm.text, "")
    }

    func testClipboardAddressOfAnotherNetworkIsNotOffered() {
        pasteboard.content = core(.mainnet)
        let vm = makeVM(network: .testnet)
        vm.showClipboard()
        XCTAssertEqual(vm.state, .clipboardNone)
    }

    // MARK: - entered / invalid (AC-02)

    func testTypingEnablesContinue() {
        let vm = makeVM()
        vm.setText(core(network))
        XCTAssertEqual(vm.state, .entered)
        XCTAssertTrue(vm.canContinue)
        XCTAssertTrue(handed.isEmpty, "typing alone hands nothing on")
    }

    func testClearingTheFieldReturnsToDefault() {
        let vm = makeVM()
        vm.setText(core(network))
        vm.clear()
        XCTAssertEqual(vm.text, "")
        XCTAssertEqual(vm.state, .initial)
        XCTAssertFalse(vm.canContinue)
    }

    // MARK: - Return in the field

    /// The field wraps to a second line, so Return reaches it as a newline: it ends editing instead.
    func testReturnEndsEditingAndLeavesNoNewline() {
        let vm = makeVM()
        let address = core(network)
        vm.isFieldFocused = true
        vm.setText(address)
        XCTAssertTrue(vm.isFieldFocused, "typing keeps the keyboard up")
        vm.setText(address + "\n")
        XCTAssertEqual(vm.text, address)
        XCTAssertFalse(vm.isFieldFocused)
        XCTAssertEqual(vm.state, .entered)
    }

    func testReturnInAnEmptyFieldEndsEditingAndLeavesItEmpty() {
        let vm = makeVM()
        vm.isFieldFocused = true
        vm.setText("\n")
        XCTAssertEqual(vm.text, "")
        XCTAssertEqual(vm.state, .initial)
        XCTAssertFalse(vm.isFieldFocused)
    }

    /// Address must not leave the screen with the keyboard up: SwiftUI then keeps the keyboard inset stale and the
    /// next keyboard covers Continue when the user comes back.
    func testHandingTheDestinationOnEndsEditingFirst() async {
        let vm = makeVM()
        var focusedWhenHandedOn = true
        vm.onResolved = { [unowned vm] _, _ in focusedWhenHandedOn = vm.isFieldFocused }
        vm.isFieldFocused = true
        vm.setText(core(network))
        await vm.continueTapped()
        XCTAssertFalse(focusedWhenHandedOn, "the keyboard is down before the flow moves on")
    }

    func testHandingAnIdentityOnEndsEditingFirst() async {
        lookup.results = [.found(IdentityRecipient(id: identityID(), username: "alice", isOwnCurrentIdentity: false))]
        let vm = makeVM()
        var focusedWhenHandedOn = true
        vm.onResolved = { [unowned vm] _, _ in focusedWhenHandedOn = vm.isFieldFocused }
        vm.isFieldFocused = true
        vm.setText(identityID())
        await vm.continueTapped()
        XCTAssertFalse(focusedWhenHandedOn, "the keyboard is down before the flow moves on")
    }

    func testPastedTextWithLineBreaksIsEnteredWithoutThem() {
        let vm = makeVM()
        let address = core(network)
        vm.isFieldFocused = true
        vm.setText(address + "\r\n")
        XCTAssertEqual(vm.text, address)
        XCTAssertFalse(vm.isFieldFocused)
        vm.setText(String(address.prefix(10)) + "\n" + String(address.dropFirst(10)))
        XCTAssertEqual(vm.text, address)
    }

    func testGarbageIsInvalidAndCannotContinue() async {
        let vm = makeVM()
        vm.setText("not-an-address")
        await vm.continueTapped()
        XCTAssertEqual(vm.state, .invalid(.invalid))
        XCTAssertFalse(vm.canContinue)
        XCTAssertTrue(handed.isEmpty, "AC-02: nothing invalid reaches the next step")
        XCTAssertTrue(lookup.lookedUp.isEmpty)
    }

    func testAddressOfAnotherNetworkIsInvalidWithTheWrongNetworkReason() async {
        let vm = makeVM(network: .testnet)
        vm.setText(core(.mainnet))
        await vm.continueTapped()
        XCTAssertEqual(vm.state, .invalid(.wrongNetwork))
        XCTAssertFalse(vm.canContinue)
        XCTAssertTrue(handed.isEmpty)
    }

    func testEditingAfterInvalidClearsTheErrorAndReenablesContinue() async {
        let vm = makeVM()
        vm.setText("not-an-address")
        await vm.continueTapped()
        vm.setText(core(network))
        XCTAssertEqual(vm.state, .entered)
        XCTAssertTrue(vm.canContinue)
    }

    // MARK: - Continue hands the destination on

    func testContinueOnACoreAddressHandsTheDestinationOn() async {
        let address = core(network)
        let vm = makeVM()
        vm.setText("  \(address)\n")
        await vm.continueTapped()
        XCTAssertEqual(handed.count, 1)
        XCTAssertEqual(handed.first?.0.type, .coreAddress)
        XCTAssertEqual(handed.first?.0.text, address)
        XCTAssertNil(handed.first?.1, "no recipient for a plain address")
        XCTAssertTrue(lookup.lookedUp.isEmpty, "no Platform lookup for an address")
    }

    func testContinueUsesTheNetworkItWasGiven() async {
        let vm = makeVM(network: .mainnet)
        vm.setText(core(.mainnet))
        await vm.continueTapped()
        XCTAssertEqual(handed.first?.0.type, .coreAddress)
    }

    func testContinueOnADashLinkKeepsTheAmount() async {
        let vm = makeVM()
        vm.setText("dash:\(core(network))?amount=1.5")
        await vm.continueTapped()
        XCTAssertEqual(handed.first?.0.type, .coreAddress)
        XCTAssertEqual(handed.first?.0.amountDuffs, 150_000_000)
    }

    func testContinueOnAPaymentRequestLinkHandsTheRequestOn() async {
        let vm = makeVM()
        vm.setText("dash:?r=https://merchant.example/pay/1")
        await vm.continueTapped()
        XCTAssertEqual(handed.first?.0.type, .paymentRequest)
        XCTAssertEqual(handed.first?.0.paymentRequestURL, URL(string: "https://merchant.example/pay/1"))
        XCTAssertTrue(lookup.lookedUp.isEmpty)
    }

    // MARK: - Identity ID (AC-13, AC-13b)

    func testIdentityIDGoesThroughCheckingThenHandsOnTheRecipient() async {
        let id = identityID()
        let recipient = IdentityRecipient(id: id, username: "alice", isOwnCurrentIdentity: false)
        lookup.suspends = true
        let vm = makeVM()
        vm.setText(id)
        let task = Task { await vm.continueTapped() }
        await waitUntilLookupSuspended()
        XCTAssertEqual(vm.state, .checking)
        XCTAssertFalse(vm.canContinue, "Continue is a loading button while checking")
        XCTAssertTrue(vm.isFieldReadOnly)
        lookup.resume(.found(recipient))
        await task.value
        XCTAssertEqual(lookup.lookedUp.first?.id, id)
        XCTAssertEqual(lookup.lookedUp.first?.network, network)
        XCTAssertEqual(handed.count, 1)
        XCTAssertEqual(handed.first?.0.type, .identityID)
        XCTAssertEqual(handed.first?.1, recipient)
    }

    func testFoundIdentityWithoutUsernameStillContinues() async {
        let id = identityID()
        let recipient = IdentityRecipient(id: id, username: nil, isOwnCurrentIdentity: false)
        lookup.results = [.found(recipient)]
        let vm = makeVM()
        vm.setText(id)
        await vm.continueTapped()
        XCTAssertEqual(handed.first?.1, recipient)
        XCTAssertNil(handed.first?.1?.username)
    }

    func testOwnCurrentIdentityIsHandedOnFlagged() async {
        let id = identityID()
        let recipient = IdentityRecipient(id: id, username: "me", isOwnCurrentIdentity: true)
        lookup.results = [.found(recipient)]
        let vm = makeVM()
        vm.setText(id)
        await vm.continueTapped()
        XCTAssertEqual(handed.first?.1?.isOwnCurrentIdentity, true)
    }

    func testIdentityNotFoundBlocksContinueUntilEdited() async {
        lookup.results = [.notFound]
        let vm = makeVM()
        vm.setText(identityID())
        await vm.continueTapped()
        XCTAssertEqual(vm.state, .notFound)
        XCTAssertFalse(vm.canContinue)
        XCTAssertFalse(vm.isFieldReadOnly)
        XCTAssertTrue(handed.isEmpty)
        vm.setText(core(network))
        XCTAssertEqual(vm.state, .entered)
        XCTAssertTrue(vm.canContinue)
    }

    func testCouldNotCheckIsNotNotFoundAndRetryRunsTheLookupAgain() async {
        let id = identityID()
        let recipient = IdentityRecipient(id: id, username: nil, isOwnCurrentIdentity: false)
        lookup.results = [.couldNotCheck, .found(recipient)]
        let vm = makeVM()
        vm.setText(id)
        await vm.continueTapped()
        XCTAssertEqual(vm.state, .checkFailed)
        XCTAssertFalse(vm.canContinue)
        XCTAssertTrue(handed.isEmpty)
        await vm.retry()
        XCTAssertEqual(lookup.lookedUp.count, 2)
        XCTAssertEqual(lookup.lookedUp.last?.id, id)
        XCTAssertEqual(handed.first?.1, recipient)
    }

    func testRetryThatFailsAgainStaysCheckFailed() async {
        lookup.results = [.couldNotCheck, .couldNotCheck]
        let vm = makeVM()
        vm.setText(identityID())
        await vm.continueTapped()
        await vm.retry()
        XCTAssertEqual(vm.state, .checkFailed)
        XCTAssertTrue(handed.isEmpty)
    }

    // MARK: - scan

    func testScannedAddressIsHandedOn() async {
        let address = core(network)
        let vm = makeVM()
        let accepted = await vm.handleScanned(address)
        XCTAssertTrue(accepted)
        XCTAssertEqual(handed.first?.0.text, address)
    }

    func testBadScanIsRejectedAndNothingIsFilledOrHandedOn() async {
        let vm = makeVM()
        let accepted = await vm.handleScanned("garbage")
        XCTAssertFalse(accepted, "the scanner stays open to scan again")
        XCTAssertTrue(handed.isEmpty)
        XCTAssertEqual(vm.text, "")
        XCTAssertEqual(vm.state, .initial)
    }

    func testScanOfAnotherNetworkAddressIsRejected() async {
        let vm = makeVM(network: .testnet)
        let accepted = await vm.handleScanned(core(.mainnet))
        XCTAssertFalse(accepted)
        XCTAssertTrue(handed.isEmpty)
    }

    func testScannedIdentityIDFillsTheFieldAndGoesThroughChecking() async {
        let id = identityID()
        lookup.suspends = true
        let vm = makeVM()
        let task = Task { await vm.handleScanned(id) }
        await waitUntilLookupSuspended()
        XCTAssertEqual(vm.text, id)
        XCTAssertEqual(vm.state, .checking)
        lookup.resume(.notFound)
        let accepted = await task.value
        XCTAssertTrue(accepted, "an Identity ID stays on this screen, not on the scanner")
        XCTAssertEqual(vm.state, .notFound)
        XCTAssertTrue(handed.isEmpty)
    }

    func testScannedIdentityIDThatCannotBeCheckedOffersRetry() async {
        lookup.results = [.couldNotCheck]
        let vm = makeVM()
        _ = await vm.handleScanned(identityID())
        XCTAssertEqual(vm.state, .checkFailed)
    }

    // MARK: - Identity links (dashpay/dashwallet-ios#1383)

    func testAnIdentityLinkTypedInTheFieldIsCheckedAndKeepsItsAmount() async {
        let id = identityID()
        let recipient = IdentityRecipient(id: id, username: "alice", isOwnCurrentIdentity: false)
        lookup.results = [.found(recipient)]
        let vm = makeVM()
        vm.setText("dash:\(id)?amount=0.1")
        await vm.continueTapped()
        XCTAssertEqual(lookup.lookedUp.map(\.id), [id])
        XCTAssertEqual(handed.first?.0.type, .identityID)
        XCTAssertEqual(handed.first?.0.amountDuffs, 10_000_000)
        XCTAssertEqual(handed.first?.1, recipient)
    }

    func testAClipboardIdentityLinkIsCheckedBeforeItIsHandedOnAndKeepsItsAmount() async {
        let id = identityID()
        let recipient = IdentityRecipient(id: id, username: "alice", isOwnCurrentIdentity: false)
        lookup.results = [.found(recipient)]
        pasteboard.content = "dash:\(id)?amount=0.1"
        let vm = makeVM()
        vm.showClipboard()
        vm.fillFromClipboard()
        XCTAssertTrue(handed.isEmpty, "an Identity is never handed on before it is checked")
        XCTAssertEqual(vm.text, id)
        await vm.continueTapped()
        XCTAssertEqual(lookup.lookedUp.map(\.id), [id])
        XCTAssertEqual(handed.first?.0.amountDuffs, 10_000_000)
        XCTAssertEqual(handed.first?.1, recipient)
    }

    func testAScannedIdentityLinkKeepsItsAmountThroughARetry() async {
        let id = identityID()
        let recipient = IdentityRecipient(id: id, username: "alice", isOwnCurrentIdentity: false)
        lookup.results = [.couldNotCheck, .found(recipient)]
        let vm = makeVM()
        let accepted = await vm.handleScanned("dash:\(id)?amount=0.1")
        XCTAssertTrue(accepted)
        XCTAssertEqual(vm.text, id)
        XCTAssertEqual(vm.state, .checkFailed)
        await vm.retry()
        XCTAssertEqual(handed.first?.0.amountDuffs, 10_000_000)
        XCTAssertEqual(handed.first?.1, recipient)
    }

    func testEditingTheFieldAfterAnIdentityLinkDropsTheLinksAmount() async {
        let id = identityID()
        let recipient = IdentityRecipient(id: id, username: "alice", isOwnCurrentIdentity: false)
        lookup.results = [.found(recipient)]
        pasteboard.content = "dash:\(id)?amount=0.1"
        let vm = makeVM()
        vm.showClipboard()
        vm.fillFromClipboard()
        vm.setText(id)
        await vm.continueTapped()
        XCTAssertNil(handed.first?.0.amountDuffs, "the field is what the user typed now")
    }
}
