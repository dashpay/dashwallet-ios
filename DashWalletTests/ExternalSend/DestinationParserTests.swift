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
import SwiftDashSDK
import XCTest

/// The destination parser behind the Address screen, the scanner and dash: links
/// (AC-02, AC-04, AC-15): what a text is for the selected network, or why it is not valid.
final class DestinationParserTests: XCTestCase {
    private typealias Network = WalletEnvironment.NetworkKind

    // MARK: - Fixtures

    // Core: scriptPubKey -> Base58Check through the app's own `ScriptAddressCodec`, so every checksum is real.
    private static let hash20 = Data((1 ... 20).map { UInt8($0) })
    private static let p2pkhScript = Data([0x76, 0xa9, 0x14] + hash20 + [0x88, 0xac])
    private static let p2shScript = Data([0xa9, 0x14] + hash20 + [0x87])

    private func core(_ network: Network, script: Bool = false) -> String {
        let payment: PaymentNetwork = network == .mainnet ? .mainnet : .testnet
        let scriptPubKey = script ? Self.p2shScript : Self.p2pkhScript
        return fixture(ScriptAddressCodec.address(forScript: scriptPubKey, network: payment))
    }

    // Platform: DIP-0018 bech32m, HRP dash/tdash, payload = type byte (0xb0 P2PKH / 0x80 P2SH) + 20-byte hash,
    // through the SDK's `Bech32m.encode` (the encoder `SwiftDashSDKCoreLifecycleTests` uses for its fixtures).
    private func platform(_ network: Network, script: Bool = false, hash: UInt8 = 0x02) -> String {
        bech32(network, Data([script ? 0x80 : 0xb0] + Array(repeating: hash, count: 20)))
    }

    // Shielded: DIP-0018 display form, payload = 0x10 + 43 raw Orchard bytes
    // (the encoding `PaymentsLandingViewModel.reloadShieldedAddress` produces).
    private func shielded(_ network: Network, fill: UInt8 = 0x07) -> String {
        bech32(network, Data([0x10] + Array(repeating: fill, count: 43)))
    }

