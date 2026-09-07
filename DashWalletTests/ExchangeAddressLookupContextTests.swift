//
//  ExchangeAddressLookupContextTests.swift
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
@testable import dashpay

final class ExchangeAddressLookupContextTests: XCTestCase {

    func testCacheKeySeparatesETHAndArbitrumVariantsOfSameTicker() {
        let ethUSDC = SwapCryptoCurrency(
            id: "usdc",
            code: "USDC",
            name: "USD Coin",
            swapAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
            chain: "ETH"
        )
        let arbUSDC = SwapCryptoCurrency(
            id: "usdc_arb",
            code: "USDC",
            name: "USD Coin (Arbitrum)",
            swapAsset: "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831",
            chain: "ARB"
        )

        let ethContext = ExchangeAddressLookupContext(coin: ethUSDC)
        let arbContext = ExchangeAddressLookupContext(coin: arbUSDC)

        XCTAssertNotEqual(ethContext.cacheKey, arbContext.cacheKey)
        XCTAssertEqual(ethContext.normalizedNetworkKey, "ethereum")
        XCTAssertEqual(arbContext.normalizedNetworkKey, "arbitrum")
    }

    func testAmbiguousTickerDetectionFlagsMultiChainAssets() {
        let ethUSDT = SwapCryptoCurrency(
            id: "usdt",
            code: "USDT",
            name: "Tether",
            swapAsset: "ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7",
            chain: "ETH"
        )
        let btc = SwapCryptoCurrency(
            id: "btc",
            code: "BTC",
            name: "Bitcoin",
            swapAsset: "BTC.BTC",
            chain: "BTC"
        )

        XCTAssertTrue(ExchangeAddressLookupContext(coin: ethUSDT).usesAmbiguousCurrencyCode)
        XCTAssertFalse(ExchangeAddressLookupContext(coin: btc).usesAmbiguousCurrencyCode)
    }

    func testCoinbaseHintsIncludeTokenIdentifierAndChain() {
        let coin = SwapCryptoCurrency(
            id: "usdc_base",
            code: "USDC",
            name: "USD Coin (Base)",
            swapAsset: "BASE.USDC-0X833589FCD6EDB6E08F4C7C32D4F71B54BDA02913",
            chain: "BASE"
        )

        let hints = ExchangeAddressLookupContext(coin: coin).coinbaseMatchHints

        XCTAssertTrue(hints.contains("USDC"))
        XCTAssertTrue(hints.contains("BASE"))
        XCTAssertTrue(hints.contains("USDC-0X833589FCD6EDB6E08F4C7C32D4F71B54BDA02913"))
    }

    func testCoinbaseNetworkMatchingAcceptsKnownAliases() {
        let ethereumUSDC = SwapCryptoCurrency(
            id: "usdc_eth",
            code: "USDC",
            name: "USD Coin (Ethereum)",
            swapAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
            chain: "ETH"
        )
        let polygonUSDC = SwapCryptoCurrency(
            id: "usdc_pol",
            code: "USDC",
            name: "USD Coin (Polygon)",
            swapAsset: "POL.USDC-0X3C499C542CEF5E3811E1192CE70D8CC03D5C3359",
            chain: "POL"
        )

        let ethereumContext = ExchangeAddressLookupContext(coin: ethereumUSDC)
        let polygonContext = ExchangeAddressLookupContext(coin: polygonUSDC)

        XCTAssertTrue(ethereumContext.matchesCoinbaseReportedNetwork("Ethereum"))
        XCTAssertTrue(ethereumContext.matchesCoinbaseReportedNetwork("ERC20"))
        XCTAssertTrue(polygonContext.matchesCoinbaseReportedNetwork("Polygon POS"))
        XCTAssertTrue(polygonContext.matchesCoinbaseReportedNetwork("MATIC"))
    }

    func testCoinbaseNetworkMatchingRejectsDifferentChains() {
        let arbitrumUSDC = SwapCryptoCurrency(
            id: "usdc_arb",
            code: "USDC",
            name: "USD Coin (Arbitrum)",
            swapAsset: "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831",
            chain: "ARB"
        )

        let context = ExchangeAddressLookupContext(coin: arbitrumUSDC)

        XCTAssertFalse(context.matchesCoinbaseReportedNetwork("Ethereum"))
        XCTAssertFalse(context.matchesCoinbaseReportedNetwork("Base"))
    }

    func testCoinbaseCreateNetworkUsesSpecificEvmSlugs() {
        let arbitrumUSDC = SwapCryptoCurrency(
            id: "usdc_arb",
            code: "USDC",
            name: "USD Coin (Arbitrum)",
            swapAsset: "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831",
            chain: "ARB"
        )
        let avalancheUSDC = SwapCryptoCurrency(
            id: "usdc_avax",
            code: "USDC",
            name: "USD Coin (Avalanche)",
            swapAsset: "AVAX.USDC-0XB97EF9EF8734C71904D8002F8B6BC66DD9C48A6E",
            chain: "AVAX"
        )
        let polygonUSDC = SwapCryptoCurrency(
            id: "usdc_pol",
            code: "USDC",
            name: "USD Coin (Polygon)",
            swapAsset: "POL.USDC-0X3C499C542CEF5E3811E1192CE70D8CC03D5C3359",
            chain: "POL"
        )

        XCTAssertEqual(ExchangeAddressLookupContext(coin: arbitrumUSDC).coinbaseCreateNetwork, "arbitrum")
        XCTAssertEqual(ExchangeAddressLookupContext(coin: avalancheUSDC).coinbaseCreateNetwork, "avacchain")
        XCTAssertEqual(ExchangeAddressLookupContext(coin: polygonUSDC).coinbaseCreateNetwork, "polygon")
    }

    func testCoinbaseCreateNetworkReturnsNilForNativeSingleNetworkAssets() {
        let bitcoin = SwapCryptoCurrency(
            id: "btc",
            code: "BTC",
            name: "Bitcoin",
            swapAsset: "BTC.BTC",
            chain: "BTC"
        )

        XCTAssertNil(ExchangeAddressLookupContext(coin: bitcoin).coinbaseCreateNetwork)
    }

    func testClearCoinbaseCacheRemovesPersistedCoinbaseAddresses() async {
        let persistedKey = "maya.coinbase.depositAddress.v1.default.USDC|arbitrum"
        UserDefaults.standard.set("0x1234567890", forKey: persistedKey)

        await MainActor.run {
            ExchangeAddressProvider.clearCoinbaseCache()
        }

        XCTAssertNil(UserDefaults.standard.string(forKey: persistedKey))
    }
}
