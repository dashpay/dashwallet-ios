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

/// The Confirm sheet's ViewModel (SCR-06, SCR-08; AC-01, AC-01b, AC-09, AC-12, AC-12b, AC-16, AC-17, AC-18):
/// only the edges are faked (the executor at `ExternalSendExecuting` and the balances); the pair policy, the amount
/// rules and the ViewModel are the real ones.
@MainActor
final class ConfirmViewModelTests: XCTestCase {
    private typealias State = ConfirmViewModel.State

    // MARK: - Fixtures

    private let oneDash: UInt64 = 100_000_000
    private let fee: UInt64 = 1_000
    private let coreBalance: UInt64 = 500_000_000
    private let platformBalance: UInt64 = 200_000_000
    private let shieldedBalance: UInt64 = 300_000_000
    private let ownID = "OwnIdentityIDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    private let coreDestination = Destination(type: .coreAddress, text: "XyCoreAddressAbcdefghijklmnopqrstuv")
    private let shieldedDestination = Destination(type: .shieldedAddress, text: "dash1shieldedaddressabcdefghijklmn")
    private var executor = FakeExecutor()
    private var backToSend: [ConfirmViewModel.BackToSend] = []
    private var outcomes: [SendOutcome] = []

    override func setUp() {
        super.setUp()
        executor = FakeExecutor()
        backToSend = []
        outcomes = []
    }

    private func makeVM(
        route: SendRoute, destination: Destination? = nil, amount: UInt64? = nil, isMax: Bool = false,
        sweepCredits: UInt64? = nil, recipient: IdentityRecipient? = nil, identityCredits: UInt64 = 5_000_000_000,
        converter: SendAmountConverting = FakeConverter(rate: 25), balances: ExternalSendBalanceReading? = nil
    ) -> ConfirmViewModel {
        let target = destination ?? defaultDestination(for: route)
        let balances = balances ?? FakeBalances(values: [
            .core: coreBalance, .shielded: shieldedBalance, .platform: platformBalance, .identity: identityCredits])
        let request = SendAmountRequest(route: route, destination: target, amount: amount ?? oneDash, isMax: isMax,
                                        sweepCredits: sweepCredits)
        let vm = ConfirmViewModel(
            request: request, recipient: recipient, executor: executor, balances: balances, converter: converter)
        vm.onBackToSend = { [unowned self] reason in backToSend.append(reason) }
        vm.onOutcome = { [unowned self] outcome in outcomes.append(outcome) }
        return vm
    }

    private func defaultDestination(for route: SendRoute) -> Destination {
        switch route {
        case .coreToShielded, .shieldedToShielded, .platformToShielded:
            return shieldedDestination
        case .coreToIdentity, .shieldedToIdentity, .platformToIdentity, .identityToIdentity:
            return Destination(type: .identityID, text: "7Zp3MqIdentityIDxxxxxxxxxxxxxxxxxxxxxxoVyBn")
        case .shieldedToPlatform, .platformToPlatform, .identityToPlatform:
            return Destination(type: .platformAddress, text: "dash1platformaddressabcdefghijklmnop")
        default:
            return coreDestination
        }
    }

    private func readyVM(
        route: SendRoute, destination: Destination? = nil, amount: UInt64? = nil, isMax: Bool = false,
        recipient: IdentityRecipient? = nil, identityCredits: UInt64 = 5_000_000_000, feeToUse: UInt64? = nil
    ) async -> ConfirmViewModel {
        executor.prepareResults = [.success(feeToUse ?? fee)]
        let vm = makeVM(route: route, destination: destination, amount: amount, isMax: isMax, recipient: recipient,
                        identityCredits: identityCredits)
        await vm.start()
        XCTAssertEqual(vm.state, .ready)
        return vm
    }

    // MARK: - Preparing (AC-01)

    func testStartAuthenticatesAndPreparesTheExactSendWhileShowingPreparing() async {
        executor.prepareResults = [.success(fee)]
        let vm = makeVM(route: .coreToCore, amount: 2 * oneDash, isMax: true)
        XCTAssertEqual(vm.state, .preparing)
        XCTAssertNil(vm.feeText)
        XCTAssertNil(vm.totalText)
        XCTAssertFalse(vm.isConfirmEnabled)
        XCTAssertEqual(executor.sentCalls, 0)
        await vm.start()
        XCTAssertEqual(executor.prepareCalls.count, 1)
        XCTAssertEqual(executor.prepareCalls.first?.route, .coreToCore)
        XCTAssertEqual(executor.prepareCalls.first?.destination, coreDestination)
        XCTAssertEqual(executor.prepareCalls.first?.amount, 2 * oneDash)
        XCTAssertEqual(executor.prepareCalls.first?.isMax, true)
        XCTAssertEqual(executor.sentCalls, 0, "nothing is broadcast before the Confirm tap")
    }

