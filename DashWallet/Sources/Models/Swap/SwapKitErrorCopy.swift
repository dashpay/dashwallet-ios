//
//  SwapKitErrorCopy.swift
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

/// Maps raw SwapKit error code strings to user-facing messages.
/// Mirrors Android's `SwapKitErrors.messageResFor`.
enum SwapKitErrorCopy {
    static let mayaMemoTooLongErrorCode = "mayaMemoTooLong"

    static func message(for rawError: String?, coin: SwapCryptoCurrency) -> String {
        let code = rawError?
            .components(separatedBy: ":")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? ""

        switch code {
        case "mayamemotoolong":
            // Two things drive the memo past the 80-byte OP_RETURN limit: the destination
            // address, and the amount-dependent streaming-limit field. Measured on 2026-08-04,
            // one ARB.YUM route to a fixed address ran 79 / 80 / 79 / 79 bytes at 0.1 / 1 / 10 /
            // 50 DASH — so blaming the address alone would send the user to the wrong fix.
            let chainLabel = SwapCryptoCurrency.chainDisplayName(coin.chain)
            return String(format: NSLocalizedString(
                "This swap's Maya instruction doesn't fit in a Dash transaction. Try a different amount, or a shorter %@ address.",
                comment: "Dash DEX / dex_error_maya_memo_too_long"
            ), chainLabel)
        case "noroutesfound":
            return NSLocalizedString(
                "This amount can't be swapped right now. Routes can be briefly unavailable — try again shortly, or try a different amount.",
                comment: "Dash DEX / dex_error_no_route"
            )
        case "blacklistasset":
            return String(format: NSLocalizedString(
                "%@ can't be swapped at the moment.",
                comment: "Dash DEX / dex_error_blacklisted"
            ), coin.code)
        case "invalidrequest", "validation_error":
            return NSLocalizedString(
                "We couldn't set up your swap. Please check the amount and address, then try again.",
                comment: "Dash DEX / dex_error_validation"
            )
        case "apikeyinvalid", "unauthorized":
            return NSLocalizedString(
                "Swaps are temporarily unavailable. Please try again later.",
                comment: "Dash DEX / dex_error_unavailable"
            )
        case "swaproutenotfound":
            return NSLocalizedString(
                "This quote expired. Please go back and try again.",
                comment: "Dash DEX / dex_error_quote_expired"
            )
        case "issanctionedaddress":
            return NSLocalizedString(
                "This address can't be used for swaps.",
                comment: "Dash DEX / dex_error_sanctioned"
            )
        case "insufficientbalance":
            return NSLocalizedString(
                "The amount is more than what you're sending.",
                comment: "Dash DEX / dex_error_insufficient_balance"
            )
        case "insufficientallowance":
            return NSLocalizedString(
                "This token needs approval before it can be swapped.",
                comment: "Dash DEX / dex_error_allowance"
            )
        case "unabletobuildtransaction":
            return NSLocalizedString(
                "We couldn't prepare this swap. Please try again.",
                comment: "Dash DEX / dex_error_build_failed"
            )
        case "invalidsourceaddress":
            return String(format: NSLocalizedString(
                "That refund address isn't a valid %@ address.",
                comment: "Dash DEX / dex_error_invalid_refund_address"
            ), coin.code)
        case "invaliddestinationaddress":
            return NSLocalizedString(
                "We couldn't set up your deposit. Please try again.",
                comment: "Dash DEX / dex_error_invalid_destination"
            )
        case "outputamountdeviationtoohigh":
            return NSLocalizedString(
                "The price moved too much. Please go back and try again.",
                comment: "Dash DEX / dex_error_price_moved"
            )
        default:
            // The generic copy is a dead end for diagnosis: the screen says only "something
            // went wrong" and the raw code is dropped here, so a QA log export contains no
            // trace of what actually failed. Record it — an unmapped code is either a new
            // SwapKit error worth adding above, or a real defect.
            DWLogger.log("SwapKit: unmapped swap error for \(coin.code) — raw: \(rawError ?? "<nil>")")
            return NSLocalizedString(
                "Something went wrong setting up your swap. Please try again.",
                comment: "Dash DEX / dex_error_generic"
            )
        }
    }
}
