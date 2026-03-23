//
//  MayaAddressValidatorTests.swift
//  DashWalletTests
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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
@testable import dashwallet

class MayaAddressValidatorTests: XCTestCase {

    // MARK: - Bitcoin (BTC chain)

    private let btcCoin = MayaCryptoCurrency(id: "btc", code: "BTC", name: "Bitcoin", mayaAsset: "BTC.BTC", chain: "BTC", iconAssetName: "maya.coin.btc")

    func testBTC_validLegacyP2PKH() {
        XCTAssertTrue(MayaAddressValidator.isValid(address: "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2", for: btcCoin))
        XCTAssertTrue(MayaAddressValidator.isValid(address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", for: btcCoin))
    }

    func testBTC_validLegacyP2SH() {
        XCTAssertTrue(MayaAddressValidator.isValid(address: "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy", for: btcCoin))
    }

    func testBTC_validSegwit() {
        XCTAssertTrue(MayaAddressValidator.isValid(address: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", for: btcCoin))
        XCTAssertTrue(MayaAddressValidator.isValid(address: "bc1qxhgnnp745zryn2ud8hm6k3mygkkpkm35020js0", for: btcCoin))
    }

    func testBTC_validTaproot() {
        XCTAssertTrue(MayaAddressValidator.isValid(address: "bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297", for: btcCoin))
    }

    func testBTC_invalid() {
        XCTAssertFalse(MayaAddressValidator.isValid(address: "", for: btcCoin))
        XCTAssertFalse(MayaAddressValidator.isValid(address: "abc123", for: btcCoin))
        XCTAssertFalse(MayaAddressValidator.isValid(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD73", for: btcCoin))
        XCTAssertFalse(MayaAddressValidator.isValid(address: "1", for: btcCoin))
        XCTAssertFalse(MayaAddressValidator.isValid(address: "bc1", for: btcCoin))
        // Contains invalid Base58 character '0' at start after prefix
        XCTAssertFalse(MayaAddressValidator.isValid(address: "10", for: btcCoin))
        // Truncated segwit — wrong length (must be exactly 42 or 62)
        XCTAssertFalse(MayaAddressValidator.isValid(address: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3", for: btcCoin))
    }

    // MARK: - Ethereum (ETH chain)

    private let ethCoin = MayaCryptoCurrency(id: "eth", code: "ETH", name: "Ethereum", mayaAsset: "ETH.ETH", chain: "ETH", iconAssetName: "maya.coin.eth")

    func testETH_valid() {
        XCTAssertTrue(MayaAddressValidator.isValid(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD73", for: ethCoin))
        XCTAssertTrue(MayaAddressValidator.isValid(address: "0x51a1449b3B6D635EddeC781cD47a99221712De97", for: ethCoin))
        XCTAssertTrue(MayaAddressValidator.isValid(address: "0x0000000000000000000000000000000000000000", for: ethCoin))
    }

    func testETH_invalid() {
        XCTAssertFalse(MayaAddressValidator.isValid(address: "", for: ethCoin))
        XCTAssertFalse(MayaAddressValidator.isValid(address: "742d35Cc6634C0532925a3b844Bc9e7595f2bD73", for: ethCoin))  // missing 0x
        XCTAssertFalse(MayaAddressValidator.isValid(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD7", for: ethCoin))  // 39 chars
        XCTAssertFalse(MayaAddressValidator.isValid(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD733", for: ethCoin))  // 41 chars
        XCTAssertFalse(MayaAddressValidator.isValid(address: "0xGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG", for: ethCoin))  // non-hex
        XCTAssertFalse(MayaAddressValidator.isValid(address: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", for: ethCoin))
    }

    // MARK: - Arbitrum (ARB chain)

    private let arbCoin = MayaCryptoCurrency(id: "arb", code: "ARB", name: "Arbitrum", mayaAsset: "ARB.ARB-0X912CE59144191C1204E64559FE8253A0E49E6548", chain: "ARB", iconAssetName: "maya.coin.arb")

    func testARB_valid() {
        XCTAssertTrue(MayaAddressValidator.isValid(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD73", for: arbCoin))
    }

    func testARB_invalid() {
        XCTAssertFalse(MayaAddressValidator.isValid(address: "abc123", for: arbCoin))
    }

    // MARK: - Kujira (KUJI chain)

    private let kujiCoin = MayaCryptoCurrency(id: "kuji", code: "KUJI", name: "Kujira", mayaAsset: "KUJI.KUJI", chain: "KUJI", iconAssetName: "maya.coin.kuji")

    func testKUJI_valid() {
        XCTAssertTrue(MayaAddressValidator.isValid(address: "kujira1r8egcurpwxftegr07gjv9gwffw4fk00960dj4f", for: kujiCoin))
    }

    func testKUJI_invalid() {
        XCTAssertFalse(MayaAddressValidator.isValid(address: "", for: kujiCoin))
        XCTAssertFalse(MayaAddressValidator.isValid(address: "kujira1", for: kujiCoin))  // too short
        XCTAssertFalse(MayaAddressValidator.isValid(address: "thor166n4w5039meulfa3p6ydg60ve6ueac7tlt0jws", for: kujiCoin))  // wrong prefix
        XCTAssertFalse(MayaAddressValidator.isValid(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD73", for: kujiCoin))
    }

    // MARK: - THORChain (THOR chain)

    private let thorCoin = MayaCryptoCurrency(id: "rune", code: "RUNE", name: "Rune", mayaAsset: "THOR.RUNE", chain: "THOR", iconAssetName: "maya.coin.rune")

    func testTHOR_valid() {
        XCTAssertTrue(MayaAddressValidator.isValid(address: "thor166n4w5039meulfa3p6ydg60ve6ueac7tlt0jws", for: thorCoin))
    }

    func testTHOR_invalid() {
        XCTAssertFalse(MayaAddressValidator.isValid(address: "", for: thorCoin))
        XCTAssertFalse(MayaAddressValidator.isValid(address: "thor1", for: thorCoin))  // too short
        XCTAssertFalse(MayaAddressValidator.isValid(address: "kujira1r8egcurpwxftegr07gjv9gwffw4fk00960dj4f", for: thorCoin))  // wrong prefix
    }

    // MARK: - Edge Cases

    func testWhitespace_trimmed() {
        XCTAssertTrue(MayaAddressValidator.isValid(address: "  0x742d35Cc6634C0532925a3b844Bc9e7595f2bD73  ", for: ethCoin))
    }

    func testEmpty_allChains() {
        let coins = MayaCryptoCurrency.supportedCoins
        for coin in coins {
            XCTAssertFalse(MayaAddressValidator.isValid(address: "", for: coin), "Empty address should be invalid for \(coin.code)")
        }
    }
}
