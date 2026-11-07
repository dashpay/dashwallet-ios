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
                             locked: @escaping @MainActor () -> Bool = { false }) -> (QRScannerViewModel, Recorder) {
        let recorder = Recorder()
        let viewModel = QRScannerViewModel(mode: mode, isWalletLocked: locked)
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