    func testAShieldedMaxPreparesWithThePlansExactCredits() async {
        executor.prepareResults = [.success(fee)]
        let vm = makeVM(route: .shieldedToPlatform, amount: 123_456, isMax: true, sweepCredits: 123_456_789)
        await vm.start()
        XCTAssertEqual(executor.prepareCalls.first?.amount, 123_456)
        XCTAssertEqual(executor.prepareCalls.first?.sweepCredits, 123_456_789)
    }

    // MARK: - Units and fiat

    func testIdentityPrepareGetsCreditsAndOtherSourcesGetDuffs() async {
        _ = await readyVM(route: .identityToCore, amount: 2 * oneDash)
        XCTAssertEqual(executor.prepareCalls.last?.amount, 2 * oneDash * 1000)
        for route in [SendRoute.coreToCore, .shieldedToCore, .platformToCore] {
            _ = await readyVM(route: route, amount: 2 * oneDash)
            XCTAssertEqual(executor.prepareCalls.last?.amount, 2 * oneDash, "\(route)")
        }
    }

    func testAmountShowsItsLocalValueWhenThereIsARate() async {
        let vm = await readyVM(route: .coreToCore, amount: 2 * oneDash)
        XCTAssertEqual(vm.amountFiatText, "$50")
    }

    func testAmountFiatIsNilWithoutARate() async {
        executor.prepareResults = [.success(fee)]
        let vm = makeVM(route: .coreToCore, converter: FakeConverter(rate: nil))
        await vm.start()
        XCTAssertNil(vm.amountFiatText)
    }

    // MARK: - Ready: amount, binding fee, total, From, To (AC-01)

    func testReadyShowsAmountBindingFeeTotalFromAndTo() async {
        let vm = await readyVM(route: .coreToCore, amount: 2 * oneDash)
        XCTAssertEqual(vm.amountText, (2 * oneDash).formattedDashAmount)
        XCTAssertEqual(vm.feeText, fee.formattedDashAmount)
        XCTAssertEqual(vm.totalText, (2 * oneDash + fee).formattedDashAmount)
        XCTAssertEqual(vm.fromText, "Core")
        XCTAssertTrue(vm.toText.hasPrefix(String(coreDestination.text.prefix(6))), vm.toText)
        XCTAssertTrue(vm.toText.contains("…"), vm.toText)
        XCTAssertTrue(vm.isConfirmEnabled)
        XCTAssertTrue(backToSend.isEmpty)
    }

    func testIdentityFeeInCreditsIsShownAndTotalledInDash() async {
        let feeCredits: UInt64 = 2_000_000
        let vm = await readyVM(route: .identityToCore, feeToUse: feeCredits)
        let feeDuffs = AmountRules.dashValue(of: feeCredits)
        XCTAssertEqual(vm.fromText, "Identity")
        XCTAssertEqual(vm.feeText, "~ " + feeDuffs.formattedDashAmount)
        XCTAssertEqual(vm.totalText, "~ " + (oneDash + feeDuffs).formattedDashAmount)
    }

    // MARK: - Exact or estimated fee (ADR-0043)

    private let estimateRoutes: [SendRoute] = [
        .coreToShielded, .coreToIdentity,
        .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity,
        .platformToCore, .platformToShielded, .platformToPlatform, .platformToIdentity,
        .identityToCore, .identityToPlatform, .identityToIdentity
    ]

    func testCoreToCoreFeeIsExactWithoutTildeOrNote() async {
        let vm = await readyVM(route: .coreToCore, amount: 2 * oneDash)
        XCTAssertTrue(vm.isFeeExact)
        XCTAssertEqual(vm.feeText, fee.formattedDashAmount)
        XCTAssertEqual(vm.totalText, (2 * oneDash + fee).formattedDashAmount)
        XCTAssertEqual(vm.feeAccessibilityValue, fee.formattedDashAmount)
    }

    func testPaymentRequestFeeIsExact() async {
        let request = Destination(type: .paymentRequest, text: "",
                                  paymentRequestURL: URL(string: "https://merchant.example/r/1"))
        let vm = await readyVM(route: .coreToCore, destination: request)
        XCTAssertTrue(vm.isFeeExact)
        XCTAssertFalse(vm.feeText?.hasPrefix("~") ?? true, vm.feeText ?? "nil")
        XCTAssertFalse(vm.totalText?.hasPrefix("~") ?? true, vm.totalText ?? "nil")
    }

    func testEveryOtherRouteShowsTheFeeAndTotalAsAnEstimate() async {
        for route in estimateRoutes {
            let vm = await readyVM(route: route, amount: oneDash)
            let feeDuffs = route.source == .identity ? AmountRules.dashValue(of: fee) : fee
            XCTAssertFalse(vm.isFeeExact, "\(route)")
            XCTAssertEqual(vm.feeText, "~ " + feeDuffs.formattedDashAmount, "\(route)")
            XCTAssertEqual(vm.totalText, "~ " + (oneDash + feeDuffs).formattedDashAmount, "\(route)")
            XCTAssertEqual(vm.feeAccessibilityValue, "about " + feeDuffs.formattedDashAmount, "\(route)")
            XCTAssertEqual(vm.totalAccessibilityValue, "about " + (oneDash + feeDuffs).formattedDashAmount,
                           "\(route)")
        }
    }

