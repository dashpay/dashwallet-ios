//
//  VotingKeyFormatTests.swift
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

import XCTest
@testable import dashpay

/// `VotingKeyFormat.problem(with:isMainnet:)` is what tells a user typing a
/// voting key by hand what is wrong with it, before the SDK locator runs.
final class VotingKeyFormatTests: XCTestCase {
    private let mainnetWIF = VotingKeyFormat.mainnetExample
    private let testnetWIF = VotingKeyFormat.testnetExample

    func testWellFormedKeyForThisNetworkPasses() {
        XCTAssertNil(VotingKeyFormat.problem(with: mainnetWIF, isMainnet: true))
        XCTAssertNil(VotingKeyFormat.problem(with: testnetWIF, isMainnet: false))
    }

    func testUncompressedKeyIsRefused() {
        // Version 0xCC + 32 bytes of 0x07, no compression flag. The signer
        // only ever votes as the compressed key, so this one could be
        // imported but never vote.
        let uncompressed = "7qbxVhSx957Z7NQFXgCMNX41jMpFkHWdnHeDizMetMcun7wmJEt"
        XCTAssertEqual(VotingKeyFormat.problem(with: uncompressed, isMainnet: true), .uncompressed)
        // The network is still checked first.
        XCTAssertEqual(VotingKeyFormat.problem(with: uncompressed, isMainnet: false), .wrongNetwork)
    }

    func testOtherNetworksKeyIsWrongNetwork() {
        XCTAssertEqual(VotingKeyFormat.problem(with: testnetWIF, isMainnet: true), .wrongNetwork)
        XCTAssertEqual(VotingKeyFormat.problem(with: mainnetWIF, isMainnet: false), .wrongNetwork)
    }

    func testAddressIsRecognised() {
        // Mainnet P2PKH (version 0x4C) over hash160 bytes 00…13.
        XCTAssertEqual(
            VotingKeyFormat.problem(with: "Xags3HEXJ4G4Uuf8va2eSxLCw2KCyEhiJ7", isMainnet: true),
            .address)
    }

    func testHexPrivateKeyIsRecognised() {
        let hex = String(repeating: "ab", count: 32)
        XCTAssertEqual(VotingKeyFormat.problem(with: hex, isMainnet: true), .hexPrivateKey)
    }

    func testHexPublicKeysAreRecognised() {
        let compressed = "02" + String(repeating: "cd", count: 32)
        let uncompressed = "04" + String(repeating: "cd", count: 64)
        XCTAssertEqual(VotingKeyFormat.problem(with: compressed, isMainnet: true), .hexPublicKey)
        XCTAssertEqual(VotingKeyFormat.problem(with: uncompressed, isMainnet: true), .hexPublicKey)
    }

    func testShortInputIsTooShort() {
        XCTAssertEqual(VotingKeyFormat.problem(with: "5T", isMainnet: true), .tooShort)
        XCTAssertEqual(
            VotingKeyFormat.problem(with: String(mainnetWIF.prefix(30)), isMainnet: true),
            .tooShort)
    }

    func testMistypedCharacterIsChecksum() {
        let mistyped = String(mainnetWIF.dropLast()) + "y"
        XCTAssertEqual(VotingKeyFormat.problem(with: mistyped, isMainnet: true), .checksum)
    }

    func testNonBase58CharacterIsInvalidCharacter() {
        let withZero = "0" + mainnetWIF.dropFirst()
        XCTAssertEqual(VotingKeyFormat.problem(with: withZero, isMainnet: true), .invalidCharacter)
    }

    func testOverLongInputIsRefusedBeforeDecoding() {
        // Longer than any WIF; would take seconds in the quadratic decoder.
        let long = String(repeating: "X", count: 100_000)
        XCTAssertEqual(VotingKeyFormat.problem(with: long, isMainnet: true), .invalid)
        XCTAssertEqual(
            VotingKeyFormat.problem(with: mainnetWIF + "1", isMainnet: true),
            .invalid)
    }
}