    private func bech32(_ network: Network, _ payload: Data) -> String {
        fixture(Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: network == .mainnet), data: payload))
    }

    // Identity ID: Base58 of 32 bytes, through `ScriptAddressCodec.base58Encode`.
    private func identityID(bytes: Int = 32) -> String {
        ScriptAddressCodec.base58Encode(Data((1 ... bytes).map { UInt8($0 * 3) }))
    }

    private func fixture(_ encoded: String?, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let encoded else {
            XCTFail("fixture encoder returned nil", file: file, line: line)
            return ""
        }
        return encoded
    }

    private func other(_ network: Network) -> Network { network == .mainnet ? .testnet : .mainnet }

    private func breakChecksum(_ text: String) -> String {
        var chars = Array(text)
        chars[chars.count - 1] = chars.last == "q" ? "p" : "q"
        return String(chars)
    }

    private func parse(_ text: String, _ network: Network) -> Result<Destination, DestinationParseError> {
        DestinationParser.parse(text, network: network)
    }

    private func assertParses(_ text: String, _ network: Network, as type: Destination.Kind, script: Bool = false,
                              file: StaticString = #filePath, line: UInt = #line) -> Destination? {
        switch parse(text, network) {
        case .success(let destination):
            XCTAssertEqual(destination.type, type, "\(text) on \(network)", file: file, line: line)
            XCTAssertEqual(destination.isScriptForm, script, "\(text) on \(network)", file: file, line: line)
            return destination
        case .failure(let error):
            XCTFail("\(text) on \(network) failed with \(error), expected \(type)", file: file, line: line)
            return nil
        }
    }

    private func assertFails(_ text: String, _ network: Network, with expected: DestinationParseError,
                             file: StaticString = #filePath, line: UInt = #line) {
        switch parse(text, network) {
        case .success(let destination):
            XCTFail("\(text) on \(network) parsed as \(destination.type), expected \(expected)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, "\(text) on \(network)", file: file, line: line)
        }
    }

    // MARK: - SendSource

    func testSendSourceHasTheFourSources() {
        XCTAssertEqual(Set(SendSource.allCases), [.core, .shielded, .platform, .identity])
    }

    // MARK: - Fixture sanity

    func testCoreFixtureMatchesTheKnownTestnetAddress() {
        XCTAssertEqual(core(.testnet).first, "y")
        XCTAssertEqual(core(.mainnet).first, "X")
        XCTAssertEqual(core(.mainnet, script: true).first, "7")
    }

    // MARK: - Each destination type, on both networks (AC-04, AC-15)

    func testEveryDestinationTypeOnEveryNetwork() {
        for network in [Network.mainnet, .testnet] {
            _ = assertParses(core(network), network, as: .coreAddress)
            _ = assertParses(platform(network), network, as: .platformAddress)
            _ = assertParses(shielded(network), network, as: .shieldedAddress)
            _ = assertParses(identityID(), network, as: .identityID)
        }
    }

    func testTheKnownTestnetCoreAddressParses() {
        _ = assertParses("ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr", .testnet, as: .coreAddress)
    }

    func testNormalizedTextIsTheAddressItself() {
        for network in [Network.mainnet, .testnet] {
            for text in [core(network), platform(network), shielded(network), identityID()] {
                XCTAssertEqual(try parse(text, network).get().text, text)
            }
        }
    }

    func testAPlainAddressCarriesNoLinkFields() throws {
        let destination = try parse(core(.testnet), .testnet).get()
        XCTAssertNil(destination.amountDuffs)
        XCTAssertNil(destination.label)
        XCTAssertNil(destination.message)
        XCTAssertNil(destination.paymentRequestURL)
    }

    // MARK: - Platform vs Shielded, judged by the whole string (AC-04)

    func testPlatformAndShieldedShareThePrefixButAreToldApart() {
        for network in [Network.mainnet, .testnet] {
            let platformText = platform(network)
            let shieldedText = shielded(network)
            XCTAssertEqual(platformText.prefix(5), shieldedText.prefix(5), "both start with the HRP")
            _ = assertParses(platformText, network, as: .platformAddress)
            _ = assertParses(shieldedText, network, as: .shieldedAddress)
        }
    }

    func testAPlatformTypeByteOnAShieldedLengthPayloadIsInvalid() {
        // Right HRP and checksum, but 44 bytes behind a Platform type byte: neither form.
        let text = bech32(.testnet, Data([0xb0] + Array(repeating: 0x07, count: 43)))
        assertFails(text, .testnet, with: .invalid)
    }

    func testAShieldedTypeByteOnAPlatformLengthPayloadIsInvalid() {
        let text = bech32(.testnet, Data([0x10] + Array(repeating: 0x02, count: 20)))
        assertFails(text, .testnet, with: .invalid)
    }

    func testAnUnknownPlatformTypeByteIsInvalid() {
        // 0x00 / 0x01 are storage bytes and never appear in a user-facing string.
        assertFails(bech32(.testnet, Data([0x00] + Array(repeating: 0x02, count: 20))), .testnet, with: .invalid)
    }

    // MARK: - Script forms

    func testScriptFormsAreFlagged() {
        for network in [Network.mainnet, .testnet] {
            _ = assertParses(core(network, script: true), network, as: .coreAddress, script: true)
            _ = assertParses(platform(network, script: true), network, as: .platformAddress, script: true)
            _ = assertParses(core(network), network, as: .coreAddress, script: false)
            _ = assertParses(platform(network), network, as: .platformAddress, script: false)
        }
    }

    // MARK: - Another network, a broken checksum, garbage (AC-02)

    func testAnotherNetworksAddressIsWrongNetwork() {
        for network in [Network.mainnet, .testnet] {
            let foreign = other(network)
            assertFails(core(foreign), network, with: .wrongNetwork)
            assertFails(core(foreign, script: true), network, with: .wrongNetwork)
            assertFails(platform(foreign), network, with: .wrongNetwork)
            assertFails(platform(foreign, script: true), network, with: .wrongNetwork)
            assertFails(shielded(foreign), network, with: .wrongNetwork)
        }
    }

    func testABrokenChecksumIsInvalid() {
        for network in [Network.mainnet, .testnet] {
            assertFails(breakChecksum(core(network)), network, with: .invalid)
            assertFails(breakChecksum(platform(network)), network, with: .invalid)
            assertFails(breakChecksum(shielded(network)), network, with: .invalid)
        }
    }

    func testTextThatIsNoDestinationIsInvalid() {
        for text in ["", "   ", "hello", "dash", "tdash1", "0x1234", "dash:", "https://example.com"] {
            assertFails(text, .mainnet, with: .invalid)
            assertFails(text, .testnet, with: .invalid)
        }
    }

    func testAnIdentityIDOfTheWrongLengthIsInvalid() {
        assertFails(identityID(bytes: 31), .testnet, with: .invalid)
        assertFails(identityID(bytes: 33), .testnet, with: .invalid)
    }

    // MARK: - Whitespace

    func testSurroundingWhitespaceIsTrimmed() throws {
        for network in [Network.mainnet, .testnet] {
            for text in [core(network), platform(network), shielded(network), identityID()] {
                let destination = try parse("  \n\t\(text) \r\n", network).get()
                XCTAssertEqual(destination.text, text)
            }
        }
    }

    // MARK: - dash: links (AC-15)

    func testAPlainLinkWithoutAnAmount() throws {
        let address = core(.testnet)
        let destination = try parse("dash:\(address)", .testnet).get()
        XCTAssertEqual(destination.type, .coreAddress)
        XCTAssertEqual(destination.text, address)
        XCTAssertNil(destination.amountDuffs)
        XCTAssertNil(destination.paymentRequestURL)
    }

    func testAPlainLinkWithAnAmountLabelAndMessage() throws {
        for network in [Network.mainnet, .testnet] {
            let address = core(network)
            let link = "dash:\(address)?amount=1.5&label=Coffee&message=Thanks"
            let destination = try parse(link, network).get()
            XCTAssertEqual(destination.type, .coreAddress)
            XCTAssertEqual(destination.text, address)
            XCTAssertEqual(destination.amountDuffs, 150_000_000)
            XCTAssertEqual(destination.label, "Coffee")
            XCTAssertEqual(destination.message, "Thanks")
            XCTAssertNil(destination.paymentRequestURL)
        }
    }

    func testALinkWithAPaymentRequestFlagsTheRequestURL() throws {
        let address = core(.testnet)
        let destination = try parse("dash:\(address)?amount=2&r=https://merchant.example/pay/abc", .testnet).get()
        XCTAssertEqual(destination.type, .coreAddress)
        XCTAssertEqual(destination.text, address)
        XCTAssertEqual(destination.paymentRequestURL, URL(string: "https://merchant.example/pay/abc"))
    }

    func testAnAddressLessPaymentRequestLinkIsAPaymentRequest() throws {
        for network in [Network.mainnet, .testnet] {
            let encoded = try parse("dash:?r=https%3A%2F%2Fmerchant.example%2Fpr", network).get()
            XCTAssertEqual(encoded.type, .paymentRequest)
            XCTAssertEqual(encoded.text, "")
            XCTAssertFalse(encoded.isScriptForm)
            XCTAssertEqual(encoded.paymentRequestURL, URL(string: "https://merchant.example/pr"))

            let link = "dash:?amount=2&label=Shop&message=Order&r=https://merchant.example/pr"
            let withFields = try parse(link, network).get()
            XCTAssertEqual(withFields.type, .paymentRequest)
            XCTAssertEqual(withFields.amountDuffs, 200_000_000)
            XCTAssertEqual(withFields.label, "Shop")
            XCTAssertEqual(withFields.message, "Order")
            XCTAssertEqual(withFields.paymentRequestURL, URL(string: "https://merchant.example/pr"))
        }
    }

    // MARK: - sender= (docs/adr/0007: only a link another app opened calls its sender back)

    func testALinkTheWalletReadItselfDropsItsSender() throws {
        let address = core(.testnet)
        let plain = try parse("dash:\(address)?amount=1&sender=merchantapp", .testnet).get()
        let request = try parse("dash:?r=https://merchant.example/pr&sender=merchantapp", .testnet).get()

        XCTAssertNil(plain.callbackScheme)
        XCTAssertNil(request.callbackScheme)
    }

    func testALinkAnotherAppOpenedKeepsItsSender() throws {
        let address = core(.testnet)
        let plain = try DestinationParser.parse(
            "dash:\(address)?amount=1&sender=merchantapp", network: .testnet, openedByApp: true).get()
        let request = try DestinationParser.parse(
            "dash:?r=https://merchant.example/pr&sender=merchantapp", network: .testnet, openedByApp: true).get()

        XCTAssertEqual(plain.callbackScheme, "merchantapp")
        XCTAssertEqual(request.callbackScheme, "merchantapp")
    }

    /// The pay-ack carries a Core txid, so only a Core link keeps its sender.
    func testAPlatformShieldedOrIdentityLinkAnotherAppOpenedKeepsNoSender() throws {
        for text in [platform(.testnet), shielded(.testnet), identityID()] {
            let link = "dash:\(text)?amount=1&sender=merchantapp"
            let opened = try DestinationParser.parse(link, network: .testnet, openedByApp: true).get()
            let readItself = try parse(link, .testnet).get()

            XCTAssertNil(opened.callbackScheme, text)
            XCTAssertNil(readItself.callbackScheme, text)
        }
    }

    func testAnAddressLessLinkWithAnEmptyOrInvalidRequestIsInvalid() {
        for network in [Network.mainnet, .testnet] {
            assertFails("dash:?r=", network, with: .invalid)
            assertFails("dash:?r=%20", network, with: .invalid)
            assertFails("dash:?amount=1", network, with: .invalid)
        }
    }

    // Payment requests made by Receive on Platform, Shielded and Identity (dashpay/dashwallet-ios#1383): the address
    // or the bare Identity ID, then `amount=` in DASH, as Android reads them (dashpay/dash-wallet#1677).

    func testAPlatformLinkWithAnAmountFillsTheAmount() throws {
        for network in [Network.mainnet, .testnet] {
            for script in [false, true] {
                let text = platform(network, script: script)
                let destination = try parse("dash:\(text)?amount=1.5", network).get()
                XCTAssertEqual(destination.type, .platformAddress)
                XCTAssertEqual(destination.text, text)
                XCTAssertEqual(destination.isScriptForm, script)
                XCTAssertEqual(destination.amountDuffs, 150_000_000)
                XCTAssertNil(destination.paymentRequestURL)
            }
        }
    }

    func testAShieldedLinkWithAnAmountFillsTheAmount() throws {
        for network in [Network.mainnet, .testnet] {
            let text = shielded(network)
            let destination = try parse("dash:\(text)?amount=0.25", network).get()
            XCTAssertEqual(destination.type, .shieldedAddress)
            XCTAssertEqual(destination.text, text)
            XCTAssertEqual(destination.amountDuffs, 25_000_000)
            XCTAssertNil(destination.paymentRequestURL)
        }
    }

    func testAnIdentityLinkWithAnAmountFillsTheAmount() throws {
        for network in [Network.mainnet, .testnet] {
            let id = identityID()
            let destination = try parse("dash:\(id)?amount=0.1", network).get()
            XCTAssertEqual(destination.type, .identityID)
            XCTAssertEqual(destination.text, id)
            XCTAssertEqual(destination.amountDuffs, 10_000_000)
            XCTAssertNil(destination.paymentRequestURL)
        }
    }

    func testAPlatformShieldedOrIdentityLinkKeepsLabelAndMessage() throws {
        let network = Network.testnet
        for text in [platform(network, script: false), shielded(network), identityID()] {
            let destination = try parse("dash:\(text)?amount=1&label=Coffee&message=Thanks", network).get()
            XCTAssertEqual(destination.label, "Coffee", text)
            XCTAssertEqual(destination.message, "Thanks", text)
            XCTAssertEqual(destination.amountDuffs, 100_000_000, text)
        }
    }

    func testAnIdentityLinkWithoutAnAmount() throws {
        let id = identityID()
        let destination = try parse("dash:\(id)", .testnet).get()
        XCTAssertEqual(destination.type, .identityID)
        XCTAssertEqual(destination.text, id)
        XCTAssertNil(destination.amountDuffs)
    }

    func testAPlatformShieldedOrIdentityLinkWithAPaymentRequestIsInvalid() {
        // A payment request is a Core merchant's; paying the link's own address would skip its verification.
        for tail in ["?amount=1&r=https://merchant.example/pr", "?req-r=https://merchant.example/pr",
                     "?r=ftp://merchant.example/pr"] {
            for text in [platform(.testnet), shielded(.testnet), identityID()] {
                assertFails("dash:\(text)\(tail)", .testnet, with: .invalid)
            }
        }
    }

    func testAPaymentRequestFieldCountsEvenWhenItsURLDoesNotParse() throws {
        // The field's presence, not its parsed URL, refuses a non-Core link: Foundation returns nil for these values.
        for tail in ["?r=https://[", "?amount=1&r=https%3A%2F%2F%5B", "?r=", "?r=not%20a%20url", "?req-label=x&r=http://a%20b"] {
            for text in [platform(.testnet), shielded(.testnet), identityID()] {
                assertFails("dash:\(text)\(tail)", .testnet, with: .invalid)
            }
        }
        // A Core link keeps develop's fallback to its own address.
        let address = core(.testnet)
        let destination = try parse("dash:\(address)?amount=1&r=https://[", .testnet).get()
        XCTAssertEqual(destination.type, .coreAddress)
        XCTAssertEqual(destination.text, address)
        XCTAssertNil(destination.paymentRequestURL)
    }

    /// O37: a required request is carried with the destination, so a failed fetch never pays the address instead.
    func testACoreLinkCarriesWhetherItsPaymentRequestIsRequired() throws {
        let request = "https://merchant.example/pr"
        XCTAssertTrue(try parse("dash:\(core(.testnet))?amount=1&req-r=\(request)", .testnet).get().isPaymentRequestRequired)
        XCTAssertTrue(try parse("dash:?req-r=\(request)", .testnet).get().isPaymentRequestRequired)
        XCTAssertFalse(try parse("dash:\(core(.testnet))?amount=1&r=\(request)", .testnet).get().isPaymentRequestRequired)
    }

    /// O40: a link split by a space is not offered by one of its words; a whole link inside text still is.
    func testFindNeverOffersAPartOfASplitLink() {
        let address = core(.testnet)
        for text in ["dash:\(address)?message=order one&req-amount=-1",
                     "dash:\(address)?label=Shop one&req-foo=1",
                     "dash:\(address) ?amount=-1",
                     "pay dash:\(address)?message=a b=c",
                     "dash:\(address)?message=order one two&req-amount=-1",
                     "Pay dash:\(address)?amount=1&message=order one two&req-r=https://merchant.example/pr"] {
            XCTAssertNil(DestinationParser.find(in: text, network: .testnet), text)
        }
        XCTAssertEqual(DestinationParser.find(in: "pay me at dash:\(address)?amount=1 thanks", network: .testnet)?
            .amountDuffs, 100_000_000)
        XCTAssertEqual(DestinationParser.find(in: "send to \(address) please", network: .testnet)?.text, address)
    }

    /// O74: the address of a link split from its scheme or its query is not offered on its own, and a link cut at
    /// the end of a line is not offered without the line that continues it.
    func testFindNeverOffersTheAddressOrTheHeadOfASplitLink() {
        let address = core(.testnet)
        for text in ["dash: \(address) ?req-amount=-1",
                     "dash:\n\(address)\n?amount=1&req-r=https://merchant.example/pr",
                     "dash: \(address) amount=1&req-r=https://merchant.example/pr",
                     "dash:\(address)?amount=1&\nreq-r=https://merchant.example/pr",
                     "dash:\(address)?amount=1\nreq-r=https://merchant.example/pr",
                     "\(address)\n&req-amount=-1"] {
            XCTAssertNil(DestinationParser.find(in: text, network: .testnet), text)
        }
    }

    /// O74: a continuing word elsewhere in the text, after an unrelated line, does not hide a complete link, and an
    /// address in prose next to a `key=value` word is still an address.
    func testFindOffersACompleteLinkDespiteUnrelatedFieldsElsewhere() {
        let address = core(.testnet)
        let link = DestinationParser.find(in: "Pay dash:\(address)?amount=1\nthanks\nOrder=42", network: .testnet)
        XCTAssertEqual(link?.amountDuffs, 100_000_000)
        XCTAssertEqual(DestinationParser.find(in: "send to \(address) ref=42", network: .testnet)?.text, address)
        XCTAssertEqual(DestinationParser.find(in: "Address: \(address) memo=1", network: .testnet)?.text, address,
                       "a label ending in a colon is not a payment scheme")
    }

    /// The clipboard's words are scanned once: a long text of colon-bearing words is not checked against every word
    /// after each of them.
    func testFindScansALongTextOfColonWordsInLinearTime() {
        let address = core(.testnet)
        let text = String(repeating: "a: ", count: 40000) + address
        measure {
            XCTAssertEqual(DestinationParser.find(in: text, network: .testnet)?.text, address)
        }
    }

    func testALinkWithMoreThanOnePaymentRequestIsInvalid() {
        let request = "https://merchant.example/pr"
        for tails in [["r=\(request)", "r=https://["], ["r=https://[", "r=\(request)"],
                      ["r=\(request)", "req-r=\(request)"], ["r=\(request)", "r=https://other.example/pr"]] {
            let query = tails.joined(separator: "&")
            for text in ["", core(.testnet), platform(.testnet), shielded(.testnet), identityID()] {
                assertFails("dash:\(text)?\(query)", .testnet, with: .invalid)
            }
        }
    }

    // MARK: - One Platform-address decoder (the transfer boundary reads it too)

    @MainActor
    func testTheTransferBoundaryRefusesAMixedCasePlatformAddress() {
        let lower = platform(.testnet)
        let mixed = lower.prefix(8).uppercased() + lower.dropFirst(8)
        XCTAssertNil(PlatformAddressSyncCoordinator.parsePlatformRecipient(bech32m: mixed))
        assertFails(mixed, .testnet, with: .invalid)
    }

    @MainActor
    func testTheTransferBoundaryReadsLowerAndUpperCaseAlike() throws {
        for network in [Network.mainnet, .testnet] {
            for script in [false, true] {
                let lower = platform(network, script: script, hash: 0x05)
                for text in [lower, lower.uppercased()] {
                    let recipient = try XCTUnwrap(PlatformAddressSyncCoordinator.parsePlatformRecipient(bech32m: text))
                    XCTAssertEqual(recipient.ffiAddressType, script ? 1 : 0, text)
                    XCTAssertEqual(recipient.hash, Data(repeating: 0x05, count: 20), text)
                }
            }
        }
    }

    @MainActor
    func testTheTransferBoundaryRefusesAShieldedAddress() {
        XCTAssertNil(PlatformAddressSyncCoordinator.parsePlatformRecipient(bech32m: shielded(.testnet)))
    }

    func testACoreLinkWithANonHTTPPaymentRequestPaysItsAddress() throws {
        // As on develop: a request that cannot be fetched falls back to the link's own Core address.
        let address = core(.testnet)
        let destination = try parse("dash:\(address)?amount=1&r=ftp://merchant.example/pr", .testnet).get()
        XCTAssertEqual(destination.type, .coreAddress)
        XCTAssertEqual(destination.text, address)
        XCTAssertNil(destination.paymentRequestURL)
    }

    func testALinkWithAnInvalidAmountIsInvalidForEveryDestination() {
        for amount in ["-1", "abc", "1e30", "184467440738", ""] {
            for text in [core(.testnet), platform(.testnet), shielded(.testnet), identityID()] {
                assertFails("dash:\(text)?amount=\(amount)", .testnet, with: .invalid)
                assertFails("dash:\(text)?req-amount=\(amount)", .testnet, with: .invalid)
            }
            // O73: beside a payment request the merchant's request decides the amount, and becomes required.
            assertTheRequestDecidesTheAmount("dash:?r=https://merchant.example/pr&amount=\(amount)")
            assertFails("dash:?r=https://merchant.example/pr&req-amount=\(amount)", .testnet, with: .invalid)
        }
    }

    private func assertTheRequestDecidesTheAmount(_ link: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .success(let destination) = parse(link, .testnet) else {
            return XCTFail("\(link) is invalid", file: file, line: line)
        }
        XCTAssertEqual(destination.type, .paymentRequest, link, file: file, line: line)
        XCTAssertTrue(destination.isPaymentRequestRequired, link, file: file, line: line)
        XCTAssertNil(destination.amountDuffs, link, file: file, line: line)
    }

    func testALinkWhoseAmountDoesNotParseWhollyIsInvalid() {
        for amount in ["1abc", "1,5", "1.2.3", "1e", "+1", "0x10", "1%20", "."] {
            for text in [core(.testnet), platform(.testnet), shielded(.testnet), identityID()] {
                assertFails("dash:\(text)?amount=\(amount)", .testnet, with: .invalid)
            }
        }
    }

    /// Two different amounts, or an invalid one next to a valid one, leave the amount open; the same amount twice is
    /// that amount (O53).
    func testALinkWithMoreThanOneAmountIsInvalid() {
        let queries = ["req-amount=-1&amount=1", "amount=1&req-amount=-1", "amount=1&amount=2", "amount=1&req-amount=2"]
        for query in queries {
            for text in [core(.testnet), platform(.testnet), shielded(.testnet), identityID()] {
                assertFails("dash:\(text)?\(query)", .testnet, with: .invalid)
            }
            let request = "dash:?r=https://merchant.example/pr&\(query)"
            if query.contains("req-amount") {
                assertFails(request, .testnet, with: .invalid)
            } else {
                assertTheRequestDecidesTheAmount(request)
            }
        }
    }

    func testAPlainDecimalAmountIsAccepted() throws {
        XCTAssertEqual(try parse("dash:\(core(.testnet))?amount=.5", .testnet).get().amountDuffs, 50_000_000)
        XCTAssertEqual(try parse("dash:\(core(.testnet))?amount=2.", .testnet).get().amountDuffs, 200_000_000)
        XCTAssertEqual(try parse("dash:\(core(.testnet))?amount=0.00000001", .testnet).get().amountDuffs, 1)
    }

    func testALinkRequiringAFieldTheDestinationDropsIsInvalid() {
        for field in ["req-user=alice", "req-currency=USD", "req-local=10"] {
            for text in [core(.testnet), platform(.testnet), shielded(.testnet), identityID()] {
                assertFails("dash:\(text)?amount=1&\(field)", .testnet, with: .invalid)
            }
            assertFails("dash:?r=https://merchant.example/pr&\(field)", .testnet, with: .invalid)
        }
    }

    func testACoreLinkRequiringAnUnusablePaymentRequestIsInvalid() {
        for request in ["ftp://merchant.example/pr", "https://", "", "not a url"] {
            assertFails("dash:\(core(.testnet))?amount=1&req-r=\(request)", .testnet, with: .invalid)
        }
    }

    func testACoreLinkRequiringAUsablePaymentRequestKeepsIt() throws {
        let destination = try DestinationParser.parse(
            "dash:\(core(.testnet))?amount=1&req-r=https://merchant.example/pr&req-sender=myapp", network: .testnet,
            openedByApp: true).get()
        XCTAssertEqual(destination.paymentRequestURL?.absoluteString, "https://merchant.example/pr")
        XCTAssertEqual(destination.callbackScheme, "myapp")
    }

    /// O56: a link naming two different apps to call back is refused in either field order; the same app twice is
    /// that app.
    func testALinkWithTwoDifferentCallbacksIsInvalid() throws {
        for query in ["req-sender=myapp&sender=other", "sender=other&req-sender=myapp", "sender=myapp&sender=other"] {
            XCTAssertThrowsError(try DestinationParser.parse(
                "dash:\(core(.testnet))?amount=1&\(query)", network: .testnet, openedByApp: true).get(), query)
        }
        let same = try DestinationParser.parse(
            "dash:\(core(.testnet))?amount=1&sender=myapp&req-sender=myapp", network: .testnet, openedByApp: true).get()
        XCTAssertEqual(same.callbackScheme, "myapp")
    }

    /// O71: a Base58 address with a valid checksum and a version no Dash network uses is not a Dash address, not an
    /// address of another network; another Dash network's address is still the wrong network.
    func testABase58AddressOfAnotherCoinIsInvalidNotTheWrongNetwork() {
        assertFails("1111111111111111111114oLvT2", .testnet, with: .invalid)
        assertFails("1111111111111111111114oLvT2", .mainnet, with: .invalid)
        assertFails(core(.mainnet), .testnet, with: .wrongNetwork)
        assertFails(core(.testnet), .mainnet, with: .wrongNetwork)
    }

    /// O53: a repeated equal amount is the link's amount; different amounts make the link invalid.
    func testARepeatedAmountIsKeptOnlyWhenEqual() throws {
        let repeated = try DestinationParser.parse("dash:\(core(.testnet))?amount=1&amount=1", network: .testnet).get()
        XCTAssertEqual(repeated.amountDuffs, 100_000_000)
        assertFails("dash:\(core(.testnet))?amount=1&amount=2", .testnet, with: .invalid)
    }

    /// A required callback is honored or the link is refused: the pay-ack goes only to a Core payment another app
    /// opened, with a scheme an app can own.
    func testALinkRequiringACallbackItCannotMakeIsInvalid() {
        for text in [platform(.testnet), shielded(.testnet), identityID()] {
            XCTAssertThrowsError(try DestinationParser.parse(
                "dash:\(text)?amount=1&req-sender=myapp", network: .testnet, openedByApp: true).get(), text)
        }
        for link in ["dash:\(core(.testnet))?amount=1&req-sender=myapp",
                     "dash:?r=https://merchant.example/pr&req-sender=myapp"] {
            assertFails(link, .testnet, with: .invalid)
        }
        for scheme in ["", "http", "not a scheme"] {
            XCTAssertThrowsError(try DestinationParser.parse(
                "dash:\(core(.testnet))?amount=1&req-sender=\(scheme)", network: .testnet, openedByApp: true).get(),
                scheme)
        }
    }

    /// O75: the requirement travels with the destination, so route selection can keep it.
    func testARequiredCallbackIsCarriedAndAnOptionalOneIsNot() throws {
        let required = try DestinationParser.parse(
            "dash:\(core(.testnet))?amount=1&req-sender=myapp", network: .testnet, openedByApp: true).get()
        let optional = try DestinationParser.parse(
            "dash:\(core(.testnet))?amount=1&sender=myapp", network: .testnet, openedByApp: true).get()
        XCTAssertTrue(required.isCallbackRequired)
        XCTAssertFalse(optional.isCallbackRequired)
    }

    /// O76: URL schemes are case-insensitive, so the same app spelled in two cases is one callback.
    func testCallbacksDifferingOnlyInCaseAreOneCallback() throws {
        for query in ["sender=ShopApp&req-sender=shopapp", "req-sender=shopapp&sender=ShopApp"] {
            let destination = try DestinationParser.parse(
                "dash:\(core(.testnet))?amount=1&\(query)", network: .testnet, openedByApp: true).get()
            XCTAssertEqual(destination.callbackScheme?.lowercased(), "shopapp", query)
        }
    }

    /// O77: a required label or message given again with a different value leaves the required text open; equal
    /// repeats and two optional values (the last is kept) still stand.
    func testARequiredLabelOrMessageGivenTwiceDifferentlyIsInvalid() throws {
        for field in ["label", "message"] {
            for query in ["req-\(field)=Invoice%2042&\(field)=Personal", "\(field)=Personal&req-\(field)=Invoice%2042",
                          "req-\(field)=Invoice%2042&req-\(field)=Personal",
                          "\(field)=Personal&\(field)=Invoice%2042&req-\(field)=Invoice%2042"] {
                assertFails("dash:\(core(.testnet))?amount=1&\(query)", .testnet, with: .invalid)
            }
            let same = try parse("dash:\(core(.testnet))?req-\(field)=Invoice&\(field)=Invoice", .testnet).get()
            XCTAssertEqual(field == "label" ? same.label : same.message, "Invoice")
            let optional = try parse("dash:\(core(.testnet))?\(field)=One&\(field)=Two", .testnet).get()
            XCTAssertEqual(field == "label" ? optional.label : optional.message, "Two")
        }
    }

    /// O73: a malformed optional amount beside a payment request that can be fetched leaves the amount to the
    /// merchant: the request is kept and required, so a failed fetch never pays the address. A malformed required
    /// amount, or one with no request to decide it, still makes the link invalid.
    func testAMalformedOptionalAmountBesideAPaymentRequestKeepsTheRequestAndRequiresIt() throws {
        for amount in ["amount=abc", "amount=1&amount=2"] {
            let link = try parse("dash:\(core(.testnet))?\(amount)&r=https://merchant.example/pr", .testnet).get()
            XCTAssertEqual(link.paymentRequestURL?.absoluteString, "https://merchant.example/pr", amount)
            XCTAssertTrue(link.isPaymentRequestRequired, amount)
            XCTAssertNil(link.amountDuffs, amount)
            let addressLess = try parse("dash:?\(amount)&r=https://merchant.example/pr", .testnet).get()
            XCTAssertEqual(addressLess.type, .paymentRequest, amount)
        }
        assertFails("dash:\(core(.testnet))?req-amount=abc&r=https://merchant.example/pr", .testnet, with: .invalid)
        assertFails("dash:\(core(.testnet))?amount=abc&r=ftp://merchant.example/pr", .testnet, with: .invalid)
        assertFails("dash:\(core(.testnet))?amount=abc", .testnet, with: .invalid)
    }

    /// O74: a query broken across lines or words cannot be read whole, so the link is not paid without what follows
    /// the break; a raw space inside a value is still read.
    func testALinkWhoseQueryIsBrokenAcrossLinesOrWordsIsInvalid() throws {
        let address = core(.testnet)
        for link in ["dash:\(address)?amount=1&\nreq-r=https://merchant.example/pr",
                     "dash:\(address)?amount=1&label=a\nreq-r=https://merchant.example/pr",
                     "dash:\(address)?amount=1& req-r=https://merchant.example/pr",
                     "dash:\(address)?amount=1&\treq-r=https://merchant.example/pr"] {
            assertFails(link, .testnet, with: .invalid)
        }
        XCTAssertEqual(try parse("dash:\(address)?label=Coffee Shop&amount=1", .testnet).get().label, "Coffee Shop")
    }

    func testALinkRequiringACallbackItCanMakeKeepsIt() throws {
        for link in ["dash:\(core(.testnet))?amount=1&req-sender=myapp",
                     "dash:?r=https://merchant.example/pr&req-sender=myapp"] {
            let destination = try DestinationParser.parse(link, network: .testnet, openedByApp: true).get()
            XCTAssertEqual(destination.callbackScheme, "myapp", link)
        }
    }

    func testAnAmountBeyondDecimalRangeIsInvalid() {
        let amounts = ["1" + String(repeating: "0", count: 160), "1e160", String(repeating: "9", count: 38) + "e130"]
        for amount in amounts {
            assertFails("dash:\(core(.testnet))?amount=\(amount)", .testnet, with: .invalid)
        }
    }

    /// A long digit run that fails at its end is refused at once, never matched in quadratic time.
    func testAVeryLongAmountIsRefusedQuickly() {
        let amount = String(repeating: "1", count: 20_000) + "x"
        measure {
            assertFails("dash:\(core(.testnet))?amount=\(amount)", .testnet, with: .invalid)
            assertFails("dash:\(core(.testnet))?amount=\(String(repeating: "1", count: 20_000))", .testnet,
                        with: .invalid)
        }
    }

    func testALinkWithTheLargestAmountThatFitsIsAccepted() throws {
        // UInt64.max duffs is 184467440737.09551615 DASH; the largest whole-duff amount below it fits.
        let destination = try parse("dash:\(core(.testnet))?amount=184467440737.09551615", .testnet).get()
        XCTAssertEqual(destination.amountDuffs, UInt64.max)
    }

    func testALinkWithAnUnknownRequiredFieldIsInvalidForEveryDestination() {
        for text in [core(.testnet), platform(.testnet), shielded(.testnet), identityID()] {
            assertFails("dash:\(text)?req-foo=1", .testnet, with: .invalid)
            assertFails("dash:\(text)?amount=1&req-somethingnew=x", .testnet, with: .invalid)
        }
        assertFails("dash:?r=https://merchant.example/pr&req-foo=1", .testnet, with: .invalid)
    }

    func testALinkWithKnownRequiredFieldsIsAccepted() throws {
        let destination = try parse(
            "dash:\(core(.testnet))?req-amount=1&req-label=Shop&req-message=Hi", .testnet).get()
        XCTAssertEqual(destination.amountDuffs, 100_000_000)
        XCTAssertEqual(destination.label, "Shop")
        XCTAssertEqual(destination.message, "Hi")
    }

    func testALinkWhoseAddressIsAPaymentRequestIsInvalid() {
        for network in [Network.mainnet, .testnet] {
            assertFails("dash:https://merchant.example/pr?amount=1", network, with: .invalid)
            assertFails("dash:dash:?r=https://merchant.example/pr", network, with: .invalid)
        }
    }

    func testAPlatformOrShieldedLinkOfAnotherNetworkIsWrongNetworkWithAnAmount() {
        for network in [Network.mainnet, .testnet] {
            let foreign = other(network)
            assertFails("dash:\(platform(foreign))?amount=1", network, with: .wrongNetwork)
            assertFails("dash:\(shielded(foreign))?amount=1", network, with: .wrongNetwork)
        }
    }

    func testALinkWithAnotherNetworksAddressIsWrongNetwork() {
        assertFails("dash:\(core(.mainnet))?amount=1", .testnet, with: .wrongNetwork)
        assertFails("dash:\(core(.testnet))?amount=1", .mainnet, with: .wrongNetwork)
        assertFails("dash:\(platform(.mainnet))", .testnet, with: .wrongNetwork)
    }

    func testALinkWithABrokenAddressIsInvalid() {
        assertFails("dash:\(breakChecksum(core(.testnet)))?amount=1", .testnet, with: .invalid)
    }

    // MARK: - find(in:) for the clipboard

    func testFindReturnsTheDestinationInsideSurroundingText() {
        for network in [Network.mainnet, .testnet] {
            for (text, type) in [(core(network), Destination.Kind.coreAddress),
                                 (platform(network), .platformAddress),
                                 (shielded(network), .shieldedAddress),
                                 (identityID(), .identityID)] {
                let found = DestinationParser.find(in: "pay me here:\n\(text)\nthanks", network: network)
                XCTAssertEqual(found?.type, type)
                XCTAssertEqual(found?.text, text)
            }
        }
    }

    func testFindReturnsTheWholeClipboardWhenItIsADestination() {
        let address = core(.testnet)
        XCTAssertEqual(DestinationParser.find(in: "  \(address)\n", network: .testnet)?.text, address)
    }

    func testFindReturnsTheFirstDestinationTheParserAccepts() {
        let first = platform(.testnet)
        let clipboard = "\(core(.mainnet)) then \(first) and \(core(.testnet))"
        let found = DestinationParser.find(in: clipboard, network: .testnet)
        XCTAssertEqual(found?.text, first, "another network's address is skipped, the first accepted one wins")
    }

    func testFindAcceptsAnAddressLessPaymentRequestLink() {
        let found = DestinationParser.find(in: "pay: dash:?r=https%3A%2F%2Fmerchant.example%2Fpr", network: .testnet)
        XCTAssertEqual(found?.type, .paymentRequest)
        XCTAssertEqual(found?.paymentRequestURL, URL(string: "https://merchant.example/pr"))
    }

    func testFindReturnsNoneWhenThereIsNoDestination() {
        XCTAssertNil(DestinationParser.find(in: "", network: .testnet))
        XCTAssertNil(DestinationParser.find(in: "just some text, no address", network: .testnet))
        XCTAssertNil(DestinationParser.find(in: core(.mainnet), network: .testnet))
        XCTAssertNil(DestinationParser.find(in: breakChecksum(platform(.testnet)), network: .testnet))
    }

    // MARK: - NFR: destination type in well under 300 ms, format only
    // Timed with `measure`, which records the time without a bound: a bound on the wall clock fails whenever the
    // runner pauses the process, so these tests check the result and the budget is read from the performance run.

    func testParsingOneAddressStaysWellUnderTheBudget() {
        let texts = [Network.mainnet, .testnet].flatMap { network in
            [core(network), platform(network), shielded(network), identityID()].map { ($0, network) }
        }
        measure {
            for (text, network) in texts {
                XCTAssertNotNil(try? parse(text, network).get(), "\(text) on \(network)")
            }
        }
    }

    // Base58 decoding is quadratic in the input length, so a long word must be refused by its length first.
    private static let longBase58Word = String(repeating: "2", count: 20_000)

    func testALongBase58WordIsRefusedWithinTheBudget() {
        measure {
            XCTAssertNil(try? parse(Self.longBase58Word, .testnet).get())
        }
    }

    func testFindSkipsLongWordsWithinTheBudgetAndStillFindsTheAddress() {
        let address = core(.testnet)
        let clipboard = "\(Self.longBase58Word) \(Self.longBase58Word)\n\(address)"
        measure {
            XCTAssertEqual(DestinationParser.find(in: clipboard, network: .testnet)?.text, address)
        }
    }

    func testAOneMegabyteClipboardFindsNothingWithinTheBudget() {
        let clipboard = String(repeating: "2", count: 1_000_000)
        measure {
            XCTAssertNil(DestinationParser.find(in: clipboard, network: .testnet))
        }
    }

    // MARK: - Bech32m length bound

    func testTheBech32mBoundIsTheLongestShieldedAddressTheCodecWrites() {
        let longest = fixture(Bech32m.encode(hrp: Bech32m.platformHrpTestnet,
                                             data: Data([0x10] + Array(repeating: 0xff, count: 43))))
        XCTAssertEqual(DashAddressClassifier.maxBech32mLength, longest.utf8.count)
        XCTAssertGreaterThanOrEqual(DashAddressClassifier.maxBech32mLength, shielded(.mainnet).utf8.count)
    }

    func testAHundredKilobyteBech32mTextNeverReachesTheDecoder() {
        let long = fixture(Bech32m.encode(hrp: Bech32m.platformHrpTestnet, data: Data(count: 64_000)))
        XCTAssertGreaterThan(long.utf8.count, 100_000)

        var decodes = 0
        let decoded = DashAddressClassifier.decodeBech32m(long) { text in
            decodes += 1
            return Bech32m.decode(text)
        }

        XCTAssertNil(decoded)
        XCTAssertEqual(decodes, 0)
        XCTAssertEqual(parse(long, .testnet), .failure(.invalid))
    }

    func testANonASCIIBech32mTextIsRefusedWithoutReachingTheDecoder() {
        let text = "é1qqqqqq"

        var decodes = 0
        let decoded = DashAddressClassifier.decodeBech32m(text) { text in
            decodes += 1
            return Bech32m.decode(text)
        }

        XCTAssertNil(decoded)
        XCTAssertEqual(decodes, 0)
        XCTAssertNil(DashAddressClassifier.decodeBech32m(text))
        XCTAssertEqual(parse(text, .testnet), .failure(.invalid))
        XCTAssertEqual(parse(text, .mainnet), .failure(.invalid))
    }

    func testTheLongestShieldedAndAPlatformAddressStillReachTheDecoder() {
        for network in [Network.mainnet, .testnet] {
            for text in [shielded(network), platform(network)] {
                var decodes = 0
                let decoded = DashAddressClassifier.decodeBech32m(text) { text in
                    decodes += 1
                    return Bech32m.decode(text)
                }
                XCTAssertNotNil(decoded, text)
                XCTAssertEqual(decodes, 1, text)
            }
        }
    }

    func testAnUpperCaseShieldedOrPlatformAddressStillParses() throws {
        for network in [Network.mainnet, .testnet] {
            XCTAssertEqual(try parse(shielded(network).uppercased(), network).get().type, .shieldedAddress)
            XCTAssertEqual(try parse(platform(network).uppercased(), network).get().type, .platformAddress)
        }
    }

    /// Bech32m is one case or the other (BIP-173); a mixed-case text is not an address, even when its lowercase
    /// form is one.
    func testAMixedCaseShieldedOrPlatformAddressIsRefused() throws {
        for network in [Network.mainnet, .testnet] {
            for text in [shielded(network), platform(network)] {
                let separator = try XCTUnwrap(text.lastIndex(of: "1"))
                let mixed = text[..<separator].uppercased() + text[separator...]
                XCTAssertNil(DashAddressClassifier.decodeBech32m(mixed), mixed)
                XCTAssertEqual(parse(mixed, network), .failure(.invalid), mixed)
            }
        }
    }

    func testFindStillFindsAShieldedAddressInsideALongClipboard() {
        let address = shielded(.testnet)
        let clipboard = String(repeating: "lorem ipsum ", count: 10_000) + address
        XCTAssertEqual(DestinationParser.find(in: clipboard, network: .testnet)?.text, address)
    }
}