    func testAnEstimateRouteShowsNoTildeOrNoteWhilePreparing() {
        let vm = makeVM(route: .platformToCore)
        XCTAssertNil(vm.feeText)
    }

    /// Closed while the warnings read the identity balance: the prepared send is released and Confirm never turns ready.
    func testClosingWhileTheWarningsAreReadNeverTurnsReady() async {
        executor.prepareResults = [.success(fee)]
        let balances = HeldIdentityBalance()
        let vm = makeVM(route: .identityToCore, balances: balances)
        let starting = Task { await vm.start() }
        for _ in 0 ..< 200 where !balances.isHolding {
            await Task.yield()
        }
        XCTAssertTrue(balances.isHolding, "the warnings never read the identity balance")

        vm.cancel()
        balances.release()
        await starting.value

        XCTAssertEqual(vm.state, .preparing)
        XCTAssertFalse(vm.isConfirmEnabled)
        XCTAssertEqual(executor.discarded, 1)
    }

    // MARK: - Auth cancelled / failed, balance not enough

    func testAuthenticationCancelledGoesBackToSendWithNothingPrepared() async {
        executor.prepareResults = [.failure(.authenticationCancelled)]
        let vm = makeVM(route: .coreToCore)
        await vm.start()
        XCTAssertEqual(backToSend, [.authenticationNotCompleted])
        XCTAssertFalse(vm.isConfirmEnabled)
        vm.cancel()
        XCTAssertEqual(executor.discarded, 0, "nothing was prepared")
        XCTAssertEqual(executor.sentCalls, 0)
    }

    func testAuthenticationFailedGoesBackToSendWithNothingPrepared() async {
        executor.prepareResults = [.failure(.authenticationFailed)]
        let vm = makeVM(route: .platformToCore)
        await vm.start()
        XCTAssertEqual(backToSend, [.authenticationNotCompleted])
        XCTAssertFalse(vm.isConfirmEnabled)
    }

    func testBalanceNotEnoughGoesBackToSend() async {
        executor.prepareResults = [.failure(.balanceNotEnough)]
        let vm = makeVM(route: .coreToCore)
        await vm.start()
        XCTAssertEqual(backToSend, [.balanceNotEnough])
        XCTAssertFalse(vm.isConfirmEnabled)
        XCTAssertEqual(executor.sentCalls, 0)
    }

    // MARK: - Fee failed (AC-01b)

    func testAFeeOrBalanceFailureGoesBackToSendForEverySourceWithNothingPrepared() async {
        for route in [SendRoute.coreToCore, .shieldedToCore, .platformToCore, .identityToCore] {
            for failure in [ExternalSendError.feeUnavailable, .balanceUnavailable] {
                backToSend = []
                executor.prepareResults = [.failure(failure)]
                let vm = makeVM(route: route)
                await vm.start()
                XCTAssertEqual(backToSend, [.feeFailed], "\(route) \(failure)")
                XCTAssertNil(vm.feeText, "\(route) \(failure)")
                XCTAssertFalse(vm.isConfirmEnabled, "\(route) \(failure)")
                await vm.confirm()
            }
        }
        XCTAssertEqual(executor.sentCalls, 0, "nothing is sent")
        XCTAssertEqual(executor.discarded, 0, "nothing was prepared")
    }

    // MARK: - Warnings (AC-16, AC-17, AC-18, AC-09, AC-12, AC-12b)

    func testNoRouteToCoreShowsTheWithdrawalDelaySentence() async {
        for route in [SendRoute.shieldedToCore, .platformToCore, .identityToCore, .coreToCore] {
            let vm = await readyVM(route: route)
            XCTAssertFalse(vm.warnings.contains { $0.contains("This is a withdrawal") }, "\(route): \(vm.warnings)")
        }
        let shielded = await readyVM(route: .shieldedToCore)
        XCTAssertFalse(shielded.warnings.contains { $0.contains("Processing time") }, "\(shielded.warnings)")
    }

    /// Owner review O7: From "Shielded balance"; exactly the "not instant" info notice, then the public notice in
    /// its Core wording, no Processing time.
    func testShieldedToCoreShowsFromShieldedBalanceAndExactlyTheTwoNotices() async {
        let vm = await readyVM(route: .shieldedToCore)
        XCTAssertEqual(vm.fromText, "Shielded balance")
        XCTAssertEqual(vm.warningItems.map(\.style), [.info, .publicExposure])
        XCTAssertEqual(vm.warnings, [
            "When sending from Shielded balance, the transaction is not instant and takes some time",
            "When sending from Shielded balance to Core the amount and destination becomes public"
        ])
        XCTAssertEqual(vm.warningItems.map(\.subtitle), [nil, nil])
    }

    func testEveryShieldedRouteShowsFromShieldedBalance() async {
        for route in [SendRoute.shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity] {
            let vm = await readyVM(route: route)
            XCTAssertEqual(vm.fromText, "Shielded balance", "\(route)")
        }
    }

