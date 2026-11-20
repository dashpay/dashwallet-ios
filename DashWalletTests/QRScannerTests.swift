//
//  QRScannerTests.swift
//  DashWalletTests
//
//  Camera-independent coverage for the unified QR scanner: payload
//  classification, and the scanner's decisions about what may leave the
//  flow it was opened in (lock state, private-key fields, redirect offers),
//  driven through `didDetectCodes` the way the camera drives it.
//

import SwiftDashSDK
import XCTest
@testable import dashpay

@MainActor
final class QRScannerTests: XCTestCase {

    // MARK: Fixtures

    /// A Core address valid on the network the test host runs on (devnet
    /// shares testnet's version bytes).
    private static let address: String = {
        let network: PaymentNetwork = WalletEnvironment.network == .mainnet ? .mainnet : .testnet
        let script = Data([0x76, 0xa9, 0x14]) + Data((0..<20).map { UInt8($0 &* 11 &+ 5) }) + Data([0x88, 0xac])
        return ScriptAddressCodec.address(forScript: script, network: network)!
    }()

    /// A DIP-0018 Platform P2PKH address (type byte 0xb0) for the network
    /// the test host runs on.
    private static let platformAddress: String = {
        let payload = Data([0xb0]) + Data((0..<20).map { UInt8($0 &* 13 &+ 1) })
        return Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: WalletEnvironment.isMainnet), data: payload)!
    }()

    private static let userLink = DashPayUserLink(
        identityId: Data((0..<32).map { UInt8($0 &* 7 &+ 3) }), username: "alice").uriString
    private static let invitationLink =
        "dashpay://invite?du=alice&assetlocktx=\(String(repeating: "ab", count: 32))&pk=A&islock=null"
    /// A WIF-shaped private key: whatever a key field scans must come back as is.
    private static let privateKey = "cVt4o7BGAig1UXywgGSmARhxMdzP5qvQsxKkSsc1XEkw3tDTQFpy"

    private final class Recorder {
        var results: [QRScanResult] = []
    }

    private func makeScanner(_ mode: QRScannerMode,
                             locked: @escaping @MainActor () -> Bool = { false },
                             hasIdentity: @escaping @MainActor () -> Bool = { true },
                             invitation: @escaping @MainActor (URL) -> QRScanResultRouter.InvitationCheck = { _ in .valid })
        -> (QRScannerViewModel, Recorder) {
        let recorder = Recorder()
        let viewModel = QRScannerViewModel(mode: mode, isWalletLocked: locked, hasDashPayIdentity: hasIdentity,
                                           checkInvitation: invitation)
        viewModel.onResult = { recorder.results.append($0) }
        return (viewModel, recorder)
    }

    private func isInvalid(_ status: QRScannerViewModel.Status) -> Bool {
        if case .invalid = status { return true }
        return false
    }

    private func isOffer(_ status: QRScannerViewModel.Status) -> Bool {
        if case .offer = status { return true }
        return false
    }

    // MARK: Classification

    func testClassifiesDashPayUserLink() {
        guard case .dashPayUser(let link) = QRPayload.classify(Self.userLink) else {
            return XCTFail("a dashpay://user link is a DashPay user")
        }
        XCTAssertEqual(link.username, "alice")
    }

    func testClassifiesInvitationLink() {
        guard case .invitation = QRPayload.classify(Self.invitationLink) else {
            return XCTFail("a dashpay://invite link is an invitation")
        }
    }

    func testClassifiesPaymentURIWithAmount() {
        guard case .payment(let parsed) = QRPayload.classify("dash:\(Self.address)?amount=1.5") else {
            return XCTFail("a dash: URI to a valid address is a payment")
        }
        XCTAssertEqual(parsed.address, Self.address)
        XCTAssertEqual(parsed.amount, 150_000_000)
    }

    func testClassifiesBareRequestURLAsPayment() {
        guard case .payment(let parsed) = QRPayload.classify("dash:?r=http%3A%2F%2Fh%2Fpr") else {
            return XCTFail("a BIP72 request URL is a payment, whatever the network")
        }
        XCTAssertNotNil(parsed.rURL)
    }

    /// #1215: a scanned `dashwallet://pay=` link is read the way the deep link
    /// router reads it, so it classifies as a payment carrying its amount.
    func testClassifiesDashWalletPayLinkAsPayment() {
        let link = "dashwallet://pay=\(Self.address)&amount=0.01916910&sender=v4v.app"
        guard case .payment(let parsed) = QRPayload.classify(link) else {
            return XCTFail("a dashwallet://pay= link with a sender is a payment")
        }
        XCTAssertEqual(parsed.address, Self.address)
        XCTAssertEqual(parsed.amount, 1_916_910)
    }

    func testClassifiesAnythingElseAsText() {
        guard case .text(let value) = QRPayload.classify("  hello world \n") else {
            return XCTFail("plain text is text")
        }
        XCTAssertEqual(value, "hello world")
    }

    // MARK: Private-key fields

    func testRawTextReturnsTheScanUntouched() {
        let (scanner, recorder) = makeScanner(.rawText)
        let scanned = " \(Self.privateKey)\n"
        scanner.didDetectCodes([scanned])
        guard case .text(let value) = recorder.results.first else {
            return XCTFail("a key field gets the scan back as text")
        }
        XCTAssertEqual(value, scanned)
        XCTAssertEqual(recorder.results.count, 1)
    }

    /// A key field never classifies, so a code that belongs to another flow
    /// is not offered elsewhere: it is handed back like anything else.
    func testRawTextNeverOffersARedirect() {
        for code in [Self.userLink, Self.invitationLink, "dash:\(Self.address)?amount=1"] {
            let (scanner, recorder) = makeScanner(.rawText)
            scanner.didDetectCodes([code])
            XCTAssertFalse(isOffer(scanner.status), code)
            guard case .text(let value) = recorder.results.first else {
                return XCTFail("\(code) comes back as text")
            }
            XCTAssertEqual(value, code)
        }
    }

    // MARK: Lock state

    func testPaymentScannerTakesAContactQRWhenUnlocked() {
        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes([Self.userLink])
        guard case .dashPayUser = recorder.results.first else {
            return XCTFail("unlocked, a contact QR leaves for the contact flow")
        }
    }

    /// Add Contact sends from the wallet's DashPay identity: without one, a
    /// contact QR goes nowhere.
    func testContactQRNeedsADashPayIdentity() {
        for mode in [QRScannerMode.payment, .addressInput(expectsDashAddress: false), .invitation, .dashPayUser] {
            let (scanner, recorder) = makeScanner(mode, hasIdentity: { false })
            scanner.didDetectCodes([Self.userLink])
            XCTAssertTrue(recorder.results.isEmpty)
            XCTAssertTrue(isInvalid(scanner.status))
        }
    }

    /// Claiming fills the wallet's one pending-invitation slot, so the
    /// payment scanner asks first.
    func testPaymentScannerOffersAnInvitation() {
        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes([Self.invitationLink])
        XCTAssertTrue(isOffer(scanner.status))
        XCTAssertTrue(recorder.results.isEmpty)

        scanner.acceptOffer()
        guard case .invitation = recorder.results.first else {
            return XCTFail("an accepted offer hands the invitation over")
        }
    }

    /// Only a voucher the wallet read as well formed can take the wallet's
    /// one pending-invitation slot, whichever scanner read it: a malformed
    /// one, or one the wallet can't read yet, is refused.
    func testOnlyAWellFormedInvitationIsHandedOver() {
        for check in [QRScanResultRouter.InvitationCheck.malformed, .unavailable] {
            for mode in [QRScannerMode.payment, .invitation, .dashPayUser] {
                let (scanner, recorder) = makeScanner(mode, invitation: { _ in check })
                scanner.didDetectCodes([Self.invitationLink])
                XCTAssertTrue(recorder.results.isEmpty)
                XCTAssertTrue(isInvalid(scanner.status))
            }
        }
    }

    func testPaymentScannerRefusesOtherFlowsWhileLocked() {
        for code in [Self.userLink, Self.invitationLink] {
            let (scanner, recorder) = makeScanner(.payment, locked: { true })
            scanner.didDetectCodes([code])
            XCTAssertTrue(recorder.results.isEmpty, code)
            XCTAssertTrue(isInvalid(scanner.status), code)
        }
    }

    /// The lock screen's own purpose — Scan to Pay — keeps working.
    func testPaymentScannerStillPaysWhileLocked() {
        let (scanner, recorder) = makeScanner(.payment, locked: { true })
        scanner.didDetectCodes(["dash:\(Self.address)?amount=1.5"])
        guard case .payment(let input) = recorder.results.first else {
            return XCTFail("a payment QR is the payment scanner's own flow")
        }
        XCTAssertEqual(input.parsedURI?.amount, 150_000_000)
    }

    /// Locked, another flow's code is refused before its eligibility is
    /// read, so the answer says nothing about the wallet.
    /// Including a scanner's own flow: a contact or invitation scanner left
    /// open under the lock hands nothing over.
    func testLockedScannerReadsNoOtherFlowsEligibility() {
        for mode in [QRScannerMode.payment, .addressInput(expectsDashAddress: false), .dashPayUser, .invitation] {
            for code in [Self.userLink, Self.invitationLink] {
                var probed = false
                let (scanner, recorder) = makeScanner(
                    mode, locked: { true },
                    hasIdentity: { probed = true; return true },
                    invitation: { _ in probed = true; return .valid })
                scanner.didDetectCodes([code])
                XCTAssertFalse(probed, code)
                XCTAssertTrue(isInvalid(scanner.status), code)
                XCTAssertTrue(recorder.results.isEmpty, code)
            }
        }
    }

    func testNoRedirectOfferWhileLocked() {
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: false), locked: { true })
        scanner.didDetectCodes([Self.userLink])
        XCTAssertFalse(isOffer(scanner.status))
        XCTAssertTrue(isInvalid(scanner.status))
        XCTAssertTrue(recorder.results.isEmpty)
    }

    func testAcceptingAnOfferAfterTheLockEngagedIsRefused() {
        var locked = false
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: false), locked: { locked })
        scanner.didDetectCodes([Self.userLink])
        XCTAssertTrue(isOffer(scanner.status))

        locked = true
        scanner.acceptOffer()
        XCTAssertTrue(recorder.results.isEmpty)
        XCTAssertTrue(isInvalid(scanner.status))
    }

    // MARK: Redirect offers

    func testFormScannerOffersAndHandsOverAContactQR() {
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: false))
        scanner.didDetectCodes([Self.userLink])
        XCTAssertTrue(isOffer(scanner.status), "a form never navigates on its own")
        XCTAssertTrue(recorder.results.isEmpty)

        scanner.acceptOffer()
        guard case .dashPayUser = recorder.results.first else {
            return XCTFail("an accepted offer hands the contact over")
        }
    }

    func testDeclinedOfferResumesScanning() {
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: false))
        scanner.didDetectCodes([Self.userLink])
        scanner.declineOffer()
        XCTAssertTrue(recorder.results.isEmpty)

        scanner.didDetectCodes(["some text"])
        guard case .text("some text") = recorder.results.first else {
            return XCTFail("scanning resumes after a declined offer")
        }
    }

    /// A declined code still in frame is not offered again straight away,
    /// and another code beside it is still read.
    func testDeclinedCodeIsPassedOverForAMoment() {
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: false))
        scanner.didDetectCodes([Self.userLink])
        scanner.declineOffer()

        scanner.didDetectCodes([Self.userLink])
        XCTAssertFalse(isOffer(scanner.status))
        XCTAssertTrue(recorder.results.isEmpty)

        scanner.didDetectCodes([Self.userLink, "some text"])
        guard case .text("some text") = recorder.results.first else {
            return XCTFail("the other code in frame is read")
        }
    }

    /// An "Open Send" redirect keeps the scanned amount on the input the
    /// router fills the Send form with.
    func testPaymentRedirectKeepsTheScannedAmount() {
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: false))
        scanner.didDetectCodes(["dash:\(Self.address)?amount=1.5"])
        XCTAssertTrue(isOffer(scanner.status))

        scanner.acceptOffer()
        guard case .payment(let input) = recorder.results.first else {
            return XCTFail("an accepted payment offer finishes with the payment")
        }
        XCTAssertEqual(input.parsedURI?.address, Self.address)
        XCTAssertEqual(input.parsedURI?.amount, 150_000_000)
        XCTAssertEqual(SendViewModel.scannedAddress(in: input), Self.address)
    }

    /// A URI amount above the coin supply is dropped before it is narrowed,
    /// so no later credit conversion can wrap it.
    /// An amount the wallet can't pay is not an open amount: the address
    /// alone is refused, by the scanner and by a failed request's fallback.
    /// The merchant's own request still decides its amount.
    func testOutOfRangeURIAmountIsRefused() {
        let atSupply = ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?amount=21000000")
        XCTAssertEqual(atSupply.amount, kMaxDashSupplyDuffs)
        XCTAssertFalse(atSupply.hasInvalidAmount)
        XCTAssertFalse(ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)").hasInvalidAmount)

        for amount in ["21000000.00000001", "184467440737", "-1", "abc", "", "1abc", "1,000", "1.2.3", "+1", " 1", "1e"] {
            for key in ["amount", "req-amount"] {
                let code = "dash:\(Self.address)?\(key)=\(amount)"
                let parsed = ParsedPaymentURI.parse(paymentString: code)
                XCTAssertTrue(parsed.hasInvalidAmount, code)
                XCTAssertFalse(parsed.isValidDashPaymentIntent, code)

                for mode in [QRScannerMode.payment, .addressInput(expectsDashAddress: true)] {
                    let (scanner, recorder) = makeScanner(mode)
                    scanner.didDetectCodes([code])
                    XCTAssertTrue(recorder.results.isEmpty, code)
                    XCTAssertTrue(isInvalid(scanner.status), code)
                }

                let request = ParsedPaymentURI.parse(
                    paymentString: "\(code)&r=https%3A%2F%2Fmerchant.invalid%2Fpr")
                XCTAssertTrue(request.isValidDashPaymentIntent, code)
                XCTAssertNil(QRScannerViewModel.fallback(afterFailedRequest: request), code)
            }
        }

        for code in ["dash:\(Self.address)?amount=abc&req-amount=1", "dash:\(Self.address)?amount=1&amount=-1"] {
            XCTAssertTrue(ParsedPaymentURI.parse(paymentString: code).hasInvalidAmount, "a later alias keeps it: \(code)")
        }
    }

    private final class ProcessorDelegate: NSObject, DWPaymentProcessorDelegate {
        var amountRequested = false
        var confirmed = false
        var failure: (error: Error?, title: String?)?
        var onFailure: (() -> Void)?
        func paymentProcessor(_ processor: DWPaymentProcessor, requestAmountWithDestination sendingDestination: String,
                              amount: UInt64) { amountRequested = true }
        func paymentProcessor(_ processor: DWPaymentProcessor, confirmPaymentOutput paymentOutput: DWPaymentOutput) {
            confirmed = true
        }
        func paymentProcessorDidCancelTransactionSigning(_ processor: DWPaymentProcessor) {}
        func paymentProcessor(_ processor: DWPaymentProcessor, didFailWithError error: Error?, title: String?,
                              message: String?) { failure = (error, title); onFailure?() }
        func paymentProcessor(_ processor: DWPaymentProcessor, didSendWithTxidWire txidWire: Data) {}
        func paymentProcessor(_ processor: DWPaymentProcessor, showProgressHUDWithMessage message: String?) {}
        func paymentInputProcessorHideProgressHUD(_ processor: DWPaymentProcessor) {}
    }

    /// An opened or scanned link with an unpayable amount gets an error the
    /// payment controller shows (it stays silent on a nil error), and no
    /// amount prompt.
    func testProcessorReportsAnUnpayableAmount() {
        let delegate = ProcessorDelegate()
        let processor = DWPaymentProcessor()
        processor.delegate = delegate
        let parsed = ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?amount=abc")
        processor.processPaymentInput(DWPaymentInputBuilder().paymentInput(withParsedURI: parsed, source: .scanQR))
        XCTAssertFalse(delegate.amountRequested)
        XCTAssertNotNil(delegate.failure?.error)
        XCTAssertEqual(delegate.failure?.title, NSLocalizedString("Invalid payment amount", comment: ""))
    }

    /// An opened or scanned link that requires its merchant request goes to
    /// that request first: no amount prompt, so no plain send to the
    /// embedded address.
    func testProcessorFetchesARequiredRequestBeforeAnyAmountPrompt() {
        for source in [DWPaymentInputSource.deepLink, .scanQR] {
            let delegate = ProcessorDelegate()
            let processor = DWPaymentProcessor()
            processor.delegate = delegate
            let parsed = ParsedPaymentURI.parse(
                paymentString: "dash:\(Self.address)?amount=1&req-r=https%3A%2F%2Fmerchant.invalid%2Fpr")
            processor.processPaymentInput(DWPaymentInputBuilder().paymentInput(withParsedURI: parsed, source: source))
            XCTAssertFalse(delegate.amountRequested)
        }
        let delegate = ProcessorDelegate()
        let processor = DWPaymentProcessor()
        processor.delegate = delegate
        let optional = ParsedPaymentURI.parse(
            paymentString: "dash:\(Self.address)?amount=1&r=https%3A%2F%2Fmerchant.invalid%2Fpr")
        processor.processPaymentInput(DWPaymentInputBuilder().paymentInput(withParsedURI: optional, source: .scanQR))
        XCTAssertTrue(delegate.amountRequested, "an optional request keeps the amount screen")
    }

    /// A required request the wallet can't use (unreadable, or given twice
    /// in either order) leaves nothing payable: the scanner and the
    /// processor refuse it with an error the payment controller shows,
    /// never an amount prompt or a plain confirmation to the address.
    func testUnusableRequiredRequestIsRefused() {
        let a = "https%3A%2F%2Fmerchant.invalid%2Fa", b = "https%3A%2F%2Fmerchant.invalid%2Fb"
        let codes = ["dash:\(Self.address)?amount=1&req-r=",
                     "dash:\(Self.address)?amount=1&req-r=\(a)&r=\(b)",
                     "dash:\(Self.address)?amount=1&r=\(b)&req-r=\(a)",
                     "dash:\(Self.address)?amount=1&r=\(a)&r=\(b)",
                     "dashwallet://pay=\(Self.address)&amount=1&req-r=\(a)&r=\(b)&sender=ctx",
                     "dashwallet://pay=\(Self.address)&amount=1&r=\(b)&req-r=\(a)&sender=ctx"]
        for code in codes {
            let parsed = ParsedPaymentURI.parse(paymentString: code)
            XCTAssertFalse(parsed.isValidDashPaymentIntent, code)
            XCTAssertNil(parsed.rURL, code)

            let modes: [QRScannerMode] = code.hasPrefix("dash:")
                ? [.payment, .addressInput(expectsDashAddress: true)] : [.payment]
            for mode in modes {
                let (scanner, recorder) = makeScanner(mode)
                scanner.didDetectCodes([code])
                if case .connecting = scanner.status { XCTFail("nothing is fetched: \(code)") }
                XCTAssertTrue(recorder.results.isEmpty, code)
                XCTAssertTrue(isInvalid(scanner.status), code)
            }

            guard code.hasPrefix("dash:") else {
                XCTAssertNil(DWURLParser.action(for: URL(string: code)!), code)
                continue
            }
            for source in [DWPaymentInputSource.deepLink, .scanQR] {
                let delegate = ProcessorDelegate()
                let processor = DWPaymentProcessor()
                processor.delegate = delegate
                processor.processPaymentInput(DWPaymentInputBuilder().paymentInput(withParsedURI: parsed, source: source))
                XCTAssertFalse(delegate.amountRequested, code)
                XCTAssertFalse(delegate.confirmed, code)
                XCTAssertNotNil(delegate.failure?.error, code)
                XCTAssertEqual(delegate.failure?.title, NSLocalizedString("Invalid Payment Request", comment: ""), code)
            }
        }
    }

    /// A pay link with payment fields in its query, which the rewrite never
    /// reads, is refused by both entry points rather than paid without them.
    func testPayLinkWithPaymentFieldsInItsQueryIsRefused() throws {
        let a = "https%3A%2F%2Fmerchant.invalid%2Fa", b = "https%3A%2F%2Fmerchant.invalid%2Fb"
        let single = "dashwallet://pay=\(Self.address)&amount=1&r=\(a)&sender=ctx"
        XCTAssertNotNil(DWURLParser.action(for: try XCTUnwrap(URL(string: single))))
        for link in ["\(single)?req-r=\(b)", "\(single)?amount=2", "\(single)?pay=\(Self.address)"] {
            XCTAssertNil(DWURLParser.action(for: try XCTUnwrap(URL(string: link))), link)
            let parsed = ParsedPaymentURI.parse(paymentString: link)
            XCTAssertFalse(parsed.isValidDashPaymentIntent, link)
            XCTAssertNil(parsed.rURL, link)
        }
    }

    /// Offers use the ranking's verdict: a required request the transport
    /// would refuse is not offered, while an optional one with a payable
    /// address still is.
    func testOfferNeedsAUsableRequestOrAPayableFallback() {
        let cleartext = "http%3A%2F%2Fmerchant.invalid%2Fpr"
        let (required, requiredRecorder) = makeScanner(.addressInput(expectsDashAddress: false))
        required.didDetectCodes(["dash:\(Self.address)?amount=1&req-r=\(cleartext)"])
        XCTAssertFalse(isOffer(required.status))
        XCTAssertTrue(isInvalid(required.status))
        XCTAssertTrue(requiredRecorder.results.isEmpty)

        let (optional, _) = makeScanner(.addressInput(expectsDashAddress: false))
        optional.didDetectCodes(["dash:\(Self.address)?amount=1&r=\(cleartext)"])
        XCTAssertTrue(isOffer(optional.status))
    }

    /// A superseded payment's merchant answer is ignored: only the current
    /// payment can reach the delegate.
    func testProcessorIgnoresASupersededRequest() {
        let delegate = ProcessorDelegate()
        let processor = DWPaymentProcessor()
        processor.delegate = delegate
        func required(_ path: String) -> DWPaymentInput {
            let parsed = ParsedPaymentURI.parse(
                paymentString: "dash:\(Self.address)?amount=1&req-r=https%3A%2F%2F127.0.0.1%3A1%2F\(path)")
            return DWPaymentInputBuilder().paymentInput(withParsedURI: parsed, source: .deepLink)
        }
        processor.processPaymentInput(required("first"))
        processor.reset()
        processor.processPaymentInput(required("second"))

        let failed = expectation(description: "the current request fails")
        failed.assertForOverFulfill = false
        var failures = 0
        delegate.onFailure = { failures += 1; failed.fulfill() }
        wait(for: [failed], timeout: 40)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(failures, 1, "the first request's answer is not delivered")
        XCTAssertFalse(delegate.confirmed)
    }

    /// A Dash request the wallet would refuse to fetch does not outrank a
    /// payable code later in the frame.
    func testUnfetchableDashRequestDoesNotCrowdOutAPayableCode() {
        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes(["dash:?r=http%3A%2F%2Fmerchant.example%2Frequest", "dash:\(Self.address)?amount=1.5"])
        guard case .payment(let input) = recorder.results.first else {
            return XCTFail("the payable code is handed over: \(scanner.status)")
        }
        XCTAssertEqual(input.parsedURI?.address, Self.address)
    }

    /// A cleartext whole URL is not fetched as a Dash request: nothing
    /// vouches for what it returns.
    func testPaymentScannerFetchesNoCleartextRequestURL() {
        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes(["http://merchant.invalid/pr"])
        if case .connecting = scanner.status { XCTFail("a cleartext request is not fetched") }
        XCTAssertTrue(isInvalid(scanner.status))
        XCTAssertTrue(recorder.results.isEmpty)
        XCTAssertFalse(ParsedPaymentURI.parse(paymentString: "http://merchant.invalid/pr").isWholeRequestURL)
    }

    /// A wrapper link that gives its amount twice is not read as an open
    /// amount, however the repeats are ordered.
    func testScannedWrapperLinkWithARepeatedAmountIsRefused() {
        let request = "r=https%3A%2F%2Fmerchant.invalid%2Fpr"
        for link in ["dashwallet://pay=\(Self.address)&amount=99999999999&amount=&sender=ctx",
                     "dashwallet://pay=\(Self.address)&amount=1&req-amount=2&sender=ctx",
                     "dashwallet://pay=\(Self.address)&amount=1&amount=2&\(request)&sender=ctx",
                     "dashwallet://pay=&amount=1&amount=2&\(request)&sender=ctx"] {
            let parsed = ParsedPaymentURI.parse(paymentString: link)
            XCTAssertFalse(parsed.isValidDashPaymentIntent, link)
            XCTAssertNil(parsed.rURL, "a refused wrapper is not reread: \(link)")
            let (scanner, recorder) = makeScanner(.payment)
            scanner.didDetectCodes([link])
            if case .connecting = scanner.status { XCTFail("a refused wrapper is not fetched: \(link)") }
            XCTAssertTrue(recorder.results.isEmpty, link)
        }
        let accepted = ParsedPaymentURI.parse(paymentString: "dashwallet://pay=\(Self.address)&amount=1&\(request)&sender=ctx")
        XCTAssertNotNil(accepted.rURL, "a well-formed wrapper keeps its request")
        XCTAssertTrue(ParsedPaymentURI.parse(
            paymentString: "dashwallet://pay=\(Self.address)&amount=1&sender=ctx").isValidDashPaymentIntent)
    }

    /// A whole request URL is fetched as a Dash request: its https scheme
    /// says where the request is, not which currency's MIME types to use.
    func testWholeRequestURLIsFetchedAsDash() {
        let parsed = ParsedPaymentURI.parse(paymentString: "https://merchant.invalid/pr")
        XCTAssertTrue(parsed.isWholeRequestURL)
        XCTAssertEqual(BIP70InteractiveCoordinator.paymentProtocolScheme(parsed.scheme!), "dash")
        XCTAssertEqual(BIP70InteractiveCoordinator.paymentProtocolScheme("http"), "http")
        XCTAssertEqual(BIP70InteractiveCoordinator.paymentProtocolScheme("bitcoin"), "bitcoin")
    }

    /// A whole request URL in frame is preferred over unrelated text, as a
    /// `dash:` intent is.
    func testPaymentScannerPrefersAWholeRequestURLOverText() {
        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes(["hello", "https://merchant.invalid/pr"])
        guard case .connecting = scanner.status else {
            return XCTFail("the request URL is fetched, not the text: \(scanner.status)")
        }
        scanner.cancel()
        XCTAssertTrue(recorder.results.isEmpty)
    }

    /// A hostless https code is no request, so it neither ranks as one nor
    /// keeps a usable request later in the frame from being fetched.
    func testUnusableHTTPSCodeDoesNotCrowdOutARequest() {
        XCTAssertFalse(ParsedPaymentURI.parse(paymentString: "https:///pr").isWholeRequestURL)

        let (alone, _) = makeScanner(.payment)
        alone.didDetectCodes(["https:///pr"])
        if case .connecting = alone.status { XCTFail("a hostless URL is not fetched") }

        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes(["https:///pr", "https://merchant.invalid/pr"])
        guard case .connecting = scanner.status else {
            return XCTFail("the usable request is fetched: \(scanner.status)")
        }
        scanner.cancel()
        XCTAssertTrue(recorder.results.isEmpty)
    }

    /// A `dash:` payment anywhere in frame wins over a whole request URL
    /// read before it: the URL would be fetched without a tap.
    func testPaymentScannerPrefersADashPaymentOverAWholeRequestURL() {
        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes(["https://merchant.invalid/pr", "dash:\(Self.address)?amount=1.5"])
        if case .connecting = scanner.status { XCTFail("the request URL is not fetched") }
        guard case .payment(let input) = recorder.results.first else {
            return XCTFail("the Dash payment is handed over")
        }
        XCTAssertEqual(input.parsedURI?.amount, 150_000_000)
    }

    /// An amount given twice, under either spelling, is a conflict: neither
    /// value is the one asked for.
    func testRepeatedURIAmountIsRefused() {
        for query in ["req-amount=1&amount=2", "amount=1&amount=1", "amount=1&req-amount=1"] {
            let code = "dash:\(Self.address)?\(query)"
            let parsed = ParsedPaymentURI.parse(paymentString: code)
            XCTAssertTrue(parsed.hasInvalidAmount, code)
            XCTAssertFalse(parsed.isValidDashPaymentIntent, code)
            let (scanner, recorder) = makeScanner(.payment)
            scanner.didDetectCodes([code])
            XCTAssertTrue(recorder.results.isEmpty, code)
        }
    }

    /// A required merchant request is the only thing that may be paid: its
    /// embedded address is no fallback when the request fails.
    func testRequiredRequestHasNoAddressFallback() {
        let request = "r=https%3A%2F%2Fmerchant.invalid%2Fpr"
        let optional = ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?\(request)")
        XCTAssertFalse(optional.requiresRequest)
        XCTAssertNotNil(QRScannerViewModel.fallback(afterFailedRequest: optional))

        let required = ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?req-\(request)")
        XCTAssertTrue(required.requiresRequest)
        XCTAssertTrue(required.isValidDashPaymentIntent)
        XCTAssertNil(QRScannerViewModel.fallback(afterFailedRequest: required))
    }

    /// Only a whole https request URL is fetched without a `dash:` scheme;
    /// another currency's `r=` request is not Dash's to fetch.
    func testPaymentScannerFetchesNoForeignSchemeRequest() {
        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes(["bitcoin:\(Self.address)?amount=1&r=https%3A%2F%2Fmerchant.invalid%2Fpr"])
        if case .connecting = scanner.status { XCTFail("a foreign request is not fetched") }
        XCTAssertTrue(isInvalid(scanner.status))
        XCTAssertTrue(recorder.results.isEmpty)
        XCTAssertTrue(ParsedPaymentURI.parse(paymentString: "https://merchant.invalid/pr").isWholeRequestURL)
    }

    /// The Send form a redirect fills reads back exactly the scanned duffs,
    /// including amounts locale formatting would group.
    func testSendFormKeepsTheScannedDuffs() {
        for (amount, duffs) in [("1.5", Int64(150_000_000)), ("1234.56789012", Int64(123_456_789_012))] {
            let parsed = ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?amount=\(amount)")
            let input = DWPaymentInputBuilder().paymentInput(withParsedURI: parsed, source: .scanQR)
            let send = SendViewModel(contactLookup: { _ in nil })
            XCTAssertTrue(send.ingestScannedInput(input))
            XCTAssertEqual(send.dashDuffs, duffs, amount)

            // Home and the lock screen open a bech32 destination's Send form
            // through the controller's `prefill(address:amountDuffs:)`.
            let routed = SendViewModel(contactLookup: { _ in nil })
            routed.prefill(address: Self.platformAddress, amountDuffs: parsed.amount)
            XCTAssertEqual(routed.dashDuffs, duffs, amount)
        }
    }

    /// A scanned link's `sender` calls no app back (ADR-0007), so an "Open
    /// Send" redirect that fills the form with the address and amount drops
    /// no callback.
    func testScannedPaymentCallsNoAppBack() {
        let link = "dash:\(Self.address)?amount=1.5&sender=someapp"
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: false))
        scanner.didDetectCodes([link])
        scanner.acceptOffer()
        guard case .payment(let redirected) = recorder.results.first else {
            return XCTFail("an accepted payment offer finishes with the payment")
        }
        XCTAssertEqual(redirected.parsedURI?.callbackScheme, "someapp")
        XCTAssertNil(redirected.callbackScheme)
        XCTAssertNil(redirected.paymentIntent?.callbackScheme)

        let (paymentScanner, paymentRecorder) = makeScanner(.payment)
        paymentScanner.didDetectCodes([link])
        guard case .payment(let scanned) = paymentRecorder.results.first else {
            return XCTFail("the payment scanner pays a payment URI")
        }
        XCTAssertNil(scanned.callbackScheme)
        XCTAssertNil(scanned.paymentIntent?.callbackScheme)
    }

    func testDashAddressFieldUnwrapsAPaymentURI() {
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: true))
        scanner.didDetectCodes(["dash:\(Self.address)?amount=1.5"])
        guard case .text(let value) = recorder.results.first else {
            return XCTFail("a Dash address field gets the bare address")
        }
        XCTAssertEqual(value, Self.address)
    }

    /// A form field that isn't a Dash address field gets text it can't pay
    /// (an https URL) as is and validates it itself.
    func testFormScannerPassesAnUnpayableURLThrough() {
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: false))
        scanner.didDetectCodes(["https://example.com/connect?id=1"])
        guard case .text(let value) = recorder.results.first else {
            return XCTFail("the field gets the URL, not a rejection")
        }
        XCTAssertEqual(value, "https://example.com/connect?id=1")
    }

    /// The payout field takes Core addresses only, but a Platform
    /// destination is still payable from Send: offer it, don't reject it.
    func testDashAddressFieldOffersSendForAPlatformAddress() {
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: true))
        scanner.didDetectCodes(["dash:\(Self.platformAddress)"])
        XCTAssertTrue(isOffer(scanner.status))
        XCTAssertTrue(recorder.results.isEmpty)
    }

    /// A foreign-scheme request is neither unwrapped into a Dash field nor
    /// offered as a Dash payment.
    func testForeignSchemeRequestIsNotTakenForDash() {
        let foreign = "bitcoin:\(Self.address)?r=https%3A%2F%2Fmerchant.invalid%2Fpr"
        for expectsDashAddress in [true, false] {
            let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: expectsDashAddress))
            scanner.didDetectCodes([foreign])
            XCTAssertFalse(isOffer(scanner.status))
            if case .text(let value) = recorder.results.first {
                XCTAssertNotEqual(value, Self.address)
            }
        }
    }

    /// A Dash merchant request with an embedded address is offered to the
    /// merchant flow, not unwrapped into a Dash address field.
    func testDashAddressFieldOffersAMerchantRequestCarryingAnAddress() {
        let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: true))
        scanner.didDetectCodes(["dash:\(Self.address)?r=https%3A%2F%2Fmerchant.invalid%2Fpr"])
        XCTAssertTrue(isOffer(scanner.status))
        XCTAssertTrue(recorder.results.isEmpty)
    }

    /// A form field gets a merchant request as an offer, not as text.
    func testFormScannerOffersADashMerchantRequest() {
        for expectsDashAddress in [false, true] {
            let (scanner, recorder) = makeScanner(.addressInput(expectsDashAddress: expectsDashAddress))
            scanner.didDetectCodes(["dash:?r=https%3A%2F%2Fmerchant.invalid%2Fpr"])
            XCTAssertTrue(isOffer(scanner.status))
            XCTAssertTrue(recorder.results.isEmpty)
        }
    }

    /// An explicit Dash merchant request carries no address, but accepting
    /// the offer fetches it like the payment scanner does.
    func testContactScannerOffersADashMerchantRequest() {
        let (scanner, _) = makeScanner(.dashPayUser)
        scanner.didDetectCodes(["dash:?r=https%3A%2F%2Fmerchant.invalid%2Fpr"])
        XCTAssertTrue(isOffer(scanner.status))

        let (bare, _) = makeScanner(.dashPayUser)
        bare.didDetectCodes(["https://merchant.invalid/pr"])
        XCTAssertTrue(isInvalid(bare.status), "a bare request URL is not a Dash payment offer")
    }

    /// The Payments screen and Enter Address hand scans to
    /// `dispatchPaymentInput`, which must send a Platform destination to the
    /// Send screen and keep a Core address on the classic processor.
    func testOnlyPlatformDestinationsRequireTheSendScreen() {
        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes(["dash:\(Self.platformAddress)?amount=1.5"])
        guard case .payment(let platformInput) = recorder.results.first else {
            return XCTFail("a Platform destination is a payment")
        }
        XCTAssertTrue(QRScanResultRouter.requiresSendScreen(platformInput))
        XCTAssertEqual(platformInput.parsedURI?.amount, 150_000_000)

        let core = DWPaymentInputBuilder().paymentInput(
            withParsedURI: ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)"), source: .scanQR)
        XCTAssertFalse(QRScanResultRouter.requiresSendScreen(core))
    }

    /// A merchant request whose fetch fails falls back to its embedded
    /// address, Platform destinations included: payable, though not a valid
    /// Core address.
    func testFailedRequestFallsBackToAnyPayableAddress() {
        let request = "r=https%3A%2F%2Fmerchant.invalid%2Fpr"
        let platform = QRScannerViewModel.fallback(
            afterFailedRequest: ParsedPaymentURI.parse(paymentString: "dash:\(Self.platformAddress)?\(request)"))
        XCTAssertEqual(platform?.address, Self.platformAddress)
        XCTAssertNil(platform?.rURL)
        XCTAssertTrue(QRScanResultRouter.requiresSendScreen(
            DWPaymentInputBuilder().paymentInput(withParsedURI: platform!, source: .scanQR)))

        let core = QRScannerViewModel.fallback(
            afterFailedRequest: ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?\(request)"))
        XCTAssertEqual(core?.address, Self.address)

        XCTAssertNil(QRScannerViewModel.fallback(
            afterFailedRequest: ParsedPaymentURI.parse(paymentString: "dash:?\(request)")))
    }

    func testPaymentScannerPrefersTheDashIntentAmongSeveralCodes() {
        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes(["hello", "dash:\(Self.address)"])
        guard case .payment(let input) = recorder.results.first else {
            return XCTFail("the valid Dash intent wins over whatever came first")
        }
        XCTAssertEqual(input.parsedURI?.address, Self.address)
    }

    func testScannerReportsOneResult() {
        let (scanner, recorder) = makeScanner(.rawText)
        scanner.didDetectCodes(["first"])
        scanner.didDetectCodes(["second"])
        XCTAssertEqual(recorder.results.count, 1)
    }
}
