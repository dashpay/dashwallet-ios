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
                             readsDashConnect: Bool = false,
                             locked: @escaping @MainActor () -> Bool = { false },
                             hasIdentity: @escaping @MainActor () -> Bool = { true },
                             invitation: @escaping @MainActor (URL) -> QRScanResultRouter.InvitationCheck = { _ in .valid })
        -> (QRScannerViewModel, Recorder) {
        let recorder = Recorder()
        let viewModel = QRScannerViewModel(mode: mode, readsDashConnect: readsDashConnect, isWalletLocked: locked,
                                           hasDashPayIdentity: hasIdentity, checkInvitation: invitation)
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

    // MARK: DashConnect codes

    private static let dashConnectCodes = ["dash-key:example", "dash-st:example", "dashpay://connect?example"]

    func testHomeScannerHandsOverADashConnectCode() {
        for code in Self.dashConnectCodes {
            let (scanner, recorder) = makeScanner(.payment, readsDashConnect: true)
            scanner.didDetectCodes([" \(code)\n"])
            guard case .dashConnect(let uri) = recorder.results.first else {
                return XCTFail("Home's scanner hands \(code) to the Connections screen")
            }
            XCTAssertEqual(uri, code)
        }
    }

    func testOtherPaymentScannersCallADashConnectCodeNotDash() {
        for code in Self.dashConnectCodes {
            let (scanner, recorder) = makeScanner(.payment)
            scanner.didDetectCodes([code])
            XCTAssertTrue(recorder.results.isEmpty, code)
            guard case .invalid(_, let message) = scanner.status else {
                return XCTFail("\(code) is not a payment")
            }
            XCTAssertEqual(message, String(localized: "Not a Dash QR code", comment: ""), code)
        }
    }

    func testHomeScannerRefusesADashConnectCodeWhileLocked() {
        let (scanner, recorder) = makeScanner(.payment, readsDashConnect: true, locked: { true })
        scanner.didDetectCodes([Self.dashConnectCodes[0]])
        XCTAssertTrue(recorder.results.isEmpty)
        XCTAssertTrue(isInvalid(scanner.status))
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
        XCTAssertEqual(delegate.failure?.title, String(localized: "Invalid payment amount", comment: ""))
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
                XCTAssertEqual(delegate.failure?.title, String(localized: "Invalid Payment Request", comment: ""), code)
            }
        }
    }

    /// BIP21: a required parameter the wallet doesn't understand leaves
    /// nothing payable — not the request, not the address alone, not an
    /// address field. An unknown optional parameter is ignored.
    func testUnsupportedRequiredParameterIsRefused() {
        let request = "r=https%3A%2F%2Fmerchant.invalid%2Fpr"
        for code in ["dash:\(Self.address)?req-memo=hi", "dash:\(Self.address)?amount=1&req-expires=1",
                     "dash:\(Self.address)?amount=1&\(request)&req-memo=hi", "dash:?\(request)&req-memo=hi",
                     "dash:\(Self.platformAddress)?req-memo=hi", "dash:\(Self.address)?req-local=25&req-currency=USD",
                     "dash:\(Self.address)?amount=1&req-user=alice"] {
            let parsed = ParsedPaymentURI.parse(paymentString: code)
            XCTAssertTrue(parsed.hasUnsupportedRequirement, code)
            XCTAssertFalse(parsed.isValidDashPaymentIntent, code)
            XCTAssertFalse(QRScannerViewModel.isOfferablePayment(parsed), code)
            XCTAssertNil(QRScannerViewModel.fallback(afterFailedRequest: parsed), code)
            XCTAssertFalse(parsed.requiresSendScreenRouting, code)
            let input = DWPaymentInputBuilder().paymentInput(withParsedURI: parsed, source: .scanQR)
            XCTAssertNil(SendViewModel.scannedAddress(in: input), code)

            for mode in [QRScannerMode.payment, .addressInput(expectsDashAddress: true), .addressInput(expectsDashAddress: false)] {
                let (scanner, recorder) = makeScanner(mode)
                scanner.didDetectCodes([code])
                if case .connecting = scanner.status { XCTFail("nothing is fetched: \(code)") }
                XCTAssertFalse(isOffer(scanner.status), code)
                XCTAssertTrue(recorder.results.isEmpty, code)
            }

            for source in [DWPaymentInputSource.deepLink, .scanQR] {
                let delegate = ProcessorDelegate()
                let processor = DWPaymentProcessor()
                processor.delegate = delegate
                processor.processPaymentInput(DWPaymentInputBuilder().paymentInput(withParsedURI: parsed, source: source))
                XCTAssertFalse(delegate.amountRequested, code)
                XCTAssertFalse(delegate.confirmed, code)
                XCTAssertEqual(delegate.failure?.title, String(localized: "Invalid Payment Request", comment: ""), code)
            }
        }

        for code in ["dash:\(Self.address)?memo=hi", "dash:\(Self.address)?req-label=Shop&req-message=Thanks&amount=1",
                     "dash:\(Self.address)?amount=1&req-IS=1", "dash:\(Self.address)?local=25&currency=USD"] {
            let parsed = ParsedPaymentURI.parse(paymentString: code)
            XCTAssertFalse(parsed.hasUnsupportedRequirement, code)
            XCTAssertTrue(parsed.isValidDashPaymentIntent, code)
            let (field, recorder) = makeScanner(.addressInput(expectsDashAddress: true))
            field.didDetectCodes([code])
            guard case .text(let address) = recorder.results.first else {
                return XCTFail("an understood or optional parameter still unwraps: \(code)")
            }
            XCTAssertEqual(address, Self.address, code)
            let input = DWPaymentInputBuilder().paymentInput(withParsedURI: parsed, source: .scanQR)
            XCTAssertEqual(SendViewModel.scannedAddress(in: input), Self.address, code)
        }
        let optional = ParsedPaymentURI.parse(paymentString: "dash:\(Self.platformAddress)?memo=hi")
        XCTAssertTrue(optional.requiresSendScreenRouting)
    }

    /// A paste or an NFC tag with a requirement the wallet can't meet is
    /// handed to the processor to refuse, never fetched and paid.
    func testPastedOrTappedUnsupportedRequirementIsRefused() {
        let code = "dash:?r=https%3A%2F%2Fmerchant.invalid%2Fpr&req-memo=hi"
        for source in [DWPaymentInputSource.pasteboard, .NFC] {
            var read: DWPaymentInput?
            DWPaymentInputBuilder().payFirst(from: [code], source: source) { read = $0 }
            let input = try? XCTUnwrap(read, "handed on without a fetch")
            XCTAssertNil(input?.bip70Confirmation)
            XCTAssertEqual(input?.parsedURI?.hasUnsupportedRequirement, true)

            let delegate = ProcessorDelegate()
            let processor = DWPaymentProcessor()
            processor.delegate = delegate
            if let input { processor.processPaymentInput(input) }
            XCTAssertFalse(delegate.confirmed)
            XCTAssertEqual(delegate.failure?.title, String(localized: "Invalid Payment Request", comment: ""))
        }
    }

    /// A pay link can't lose a requirement on its way to the `dash:` URI:
    /// one the rewrite would drop as malformed, or one in the query it never
    /// reads, refuses the link. A well-formed one is carried over.
    func testPayLinkKeepsOrRefusesItsRequirements() throws {
        let link = "dashwallet://pay=\(Self.address)&amount=1&sender=ctx"
        for refused in ["\(link)&req-memo", "\(link)&req-memo=a=b", "\(link)?req-memo=hi", "\(link)?req-IS=1"] {
            XCTAssertNil(DWURLParser.action(for: try XCTUnwrap(URL(string: refused))), refused)
        }
        let carried = try XCTUnwrap(DWURLParser.paymentURL(forScannedLink: try XCTUnwrap(URL(string: "\(link)&req-memo=hi"))))
        XCTAssertTrue(ParsedPaymentURI.parse(paymentString: carried.absoluteString).hasUnsupportedRequirement)
        XCTAssertNotNil(DWURLParser.action(for: try XCTUnwrap(URL(string: "\(link)&req-IS=1"))))
    }

    /// A scan calls no app back, so a required callback is refused there,
    /// while an optional `sender` is still ignored and a link another app
    /// opened still meets it.
    func testScannedRequiredCallbackIsRefused() throws {
        let required = "dash:\(Self.address)?amount=1&req-sender=ctx"
        XCTAssertTrue(ParsedPaymentURI.parse(paymentString: required).hasUnsupportedRequirement)
        XCTAssertFalse(ParsedPaymentURI.parse(openedLink: required).hasUnsupportedRequirement)
        XCTAssertFalse(ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?amount=1&sender=ctx").hasUnsupportedRequirement)

        let link = try XCTUnwrap(URL(string: "dashwallet://pay=\(Self.address)&amount=1&sender=ctx&req-sender=ctx"))
        XCTAssertNotNil(DWURLParser.action(for: link))
        let scanned = try XCTUnwrap(DWURLParser.paymentURL(forScannedLink: link))
        XCTAssertTrue(ParsedPaymentURI.parse(paymentString: scanned.absoluteString).hasUnsupportedRequirement)

        for code in [required, link.absoluteString] {
            let (scanner, recorder) = makeScanner(.payment)
            scanner.didDetectCodes([code])
            XCTAssertTrue(recorder.results.isEmpty, code)
        }
    }

    /// Send's clipboard suggestion reads a copied payment URI as a payment:
    /// one the scanner would refuse suggests no address, while an unknown
    /// optional parameter and plain prose still suggest one.
    func testClipboardSuggestionRefusesWhatTheScannerRefuses() {
        for refused in ["dash:\(Self.address)?amount=1&req-memo=x", "dash:\(Self.address)?req-amount=1",
                        "Pay dash:\(Self.address)?amount=abc today", "dash:\(Self.address)?req-r"] {
            XCTAssertNil(SendViewModel.detect(in: refused), refused)
        }
        for suggested in ["dash:\(Self.address)?amount=1", "dash:\(Self.address)?amount=1&memo=x",
                          "Note: pay \(Self.address) please"] {
            XCTAssertEqual(SendViewModel.detect(in: suggested)?.address, Self.address, suggested)
        }
    }

    /// A scanned invoice's amount is what is sent, in either unit: at a known
    /// rate fiat shows its two-decimal reading, and DASH comes back exact from
    /// the duffs. Without a rate the amount stays in DASH. An edit replaces it.
    func testAnInvoiceAmountStaysExactAcrossUnits() {
        let exchanger = CurrencyExchanger.shared
        let saved = exchanger.currencies
        let provider = MockRatesProvider()
        exchanger.configure(dataProvider: provider)
        defer { provider.updateHandler?(saved) }
        provider.updateHandler?([RateObject(code: App.fiatCurrency, name: App.fiatCurrency, price: 30)])

        let send = SendViewModel(contactLookup: { _ in nil })
        send.prefill(address: Self.address, amountDuffs: 123_456_789, requiresAmount: true)
        let shown = send.amountText
        send.unit = .fiat
        XCTAssertEqual(send.unit, .fiat)
        XCTAssertEqual(send.amountText, "37.04")
        XCTAssertEqual(send.dashDuffsUnsigned, 123_456_789)
        send.unit = .dash
        XCTAssertEqual(send.amountText, shown, "drawn from the duffs, not from the fiat reading")
        XCTAssertEqual(send.dashDuffsUnsigned, 123_456_789)

        provider.updateHandler?([])
        send.unit = .fiat
        XCTAssertEqual(send.unit, .dash, "without a rate the amount stays in DASH")
        XCTAssertEqual(send.amountText, shown)

        send.amountText = "2"
        XCTAssertEqual(send.dashDuffsUnsigned, 200_000_000)
    }

    /// Max, the Core drain's estimate included, takes the amount over from a
    /// scanned invoice. Once a funding change drops the selection, what is
    /// sent is exactly the estimate the editor still shows.
    func testMaxReplacesAnInvoiceAmount() {
        // Large enough for a locale formatter to group: "1,234.56789012".
        let estimate: UInt64 = 123_456_789_012
        for apply in [{ (send: SendViewModel) in send.applyMax(duffs: estimate) },
                      { (send: SendViewModel) in send.applyCoreDrainEstimate(estimate) }] {
            let send = SendViewModel(contactLookup: { _ in nil })
            send.prefill(address: Self.address, amountDuffs: 123_456_789, requiresAmount: true)
            apply(send)
            XCTAssertTrue(send.isMaxSelected)
            XCTAssertEqual(send.amountText, SendViewModel.editorText(duffs: estimate))
            send.source = send.source == .core ? .platform : .core
            XCTAssertFalse(send.isMaxSelected)
            XCTAssertEqual(send.amountText, SendViewModel.editorText(duffs: estimate))
            XCTAssertEqual(send.dashDuffsUnsigned, estimate)
        }
    }

    /// A pay wrapper that names its sender twice, in either order, is refused:
    /// the last would decide which app is called back.
    func testPayLinkWithConflictingSendersIsRefused() throws {
        let link = "dashwallet://pay=\(Self.address)&amount=1"
        for senders in ["sender=ctx&sender=other&req-sender=ctx", "sender=other&sender=ctx&req-sender=ctx",
                        "sender=ctx&sender=ctx"] {
            XCTAssertNil(DWURLParser.action(for: try XCTUnwrap(URL(string: "\(link)&\(senders)"))), senders)
        }
        XCTAssertNotNil(DWURLParser.action(for: try XCTUnwrap(URL(string: "\(link)&sender=ctx&req-sender=ctx"))))
    }

    /// A refused pay wrapper is not prose: neither Send's clipboard suggestion
    /// nor the pasteboard extractor picks its recipient out of it.
    func testARefusedPayLinkYieldsNoAddress() {
        let refused = "dashwallet://pay=\(Self.address)&amount=1&sender=ctx&req-memo=x"
        XCTAssertNil(SendViewModel.detect(in: refused))
        XCTAssertTrue(ParsedPaymentURI.textMentionsPaymentLink(refused), "the extractor then adds no pieces")
        XCTAssertFalse(ParsedPaymentURI.parse(paymentString: ParsedPaymentURI.soleLink(in: refused) ?? "")
            .isValidDashPaymentIntent)
        let prose = "Note: pay \(Self.address) please"
        XCTAssertEqual(SendViewModel.detect(in: prose)?.address, Self.address)
        XCTAssertFalse(ParsedPaymentURI.textMentionsPaymentLink(prose))
        XCTAssertFalse(ParsedPaymentURI.textMentionsPaymentLink("Amount to pay: 1 DASH to \(Self.address)"))
    }

    /// Both clipboard readers take a payment link whole and only when the
    /// text is that one link: a query may hold brackets, quotes, spaces and
    /// percent-encoded keys, so any part of a link could pay without what the
    /// rest of it required. Prose with no link still yields its address.
    func testClipboardReadsDelimitedLinksWhole() {
        let address = Self.address
        let refused = "dashwallet://pay=\(address)&amount=1&sender=ctx&req-memo=x"
        // A merchant request is fetched whole; its metadata names no recipient.
        XCTAssertNil(SendViewModel.detect(in: "dash:?r=https://merchant.example/r&label=\(address)"))
        for text in ["(\(refused))", "<\(refused)>", "see [dash:\(address)?req-amount=1].",
                     "dash:\(address)?label=Shop(1)&req-memo=hi", "(dash:\(address)?label=a(b)&req-memo=hi)",
                     "dash:\(address)?label=Shop(1)&req%2Dmemo=hi", "dash:\(address)?label=Shop(1)&amount=abc",
                     "Invoice dash:\(address)?label=Joe Shop&req-memo=hi", "Due:5 DASHdash:\(address)?req-amount=5",
                     "Pay (dash:\(address)?amount=1) or dash:\(address)?req-memo=hi",
                     "dash: \(address)?req-memo=hi", "pay: \(address)?req-memo=hi", "(pay: \(address)?req-memo=hi)",
                     "<pay: \(address)?req-memo=hi>", "\"pay: \(address)?req-memo=hi\"",
                     "Invoice (pay: \(address)?req-memo=hi)", "Invoice (pay: \(address)&req-memo=hi)",
                     "Invoice (pay: ?req-memo=hi&label=\(address))", "Invoice (pay: &label=\(address))",
                     "Invoice (pay: ?label=\(address))", "\u{201C}pay: \(address)?req-memo=hi\u{201D}", ".dash:\(address)?req-amount=5..",
                     "(bitcoin:\(address)?req-memo=1)"] {
            XCTAssertNil(SendViewModel.detect(in: text), text)
            XCTAssertTrue(ParsedPaymentURI.textMentionsPaymentLink(text), text)
            if let link = ParsedPaymentURI.soleLink(in: text) {
                XCTAssertFalse(ParsedPaymentURI.parse(paymentString: link).isValidDashPaymentIntent, text)
            }
        }

        // Read whole first: trimming does not make a refused link payable.
        let unpayable = "dash:\(address)?amount=1.5."
        XCTAssertFalse(ParsedPaymentURI.parse(paymentString: unpayable).isValidDashPaymentIntent)
        XCTAssertNil(SendViewModel.detect(in: unpayable))

        for text in ["(dash:\(address)?amount=1).", "dash:\(address)?amount=1", "<dash:\(address)>"] {
            XCTAssertNotNil(ParsedPaymentURI.soleLink(in: text), text)
            XCTAssertEqual(SendViewModel.detect(in: text)?.address, address, text)
        }
        XCTAssertNil(ParsedPaymentURI.soleLink(in: "Pay (dash:\(address)?amount=1)."))
        // A whole merchant request URL is fetched, never mined for an order reference.
        for request in ["https://merchant.example/pay?order=\(address)", "http://merchant.example/pay?order=\(address)"] {
            XCTAssertTrue(ParsedPaymentURI.textMentionsPaymentLink(request), request)
            XCTAssertNil(SendViewModel.detect(in: request), request)
        }
        XCTAssertEqual(SendViewModel.detect(in: "Send to \(address), thanks")?.address, address)
        for prose in ["Amount to pay: 1 DASH to \(address)", "Our site moved to https: see \(address)",
                      "Is this your address \(address)? Thanks", "Send to \(address) & thanks"] {
            XCTAssertFalse(ParsedPaymentURI.textMentionsPaymentLink(prose), prose)
            XCTAssertEqual(SendViewModel.detect(in: prose)?.address, address, prose)
        }

        // A merchant request is tried before its fallback address, so a passive
        // read offers neither.
        for text in ["dash:\(address)?r=https%3A%2F%2Fmerchant.example%2Fpr",
                     "dash:\(address)?amount=1&r=https://merchant.example/pr"] {
            XCTAssertTrue(ParsedPaymentURI.parse(paymentString: text).isValidDashPaymentIntent, text)
            XCTAssertNil(SendViewModel.detect(in: text), text)
        }
    }

    /// The receive QR a payer scans, center cutout and logo included, still
    /// decodes to its payload at the sizes the receive screen shows.
    func testTheReceiveQRStillDecodes() throws {
        let payload = "dash:\(Self.address)?amount=1.5"
        let raw = try XCTUnwrap(UIImage.dw_image(withQRCodeData: Data(payload.utf8), color: .black))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for amount: UInt64 in [0, 150_000_000] {
            let model = DWBaseReceiveModel(amount: amount)
            let shown = model.qrCodeImage(withRawQRImage: raw, hasAmount: amount > 0)
            let onWhite = UIGraphicsImageRenderer(size: shown.size).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: shown.size))
                shown.draw(at: .zero)
            }
            let cgImage = try XCTUnwrap(onWhite.cgImage)
            let decoded = detector.features(in: CIImage(cgImage: cgImage))
                .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(decoded, [payload], "amount \(amount)")
        }
    }

    /// DashSpend's checkout calls no app back, so one that requires it is
    /// refused before anything is authorized or fetched.
    func testDashSpendRefusesARequiredAppCallback() async {
        await assertDashSpendRefuses("dash:?r=https://merchant.example/r&req-sender=ctx")
    }

    /// DashSpend pays only a Dash merchant request: another currency's is
    /// refused before anything is authorized or fetched.
    func testDashSpendRefusesAForeignMerchantRequest() async {
        await assertDashSpendRefuses("bitcoin:?r=https://merchant.example/r")
    }

    private func assertDashSpendRefuses(_ url: String, line: UInt = #line) async {
        do {
            _ = try await SendCoinsService().payWithDashUrl(
                url: url,
                validate: { _ in XCTFail("checked a refused link", line: line) })
            XCTFail("paid", line: line)
        } catch DashSpendError.paymentProcessingError {
        } catch {
            XCTFail("\(error)", line: line)
        }
    }

    /// A rescan does not carry Max to the new recipient: the amount starts
    /// afresh, or takes the invoice's.
    func testRescanClearsMax() {
        let send = SendViewModel(contactLookup: { _ in nil })
        send.applyMax(duffs: 5_000_000)
        XCTAssertTrue(send.isMaxSelected)
        send.prefill(address: Self.address, amountDuffs: 0)
        XCTAssertFalse(send.isMaxSelected)
        XCTAssertEqual(send.dashDuffsUnsigned, 0)

        send.applyMax(duffs: 5_000_000)
        send.prefill(address: Self.address, amountDuffs: 150_000_000)
        XCTAssertFalse(send.isMaxSelected)
        XCTAssertEqual(send.dashDuffsUnsigned, 150_000_000)
    }

    /// Only Max takes the full-balance withdrawal, which pays whatever the
    /// balance is at submission; an amount that equals the quote is fixed.
    func testOnlyMaxSelectsTheFullPlatformWithdrawal() {
        XCTAssertTrue(SendViewModel.isFullPlatformWithdrawal(maxDuffs: 5_000, withdrawableDuffs: 5_000))
        XCTAssertFalse(SendViewModel.isFullPlatformWithdrawal(maxDuffs: nil, withdrawableDuffs: 5_000))
        XCTAssertFalse(SendViewModel.isFullPlatformWithdrawal(maxDuffs: 5_000, withdrawableDuffs: 6_000))
        XCTAssertFalse(SendViewModel.isFullPlatformWithdrawal(maxDuffs: nil, withdrawableDuffs: nil))
    }

    /// A pay link's recipient is a bare destination: one carrying URI syntax
    /// could hide fields the rewrite then replaces, so it is refused, opened
    /// or scanned.
    func testPayLinkRecipientWithURISyntaxIsRefused() throws {
        let single = "dashwallet://pay=\(Self.address)&amount=1&sender=ctx"
        XCTAssertNotNil(DWURLParser.action(for: try XCTUnwrap(URL(string: single))))
        XCTAssertNotNil(DWURLParser.paymentURL(forScannedLink: try XCTUnwrap(URL(string: single))))
        for pay in ["\(Self.address)%3Freq-memo%3Dhi", "\(Self.address)%3Famount%3D2", "dash%3A\(Self.address)",
                    "\(Self.address)%23x", "\(Self.address)%2Fx"] {
            let link = "dashwallet://pay=\(pay)&amount=1&sender=ctx"
            guard let url = URL(string: link) else { continue }
            XCTAssertNil(DWURLParser.action(for: url), link)
            XCTAssertNil(DWURLParser.paymentURL(forScannedLink: url), link)
            let (scanner, recorder) = makeScanner(.payment)
            scanner.didDetectCodes([link])
            XCTAssertTrue(recorder.results.isEmpty, link)
        }
    }

    /// An amount whose exponent overflows `Decimal` is no amount the wallet
    /// can pay, never an open amount.
    func testOverflowingURIAmountIsRefused() {
        for amount in ["1e300", "9e200", "1E999"] {
            let parsed = ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?amount=\(amount)")
            XCTAssertTrue(parsed.hasInvalidAmount, amount)
            XCTAssertFalse(parsed.isValidDashPaymentIntent, amount)
        }
        XCTAssertEqual(ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?amount=1e-9").amount, 1)
    }

    /// An invoice that requires an amount of nothing is refused, so a rescan
    /// can't keep the earlier invoice's amount for its recipient. A required
    /// amount always replaces the form's, even an empty one.
    func testRequiredZeroAmountIsRefused() {
        for code in ["dash:\(Self.address)?req-amount=0", "dash:\(Self.address)?req-amount=0.0"] {
            let parsed = ParsedPaymentURI.parse(paymentString: code)
            XCTAssertTrue(parsed.hasInvalidAmount, code)
            XCTAssertFalse(parsed.isValidDashPaymentIntent, code)
            let (scanner, recorder) = makeScanner(.payment)
            scanner.didDetectCodes([code])
            XCTAssertTrue(recorder.results.isEmpty, code)
            XCTAssertTrue(isInvalid(scanner.status), code)
        }
        XCTAssertFalse(ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?amount=0").hasInvalidAmount)

        let send = SendViewModel(contactLookup: { _ in nil })
        send.prefill(address: Self.address, amountDuffs: 100_000_000, requiresAmount: true)
        send.prefill(address: Self.platformAddress, amountDuffs: 0, requiresAmount: true)
        XCTAssertEqual(send.addressText, Self.platformAddress)
        XCTAssertEqual(send.dashDuffs, 0)
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
    /// address still is, and accepting it pays that address without a fetch.
    func testOfferNeedsAUsableRequestOrAPayableFallback() {
        let cleartext = "http%3A%2F%2Fmerchant.invalid%2Fpr"
        let (required, requiredRecorder) = makeScanner(.addressInput(expectsDashAddress: false))
        required.didDetectCodes(["dash:\(Self.address)?amount=1&req-r=\(cleartext)"])
        XCTAssertFalse(isOffer(required.status))
        XCTAssertTrue(isInvalid(required.status))
        XCTAssertTrue(requiredRecorder.results.isEmpty)

        let (optional, optionalRecorder) = makeScanner(.addressInput(expectsDashAddress: false))
        optional.didDetectCodes(["dash:\(Self.address)?amount=1&r=\(cleartext)"])
        XCTAssertTrue(isOffer(optional.status))

        optional.acceptOffer()
        if case .connecting = optional.status { XCTFail("the refused request is not fetched") }
        guard case .payment(let input) = optionalRecorder.results.first else {
            return XCTFail("an accepted offer pays the embedded address")
        }
        XCTAssertEqual(input.parsedURI?.address, Self.address)
        XCTAssertNil(input.parsedURI?.rURL)
    }

    /// A superseded payment's merchant answer is ignored: only the current
    /// payment can reach the delegate.
    func testProcessorIgnoresASupersededRequest() {
        let delegate = ProcessorDelegate()
        let processor = DWPaymentProcessor()
        processor.delegate = delegate
        func required(_ request: String) -> DWPaymentInput {
            let parsed = ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)?amount=1&req-r=\(request)")
            return DWPaymentInputBuilder().paymentInput(withParsedURI: parsed, source: .deepLink)
        }
        let failed = expectation(description: "the current request fails")
        failed.assertForOverFulfill = false
        var failures: [String?] = []
        delegate.onFailure = { failures.append(delegate.failure?.error?.localizedDescription); failed.fulfill() }

        // The stale request goes out to the network; its replacement is refused before any (it
        // names a requirement the wallet doesn't know), so the answer that arrives says whose it is.
        processor.processPaymentInput(required("https%3A%2F%2F127.0.0.1%3A1%2Fstale"))
        processor.reset()
        processor.processPaymentInput(required("https%3A%2F%2F127.0.0.1%3A1%2Fcurrent&req-foo=1"))

        wait(for: [failed], timeout: 40)
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        XCTAssertEqual(failures, [String(localized: "Invalid Payment Request", comment: "")],
                       "only the current request's answer is delivered")
        XCTAssertFalse(delegate.confirmed)
    }

    /// A pay link naming two recipients, in either order, is refused by both
    /// entry points; so is a refused pay link in any letter case, which is
    /// not reread as the plain alias.
    func testAmbiguousOrMixedCasePayLinkIsRefused() throws {
        let other = "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW"
        let single = "dashwallet://pay=\(Self.address)&amount=1&sender=ctx"
        XCTAssertNotNil(DWURLParser.action(for: try XCTUnwrap(URL(string: single))))
        for link in ["dashwallet://pay=\(Self.address)&pay=\(other)&amount=1&sender=ctx",
                     "dashwallet://pay=\(other)&amount=1&pay=\(Self.address)&sender=ctx",
                     "DashWallet://pay=\(Self.address)&amount=1&amount=2&sender=ctx",
                     "DASHWALLET://PAY=\(Self.address)&amount=1&amount=2&sender=ctx",
                     "dashwallet://pay=\(Self.address)&amount=1&amount=2@x",
                     "dashwallet://pay=\(Self.address)&amount=1&amount=2&sender=ctx&label=a b"] {
            if let url = URL(string: link) { XCTAssertNil(DWURLParser.action(for: url), link) }
            let parsed = ParsedPaymentURI.parse(paymentString: link)
            XCTAssertFalse(parsed.isValidDashPaymentIntent, link)
            XCTAssertNil(parsed.address, link)
            let (scanner, recorder) = makeScanner(.payment)
            scanner.didDetectCodes([link])
            XCTAssertTrue(recorder.results.isEmpty, link)
        }
    }

    /// A rescan into the same Send form takes the new invoice's required
    /// amount instead of keeping the first one's; an optional amount still
    /// leaves an entered one alone.
    func testRescannedInvoiceReplacesTheAmount() {
        let other = "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW"
        let send = SendViewModel(contactLookup: { _ in nil })
        let builder = DWPaymentInputBuilder()
        func ingest(_ code: String) {
            XCTAssertTrue(send.ingestScannedInput(
                builder.paymentInput(withParsedURI: ParsedPaymentURI.parse(paymentString: code), source: .scanQR)))
        }
        ingest("dash:\(Self.address)?req-amount=1")
        ingest("dash:\(other)?req-amount=2")
        XCTAssertEqual(send.addressText, other)
        XCTAssertEqual(send.dashDuffs, 200_000_000)

        ingest("dash:\(Self.address)?amount=3")
        XCTAssertEqual(send.dashDuffs, 200_000_000, "an optional amount is a hint")
    }

    /// An invoice's required amount is not dropped to fill an address field:
    /// it is offered to Send instead. An optional amount still unwraps.
    func testRequiredAmountInvoiceIsNotUnwrappedIntoAnAddressField() {
        let (invoice, invoiceRecorder) = makeScanner(.addressInput(expectsDashAddress: true))
        invoice.didDetectCodes(["dash:\(Self.address)?req-amount=1.5"])
        XCTAssertTrue(isOffer(invoice.status))
        XCTAssertTrue(invoiceRecorder.results.isEmpty)

        let (optional, optionalRecorder) = makeScanner(.addressInput(expectsDashAddress: true))
        optional.didDetectCodes(["dash:\(Self.address)?amount=1.5"])
        guard case .text(let address) = optionalRecorder.results.first else {
            return XCTFail("an optional amount still unwraps the address")
        }
        XCTAssertEqual(address, Self.address)
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
        guard case .invalid(_, let message) = scanner.status else {
            return XCTFail("a cleartext request is refused")
        }
        XCTAssertEqual(message, BIP70Error.insecureTransport.errorDescription, "the scanner says why")
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
            routed.prefill(address: Self.platformAddress, amountDuffs: parsed.amount, requiresAmount: parsed.requiresAmount)
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

    /// `DWBasePayViewController didScanPaymentInput:` sends a Platform
    /// destination to the Send screen and keeps a Core address on the
    /// classic processor.
    func testOnlyPlatformDestinationsRequireTheSendScreen() throws {
        let (scanner, recorder) = makeScanner(.payment)
        scanner.didDetectCodes(["dash:\(Self.platformAddress)?amount=1.5"])
        guard case .payment(let platformInput) = recorder.results.first else {
            return XCTFail("a Platform destination is a payment")
        }
        let platform = try XCTUnwrap(platformInput.parsedURI)
        XCTAssertTrue(platform.requiresSendScreenRouting)
        XCTAssertEqual(platform.amount, 150_000_000)

        XCTAssertFalse(ParsedPaymentURI.parse(paymentString: "dash:\(Self.address)").requiresSendScreenRouting)
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
        XCTAssertEqual(platform?.requiresSendScreenRouting, true)

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