    func testShieldedToNonShieldedWarnsThatAmountAndDestinationBecomePublic() async {
        let text = "Sending from Shielded to an address that is not Shielded makes the amount and the "
            + "destination public."
        for route in [SendRoute.shieldedToPlatform, .shieldedToIdentity] {
            let vm = await readyVM(route: route)
            XCTAssertTrue(vm.warnings.contains(text), "\(route): \(vm.warnings)")
        }
        let toShielded = await readyVM(route: .shieldedToShielded)
        XCTAssertFalse(toShielded.warnings.contains(text))
    }

    func testExistingSendWarningsStayInTheirOldWording() async {
        let core = await readyVM(route: .coreToCore)
        XCTAssertTrue(core.warnings.contains { $0.contains("Double-check the address") }, "\(core.warnings)")

        // Max fills the balance less the fee, and the executor drains the wallet.
        let drain = await readyVM(route: .coreToShielded, amount: coreBalance - fee, isMax: true)
        XCTAssertTrue(drain.warnings.contains { $0.contains("Sends all eligible Transparent funds") },
                      "\(drain.warnings)")
        let notMax = await readyVM(route: .coreToShielded, amount: coreBalance)
        XCTAssertFalse(notMax.warnings.contains { $0.contains("Sends all eligible Transparent funds") },
                       "\(notMax.warnings)")

        let platform = await readyVM(route: .platformToCore)
        XCTAssertTrue(platform.warnings.contains { $0.contains("Processing time") }, "\(platform.warnings)")
    }

    func testEveryWarningThatAppliesIsStacked() async {
        let amount = platformBalance - fee
        let expected = SendPairPolicy.warnings(source: .platform, destination: coreDestination, isMax: true)
        XCTAssertTrue(expected.contains(.fullPlatformWithdrawal))
        XCTAssertGreaterThan(expected.count, 1)
        let vm = await readyVM(route: .platformToCore, amount: amount, isMax: true)
        XCTAssertEqual(vm.warnings.count, expected.count, "\(vm.warnings)")
        XCTAssertEqual(Set(vm.warnings).count, vm.warnings.count, "no warning is repeated")
    }

    func testIdentityAmountLeavingLessThanTheReserveWarnsDashPayMayStop() async {
        let reserveText = "This leaves less than the DashPay reserve."
        let feeCredits: UInt64 = 1_000_000
        let amount: UInt64 = 1_000_000
        let below = amount * 1000 + feeCredits + IdentityCreditBalance.lowBalance / 2
        let low = await readyVM(route: .identityToCore, amount: amount, identityCredits: below, feeToUse: feeCredits)
        XCTAssertTrue(low.warnings.contains { $0.hasPrefix(reserveText) }, "\(low.warnings)")

        let above = amount * 1000 + feeCredits + IdentityCreditBalance.lowBalance * 2
        let fine = await readyVM(route: .identityToCore, amount: amount, identityCredits: above, feeToUse: feeCredits)
        XCTAssertFalse(fine.warnings.contains { $0.hasPrefix(reserveText) }, "\(fine.warnings)")
    }

    /// O63: an Identity Max that Confirm's own balance read shows dipping into the reserve is not offered: it is
    /// discarded and Send plans Max again. A typed amount in the same state is only warned.
    func testAnIdentityMaxThatTheConfirmReadShowsDippingIntoTheReserveReturnsToSend() async {
        let feeCredits: UInt64 = 1_000_000
        let amount: UInt64 = 1_000_000
        let below = amount * 1000 + feeCredits + IdentityCreditBalance.lowBalance / 2
        executor.prepareResults = [.success(feeCredits)]
        let max = makeVM(route: .identityToCore, amount: amount, isMax: true, identityCredits: below)
        await max.start()
        XCTAssertNotEqual(max.state, .ready)
        XCTAssertFalse(max.isConfirmEnabled)
        XCTAssertEqual(backToSend, [.balanceNotEnough])
        XCTAssertEqual(executor.discarded, 1)
        XCTAssertEqual(executor.sentCalls, 0)

        let typed = await readyVM(route: .identityToCore, amount: amount, identityCredits: below, feeToUse: feeCredits)
        XCTAssertTrue(typed.isConfirmEnabled)
    }

    /// An Identity Max whose balance Confirm cannot read is not offered either (dispatch would refuse it): Send shows
    /// that the fee could not be calculated.
    func testAnIdentityMaxWhoseBalanceConfirmCannotReadReturnsToSend() async {
        executor.prepareResults = [.success(fee)]
        let vm = makeVM(route: .identityToCore, isMax: true, balances: FakeBalances(values: [:]))
        await vm.start()
        XCTAssertFalse(vm.isConfirmEnabled)
        XCTAssertEqual(backToSend, [.feeFailed])
        XCTAssertEqual(executor.discarded, 1)
    }

