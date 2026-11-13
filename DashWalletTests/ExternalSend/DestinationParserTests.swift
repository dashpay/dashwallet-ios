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

    func testAPlatformShieldedOrIdentityLinkCarriesNoPaymentRequest() throws {
        let tail = "?amount=1&r=https://merchant.example/pr"
        for text in [platform(.testnet), shielded(.testnet), identityID()] {
            let destination = try parse("dash:\(text)\(tail)", .testnet).get()
            XCTAssertEqual(destination.amountDuffs, 100_000_000)
            XCTAssertNil(destination.paymentRequestURL, "only a Core link has a payment request to fall back from")
        }
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

    func testParsingOneAddressStaysWellUnderTheBudget() {
        let clock = ContinuousClock()
        for network in [Network.mainnet, .testnet] {
            for text in [core(network), platform(network), shielded(network), identityID()] {
                let elapsed = clock.measure { _ = parse(text, network) }
                XCTAssertLessThan(elapsed, .milliseconds(100), "\(text) on \(network)")
            }
        }
    }

    // Base58 decoding is quadratic in the input length, so a long word must be refused by its length first.
    private static let longBase58Word = String(repeating: "2", count: 20_000)

    func testALongBase58WordIsRefusedWithinTheBudget() {
        let clock = ContinuousClock()
        var result: Result<Destination, DestinationParseError>?
        let elapsed = clock.measure { result = parse(Self.longBase58Word, .testnet) }
        XCTAssertNil(result.flatMap { try? $0.get() })
        XCTAssertLessThan(elapsed, .milliseconds(100))
    }

    func testFindSkipsLongWordsWithinTheBudgetAndStillFindsTheAddress() {
        let address = core(.testnet)
        let clipboard = "\(Self.longBase58Word) \(Self.longBase58Word)\n\(address)"
        let clock = ContinuousClock()
        var found: Destination?
        let elapsed = clock.measure { found = DestinationParser.find(in: clipboard, network: .testnet) }
        XCTAssertEqual(found?.text, address)
        XCTAssertLessThan(elapsed, .milliseconds(100))
    }

    func testAOneMegabyteClipboardFindsNothingWithinTheBudget() {
        let clipboard = String(repeating: "2", count: 1_000_000)
        let clock = ContinuousClock()
        var found: Destination?
        let elapsed = clock.measure { found = DestinationParser.find(in: clipboard, network: .testnet) }
        XCTAssertNil(found)
        XCTAssertLessThan(elapsed, .milliseconds(300))
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

    func testFindStillFindsAShieldedAddressInsideALongClipboard() {
        let address = shielded(.testnet)
        let clipboard = String(repeating: "lorem ipsum ", count: 10_000) + address
        XCTAssertEqual(DestinationParser.find(in: clipboard, network: .testnet)?.text, address)
    }
}
