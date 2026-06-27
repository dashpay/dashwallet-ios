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
    /// Stable unique identifier used by `Identifiable` (e.g. `"btc"`, `"usdc_arb"`).
    let id: String
    /// Ticker symbol displayed in the UI (e.g. `"BTC"`, `"USDC"`).
    let code: String
    /// Human-readable plain base name (e.g. `"Bitcoin"`, `"USD Coin"`, `"Ethereum"`).
    /// Chain suffixes are NOT stored here; `SelectCoinViewModel.disambiguateDisplayNames`
    /// appends them at runtime for codes shared across chains.
    let name: String
    /// Maya pool asset string used in API calls (e.g. `"BTC.BTC"`, `"ETH.USDC-0XA0B8..."`).
    let mayaAsset: String
    /// Maya chain identifier used for local address validation (e.g. `"BTC"`, `"ARB"`).
    let chain: String
    /// Remote icon URL string sourced from SwapKit `logoURI`. Nil when not yet loaded or unavailable.
    var iconURL: String?

    // MARK: - Supported Coins

    /// Curated set of Maya/SwapKit assets the wallet exposes in the Select Coin picker.
    /// Mirrors Android `MayaCurrencyList.all` (kept in sync with SwapKit `/swapTo`).
    /// Source: `~/Desktop/swapkit-integration/android-supported-coins.txt`
    static let supportedAssets: Set<String> = [
        "ADA.ADA",
        "ARB.ARB-0X912CE59144191C1204E64559FE8253A0E49E6548",
        "ARB.ETH",
        "ARB.GLD-0XAFD091F140C21770F4E5D53D26B2859AE97555AA",
        "ARB.LEO-0X93864D81175095DD93360FFA2A529B8642F76A6E",
        "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831",
        "ARB.USDT-0XFD086BC7CD5C481DCC9C85EBE478A1C0B69FCBB9",
        "ARB.USDT0-0XFD086BC7CD5C481DCC9C85EBE478A1C0B69FCBB9",
        "ARB.WBTC-0X2F2A2543B76A4166549F7AAB2E75BEF0AEFC5B0F",
        "ARB.WETH-0X82AF49447D8A07E3BD95BD0D56F35241523FBAB1",
        "ARB.WSTETH-0X5979D7B546E38E414F7E9822514BE443A4800529",
        "ARB.YUM-0X9F41B34F42058A7B74672055A5FAE22C4B113FD1",
        "AVAX.AVAX",
        "AVAX.USDC-0XB97EF9EF8734C71904D8002F8B6BC66DD9C48A6E",
        "AVAX.USDT-0X9702230A8EA53601F5CD2DC00FDBC13D4DF4A8C7",
        "BASE.CBBTC-0XCBB7C0000AB88B473B1F5AFD9EF808440EED33BF",
        "BASE.CFI-0X0382E3FEE4A420BD446367D468A6F00225853420",
        "BASE.ETH",
        "BASE.USDC-0X833589FCD6EDB6E08F4C7C32D4F71B54BDA02913",
        "BASE.WETH-0X4200000000000000000000000000000000000006",
        "BCH.BCH",
        "BERA.BERA",
        "BERA.USDT0-0X779DED0C9E1022225F8E0630B35A9B54BE713736",
        "BSC.ASTER-0X000AE314E2A2172A039B26378814C252734F556A",
        "BSC.BNB",
        "BSC.NEAR-0X1FA4A73A3F0133F0025378AF00236F3ABDEE5D63",
        "BSC.RHEA-0X4C067DE26475E1CEFEE8B8D1F6E2266B33A2372E",
        "BSC.USDC-0X8AC76A51CC950D9822D68B83FE1AD97B32CD580D",
        "BSC.USDT-0X55D398326F99059FF775485246999027B3197955",
        "BTC.BTC",
        "DOGE.DOGE",
        "ETH.ADI-0X8B1484D57ABBE239BB280661377363B03C89CAEA",
        "ETH.AURORA-0XAAAAAA20D9E0E2461697782EF11675F668207961",
        "ETH.CBBTC-0XCBB7C0000AB88B473B1F5AFD9EF808440EED33BF",
        "ETH.DAI-0X6B175474E89094C44DA98B954EEDEAC495271D0F",
        "ETH.ETH",
        "ETH.MOCA-0X53312F85BBA24C8CB99CFFC13BF82420157230D3",
        "ETH.MOG-0XAAEE1A9723AADB7AFA2810263653A34BA2C21C7A",
        "ETH.PEPE-0X6982508145454CE325DDBE47A25D4EC3D2311933",
        "ETH.SAFE-0X5AFE3855358E112B5647B952709E6165E1C1EEEE",
        "ETH.SHIB-0X95AD61B0A150D79219DCF64E1E6CC01F0B64C4CE",
        "ETH.TURBO-0XA35923162C49CF95E6BF26623385EB431AD920D3",
        "ETH.USD1-0X8D0D000EE44948FC98C9B98A4FA4921476F08B0D",
        "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
        "ETH.USDF-0XFA2B947EEC368F42195F24F36D2AF29F7C24CEC2",
        "ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7",
        "ETH.WBTC-0X2260FAC5E5542A773AA44FBCFEDF7C193BC2C599",
        "ETH.WETH-0XC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2",
        "ETH.WSTETH-0X7F39C581F595B53C5CB19BD0B3F8DA6C935E2CA0",
        "GNO.COW-0X177127622C4A00F3D409B75571E12CB3C8973D3C",
        "GNO.EURE-0X420CA0F9B9B604CE0FD9C18EF134C705E5FA3430",
        "GNO.GNO-0X9C58BACC331C9AA871AFD802DB6379A98E80CEDB",
        "GNO.SAFE-0X4D18815D14FE5C3304E87B3FA18318BAA5C23820",
        "GNO.USDC-0X2A22F9C3B484C3629090FEED35F17FF8F88F76F0",
        "GNO.USDT-0X4ECABA5870353805A9F068101A40E0F32ED605C6",
        "GNO.WETH-0X6A023CCD1FF6F2045C3309768EAD9E68F978F6E1",
        "GNO.XDAI",
        "LTC.LTC",
        "MAYA.CACAO",
        "MAYA.MAYA",
        "MONAD.MON",
        "MONAD.USDC-0X754704BC059F8C67012FED69BC8A327A5AAFB603",
        "MONAD.USDT0-0XE7CD86E13AC4309349F30B3435A9D337750FC82D",
        "NEAR.AURORA-AAAAAA20D9E0E2461697782EF11675F668207961.FACTORY.BRIDGE.NEAR",
        "NEAR.BTC-NBTC.BRIDGE.NEAR",
        "NEAR.CFI-CFI.CONSUMER-FI.NEAR",
        "NEAR.ETH-ETH.BRIDGE.NEAR",
        "NEAR.FRAX-853D955ACEF822DB058EB8505911ED77F175B99E.FACTORY.BRIDGE.NEAR",
        "NEAR.ITLX-ITLX.INTELLEX_XYZ.NEAR",
        "NEAR.JAMBO-JAMBO-1679.MEME-COOKING.NEAR",
        "NEAR.NEAR",
        "NEAR.NOEAR-NOEAR-324.MEME-COOKING.NEAR",
        "NEAR.NPRO-NPRO.NEARMOBILE.NEAR",
        "NEAR.NEARKAT-KAT.TOKEN0.NEAR",
        "NEAR.PUBLIC-TOKEN.PUBLICAILAB.NEAR",
        "NEAR.PURGE-PURGE-558.MEME-COOKING.NEAR",
        "NEAR.RHEA-TOKEN.RHEALAB.NEAR",
        "NEAR.SHITZU-TOKEN.0XSHITZU.NEAR",
        "NEAR.STJACK-STJACK.TKN.PRIMITIVES.NEAR",
        "NEAR.SWEAT-TOKEN.SWEAT",
        "NEAR.TURBO-A35923162C49CF95E6BF26623385EB431AD920D3.FACTORY.BRIDGE.NEAR",
        "NEAR.USDC-17208628F84F5D6AD33F0DA3BBBEB27FFCB398EAC501A31BD6AD2011E36133A1",
        "NEAR.USDT-USDT.TETHER-TOKEN.NEAR",
        "NEAR.ZEC-ZEC.OMFT.NEAR",
        "NEAR.MPDAO-MPDAO-TOKEN.NEAR",
        "NEAR.NRUSDT-LSD-USDT.RHEALAB.NEAR",
        "NEAR.STNEAR-META-POOL.NEAR",
        "NEAR.WBTC-2260FAC5E5542A773AA44FBCFEDF7C193BC2C599.FACTORY.BRIDGE.NEAR",
        "NEAR.WNEAR-WRAP.NEAR",
        "OP.ETH",
        "OP.OP-0X4200000000000000000000000000000000000042",
        "OP.USDC-0X0B2C639C533813F4AA9D7837CAF62653D097FF85",
        "OP.USDT-0X94B008AA00579C1307B0EF2C499AD98A8CE58E58",
        "OP.WETH-0X4200000000000000000000000000000000000006",
        "POL.POL",
        "POL.USDC-0X3C499C542CEF5E3811E1192CE70D8CC03D5C3359",
        "POL.USDT-0XC2132D05D31C914A87C6611C10748AEB04B58E8F",
        "POL.WETH-0X7CEB23FD6BC0ADD59E62AC25578270CFF1B9F619",
        "SOL.PENGU-2ZMMHCVQEXDTDE6VSFS7S7D5OUODFJHE8VD1GNBOUAUV",
        "SOL.SOL",
        "SOL.SPX-J3NKXXXZCNNIMJKW9HYB2K4LUXGWB6T1FTPTQVSV3KFR",
        "SOL.TRUMP-6P6XGHYF7AEE6TZKSMFSKO444WQOP15ICUSQI2JFGIPN",
        "SOL.TURBO-2DYZU65QA9ZDX1UEE7GX71K7FIWYUK6SZDRVJ7AUQ5WM",
        "SOL.USDC-EPJFWDD5AUFQSSQEM2QN1XZYBAPC8G4WEGGKZWYTDT1V",
        "SOL.USDT-ES9VMFRZACERMJFRF4H2FYD4KCONKY11MCCE8BENWNYB",
        "SOL.$WIF-EKPQGSJTJMFQKZ9KQANSQYXRCF8FBOPZLHYXDM65ZCJM",
        "SOL.ZEC-A7BDIYDS5GJQGFTXF17PPRHTDKPKKRQBKTR27DXVQXAS",
        "SOL.XBTC-CTZPWV73SN1DMGVU3ZTLV9YWSYUAANBNI19YWDAZNNKN",
        "STRK.STRK",
        "SUI.SUI",
        "SUI.USDC-0XDBA34672E30CB065B1F93E3AB55318768FD6FEF66C15942C9F7CB846E2F900E7::USDC::USDC",
        "THOR.RUNE",
        "TON.TON",
        "TON.USDT-EQCXE6MUTQJKFNGFAROTKOT1LZBDIIX1KCIXRV7NW2ID_SDS",
        "TRON.TRX",
        "TRON.USDT-TR7NHQJEKQXGTCI8Q8ZY4PL8OTSZGJLJ6T",
        "XLAYER.OKB",
        "XLAYER.USDC-0X74B7F16337B8972027F6196A17A631AC6DE26D22",
        "XLAYER.USDT0-0X779DED0C9E1022225F8E0630B35A9B54BE713736",
        "XRP.XRP",
        "ZEC.ZEC",
    ]

    /// All Maya-supported destination coins, grouped by chain.
    /// DASH is excluded — it is always the source currency.
    /// Covers every identifier in `supportedAssets` (130 entries). Names use plain base names;
    /// `SelectCoinViewModel.disambiguateDisplayNames` appends a chain suffix at runtime for
    /// any code that appears on more than one chain.
    static let supportedCoins: [MayaCryptoCurrency] = [
        // BTC
        MayaCryptoCurrency(id: "btc", code: "BTC", name: "Bitcoin", mayaAsset: "BTC.BTC", chain: "BTC"),

        // ADA
        MayaCryptoCurrency(id: "ada", code: "ADA", name: "Cardano", mayaAsset: "ADA.ADA", chain: "ADA"),

        // ETH chain
        MayaCryptoCurrency(id: "eth", code: "ETH", name: "Ethereum", mayaAsset: "ETH.ETH", chain: "ETH"),
        MayaCryptoCurrency(id: "adi", code: "ADI", name: "ADI", mayaAsset: "ETH.ADI-0X8B1484D57ABBE239BB280661377363B03C89CAEA", chain: "ETH"),
        MayaCryptoCurrency(id: "aurora_eth", code: "AURORA", name: "Aurora", mayaAsset: "ETH.AURORA-0XAAAAAA20D9E0E2461697782EF11675F668207961", chain: "ETH"),
        MayaCryptoCurrency(id: "cbbtc_eth", code: "cbBTC", name: "Coinbase Wrapped BTC", mayaAsset: "ETH.CBBTC-0XCBB7C0000AB88B473B1F5AFD9EF808440EED33BF", chain: "ETH"),
        MayaCryptoCurrency(id: "dai_eth", code: "DAI", name: "Dai", mayaAsset: "ETH.DAI-0X6B175474E89094C44DA98B954EEDEAC495271D0F", chain: "ETH"),
        MayaCryptoCurrency(id: "moca", code: "MOCA", name: "Mocaverse", mayaAsset: "ETH.MOCA-0X53312F85BBA24C8CB99CFFC13BF82420157230D3", chain: "ETH"),
        MayaCryptoCurrency(id: "mog", code: "MOG", name: "Mog Coin", mayaAsset: "ETH.MOG-0XAAEE1A9723AADB7AFA2810263653A34BA2C21C7A", chain: "ETH"),
        MayaCryptoCurrency(id: "pepe", code: "PEPE", name: "PEPE", mayaAsset: "ETH.PEPE-0X6982508145454CE325DDBE47A25D4EC3D2311933", chain: "ETH"),
        MayaCryptoCurrency(id: "safe_eth", code: "SAFE", name: "Safe", mayaAsset: "ETH.SAFE-0X5AFE3855358E112B5647B952709E6165E1C1EEEE", chain: "ETH"),
        MayaCryptoCurrency(id: "shib", code: "SHIB", name: "Shiba Inu", mayaAsset: "ETH.SHIB-0X95AD61B0A150D79219DCF64E1E6CC01F0B64C4CE", chain: "ETH"),
        MayaCryptoCurrency(id: "turbo_eth", code: "TURBO", name: "Turbo", mayaAsset: "ETH.TURBO-0XA35923162C49CF95E6BF26623385EB431AD920D3", chain: "ETH"),
        MayaCryptoCurrency(id: "usd1", code: "USD1", name: "USD1", mayaAsset: "ETH.USD1-0X8D0D000EE44948FC98C9B98A4FA4921476F08B0D", chain: "ETH"),
        MayaCryptoCurrency(id: "usdc", code: "USDC", name: "USD Coin", mayaAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48", chain: "ETH"),
        MayaCryptoCurrency(id: "usdf", code: "USDf", name: "Falcon USD", mayaAsset: "ETH.USDF-0XFA2B947EEC368F42195F24F36D2AF29F7C24CEC2", chain: "ETH"),
        MayaCryptoCurrency(id: "usdt", code: "USDT", name: "Tether", mayaAsset: "ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7", chain: "ETH"),
        MayaCryptoCurrency(id: "wbtc_eth", code: "WBTC", name: "Wrapped Bitcoin", mayaAsset: "ETH.WBTC-0X2260FAC5E5542A773AA44FBCFEDF7C193BC2C599", chain: "ETH"),
        MayaCryptoCurrency(id: "weth_eth", code: "WETH", name: "WETH", mayaAsset: "ETH.WETH-0XC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2", chain: "ETH"),
        MayaCryptoCurrency(id: "wsteth", code: "WSTETH", name: "Wrapped stETH", mayaAsset: "ETH.WSTETH-0X7F39C581F595B53C5CB19BD0B3F8DA6C935E2CA0", chain: "ETH"),

        // ARB (Arbitrum One)
        MayaCryptoCurrency(id: "arb", code: "ARB", name: "Arbitrum", mayaAsset: "ARB.ARB-0X912CE59144191C1204E64559FE8253A0E49E6548", chain: "ARB"),
        MayaCryptoCurrency(id: "eth_arb", code: "ETH", name: "Ethereum", mayaAsset: "ARB.ETH", chain: "ARB"),
        MayaCryptoCurrency(id: "gld", code: "GLD", name: "Goldario", mayaAsset: "ARB.GLD-0XAFD091F140C21770F4E5D53D26B2859AE97555AA", chain: "ARB"),
        MayaCryptoCurrency(id: "leo", code: "LEO", name: "LEO", mayaAsset: "ARB.LEO-0X93864D81175095DD93360FFA2A529B8642F76A6E", chain: "ARB"),
        MayaCryptoCurrency(id: "usdc_arb", code: "USDC", name: "USD Coin", mayaAsset: "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831", chain: "ARB"),
        MayaCryptoCurrency(id: "usdt_arb", code: "USDT", name: "Tether", mayaAsset: "ARB.USDT-0XFD086BC7CD5C481DCC9C85EBE478A1C0B69FCBB9", chain: "ARB"),
        MayaCryptoCurrency(id: "usdt0_arb", code: "USDT0", name: "USDT0", mayaAsset: "ARB.USDT0-0XFD086BC7CD5C481DCC9C85EBE478A1C0B69FCBB9", chain: "ARB"),
        MayaCryptoCurrency(id: "wbtc", code: "WBTC", name: "Wrapped Bitcoin", mayaAsset: "ARB.WBTC-0X2F2A2543B76A4166549F7AAB2E75BEF0AEFC5B0F", chain: "ARB"),
        MayaCryptoCurrency(id: "weth_arb", code: "WETH", name: "WETH", mayaAsset: "ARB.WETH-0X82AF49447D8A07E3BD95BD0D56F35241523FBAB1", chain: "ARB"),
        MayaCryptoCurrency(id: "wsteth_arb", code: "WSTETH", name: "Wrapped stETH", mayaAsset: "ARB.WSTETH-0X5979D7B546E38E414F7E9822514BE443A4800529", chain: "ARB"),
        MayaCryptoCurrency(id: "yum", code: "YUM", name: "YUM", mayaAsset: "ARB.YUM-0X9F41B34F42058A7B74672055A5FAE22C4B113FD1", chain: "ARB"),

        // AVAX
        MayaCryptoCurrency(id: "avax", code: "AVAX", name: "Avalanche", mayaAsset: "AVAX.AVAX", chain: "AVAX"),
        MayaCryptoCurrency(id: "usdc_avax", code: "USDC", name: "USDC", mayaAsset: "AVAX.USDC-0XB97EF9EF8734C71904D8002F8B6BC66DD9C48A6E", chain: "AVAX"),
        MayaCryptoCurrency(id: "usdt_avax", code: "USDT", name: "Tether", mayaAsset: "AVAX.USDT-0X9702230A8EA53601F5CD2DC00FDBC13D4DF4A8C7", chain: "AVAX"),

        // BASE
        MayaCryptoCurrency(id: "cbbtc_base", code: "cbBTC", name: "Coinbase Wrapped BTC", mayaAsset: "BASE.CBBTC-0XCBB7C0000AB88B473B1F5AFD9EF808440EED33BF", chain: "BASE"),
        MayaCryptoCurrency(id: "cfi_base", code: "CFI", name: "ConsumerFi Protocol", mayaAsset: "BASE.CFI-0X0382E3FEE4A420BD446367D468A6F00225853420", chain: "BASE"),
        MayaCryptoCurrency(id: "eth_base", code: "ETH", name: "Ethereum", mayaAsset: "BASE.ETH", chain: "BASE"),
        MayaCryptoCurrency(id: "usdc_base", code: "USDC", name: "USDC", mayaAsset: "BASE.USDC-0X833589FCD6EDB6E08F4C7C32D4F71B54BDA02913", chain: "BASE"),
        MayaCryptoCurrency(id: "weth_base", code: "WETH", name: "WETH", mayaAsset: "BASE.WETH-0X4200000000000000000000000000000000000006", chain: "BASE"),

        // BCH
        MayaCryptoCurrency(id: "bch", code: "BCH", name: "Bitcoin Cash", mayaAsset: "BCH.BCH", chain: "BCH"),

        // BERA
        MayaCryptoCurrency(id: "bera", code: "BERA", name: "Berachain", mayaAsset: "BERA.BERA", chain: "BERA"),
        MayaCryptoCurrency(id: "usdt0_bera", code: "USDT0", name: "USDT0", mayaAsset: "BERA.USDT0-0X779DED0C9E1022225F8E0630B35A9B54BE713736", chain: "BERA"),

        // BSC
        MayaCryptoCurrency(id: "aster_bsc", code: "ASTER", name: "Aster", mayaAsset: "BSC.ASTER-0X000AE314E2A2172A039B26378814C252734F556A", chain: "BSC"),
        MayaCryptoCurrency(id: "bnb", code: "BNB", name: "BNB", mayaAsset: "BSC.BNB", chain: "BSC"),
        MayaCryptoCurrency(id: "near_bsc", code: "NEAR", name: "NEAR Protocol", mayaAsset: "BSC.NEAR-0X1FA4A73A3F0133F0025378AF00236F3ABDEE5D63", chain: "BSC"),
        MayaCryptoCurrency(id: "rhea_bsc", code: "RHEA", name: "RHEA", mayaAsset: "BSC.RHEA-0X4C067DE26475E1CEFEE8B8D1F6E2266B33A2372E", chain: "BSC"),
        MayaCryptoCurrency(id: "usdc_bsc", code: "USDC", name: "USDC", mayaAsset: "BSC.USDC-0X8AC76A51CC950D9822D68B83FE1AD97B32CD580D", chain: "BSC"),
        MayaCryptoCurrency(id: "usdt_bsc", code: "USDT", name: "USDT", mayaAsset: "BSC.USDT-0X55D398326F99059FF775485246999027B3197955", chain: "BSC"),

        // DOGE
        MayaCryptoCurrency(id: "doge", code: "DOGE", name: "Dogecoin", mayaAsset: "DOGE.DOGE", chain: "DOGE"),

        // GNO
        MayaCryptoCurrency(id: "cow_gno", code: "COW", name: "COW", mayaAsset: "GNO.COW-0X177127622C4A00F3D409B75571E12CB3C8973D3C", chain: "GNO"),
        MayaCryptoCurrency(id: "eure", code: "EURe", name: "EURe", mayaAsset: "GNO.EURE-0X420CA0F9B9B604CE0FD9C18EF134C705E5FA3430", chain: "GNO"),
        MayaCryptoCurrency(id: "gno", code: "GNO", name: "GNO", mayaAsset: "GNO.GNO-0X9C58BACC331C9AA871AFD802DB6379A98E80CEDB", chain: "GNO"),
        MayaCryptoCurrency(id: "safe_gno", code: "SAFE", name: "SAFE", mayaAsset: "GNO.SAFE-0X4D18815D14FE5C3304E87B3FA18318BAA5C23820", chain: "GNO"),
        MayaCryptoCurrency(id: "usdc_gno", code: "USDC", name: "USDC", mayaAsset: "GNO.USDC-0X2A22F9C3B484C3629090FEED35F17FF8F88F76F0", chain: "GNO"),
        MayaCryptoCurrency(id: "usdt_gno", code: "USDT", name: "USDT", mayaAsset: "GNO.USDT-0X4ECABA5870353805A9F068101A40E0F32ED605C6", chain: "GNO"),
        MayaCryptoCurrency(id: "weth_gno", code: "WETH", name: "WETH", mayaAsset: "GNO.WETH-0X6A023CCD1FF6F2045C3309768EAD9E68F978F6E1", chain: "GNO"),
        MayaCryptoCurrency(id: "xdai", code: "xDAI", name: "XDAI", mayaAsset: "GNO.XDAI", chain: "GNO"),

        // KUJI

        // LTC
        MayaCryptoCurrency(id: "ltc", code: "LTC", name: "Litecoin", mayaAsset: "LTC.LTC", chain: "LTC"),

        // MAYA
        MayaCryptoCurrency(id: "cacao", code: "CACAO", name: "Maya Protocol", mayaAsset: "MAYA.CACAO", chain: "MAYA"),
        MayaCryptoCurrency(id: "maya", code: "MAYA", name: "MAYA", mayaAsset: "MAYA.MAYA", chain: "MAYA"),

        // MONAD
        MayaCryptoCurrency(id: "mon", code: "MON", name: "Monad", mayaAsset: "MONAD.MON", chain: "MONAD"),
        MayaCryptoCurrency(id: "usdc_monad", code: "USDC", name: "USDC", mayaAsset: "MONAD.USDC-0X754704BC059F8C67012FED69BC8A327A5AAFB603", chain: "MONAD"),
        MayaCryptoCurrency(id: "usdt0_monad", code: "USDT0", name: "USDT0", mayaAsset: "MONAD.USDT0-0XE7CD86E13AC4309349F30B3435A9D337750FC82D", chain: "MONAD"),

        // NEAR
        MayaCryptoCurrency(id: "near", code: "NEAR", name: "NEAR Protocol", mayaAsset: "NEAR.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "aurora_near", code: "AURORA", name: "AURORA", mayaAsset: "NEAR.AURORA-AAAAAA20D9E0E2461697782EF11675F668207961.FACTORY.BRIDGE.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "btc_near", code: "BTC", name: "BTC", mayaAsset: "NEAR.BTC-NBTC.BRIDGE.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "cfi_near", code: "CFI", name: "CFI", mayaAsset: "NEAR.CFI-CFI.CONSUMER-FI.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "eth_near", code: "ETH", name: "ETH", mayaAsset: "NEAR.ETH-ETH.BRIDGE.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "frax_near", code: "FRAX", name: "FRAX", mayaAsset: "NEAR.FRAX-853D955ACEF822DB058EB8505911ED77F175B99E.FACTORY.BRIDGE.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "itlx", code: "ITLX", name: "Intellex", mayaAsset: "NEAR.ITLX-ITLX.INTELLEX_XYZ.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "jambo", code: "JAMBO", name: "JAMBO", mayaAsset: "NEAR.JAMBO-JAMBO-1679.MEME-COOKING.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "mpdao", code: "mpDAO", name: "Meta Pool DAO", mayaAsset: "NEAR.MPDAO-MPDAO-TOKEN.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "nearkat", code: "NearKat", name: "NearKat", mayaAsset: "NEAR.NEARKAT-KAT.TOKEN0.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "noear", code: "NOEAR", name: "NOEAR", mayaAsset: "NEAR.NOEAR-NOEAR-324.MEME-COOKING.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "npro", code: "NPRO", name: "NPRO", mayaAsset: "NEAR.NPRO-NPRO.NEARMOBILE.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "nrusdt", code: "nrUsdt", name: "nrUsdt", mayaAsset: "NEAR.NRUSDT-LSD-USDT.RHEALAB.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "public_near", code: "PUBLIC", name: "PublicAI", mayaAsset: "NEAR.PUBLIC-TOKEN.PUBLICAILAB.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "purge", code: "PURGE", name: "PURGE", mayaAsset: "NEAR.PURGE-PURGE-558.MEME-COOKING.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "rhea_near", code: "RHEA", name: "RHEA", mayaAsset: "NEAR.RHEA-TOKEN.RHEALAB.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "shitzu", code: "SHITZU", name: "Shitzu", mayaAsset: "NEAR.SHITZU-TOKEN.0XSHITZU.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "stjack", code: "STJACK", name: "STJACK", mayaAsset: "NEAR.STJACK-STJACK.TKN.PRIMITIVES.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "stnear", code: "stNEAR", name: "Staked NEAR", mayaAsset: "NEAR.STNEAR-META-POOL.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "sweat", code: "SWEAT", name: "SWEAT", mayaAsset: "NEAR.SWEAT-TOKEN.SWEAT", chain: "NEAR"),
        MayaCryptoCurrency(id: "turbo_near", code: "TURBO", name: "TURBO", mayaAsset: "NEAR.TURBO-A35923162C49CF95E6BF26623385EB431AD920D3.FACTORY.BRIDGE.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "usdc_near", code: "USDC", name: "USDC", mayaAsset: "NEAR.USDC-17208628F84F5D6AD33F0DA3BBBEB27FFCB398EAC501A31BD6AD2011E36133A1", chain: "NEAR"),
        MayaCryptoCurrency(id: "usdt_near", code: "USDT", name: "USDT", mayaAsset: "NEAR.USDT-USDT.TETHER-TOKEN.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "wbtc_near", code: "wBTC", name: "wBTC", mayaAsset: "NEAR.WBTC-2260FAC5E5542A773AA44FBCFEDF7C193BC2C599.FACTORY.BRIDGE.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "wnear", code: "wNEAR", name: "Wrapped Near", mayaAsset: "NEAR.WNEAR-WRAP.NEAR", chain: "NEAR"),
        MayaCryptoCurrency(id: "zec_near", code: "ZEC", name: "ZEC", mayaAsset: "NEAR.ZEC-ZEC.OMFT.NEAR", chain: "NEAR"),

        // OP
        MayaCryptoCurrency(id: "eth_op", code: "ETH", name: "Ethereum", mayaAsset: "OP.ETH", chain: "OP"),
        MayaCryptoCurrency(id: "op", code: "OP", name: "OP", mayaAsset: "OP.OP-0X4200000000000000000000000000000000000042", chain: "OP"),
        MayaCryptoCurrency(id: "usdc_op", code: "USDC", name: "USDC", mayaAsset: "OP.USDC-0X0B2C639C533813F4AA9D7837CAF62653D097FF85", chain: "OP"),
        MayaCryptoCurrency(id: "usdt_op", code: "USDT", name: "USDT", mayaAsset: "OP.USDT-0X94B008AA00579C1307B0EF2C499AD98A8CE58E58", chain: "OP"),
        MayaCryptoCurrency(id: "weth_op", code: "WETH", name: "WETH", mayaAsset: "OP.WETH-0X4200000000000000000000000000000000000006", chain: "OP"),

        // POL
        MayaCryptoCurrency(id: "pol", code: "POL", name: "POL", mayaAsset: "POL.POL", chain: "POL"),
        MayaCryptoCurrency(id: "usdc_pol", code: "USDC", name: "USDC", mayaAsset: "POL.USDC-0X3C499C542CEF5E3811E1192CE70D8CC03D5C3359", chain: "POL"),
        MayaCryptoCurrency(id: "usdt_pol", code: "USDT", name: "USDT", mayaAsset: "POL.USDT-0XC2132D05D31C914A87C6611C10748AEB04B58E8F", chain: "POL"),
        MayaCryptoCurrency(id: "weth_pol", code: "WETH", name: "WETH", mayaAsset: "POL.WETH-0X7CEB23FD6BC0ADD59E62AC25578270CFF1B9F619", chain: "POL"),

        // SOL
        MayaCryptoCurrency(id: "sol", code: "SOL", name: "Solana", mayaAsset: "SOL.SOL", chain: "SOL"),
        MayaCryptoCurrency(id: "pengu", code: "PENGU", name: "Pudgy Penguins", mayaAsset: "SOL.PENGU-2ZMMHCVQEXDTDE6VSFS7S7D5OUODFJHE8VD1GNBOUAUV", chain: "SOL"),
        MayaCryptoCurrency(id: "spx", code: "SPX", name: "SPX6900", mayaAsset: "SOL.SPX-J3NKXXXZCNNIMJKW9HYB2K4LUXGWB6T1FTPTQVSV3KFR", chain: "SOL"),
        MayaCryptoCurrency(id: "trump", code: "TRUMP", name: "Official Trump", mayaAsset: "SOL.TRUMP-6P6XGHYF7AEE6TZKSMFSKO444WQOP15ICUSQI2JFGIPN", chain: "SOL"),
        MayaCryptoCurrency(id: "turbo_sol", code: "TURBO", name: "Turbo", mayaAsset: "SOL.TURBO-2DYZU65QA9ZDX1UEE7GX71K7FIWYUK6SZDRVJ7AUQ5WM", chain: "SOL"),
        MayaCryptoCurrency(id: "usdc_sol", code: "USDC", name: "USDC", mayaAsset: "SOL.USDC-EPJFWDD5AUFQSSQEM2QN1XZYBAPC8G4WEGGKZWYTDT1V", chain: "SOL"),
        MayaCryptoCurrency(id: "usdt_sol", code: "USDT", name: "Tether", mayaAsset: "SOL.USDT-ES9VMFRZACERMJFRF4H2FYD4KCONKY11MCCE8BENWNYB", chain: "SOL"),
        MayaCryptoCurrency(id: "wif", code: "WIF", name: "dogwifhat", mayaAsset: "SOL.$WIF-EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm", chain: "SOL"),
        MayaCryptoCurrency(id: "xbtc", code: "xBTC", name: "OKX Wrapped BTC", mayaAsset: "SOL.XBTC-CTZPWV73SN1DMGVU3ZTLV9YWSYUAANBNI19YWDAZNNKN", chain: "SOL"),
        MayaCryptoCurrency(id: "zec_sol", code: "ZEC", name: "Zcash", mayaAsset: "SOL.ZEC-A7BDIYDS5GJQGFTXF17PPRHTDKPKKRQBKTR27DXVQXAS", chain: "SOL"),

        // STRK
        MayaCryptoCurrency(id: "strk", code: "STRK", name: "Starknet", mayaAsset: "STRK.STRK", chain: "STRK"),

        // SUI
        MayaCryptoCurrency(id: "sui", code: "SUI", name: "Sui", mayaAsset: "SUI.SUI", chain: "SUI"),
        MayaCryptoCurrency(id: "usdc_sui", code: "USDC", name: "USDC", mayaAsset: "SUI.USDC-0XDBA34672E30CB065B1F93E3AB55318768FD6FEF66C15942C9F7CB846E2F900E7::USDC::USDC", chain: "SUI"),

        // THOR
        MayaCryptoCurrency(id: "rune", code: "RUNE", name: "Rune", mayaAsset: "THOR.RUNE", chain: "THOR"),

        // TON
        MayaCryptoCurrency(id: "ton", code: "TON", name: "TON", mayaAsset: "TON.TON", chain: "TON"),
        MayaCryptoCurrency(id: "usdt_ton", code: "USDT", name: "USDT", mayaAsset: "TON.USDT-EQCXE6MUTQJKFNGFAROTKOT1LZBDIIX1KCIXRV7NW2ID_SDS", chain: "TON"),

        // TRON
        MayaCryptoCurrency(id: "trx", code: "TRX", name: "Tron", mayaAsset: "TRON.TRX", chain: "TRON"),
        MayaCryptoCurrency(id: "usdt_tron", code: "USDT", name: "USDT", mayaAsset: "TRON.USDT-TR7NHQJEKQXGTCI8Q8ZY4PL8OTSZGJLJ6T", chain: "TRON"),

        // XLAYER
        MayaCryptoCurrency(id: "okb", code: "OKB", name: "OKB", mayaAsset: "XLAYER.OKB", chain: "XLAYER"),
        MayaCryptoCurrency(id: "usdc_xlayer", code: "USDC", name: "USDC", mayaAsset: "XLAYER.USDC-0X74B7F16337B8972027F6196A17A631AC6DE26D22", chain: "XLAYER"),
        MayaCryptoCurrency(id: "usdt0_xlayer", code: "USDT0", name: "USDT0", mayaAsset: "XLAYER.USDT0-0X779DED0C9E1022225F8E0630B35A9B54BE713736", chain: "XLAYER"),

        // XRP
        MayaCryptoCurrency(id: "xrp", code: "XRP", name: "XRP", mayaAsset: "XRP.XRP", chain: "XRP"),

        // ZEC
        MayaCryptoCurrency(id: "zec", code: "ZEC", name: "Zcash", mayaAsset: "ZEC.ZEC", chain: "ZEC"),
    ]

    // MARK: - Factory

    /// Returns the known `MayaCryptoCurrency` for a Maya asset string, or synthesises
    /// an unknown-coin record as a safe fallback. Returns `nil` for `DASH.DASH`.
    static func coin(for mayaAsset: String) -> MayaCryptoCurrency? {
        let normalizedAsset = mayaAsset.uppercased()

        guard normalizedAsset != "DASH.DASH" else { return nil }

        if let knownCoin = supportedCoins.first(where: { $0.mayaAsset.uppercased() == normalizedAsset }) {
            return knownCoin
        }

        // Synthesise a minimal record for assets not yet in the static list.
        let parts = mayaAsset.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        let chain = parts[0].uppercased()
        let assetComponent = parts[1]
        let code = (assetComponent.split(separator: "-", maxSplits: 1).first.map(String.init) ?? assetComponent).uppercased()

        // Generate a network-aware display name so ambiguous symbols (e.g. two USDC pools on
        // different chains) remain distinguishable without hardcoding suffixes in the UI layer.
        let chainLabel = Self.chainDisplayName(chain)
        let synthesizedName = chainLabel.isEmpty ? code : "\(code) (\(chainLabel))"

        return MayaCryptoCurrency(
            id: normalizedAsset
                .lowercased()
                .replacingOccurrences(of: ".", with: "_")
                .replacingOccurrences(of: "-", with: "_"),
            code: code,
            name: synthesizedName,
            mayaAsset: mayaAsset,
            chain: chain
        )
    }

    /// Curated lookup for `mayaAsset`, or nil when it is not part of the Android-mirrored
    /// allow-list. Returns a rich entry from `supportedCoins` when one exists, otherwise
    /// synthesises a display-safe fallback while preserving the original transported asset.
    static func knownCoin(for mayaAsset: String) -> MayaCryptoCurrency? {
        let normalizedAsset = mayaAsset.uppercased()
        guard normalizedAsset != "DASH.DASH" else { return nil }
        guard supportedAssets.contains(normalizedAsset) else { return nil }
        return supportedCoins.first { $0.mayaAsset.uppercased() == normalizedAsset }
            ?? coin(for: mayaAsset)
    }

    // MARK: - Chain display helpers

    /// Maps a Maya chain identifier to a human-readable label used in synthesised coin names.
    /// Returns the raw chain string as-is for chains not in the table.
    static func chainDisplayName(_ chain: String) -> String {
        switch chain.uppercased() {
        case "ARB":  return "Arbitrum"
        case "AVAX": return "Avalanche"
        case "BASE": return "Base"
        case "BCH":  return "Bitcoin Cash"
        case "BERA": return "Berachain"
        case "ETH":  return "Ethereum"
        case "BTC":  return "Bitcoin"
        case "BSC":  return "BNB Chain"
        case "DOGE": return "Dogecoin"
        case "GNO":  return "Gnosis"
        case "LTC":  return "Litecoin"
        case "MONAD": return "Monad"
        case "OP":   return "Optimism"
        case "POL":  return "Polygon"
        case "SOL":  return "Solana"
        case "STRK": return "Starknet"
        case "SUI":  return "Sui"
        case "NEAR": return "NEAR"
        case "TON":  return "Toncoin"
        case "TRON": return "Tron"
        case "XLAYER": return "X Layer"
        case "ZEC":  return "Zcash"
        case "XRD":  return "Radix"
        case "KUJI": return "Kujira"
        case "THOR": return "THORChain"
        case "ADA":  return "Cardano"
        case "MAYA": return "Maya"
        case "DASH": return ""   // source chain — never synthesised
        default:     return chain
        }
    }
}