    func testSomeoneElsesIdentityShowsTheUsernameAndNoBalanceStatement() async {
        let recipient = IdentityRecipient(id: "7Zp3MqIdentityIDxxxxxxxxxxxxxxxxxxxxxxoVyBn", username: "bob",
                                          isOwnCurrentIdentity: false)
        let vm = await readyVM(route: .platformToIdentity, recipient: recipient)
        XCTAssertTrue(vm.toText.hasPrefix("bob"), vm.toText)
        XCTAssertFalse(vm.warnings.contains { $0.contains("identity balance") }, "\(vm.warnings)")
    }

    func testSomeoneElsesIdentityWithoutAUsernameShowsNoBalanceStatement() async {
        let recipient = IdentityRecipient(id: "7Zp3MqIdentityIDxxxxxxxxxxxxxxxxxxxxxxoVyBn", username: nil,
                                          isOwnCurrentIdentity: false)
        let vm = await readyVM(route: .shieldedToIdentity, recipient: recipient)
        XCTAssertFalse(vm.warnings.contains { $0.contains("identity's balance") }, "\(vm.warnings)")
    }

    func testOwnIdentityIsYourIdentityAndStatesTheTopUp() async {
        let recipient = IdentityRecipient(id: ownID, username: "me", isOwnCurrentIdentity: true)
        for route in [SendRoute.coreToIdentity, .shieldedToIdentity, .platformToIdentity] {
            let vm = await readyVM(route: route, recipient: recipient)
            XCTAssertTrue(vm.toText.hasPrefix("Your identity"), "\(route): \(vm.toText)")
            XCTAssertTrue(vm.warnings.contains("This tops up your own Identity credits."), "\(vm.warnings)")
        }
    }

    // MARK: - A link's label and message, a payment request's merchant and memo (AC-15)

    func testALabelledLinkShowsItsLabelInToAndItsMessageAsAnInfoLine() async {
        let labelled = Destination(type: .coreAddress, text: coreDestination.text, label: "Coffee Shop",
                                   message: "Table 4")
        let vm = await readyVM(route: .coreToCore, destination: labelled)
        XCTAssertTrue(vm.toText.hasPrefix("Coffee Shop · "), vm.toText)
        XCTAssertTrue(vm.toText.contains("…"), vm.toText)
        XCTAssertTrue(vm.warnings.contains("Table 4"), "\(vm.warnings)")
    }

    /// An unsigned link never names an identity: without a username the To row shows the Identity ID alone, on
    /// every route that pays one, and the link's message says where it came from.
    func testAnIdentityLinksLabelNeverNamesTheRecipientAndItsMessageIsMarkedAsTheLinks() async {
        let id = "7Zp3MqIdentityIDxxxxxxxxxxxxxxxxxxxxxxoVyBn"
        let link = Destination(type: .identityID, text: id, label: "Your identity", message: "Top up mine")
        let recipient = IdentityRecipient(id: id, username: nil, isOwnCurrentIdentity: false)
        for route in [SendRoute.platformToIdentity, .shieldedToIdentity, .identityToIdentity, .coreToIdentity] {
            let vm = await readyVM(route: route, destination: link, recipient: recipient)
            XCTAssertFalse(vm.toText.contains("Your identity"), "\(route): \(vm.toText)")
            XCTAssertTrue(vm.toText.hasPrefix("7Zp3Mq"), "\(route): \(vm.toText)")
            XCTAssertTrue(vm.warnings.contains("Message in the link: Top up mine"), "\(route): \(vm.warnings)")
            XCTAssertFalse(vm.warnings.contains("Top up mine"), "\(route): \(vm.warnings)")
        }
    }

    func testAVerifiedPaymentRequestShowsTheMerchantWithTheLock() async {
        let request = Destination(type: .coreAddress, text: coreDestination.text, label: "Merchant",
                                  message: "Order 7", paymentRequestURL: URL(string: "https://merchant.example/r/1"),
                                  isVerifiedMerchant: true)
        let vm = await readyVM(route: .coreToCore, destination: request)
        XCTAssertTrue(vm.toText.hasPrefix("🔒 Merchant · "), vm.toText)
        XCTAssertTrue(vm.warnings.contains("Order 7"), "\(vm.warnings)")
    }

