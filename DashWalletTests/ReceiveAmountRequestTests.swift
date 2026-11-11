//
//  ReceiveAmountRequestTests.swift
//  DashWalletTests
//
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

import SwiftDashSDK
import XCTest
@testable import dashpay

/// Specify amount on Shielded, Platform and Identity: the request is
/// `dash:<address-or-ID>?amount=<DASH>`, the amount formatted exactly as Core's.
@MainActor
final class ReceiveAmountRequestTests: XCTestCase {

    // MARK: Fixtures

    private static let platformMainnet = "dash1krma5z3ttj75la4m93xcndna9ullamq9y5e9n5rs"
    private static let platformTestnet = "tdash1krma5z3ttj75la4m93xcndna9ullamq9y5fzq2j7"

    /// DIP-0018 shielded display form: `0x10` + 43 raw Orchard bytes.
    private static func shielded(hrp: String) throws -> String {
        let payload = Data([0x10]) + Data((0..<43).map { UInt8($0 * 5) })
        return try XCTUnwrap(Bech32m.encode(hrp: hrp, data: payload))
    }

    private static let identityId = Data((1...32).map { UInt8($0) })
    private static var identityIdBase58: String { ScriptAddressCodec.base58Encode(identityId) }

    private func request(_ address: String, _ duffs: UInt64,
                         option: ReceiveOption = .platform) -> OptionAmountRequestModel {
        OptionAmountRequestModel(address: address, amount: duffs, option: option)
    }

    // MARK: Payload per option

    func testPlatformPayloadMainnetAndTestnet() {
        XCTAssertEqual(request(Self.platformMainnet, 1_234_567_890).paymentAddressOrRequestToShare(),
                       "dash:\(Self.platformMainnet)?amount=12.3456789")
        XCTAssertEqual(request(Self.platformTestnet, 1_234_567_890).paymentAddressOrRequestToShare(),
                       "dash:\(Self.platformTestnet)?amount=12.3456789")
    }

    func testShieldedPayloadMainnetAndTestnet() throws {
        for hrp in ["dash", "tdash"] {
            let address = try Self.shielded(hrp: hrp)
            XCTAssertEqual(request(address, 25_000_000, option: .shielded).paymentAddressOrRequestToShare(),
                           "dash:\(address)?amount=0.25")
        }
    }

    func testIdentityPayloadCarriesTheBareBase58Id() {
        let id = Self.identityIdBase58
        XCTAssertEqual(request(id, 1_234_567_890, option: .identity).paymentAddressOrRequestToShare(),
                       "dash:\(id)?amount=12.3456789")
    }

    /// Smallest and largest amounts: no exponent, no trailing zeros, nothing
    /// but `amount=` after the address (no fiat, no username).
    func testAmountFormattingAtTheEdges() {
        let a = Self.platformMainnet
        XCTAssertEqual(request(a, 1).paymentAddressOrRequestToShare(), "dash:\(a)?amount=0.00000001")
        XCTAssertEqual(request(a, 100_000_000).paymentAddressOrRequestToShare(), "dash:\(a)?amount=1")
        XCTAssertEqual(request(a, 2_100_000_000_000_000).paymentAddressOrRequestToShare(),
                       "dash:\(a)?amount=21000000")
        XCTAssertEqual(request(a, 2_099_999_999_999_999).paymentAddressOrRequestToShare(),
                       "dash:\(a)?amount=20999999.99999999")
    }

    /// The scanner on the current network reads the amount back from a
    /// Platform and a Shielded request.
    func testSendReadsTheAmountBackForPlatformAndShielded() throws {
        let hrp = Bech32m.platformHrp(mainnet: WalletEnvironment.isMainnet)
        let platform = hrp == "dash" ? Self.platformMainnet : Self.platformTestnet
        for address in [platform, try Self.shielded(hrp: hrp)] {
            let parsed = ParsedPaymentURI.parse(
                paymentString: request(address, 1_234_567_890).paymentAddressOrRequestToShare())
            XCTAssertEqual(parsed.address, address)
            XCTAssertEqual(parsed.amount, 1_234_567_890)
        }
    }

