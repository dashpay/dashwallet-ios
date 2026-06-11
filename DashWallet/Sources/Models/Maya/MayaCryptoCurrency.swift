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
    /// Human-readable name (e.g. `"Bitcoin"`, `"USD Coin (Arbitrum)"`).
    let name: String
    /// Maya pool asset string used in API calls (e.g. `"BTC.BTC"`, `"ETH.USDC-0XA0B8..."`).
    let mayaAsset: String
    /// Maya chain identifier used for local address validation (e.g. `"BTC"`, `"ARB"`).
    let chain: String
    /// Name of the local image asset. `"convert.crypto"` is the generic placeholder,
    /// used when no dedicated local icon exists — `MayaCoinIconView` falls back to
    /// remote loading in that case.
    let iconAssetName: String

    // MARK: - Supported Coins

    /// Curated set of Maya/SwapKit assets the wallet exposes in the Select Coin picker.
    /// Mirrors Android `MayaCurrencyList.all` (kept in sync with SwapKit `/swapTo`).
    /// Source: `~/Desktop/swapkit-integration/android-supported-coins.txt`
    static let supportedAssets: Set<String> = [
        "ADA.ADA",
        "ARB.ARB-0X912CE59144191C1204E64559FE8253A0E49E6548",
        "ARB.DAI-0XDA10009CBD5D07DD0CECC66161FC93D7C9000DA1",
        "ARB.ETH",
        "ARB.GLD-0XAFD091F140C21770F4E5D53D26B2859AE97555AA",
        "ARB.LEO-0X93864D81175095DD93360FFA2A529B8642F76A6E",
        "ARB.LINK-0XF97F4DF75117A78C1A5A0DBB814AF92458539FB4",
        "ARB.PEPE-0X25D887CE7A35172C62FEBFD67A1856F20FAEBB00",
        "ARB.TGT-0X429FED88F10285E61B12BDF00848315FBDFCC341",
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
        "ETH.LLD-0X054C9D4C6F4EA4E14391ADDD1812106C97D05690",
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
        "KUJI.KUJI",
        "KUJI.USK",
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
        "SOL.WIF-ZCJM",
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
        "ALICE.NEAR",
        "XLAYER.OKB",
        "XLAYER.USDC-0X74B7F16337B8972027F6196A17A631AC6DE26D22",
        "XLAYER.USDT0-0X779DED0C9E1022225F8E0630B35A9B54BE713736",
        "XRD.XRD",
        "XRP.XRP",
        "ZEC.ZEC",
    ]

    /// All Maya-supported destination coins, grouped by chain.
    /// DASH is excluded — it is always the source currency.
    static let supportedCoins: [MayaCryptoCurrency] = [
        // BTC
        MayaCryptoCurrency(
            id: "btc", code: "BTC", name: "Bitcoin", mayaAsset: "BTC.BTC",
            chain: "BTC", iconAssetName: "maya.coin.btc"
        ),

        // ADA
        MayaCryptoCurrency(
            id: "ada", code: "ADA", name: "Cardano", mayaAsset: "ADA.ADA",
            chain: "ADA", iconAssetName: "convert.crypto"
        ),

        // ETH chain
        MayaCryptoCurrency(
            id: "eth", code: "ETH", name: "Ethereum", mayaAsset: "ETH.ETH",
            chain: "ETH", iconAssetName: "maya.coin.eth"
        ),
        MayaCryptoCurrency(
            id: "moca", code: "MOCA", name: "Mocaverse",
            mayaAsset: "ETH.MOCA-0X53312F85BBA24C8CB99CFFC13BF82420157230D3",
            chain: "ETH", iconAssetName: "convert.crypto"
        ),
        MayaCryptoCurrency(
            id: "pepe", code: "PEPE", name: "PEPE",
            mayaAsset: "ETH.PEPE-0X6982508145454CE325DDBE47A25D4EC3D2311933",
            chain: "ETH", iconAssetName: "maya.coin.pepe"
        ),
        MayaCryptoCurrency(
            id: "usdc", code: "USDC", name: "USD Coin",
            mayaAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
            chain: "ETH", iconAssetName: "maya.coin.usdc"
        ),
        MayaCryptoCurrency(
            id: "usdt", code: "USDT", name: "Tether",
            mayaAsset: "ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7",
            chain: "ETH", iconAssetName: "maya.coin.usdt"
        ),
        MayaCryptoCurrency(
            id: "wsteth", code: "WSTETH", name: "Wrapped stETH",
            mayaAsset: "ETH.WSTETH-0X7F39C581F595B53C5CB19BD0B3F8DA6C935E2CA0",
            chain: "ETH", iconAssetName: "maya.coin.wsteth"
        ),

        // ARB (Arbitrum One)
        MayaCryptoCurrency(
            id: "arb", code: "ARB", name: "Arbitrum",
            mayaAsset: "ARB.ARB-0X912CE59144191C1204E64559FE8253A0E49E6548",
            chain: "ARB", iconAssetName: "maya.coin.arb"
        ),
        MayaCryptoCurrency(
            id: "eth_arb", code: "ETH", name: "Ethereum (Arbitrum)", mayaAsset: "ARB.ETH",
            chain: "ARB", iconAssetName: "maya.coin.eth"
        ),
        MayaCryptoCurrency(
            id: "dai", code: "DAI", name: "Dai",
            mayaAsset: "ARB.DAI-0XDA10009CBD5D07DD0CECC66161FC93D7C9000DA1",
            chain: "ARB", iconAssetName: "maya.coin.dai"
        ),
        MayaCryptoCurrency(
            id: "gld", code: "GLD", name: "Goldario",
            mayaAsset: "ARB.GLD-0XAFD091F140C21770F4E5D53D26B2859AE97555AA",
            chain: "ARB", iconAssetName: "maya.coin.gld"
        ),
        MayaCryptoCurrency(
            id: "leo", code: "LEO", name: "LEO",
            mayaAsset: "ARB.LEO-0X93864D81175095DD93360FFA2A529B8642F76A6E",
            chain: "ARB", iconAssetName: "maya.coin.leo"
        ),
        MayaCryptoCurrency(
            id: "link", code: "LINK", name: "ChainLink",
            mayaAsset: "ARB.LINK-0XF97F4DF75117A78C1A5A0DBB814AF92458539FB4",
            chain: "ARB", iconAssetName: "maya.coin.link"
        ),
        MayaCryptoCurrency(
            id: "pepe_arb", code: "PEPE", name: "PEPE (Arbitrum)",
            mayaAsset: "ARB.PEPE-0X25D887CE7A35172C62FEBFD67A1856F20FAEBB00",
            chain: "ARB", iconAssetName: "maya.coin.pepe"
        ),
        MayaCryptoCurrency(
            id: "tgt", code: "TGT", name: "THORWallet",
            mayaAsset: "ARB.TGT-0X429FED88F10285E61B12BDF00848315FBDFCC341",
            chain: "ARB", iconAssetName: "maya.coin.tgt"
        ),
        MayaCryptoCurrency(
            id: "usdc_arb", code: "USDC", name: "USD Coin (Arbitrum)",
            mayaAsset: "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831",
            chain: "ARB", iconAssetName: "maya.coin.usdc"
        ),
        MayaCryptoCurrency(
            id: "usdt_arb", code: "USDT", name: "Tether",
            mayaAsset: "ARB.USDT-0XFD086BC7CD5C481DCC9C85EBE478A1C0B69FCBB9",
            chain: "ARB", iconAssetName: "maya.coin.usdt"
        ),
        MayaCryptoCurrency(
            id: "wbtc", code: "WBTC", name: "Wrapped Bitcoin",
            mayaAsset: "ARB.WBTC-0X2F2A2543B76A4166549F7AAB2E75BEF0AEFC5B0F",
            chain: "ARB", iconAssetName: "maya.coin.wbtc"
        ),
        MayaCryptoCurrency(
            id: "wsteth_arb", code: "WSTETH", name: "Wrapped stETH",
            mayaAsset: "ARB.WSTETH-0X5979D7B546E38E414F7E9822514BE443A4800529",
            chain: "ARB", iconAssetName: "maya.coin.wsteth"
        ),
        MayaCryptoCurrency(
            id: "yum", code: "YUM", name: "YUM",
            mayaAsset: "ARB.YUM-0X9F41B34F42058A7B74672055A5FAE22C4B113FD1",
            chain: "ARB", iconAssetName: "convert.crypto"
        ),

        // Other chains
        MayaCryptoCurrency(
            id: "kuji", code: "KUJI", name: "Kujira", mayaAsset: "KUJI.KUJI",
            chain: "KUJI", iconAssetName: "maya.coin.kuji"
        ),
        MayaCryptoCurrency(
            id: "rune", code: "RUNE", name: "Rune", mayaAsset: "THOR.RUNE",
            chain: "THOR", iconAssetName: "maya.coin.rune"
        ),
        MayaCryptoCurrency(
            id: "sol", code: "SOL", name: "Solana", mayaAsset: "SOL.SOL",
            chain: "SOL", iconAssetName: "convert.crypto"
        ),
        MayaCryptoCurrency(
            id: "near", code: "NEAR", name: "NEAR Protocol", mayaAsset: "NEAR.NEAR",
            chain: "NEAR", iconAssetName: "convert.crypto"
        ),
        MayaCryptoCurrency(
            id: "trx", code: "TRX", name: "Tron", mayaAsset: "TRON.TRX",
            chain: "TRON", iconAssetName: "convert.crypto"
        ),
        MayaCryptoCurrency(
            id: "zec", code: "ZEC", name: "Zcash", mayaAsset: "ZEC.ZEC",
            chain: "ZEC", iconAssetName: "convert.crypto"
        ),
        MayaCryptoCurrency(
            id: "xrd", code: "XRD", name: "Radix", mayaAsset: "XRD.XRD",
            chain: "XRD", iconAssetName: "convert.crypto"
        ),
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
            chain: chain,
            iconAssetName: "convert.crypto"
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