    /// Confirm shows an unsigned request as the old confirm screen does (`BIP70InteractivePolicy`): its name and note
    /// labelled unverified, the note on one line and capped, and every address it pays with the amount it receives.
    func testAnUnsignedPaymentRequestIsLabelledUnverifiedAndListsEveryAddress() async {
        let other = "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW"
        let longNote = "Line one\nline two " + String(repeating: "x", count: 200)
        let details = PaymentDetails(network: "test", outputs: [], memo: longNote)
        let box = BIP70ConfirmationBox(Confirmation(
            merchantName: "Shop", isSecure: false,
            recipients: [(address: coreDestination.text, amount: 60_000), (address: other, amount: 40_000)],
            amount: 100_000, estimatedFee: 226, network: .testnet, paymentURL: nil, scheme: "dash",
            merchantData: nil, memo: longNote, callbackScheme: nil,
            request: PaymentRequest(serializedDetails: details.encoded())))
        let request = Destination(type: .coreAddress, text: coreDestination.text, amountDuffs: 100_000, label: "Shop",
                                  message: longNote, paymentRequestURL: URL(string: "https://merchant.example/r/1"),
                                  verifiedRequest: box)
        let vm = await readyVM(route: .coreToCore, destination: request, amount: 100_000)

        XCTAssertTrue(vm.toText.hasPrefix("Unverified recipient: Shop · "), vm.toText)
        let note = vm.warnings.first { $0.hasPrefix("Unverified note: ") }
        XCTAssertEqual(note?.contains("\n"), false, "\(vm.warnings)")
        XCTAssertEqual(note?.hasSuffix("…"), true, "\(vm.warnings)")
        XCTAssertEqual(note.map { ($0 as NSString).length },
                       ("Unverified note: " as NSString).length + BIP70InteractivePolicy.unverifiedNoteMaxLength)
        let recipients = vm.warnings.first { $0.hasPrefix("This payment goes to 2 addresses.") }
        XCTAssertEqual(recipients?.contains(coreDestination.text), true, "\(vm.warnings)")
        XCTAssertEqual(recipients?.contains(other), true, "\(vm.warnings)")
    }

    // MARK: - The full recipient (AC-01, AC-12)

    func testTappingToShowsTheWholeAddressAndTappingAgainShortensIt() async {
        let vm = await readyVM(route: .coreToCore)
        let short = vm.toText
        XCTAssertFalse(vm.isRecipientExpanded)
        XCTAssertTrue(short.contains("…"), short)

        vm.toggleRecipient()

        XCTAssertTrue(vm.isRecipientExpanded)
        XCTAssertEqual(vm.toText, coreDestination.text)

        vm.toggleRecipient()

        XCTAssertEqual(vm.toText, short)
    }

    func testVoiceOverReadsTheWholeRecipientEitherWay() async {
        let vm = await readyVM(route: .coreToCore)
        XCTAssertEqual(vm.toAccessibilityValue, coreDestination.text)
        vm.toggleRecipient()
        XCTAssertEqual(vm.toAccessibilityValue, coreDestination.text)
    }

    func testAnIdentityRecipientExpandsToTheUsernameAndTheWholeIdentityID() async {
        let id = "7Zp3MqIdentityIDxxxxxxxxxxxxxxxxxxxxxxoVyBn"
        let recipient = IdentityRecipient(id: id, username: "bob", isOwnCurrentIdentity: false)
        let vm = await readyVM(route: .platformToIdentity, recipient: recipient)

        vm.toggleRecipient()

        XCTAssertEqual(vm.toText, "bob · " + id)
        XCTAssertEqual(vm.toAccessibilityValue, "bob · " + id)
    }

    func testAPaymentRequestExpandsToTheMerchantTheWholeAddressAndTheRequestURL() async {
        let url = "https://merchant.example/r/1"
        let request = Destination(type: .coreAddress, text: coreDestination.text, label: "Merchant",
                                  paymentRequestURL: URL(string: url), isVerifiedMerchant: true)
        let vm = await readyVM(route: .coreToCore, destination: request)
        XCTAssertFalse(vm.toText.contains(url), vm.toText)

        vm.toggleRecipient()

        XCTAssertEqual(vm.toText, "🔒 Merchant · " + coreDestination.text + "\n" + url)
    }

    func testAnAddressWithoutALabelShowsOnlyTheShortAddress() async {
        let vm = await readyVM(route: .coreToCore)
        XCTAssertFalse(vm.toText.contains(" · "), vm.toText)
    }

    // MARK: - Who pays the Platform fee on a Core asset lock

    /// The identity receives at least the typed amount: the top-up's Platform fee is in the fee row on top of it,
    /// and no note says the identity receives less.
    func testCoreToIdentityShowsTheTypedAmountAndThePlatformFeeInTheFeeRow() async {
        let minerFee: UInt64 = 2_250
        let fee = ExternalSendFeeEstimator.coreTopUpPlatformFeeDuffs + minerFee
        let vm = await readyVM(route: .coreToIdentity, amount: oneDash, feeToUse: fee)
        XCTAssertEqual(vm.amountText, oneDash.formattedDashAmount)
        XCTAssertEqual(vm.feeText, "~ " + fee.formattedDashAmount)
        XCTAssertEqual(vm.totalText, "~ " + (oneDash + fee).formattedDashAmount, "the total is what leaves the wallet")
    }

    func testNoRouteSaysThePlatformFeeComesOutOfTheAmount() async {
        let routes: [SendRoute] = [
            .coreToIdentity, .coreToCore, .coreToShielded, .platformToIdentity, .shieldedToPlatform
        ]
        for route in routes {
            let vm = await readyVM(route: route)
            let mentionsPlatformFee = vm.warnings.contains {
                $0.hasPrefix("The Platform fee is taken")
            }
            XCTAssertFalse(mentionsPlatformFee, "\(route): \(vm.warnings)")
        }
    }

