//
//  MayaAddressValidator.swift
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

/// Validates destination addresses for Maya swaps based on chain type.
///
/// Performs local format validation (regex-based) to catch obvious errors.
/// The Maya API provides second-level validation when the user taps Continue.
struct MayaAddressValidator {

    /// Validates whether the given address is a plausible format for the coin's chain.
    static func isValid(address: String, for coin: MayaCryptoCurrency) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        switch coin.chain {
        case "BTC":
            return isValidBitcoinAddress(trimmed)
        case "ETH", "ARB":
            return isValidEVMAddress(trimmed)
        case "KUJI":
            return isValidBech32Address(trimmed, hrp: "kujira", dataLength: 38)
        case "THOR":
            return isValidBech32Address(trimmed, hrp: "thor", dataLength: 38)
        default:
            // Unknown chain — allow any non-empty input; Maya API will validate
            return true
        }
    }

    // MARK: - Bitcoin

    /// Validates Bitcoin addresses: legacy P2PKH (1...), P2SH (3...), and Bech32 SegWit/Taproot (bc1...).
    private static func isValidBitcoinAddress(_ address: String) -> Bool {
        // Legacy Base58Check: P2PKH (1...) or P2SH (3...) — 25-34 Base58 characters
        if address.hasPrefix("1") || address.hasPrefix("3") {
            return matchesPattern("^[13][1-9A-HJ-NP-Za-km-z]{24,33}$", address)
        }

        // Bech32 SegWit and Taproot — valid lengths are exactly 42 or 62 chars total:
        //   bc1q + 38 data chars = 42 (P2WPKH witness v0, 20-byte program)
        //   bc1q + 58 data chars = 62 (P2WSH witness v0, 32-byte program)
        //   bc1p + 58 data chars = 62 (Taproot witness v1, 32-byte program)
        let lower = address.lowercased()
        if lower.hasPrefix("bc1q") {
            return matchesPattern("^bc1q[a-z0-9]{38}$", lower) ||
                   matchesPattern("^bc1q[a-z0-9]{58}$", lower)
        }
        if lower.hasPrefix("bc1p") {
            return matchesPattern("^bc1p[a-z0-9]{58}$", lower)
        }

        return false
    }

    // MARK: - EVM (Ethereum, Arbitrum)

    private static func isValidEVMAddress(_ address: String) -> Bool {
        matchesPattern("^0x[a-fA-F0-9]{40}$", address)
    }

    // MARK: - Bech32 (Kujira, THORChain)

    private static func isValidBech32Address(_ address: String, hrp: String, dataLength: Int) -> Bool {
        matchesPattern("^\(hrp)1[a-z0-9]{\(dataLength)}$", address.lowercased())
    }

    // MARK: - Helpers

    private static func matchesPattern(_ pattern: String, _ string: String) -> Bool {
        string.range(of: pattern, options: .regularExpression) != nil
    }
}
