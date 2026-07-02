//
//  SwapDepositURIBuilder.swift
//  DashWallet
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

import Foundation

/// Builds the deposit payment URI encoded in the Buy "Send {COIN}" QR code.
///
/// Mirrors Android (`SwapCryptoCurrency.getPaymentRequestURI`):
/// - UTXO chains (BTC/BCH/LTC/DOGE/ZEC) → BIP21 `bitcoin:<addr>?amount=…`.
/// - EVM chains → EIP-681:
///     - native gas coin → `ethereum:<addr>@<chainId>?value=<amount·1e18>`
///     - ERC-20 token   → `ethereum:<contract>@<chainId>/transfer?address=<addr>&uint256=<amount·10^decimals>`
/// - Any other chain → the bare deposit address (no widely-honored URI scheme).
enum SwapDepositURIBuilder {

    // MARK: - Public

    static func uri(for coin: SwapCryptoCurrency, address: String, amount: String, memo: String?) -> String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return "" }

        let chain = coin.chain.uppercased()

        if isUTXOChain(chain) {
            return utxoURI(chain: chain, address: trimmedAddress, amount: amount, memo: memo)
        }

        if let chainId = evmChainIDs[chain] {
            return evmURI(for: coin, address: trimmedAddress, amount: amount, chainID: chainId)
        }

        // Non-EVM, non-UTXO chains (Cosmos, Solana, NEAR, Sui, …): no scheme most wallets honor,
        // so encode the bare address — the user picks asset/amount in their wallet.
        return trimmedAddress
    }

    static func isUTXOChain(_ chain: String) -> Bool {
        switch chain.uppercased() {
        case "BTC", "BCH", "DOGE", "LTC", "ZEC":
            return true
        default:
            return false
        }
    }

    /// The amount to display in the "Amount to send" row, truncated to the asset's real on-chain
    /// decimals so a token like USDC (6 decimals) never shows an un-sendable 8-decimal value.
    /// Matches the truncation used for the URI's base-unit amount. Non-EVM chains are shown as-is.
    static func displaySendAmount(for coin: SwapCryptoCurrency, amount: String) -> String {
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let places = displayDecimals(for: coin),
              let value = Decimal(string: trimmed) else {
            return trimTrailingZeros(trimmed)
        }
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, places, .down)
        return trimTrailingZeros(NSDecimalNumber(decimal: rounded).stringValue)
    }

    // MARK: - EVM (EIP-681)

    private static let nativeDecimals = 18

    /// SwapKit/Maya chain prefix → EIP-155 chain id (mirrors Android `EVM_CHAIN_IDS`).
    private static let evmChainIDs: [String: Int] = [
        "ETH": 1,
        "OP": 10,
        "BSC": 56,
        "GNO": 100,
        "POL": 137,
        "MONAD": 143,
        "XLAYER": 196,
        "BASE": 8453,
        "ARB": 42161,
        "AVAX": 43114,
        "BERA": 80094,
    ]

    private static func evmURI(for coin: SwapCryptoCurrency, address: String, amount: String, chainID: Int) -> String {
        let contract = tokenContract(for: coin)

        // No contract → native gas coin (e.g. ARB.ETH): EIP-681 native value form.
        guard !contract.isEmpty else {
            let value = baseUnits(amount, decimals: nativeDecimals)
            return "ethereum:\(address)@\(chainID)?value=\(value)"
        }

        // ERC-20 token: EIP-681 /transfer form.
        let value = baseUnits(amount, decimals: tokenDecimals(for: coin))
        return "ethereum:\(contract)@\(chainID)/transfer?address=\(address)&uint256=\(value)"
    }

    /// ERC-20 contract = the part after the first "-" in the SwapKit asset id
    /// (e.g. `ARB.USDC-0xaf88…` → `0xaf88…`), lower-cased. Empty for native-coin entries.
    private static func tokenContract(for coin: SwapCryptoCurrency) -> String {
        guard let range = coin.swapAsset.range(of: "-") else { return "" }
        return String(coin.swapAsset[range.upperBound...]).lowercased()
    }

    /// Token base-unit exponent (mirrors Android `defaultDecimals`).
    private static func tokenDecimals(for coin: SwapCryptoCurrency) -> Int {
        switch coin.code.uppercased() {
        case "USDC", "USDT":
            // Binance-Peg USDC/USDT on BSC are 18 decimals; elsewhere these stablecoins are 6.
            return coin.chain.uppercased() == "BSC" ? 18 : 6
        case "USDT0":
            return 6
        case "WBTC", "CBBTC":
            return 8
        default:
            return 18
        }
    }

    /// On-chain decimals used to round the *displayed* send amount. EVM only; nil elsewhere.
    private static func displayDecimals(for coin: SwapCryptoCurrency) -> Int? {
        guard evmChainIDs[coin.chain.uppercased()] != nil else { return nil }
        return tokenContract(for: coin).isEmpty ? nativeDecimals : tokenDecimals(for: coin)
    }

    /// `amount × 10^decimals`, truncated toward zero, as a plain integer string (no exponent).
    private static func baseUnits(_ amount: String, decimals: Int) -> String {
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: trimmed), value > 0 else { return "0" }

        var multiplier = Decimal(1)
        for _ in 0..<decimals { multiplier *= 10 }

        var scaled = value * multiplier
        var truncated = Decimal()
        NSDecimalRound(&truncated, &scaled, 0, .down)
        return NSDecimalNumber(decimal: truncated).stringValue
    }

    private static func trimTrailingZeros(_ s: String) -> String {
        guard s.contains(".") else { return s }
        var result = s
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    // MARK: - UTXO (BIP21)

    private static func utxoURI(chain: String, address: String, amount: String, memo: String?) -> String {
        var components = URLComponents()
        components.scheme = utxoScheme(for: chain)
        components.path = address

        var items = [URLQueryItem]()
        let trimmedAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAmount.isEmpty {
            items.append(URLQueryItem(name: "amount", value: trimmedAmount))
        }
        if let memo = memo?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty {
            items.append(URLQueryItem(name: "message", value: memo))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? address
    }

    private static func utxoScheme(for chain: String) -> String {
        switch chain.uppercased() {
        case "BTC":  return "bitcoin"
        case "BCH":  return "bitcoincash"
        case "DOGE": return "dogecoin"
        case "LTC":  return "litecoin"
        case "ZEC":  return "zcash"
        default:     return "bitcoin"
        }
    }
}