    /// The lock carries Platform's minimum top-up fee and Platform charges less, so the identity gets the rest: Confirm
    /// says so for Core -> Identity, to the holder's own identity and to someone else's.
    func testCoreToIdentityStatesThatTheUnusedPlatformFeeGoesToTheIdentity() async {
        let note = "Any unused part of the Platform fee goes to the identity."
        let recipients = [
            IdentityRecipient(id: ownID, username: "me", isOwnCurrentIdentity: true),
            IdentityRecipient(id: "7Zp3MqIdentityIDxxxxxxxxxxxxxxxxxxxxxxoVyBn", username: "bob",
                              isOwnCurrentIdentity: false)
        ]
        for recipient in recipients {
            let vm = await readyVM(route: .coreToIdentity, recipient: recipient)
            XCTAssertEqual(vm.warningItems.filter { $0.title == note }.count, 1, "\(vm.warnings)")
            XCTAssertEqual(vm.warningItems.first { $0.title == note }?.style, .info)
        }
    }

    func testNoOtherRouteMentionsTheUnusedPlatformFee() async {
        let routes: [SendRoute] = [
            .coreToCore, .coreToShielded, .shieldedToCore, .shieldedToShielded, .shieldedToPlatform,
            .shieldedToIdentity, .platformToCore, .platformToShielded, .platformToPlatform, .platformToIdentity,
            .identityToCore, .identityToPlatform, .identityToIdentity
        ]
        for route in routes {
            let vm = await readyVM(route: route)
            XCTAssertFalse(vm.warnings.contains { $0.contains("unused part of the Platform fee") },
                           "\(route): \(vm.warnings)")
        }
    }

    // MARK: - Cancel (ADR-0039)

    func testCancelDiscardsThePreparedSendAndReturnsToSendWithNothingSent() async {
        let vm = await readyVM(route: .coreToCore)
        vm.cancel()
        XCTAssertEqual(executor.discarded, 1)
        XCTAssertEqual(backToSend, [.cancelled])
        XCTAssertEqual(executor.sentCalls, 0)
        XCTAssertTrue(outcomes.isEmpty)
    }

    // MARK: - Confirm and Sending (SCR-08)

    func testConfirmShowsSendingThenHandsTheOutcomeOnExactlyOnce() async {
        executor.sendOutcome = .sent
        let vm = await readyVM(route: .coreToCore)
        await vm.confirm()
        XCTAssertEqual(executor.sentCalls, 1)
        XCTAssertEqual(outcomes.count, 1)
        guard case .sent? = outcomes.first else { return XCTFail("expected .sent, got \(outcomes)") }
        XCTAssertEqual(executor.discarded, 0)
    }

    func testSendingLocksTheSheetHidesCancelAndDisablesConfirmUntilTheOutcome() async {
        executor.holdSend = true
        executor.sendOutcome = .inFlight
        let vm = await readyVM(route: .coreToCore)
        XCTAssertFalse(vm.isDismissLocked)
        XCTAssertTrue(vm.isCancelVisible)
        let sending = Task { await vm.confirm() }
        await waitUntil { self.executor.sentCalls == 1 }
        XCTAssertEqual(vm.state, .sending)
        XCTAssertTrue(vm.isDismissLocked)
        XCTAssertFalse(vm.isCancelVisible)
        XCTAssertFalse(vm.isConfirmEnabled)
        XCTAssertTrue(outcomes.isEmpty)
        vm.cancel()
        XCTAssertEqual(executor.discarded, 0, "Cancel does nothing while sending")
        XCTAssertTrue(backToSend.isEmpty)
        executor.releaseSend()
        await sending.value
        guard case .inFlight? = outcomes.first else { return XCTFail("expected .inFlight, got \(outcomes)") }
        XCTAssertEqual(outcomes.count, 1)
    }

    func testCloseWhileWaitingForTheNetworkHandsInFlightOnceAndDropsTheLateOutcome() async {
        executor.holdSend = true
        executor.reportsSlowNetwork = true
        executor.sendOutcome = .sent
        let vm = await readyVM(route: .coreToShielded)
        let sending = Task { await vm.confirm() }
        await waitUntil { vm.isWaitingForNetwork }
        XCTAssertEqual(vm.state, .sending)
        XCTAssertTrue(outcomes.isEmpty)

        vm.closeWhileWaitingForNetwork()
        vm.closeWhileWaitingForNetwork()
        guard case .inFlight? = outcomes.first else { return XCTFail("expected .inFlight, got \(outcomes)") }
        XCTAssertEqual(outcomes.count, 1)

        executor.releaseSend()
        await sending.value
        XCTAssertEqual(outcomes.count, 1, "the send's own result no longer reaches the flow")
    }

