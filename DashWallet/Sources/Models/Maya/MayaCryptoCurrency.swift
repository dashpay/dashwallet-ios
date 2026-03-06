//
//  MayaCryptoCurrency.swift
//  DashWallet
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

import Foundation

struct MayaCryptoCurrency: Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
    let mayaAsset: String
    let chain: String
    let iconAssetName: String

    /// All Maya-supported coins (excluding DASH which is the source currency)
    static let supportedCoins: [MayaCryptoCurrency] = [
        MayaCryptoCurrency(id: "btc", code: "BTC", name: "Bitcoin", mayaAsset: "BTC.BTC", chain: "BTC", iconAssetName: "maya.coin.btc"),
        MayaCryptoCurrency(id: "eth", code: "ETH", name: "Ethereum", mayaAsset: "ETH.ETH", chain: "ETH", iconAssetName: "maya.coin.eth"),
        MayaCryptoCurrency(id: "pepe", code: "PEPE", name: "PEPE", mayaAsset: "ETH.PEPE-0X6982508145454CE325DDBE47A25D4EC3D2311933", chain: "ETH", iconAssetName: "maya.coin.pepe"),
        MayaCryptoCurrency(id: "usdc", code: "USDC", name: "USD Coin", mayaAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48", chain: "ETH", iconAssetName: "maya.coin.usdc"),
        MayaCryptoCurrency(id: "usdt", code: "USDT", name: "Tether", mayaAsset: "ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7", chain: "ETH", iconAssetName: "maya.coin.usdt"),
        MayaCryptoCurrency(id: "wsteth", code: "WSTETH", name: "Wrapped stETH", mayaAsset: "ETH.WSTETH-0X7F39C581F595B53C5CB19BD0B3F8DA6C935E2CA0", chain: "ETH", iconAssetName: "maya.coin.wsteth"),
        MayaCryptoCurrency(id: "arb", code: "ARB", name: "Arbitrum", mayaAsset: "ARB.ARB-0X912CE59144191C1204E64559FE8253A0E49E6548", chain: "ARB", iconAssetName: "maya.coin.arb"),
        MayaCryptoCurrency(id: "eth_arb", code: "ETH", name: "Ethereum (Arbitrum)", mayaAsset: "ARB.ETH", chain: "ARB", iconAssetName: "maya.coin.eth"),
        MayaCryptoCurrency(id: "dai", code: "DAI", name: "Dai", mayaAsset: "ARB.DAI-0XDA10009CBD5D07DD0CECC66161FC93D7C9000DA1", chain: "ARB", iconAssetName: "maya.coin.dai"),
        MayaCryptoCurrency(id: "gld", code: "GLD", name: "Goldario", mayaAsset: "ARB.GLD-0XAFD091F140C21770F4E5D53D26B2859AE97555AA", chain: "ARB", iconAssetName: "maya.coin.gld"),
        MayaCryptoCurrency(id: "leo", code: "LEO", name: "LEO", mayaAsset: "ARB.LEO-0X93864D81175095DD93360FFA2A529B8642F76A6E", chain: "ARB", iconAssetName: "maya.coin.leo"),
        MayaCryptoCurrency(id: "link", code: "LINK", name: "ChainLink", mayaAsset: "ARB.LINK-0XF97F4DF75117A78C1A5A0DBB814AF92458539FB4", chain: "ARB", iconAssetName: "maya.coin.link"),
        MayaCryptoCurrency(id: "pepe_arb", code: "PEPE", name: "PEPE (Arbitrum)", mayaAsset: "ARB.PEPE-0X25D887CE7A35172C62FEBFD67A1856F20FAEBB00", chain: "ARB", iconAssetName: "maya.coin.pepe"),
        MayaCryptoCurrency(id: "tgt", code: "TGT", name: "THORWallet", mayaAsset: "ARB.TGT-0X429FED88F10285E61B12BDF00848315FBDFCC341", chain: "ARB", iconAssetName: "maya.coin.tgt"),
        MayaCryptoCurrency(id: "usdc_arb", code: "USDC", name: "USD Coin (Arbitrum)", mayaAsset: "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831", chain: "ARB", iconAssetName: "maya.coin.usdc"),
        MayaCryptoCurrency(id: "wbtc", code: "WBTC", name: "Wrapped Bitcoin", mayaAsset: "ARB.WBTC-0X2F2A2543B76A4166549F7AAB2E75BEF0AEFC5B0F", chain: "ARB", iconAssetName: "maya.coin.wbtc"),
        MayaCryptoCurrency(id: "wsteth_arb", code: "WSTETH", name: "Wrapped stETH (ARB)", mayaAsset: "ARB.WSTETH-0X5979D7B546E38E414F7E9822514BE443A4800529", chain: "ARB", iconAssetName: "maya.coin.wsteth"),
        MayaCryptoCurrency(id: "kuji", code: "KUJI", name: "Kujira", mayaAsset: "KUJI.KUJI", chain: "KUJI", iconAssetName: "maya.coin.kuji"),
        MayaCryptoCurrency(id: "rune", code: "RUNE", name: "Rune", mayaAsset: "THOR.RUNE", chain: "THOR", iconAssetName: "maya.coin.rune"),
    ]
}
