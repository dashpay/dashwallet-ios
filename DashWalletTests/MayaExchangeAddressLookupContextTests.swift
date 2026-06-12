//
//  MayaExchangeAddressLookupContextTests.swift
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

final class MayaExchangeAddressLookupContextTests: XCTestCase {

    func testCacheKeySeparatesETHAndArbitrumVariantsOfSameTicker() {
        let ethUSDC = MayaCryptoCurrency(
            id: "usdc",
            code: "USDC",
            name: "USD Coin",
            mayaAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
            chain: "ETH",
            iconAssetName: "maya.coin.usdc"
        )
        let arbUSDC = MayaCryptoCurrency(
            id: "usdc_arb",
            code: "USDC",
            name: "USD Coin (Arbitrum)",
            mayaAsset: "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831",
            chain: "ARB",
            iconAssetName: "maya.coin.usdc"
        )

        let ethContext = MayaExchangeAddressLookupContext(coin: ethUSDC)
        let arbContext = MayaExchangeAddressLookupContext(coin: arbUSDC)

        XCTAssertNotEqual(ethContext.cacheKey, arbContext.cacheKey)
        XCTAssertEqual(ethContext.normalizedNetworkKey, "ethereum")
        XCTAssertEqual(arbContext.normalizedNetworkKey, "arbitrum")
    }

    func testAmbiguousTickerDetectionFlagsMultiChainAssets() {
        let ethUSDT = MayaCryptoCurrency(
            id: "usdt",
            code: "USDT",
            name: "Tether",
            mayaAsset: "ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7",
            chain: "ETH",
            iconAssetName: "maya.coin.usdt"
        )
        let btc = MayaCryptoCurrency(
            id: "btc",
            code: "BTC",
            name: "Bitcoin",
            mayaAsset: "BTC.BTC",
            chain: "BTC",
            iconAssetName: "maya.coin.btc"
        )

        XCTAssertTrue(MayaExchangeAddressLookupContext(coin: ethUSDT).usesAmbiguousCurrencyCode)
        XCTAssertFalse(MayaExchangeAddressLookupContext(coin: btc).usesAmbiguousCurrencyCode)
    }

    func testCoinbaseHintsIncludeTokenIdentifierAndChain() {
        let coin = MayaCryptoCurrency(
            id: "usdc_base",
            code: "USDC",
            name: "USD Coin (Base)",
            mayaAsset: "BASE.USDC-0X833589FCD6EDB6E08F4C7C32D4F71B54BDA02913",
            chain: "BASE",
            iconAssetName: "maya.coin.usdc"
        )

        let hints = MayaExchangeAddressLookupContext(coin: coin).coinbaseMatchHints

        XCTAssertTrue(hints.contains("USDC"))
        XCTAssertTrue(hints.contains("BASE"))
        XCTAssertTrue(hints.contains("USDC-0X833589FCD6EDB6E08F4C7C32D4F71B54BDA02913"))
    }

    func testCoinbaseNetworkMatchingAcceptsKnownAliases() {
        let ethereumUSDC = MayaCryptoCurrency(
            id: "usdc_eth",
            code: "USDC",
            name: "USD Coin (Ethereum)",
            mayaAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
            chain: "ETH",
            iconAssetName: "maya.coin.usdc"
        )
        let polygonUSDC = MayaCryptoCurrency(
            id: "usdc_pol",
            code: "USDC",
            name: "USD Coin (Polygon)",
            mayaAsset: "POL.USDC-0X3C499C542CEF5E3811E1192CE70D8CC03D5C3359",
            chain: "POL",
            iconAssetName: "maya.coin.usdc"
        )

        let ethereumContext = MayaExchangeAddressLookupContext(coin: ethereumUSDC)
        let polygonContext = MayaExchangeAddressLookupContext(coin: polygonUSDC)

        XCTAssertTrue(ethereumContext.matchesCoinbaseReportedNetwork("Ethereum"))
        XCTAssertTrue(ethereumContext.matchesCoinbaseReportedNetwork("ERC20"))
        XCTAssertTrue(polygonContext.matchesCoinbaseReportedNetwork("Polygon POS"))
        XCTAssertTrue(polygonContext.matchesCoinbaseReportedNetwork("MATIC"))
    }

    func testCoinbaseNetworkMatchingRejectsDifferentChains() {
        let arbitrumUSDC = MayaCryptoCurrency(
            id: "usdc_arb",
            code: "USDC",
            name: "USD Coin (Arbitrum)",
            mayaAsset: "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831",
            chain: "ARB",
            iconAssetName: "maya.coin.usdc"
        )

        let context = MayaExchangeAddressLookupContext(coin: arbitrumUSDC)

        XCTAssertFalse(context.matchesCoinbaseReportedNetwork("Ethereum"))
        XCTAssertFalse(context.matchesCoinbaseReportedNetwork("Base"))
    }
}