    func testCloseDoesNothingBeforeTheNetworkWaitIsReported() async {
        executor.holdSend = true
        executor.sendOutcome = .sent
        let vm = await readyVM(route: .coreToShielded)
        let sending = Task { await vm.confirm() }
        await waitUntil { self.executor.sentCalls == 1 }
        XCTAssertFalse(vm.isWaitingForNetwork)
        vm.closeWhileWaitingForNetwork()
        XCTAssertTrue(outcomes.isEmpty)
        executor.releaseSend()
        await sending.value
        guard case .sent? = outcomes.first else { return XCTFail("expected .sent, got \(outcomes)") }
    }

    /// A whole-balance send whose balance changed after Confirm sent nothing: Send plans Max again.
    func testABalanceChangedAtDispatchReturnsToSendInsteadOfAnOutcome() async {
        executor.sendOutcome = .notSent(.balanceChanged)
        let vm = await readyVM(route: .platformToCore)
        await vm.confirm()
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertEqual(backToSend, [.balanceNotEnough])
    }

    func testNotSentOutcomeIsHandedOnUnchanged() async {
        executor.sendOutcome = .notSent(.offline)
        let vm = await readyVM(route: .coreToCore)
        await vm.confirm()
        guard case .notSent(.offline)? = outcomes.first else { return XCTFail("got \(outcomes)") }
    }

    func testDoubleTapOnConfirmSendsOnce() async {
        executor.holdSend = true
        executor.sendOutcome = .sent
        let vm = await readyVM(route: .coreToCore)
        let first = Task { await vm.confirm() }
        await waitUntil { self.executor.sentCalls == 1 }
        await vm.confirm()
        executor.releaseSend()
        await first.value
        XCTAssertEqual(executor.sentCalls, 1)
        XCTAssertEqual(outcomes.count, 1)
    }

    func testConfirmBeforeReadySendsNothing() async {
        let vm = makeVM(route: .coreToCore)
        await vm.confirm()
        XCTAssertEqual(executor.sentCalls, 0)
        XCTAssertTrue(outcomes.isEmpty)
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "condition not reached")
    }
}

// MARK: - Fakes

/// The executor at its protocol: returns the queued prepare results, counts calls, and can hold `send`.
/// `PreparedExternalSend` is built through its initializer, which the production side exposes to the module.
@MainActor
private final class FakeExecutor: ExternalSendExecuting {
    struct PrepareCall: Equatable {
        let route: SendRoute
        let destination: Destination
        let amount: UInt64
        let isMax: Bool
        let sweepCredits: UInt64?
    }

    var prepareResults: [Result<UInt64, ExternalSendError>] = []
    var sendOutcome: SendOutcome = .sent
    var holdSend = false
    /// The send reports a late lock proof (as the executor does past its delay) before it holds.
    var reportsSlowNetwork = false
    private(set) var prepareCalls: [PrepareCall] = []
    private(set) var sentCalls = 0
    private(set) var discarded = 0
    private var gate: CheckedContinuation<Void, Never>?

    func prepare(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool, sweepCredits: UInt64?
    ) async throws -> PreparedExternalSend {
        prepareCalls.append(PrepareCall(
            route: route, destination: destination, amount: amount, isMax: isMax, sweepCredits: sweepCredits))
        guard !prepareResults.isEmpty else { throw ExternalSendError.feeUnavailable }
        switch prepareResults.removeFirst() {
        case .success(let fee):
            return PreparedExternalSend(
                route: route, amount: amount, fee: fee, isMax: isMax, plan: .routed(destination: destination))
        case .failure(let error):
            throw error
        }
    }

    func send(_ prepared: PreparedExternalSend) async -> SendOutcome {
        sentCalls += 1
        if reportsSlowNetwork { prepared.onSlowNetwork?() }
        if holdSend { await withCheckedContinuation { gate = $0 } }
        return sendOutcome
    }

    func discard(_ prepared: PreparedExternalSend) {
        discarded += 1
    }

    func releaseSend() {
        gate?.resume()
        gate = nil
    }
}

/// The identity balance read suspends until `release`; every other source reads nothing.
@MainActor
private final class HeldIdentityBalance: ExternalSendBalanceReading {
    private var held: CheckedContinuation<Void, Never>?
    var isHolding: Bool { held != nil }

    func spendableBalance(of source: SendSource) async -> UInt64? {
        guard source == .identity else { return nil }
        await withCheckedContinuation { held = $0 }
        return 5_000_000_000
    }

    func release() {
        held?.resume()
        held = nil
    }
}

private struct FakeBalances: ExternalSendBalanceReading {
    let values: [SendSource: UInt64]

    func spendableBalance(of source: SendSource) async -> UInt64? { values[source] }
}

/// A fixed rate of `rate` local units per DASH; no rate answers nil everywhere.
private struct FakeConverter: SendAmountConverting {
    let rate: Decimal?

    func fiat(forDuffs duffs: UInt64) -> Decimal? { rate.map { Decimal(duffs) / 100_000_000 * $0 } }
    func duffs(forFiat fiat: Decimal) -> UInt64? { nil }
    func fiatText(forDuffs duffs: UInt64) -> String? { fiat(forDuffs: duffs).map { "$\($0)" } }
}
