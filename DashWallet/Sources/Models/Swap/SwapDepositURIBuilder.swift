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

        if chain == "SOL" {
            return solanaPayURI(for: coin, address: trimmedAddress, amount: amount)
        }

        if chain == "ADA" {
            return cardanoURI(address: trimmedAddress, amount: amount)
        }

        if chain == "SUI" {
            return suiPayURI(for: coin, address: trimmedAddress, amount: amount)
        }

        // Non-EVM, non-UTXO, non-SOL, non-ADA, non-SUI chains (NEAR, TRON, STRK, …): no scheme most
        // wallets honor, so encode the bare address — the user picks asset/amount in their wallet.
        return trimmedAddress
    }

    /// True when the URI for this coin is a bare deposit address with no amount/memo embedded
    /// (i.e. non-EVM, non-UTXO, non-SOL, non-ADA, non-SUI chains such as NEAR, Cosmos, TON, XRP…).
    static func isBareURI(for coin: SwapCryptoCurrency) -> Bool {
        let chain = coin.chain.uppercased()
        return !isUTXOChain(chain) && evmChainIDs[chain] == nil
            && chain != "SOL" && chain != "ADA" && chain != "SUI"
    }

    static func isUTXOChain(_ chain: String) -> Bool {
        switch chain.uppercased() {
        case "BTC", "BCH", "DOGE", "LTC", "ZEC":
            return true
        default:
            return false
        }
    }

    /// The amount to display in the "Amount to send" row, rounded to the asset's real on-chain
    /// decimals so a token like USDC (6 decimals) never shows an un-sendable 8-decimal value.
    /// Matches the rounding used for the URI's base-unit amount. Non-EVM chains are shown as-is.
    ///
    /// Rounds UP: the swap provider refunds a deposit that falls even one base unit short of the
    /// quoted amount, while an overpayment of one base unit is accepted. Rounding down here is what
    /// caused a quoted 5.701673 USDC to be deposited as 5.701672 and refunded.
    static func displaySendAmount(for coin: SwapCryptoCurrency, amount: String) -> String {
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let places = displayDecimals(for: coin),
              let value = Decimal(string: trimmed) else {
            return trimTrailingZeros(trimmed)
        }
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, places, .up)
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
            guard let value = baseUnits(amount, decimals: nativeDecimals) else {
                return address
            }
            return "ethereum:\(address)@\(chainID)?value=\(value)"
        }

        // ERC-20 token: EIP-681 /transfer form. Decimals default to 18 (ERC-20 norm) for tokens
        // outside the special-cased set, so most tokens get a proper URI instead of a bare address.
        guard let value = baseUnits(amount, decimals: tokenDecimals(for: coin)) else {
            return address
        }
        return "ethereum:\(contract)@\(chainID)/transfer?address=\(address)&uint256=\(value)"
    }

    /// ERC-20 contract = the part after the first "-" in the SwapKit asset id
    /// (e.g. `ARB.USDC-0xaf88…` → `0xaf88…`), lower-cased. Empty for native-coin entries.
    private static func tokenContract(for coin: SwapCryptoCurrency) -> String {
        guard let range = coin.swapAsset.range(of: "-") else { return "" }
        return String(coin.swapAsset[range.upperBound...]).lowercased()
    }

    /// Token base-unit exponent. Special-cases the common non-18 ERC-20s (stablecoins, wrapped BTC)
    /// and defaults to **18** for everything else — the ERC-20 norm, and what Android does. Most
    /// tokens are 18-decimal; defaulting to 18 lets us emit a proper EIP-681 URI for them instead
    /// of falling back to a bare address. (A rare non-18 token outside the special cases would get
    /// an off-by-10^n `uint256`; the "Amount to send" row remains the human-readable source of truth.)
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
        if tokenContract(for: coin).isEmpty { return nativeDecimals }
        return tokenDecimals(for: coin)
    }

    /// `amount × 10^decimals`, rounded up to a whole base unit, as a plain integer string
    /// (no exponent). Rounds up for the same reason as `displaySendAmount` — a deposit one base
    /// unit short of the quote gets refunded, one unit over does not — and so the `uint256` the
    /// external wallet sends always matches the amount we display.
    /// Returns nil when the amount is unparseable or ≤ 0 — callers must omit the amount
    /// parameter from the URI rather than encoding a zero-value payment request.
    private static func baseUnits(_ amount: String, decimals: Int) -> String? {
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reject anything containing grouping separators, currency symbols, or other
        // non-decimal characters — Decimal(string:) silently truncates at the first
        // non-numeric character (e.g. "2,000" → 2), which would under-encode the amount.
        guard trimmed.range(of: #"^\d*\.?\d+$"#, options: .regularExpression) != nil else { return nil }
        guard let value = Decimal(string: trimmed), value > 0 else { return nil }

        var multiplier = Decimal(1)
        for _ in 0..<decimals { multiplier *= 10 }

        var scaled = value * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .up)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    // MARK: - Solana Pay

    private static func solanaPayURI(for coin: SwapCryptoCurrency, address: String, amount: String) -> String {
        var components = URLComponents()
        components.scheme = "solana"
        components.path = address

        var items = [URLQueryItem]()
        // Solana Pay amount is in TOKEN (UI) units, not base units — pass the human amount as-is
        // (only when it's a well-formed decimal; otherwise omit rather than emit a bad amount).
        let trimmedAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAmount.isEmpty, Decimal(string: trimmedAmount) != nil {
            items.append(URLQueryItem(name: "amount", value: trimmedAmount))
        }
        let mint = splTokenMint(for: coin)   // original-case, NOT lowercased
        if !mint.isEmpty {
            items.append(URLQueryItem(name: "spl-token", value: mint))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? address
    }

    /// SPL mint = the segment after the first "-" in the SwapKit asset id, preserving case.
    /// Empty for native SOL (`SOL.SOL`). Case-sensitive — never lowercase (base58).
    private static func splTokenMint(for coin: SwapCryptoCurrency) -> String {
        guard let range = coin.swapAsset.range(of: "-") else { return "" }
        return String(coin.swapAsset[range.upperBound...])
    }

    // MARK: - Cardano (CIP-13)

    // Uses string concatenation rather than URLComponents — `web+cardano` contains `+` which
    // URLComponents percent-encodes in the scheme position. Address and amount are URL-safe.
    private static func cardanoURI(address: String, amount: String) -> String {
        let trimmedAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAmount.isEmpty, Decimal(string: trimmedAmount) != nil {
            return "web+cardano:\(address)?amount=\(trimmedAmount)"
        }
        return "web+cardano:\(address)"
    }

    // MARK: - Sui (Payment Kit URI)

    /// Full type identifier for native SUI (Payment Kit `coinType`).
    private static let suiNativeCoinType =
        "0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI"

    /// Builds a Sui Payment Kit transaction URI (`sui:pay?…`), which Sui wallets (e.g. Slush) honor.
    /// `amount` is base units of the coin type (MIST for native SUI, 9 decimals; SUI-native USDC is
    /// 6 decimals). `nonce` is required (unique ASCII ≤36 chars). `registry` is omitted → ephemeral
    /// P2P transfer with no on-chain record, which is exactly what a deposit needs.
    private static func suiPayURI(for coin: SwapCryptoCurrency, address: String, amount: String) -> String {
        // Amount must be encodable; otherwise fall back to the bare address (never a bad amount).
        guard let value = baseUnits(amount, decimals: suiDecimals(for: coin)) else {
            return address
        }

        var components = URLComponents()
        components.scheme = "sui"
        components.path = "pay"
        components.queryItems = [
            URLQueryItem(name: "receiver", value: address),
            URLQueryItem(name: "amount", value: value),
            URLQueryItem(name: "coinType", value: suiCoinType(for: coin)),
            URLQueryItem(name: "nonce", value: suiNonce(for: address)),
        ]
        return components.string ?? address
    }

    /// On-chain decimals for the Sui coin: native SUI is 9 (MIST); Sui-native USDC is 6.
    private static func suiDecimals(for coin: SwapCryptoCurrency) -> Int {
        coin.code.uppercased() == "USDC" ? 6 : 9
    }

    /// Sui `coinType` = the segment after the first "-" in the SwapKit asset id, preserving case
    /// (e.g. `SUI.USDC-0x…::USDC` → `0x…::USDC`). Native SUI (`SUI.SUI`) has no "-" → the 0x2 type.
    private static func suiCoinType(for coin: SwapCryptoCurrency) -> String {
        guard let range = coin.swapAsset.range(of: "-") else { return suiNativeCoinType }
        return String(coin.swapAsset[range.upperBound...])
    }

    /// Deterministic per-deposit `nonce`: up to 32 hex chars of the deposit address (ASCII, ≤36).
    /// Stable across re-renders and unique per deposit; ephemeral payments don't enforce uniqueness.
    private static func suiNonce(for address: String) -> String {
        let hex = address.hasPrefix("0x") || address.hasPrefix("0X") ? String(address.dropFirst(2)) : address
        return String(hex.prefix(32))
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
        let scheme = utxoScheme(for: chain)
        components.scheme = scheme

        // Some backends return the address WITH its scheme prefix (notably BCH CashAddr:
        // "bitcoincash:qqm88…"). Strip a duplicate leading "<scheme>:" so we don't emit
        // "bitcoincash:bitcoincash%3Aqqm…" (a malformed URI no wallet can parse).
        var addr = address
        let prefix = scheme + ":"
        if addr.lowercased().hasPrefix(prefix.lowercased()) {
            addr = String(addr.dropFirst(prefix.count))
        }
        components.path = addr

        var items = [URLQueryItem]()
        let trimmedAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let amountIsValid = trimmedAmount.range(of: #"^\d*\.?\d+$"#, options: .regularExpression) != nil
            && Decimal(string: trimmedAmount).map { $0 > 0 } == true
        if amountIsValid {
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