    // MARK: What the sheet shows

    func testSheetShowsTheValueWithTheCaptionOfItsOption() {
        let platform = request(Self.platformMainnet, 1)
        XCTAssertEqual(platform.paymentAddress, Self.platformMainnet)
        XCTAssertEqual(platform.addressCaption, NSLocalizedString("Your DASH address", comment: ""))
        XCTAssertNil(platform.username)
        XCTAssertNotNil(platform.qrCodeImage)

        let identity = request(Self.identityIdBase58, 1, option: .identity)
        XCTAssertEqual(identity.paymentAddress, Self.identityIdBase58)
        XCTAssertEqual(identity.addressCaption, NSLocalizedString("Identity ID", comment: ""))
    }

    /// Copy puts the whole request on the pasteboard, as Core's sheet does.
    func testCopyCopiesTheRequest() {
        let model = request(Self.platformMainnet, 100_000_000)
        UIPasteboard.general.string = nil
        model.copyAddressToPasteboard()
        XCTAssertEqual(UIPasteboard.general.string, "dash:\(Self.platformMainnet)?amount=1")
    }

    /// The sheet's own balance check reads Core addresses only; on these rails
    /// the landing's receipt is what closes it.
    func testTheSheetsOwnReceivedCheckNeverFires() {
        XCTAssertNil(request(Self.platformMainnet, 1).requestAmountReceivedInfoIfReceived())
    }

    // MARK: Enabled state per option

    func testSpecifyAmountIsOfferedOnEveryOptionWithAnAddress() throws {
        let model = PaymentsLandingViewModel.makeForPreview(
            activeTab: .receive,
            coreAddress: "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN",
            platformAddress: Self.platformMainnet,
            shieldedAddress: try Self.shielded(hrp: "dash"))
        model.updateReceiveState(
            isAdvancedMode: true,
            identity: try XCTUnwrap(ReceiveIdentity(identityId: Self.identityId, username: "alice")))

        for option in ReceiveOption.allCases {
            model.network = option
            XCTAssertTrue(model.canSpecifyAmount, "\(option)")
        }
    }

    func testSpecifyAmountIsNotOfferedWithoutAnAddressOrId() {
        let model = PaymentsLandingViewModel.makeForPreview(
            activeTab: .receive, coreAddress: nil, platformAddress: nil, shieldedAddress: nil)
        model.updateReceiveState(isAdvancedMode: true, identity: nil)

        for option in ReceiveOption.allCases {
            model.network = option
            XCTAssertFalse(model.canSpecifyAmount, "\(option)")
        }
    }

    // MARK: The request the landing builds

    func testLandingBuildsTheRequestForTheSelectedOption() throws {
        let shielded = try Self.shielded(hrp: "dash")
        let model = PaymentsLandingViewModel.makeForPreview(
            activeTab: .receive, platformAddress: Self.platformMainnet, shieldedAddress: shielded)
        model.updateReceiveState(
            isAdvancedMode: true,
            identity: try XCTUnwrap(ReceiveIdentity(identityId: Self.identityId, username: "alice")))

        let expected: [ReceiveOption: String] = [
            .platform: Self.platformMainnet,
            .shielded: shielded,
            .identity: Self.identityIdBase58,
        ]
        for (option, address) in expected {
            model.network = option
            let built = try XCTUnwrap(model.optionAmountRequest(amount: 100_000_000), "\(option)")
            XCTAssertEqual(built.paymentAddressOrRequestToShare(), "dash:\(address)?amount=1", "\(option)")
        }
    }

    /// Core keeps its own model, which adds the fiat and username parameters.
    func testLandingLeavesCoreToItsOwnModel() {
        let model = PaymentsLandingViewModel.makeForPreview(activeTab: .receive, network: .core)
        XCTAssertNil(model.optionAmountRequest(amount: 100_000_000))
    }
}
