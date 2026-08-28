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
/// Mirrors Android's `SwapKitErrors`.
///
/// SwapKit reports a failure in one of two places, and the code is the only stable identifier in
/// either: the top-level `error` field (`noRoutesFound`, `validation_error`, …) on a non-2xx body,
/// or `providerErrors[].errorCode` on a 200 that carries no routes. Provider-level failures reach
/// this type through `providerErrorMessage(_:)`, which puts the code back in front of the prose so
/// a single `"<code>: <detail>"` shape covers both — matching on the prose instead would drop
/// `sellAssetAmountTooSmall` into the generic copy, which is exactly the case where the user needs
/// to be told to raise the amount.
enum SwapKitErrorCopy {
    static let mayaMemoTooLongErrorCode = "mayaMemoTooLong"
    /// Top-level code for "no provider can carry this pair/amount", lowercased for matching.
    static let noRoutesFoundCode = "noroutesfound"

    /// A provider-level failure rendered in the same `"<code>: <detail>"` shape the top-level
    /// `error` field uses, so both reach `message(for:coin:minimum:)` through one path.
    /// Nil when the provider reported neither a code nor prose.
    static func providerErrorMessage(_ error: SwapKitProviderError?) -> String? {
        let code = error?.errorCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (code?.isEmpty == false ? code : nil, detail?.isEmpty == false ? detail : nil) {
        case let (code?, detail?):
            return "\(code): \(detail)"
        case let (code?, nil):
            return code
        case let (nil, detail?):
            return detail
        case (nil, nil):
            return nil
        }
    }

    /// True when the failure means "the sell amount is under what this route can fill" — the case
    /// the amount screens surface inline (raise the amount and retry) instead of as a dead end.
    /// `noRoutesFound` is included because SwapKit answers with it for amounts far below the
    /// minimum and only switches to an explicit below-minimum code close to the floor: measured
    /// 2026-08-28, DASH → BTC returned `noRoutesFound` at 0.01 DASH and `sellAssetAmountTooSmall`
    /// (min 0.175) at 0.05. It is genuinely ambiguous — a route can also be briefly unavailable —
    /// so its copy stays neutral.
    static func isAmountTooLow(_ rawError: String?) -> Bool {
        let code = code(of: rawError)
        return code == noRoutesFoundCode || isBelowMinimumCode(code)
    }

    static func message(for rawError: String?, coin: SwapCryptoCurrency) -> String {
        let code = code(of: rawError)

        // Per-provider below-minimum codes are family-matched rather than enumerated: SwapKit does
        // not document the per-provider vocabulary, and the prefix names whichever side was too
        // small (`sellAssetAmountTooSmall` today). Both forms carry "amount", so an unrelated
        // below-threshold code — a too-low fee, say — stays out.
        if isBelowMinimumCode(code) {
            return NSLocalizedString(
                "This amount is below the minimum for this swap. Please enter a larger amount.",
                comment: "Dash DEX / dex_error_amount_too_small"
            )
        }

        switch code {
        // `memoTooLongForSourceChain` is SwapKit's own name for what the wallet also detects
        // locally before broadcasting; both mean the OP_RETURN will not fit.
        case "mayamemotoolong", "memotoolongforsourcechain":
            // Two things drive the memo past the 80-byte OP_RETURN limit: the destination
            // address, and the amount-dependent streaming-limit field. Measured on 2026-08-04,
            // one ARB.YUM route to a fixed address ran 79 / 80 / 79 / 79 bytes at 0.1 / 1 / 10 /
            // 50 DASH — so blaming the address alone would send the user to the wrong fix.
            let chainLabel = SwapCryptoCurrency.chainDisplayName(coin.chain)
            return String(format: NSLocalizedString(
                "This swap's Maya instruction doesn't fit in a Dash transaction. Try a different amount, or a shorter %@ address.",
                comment: "Dash DEX / dex_error_maya_memo_too_long"
            ), chainLabel)
        case noRoutesFoundCode:
            return NSLocalizedString(
                "This amount can't be swapped right now. Routes can be briefly unavailable — try again shortly, or try a different amount.",
                comment: "Dash DEX / dex_error_no_route"
            )
        case "blacklistasset", "invalidasset":
            return String(format: NSLocalizedString(
                "%@ can't be swapped at the moment.",
                comment: "Dash DEX / dex_error_blacklisted"
            ), coin.code)
        case "invalidrequest", "validation_error":
            return NSLocalizedString(
                "We couldn't set up your swap. Please check the amount and address, then try again.",
                comment: "Dash DEX / dex_error_validation"
            )
        // `apiRequestFailed` is SwapKit failing to reach the provider it quotes through — an
        // upstream outage from the user's side, same as an unavailable swap desk.
        case "apikeyinvalid", "unauthorized", "apirequestfailed":
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
        // `invalidRoute` is a quoted route SwapKit then refuses to execute — nothing the user can
        // correct, and retrying re-quotes, so it takes the same copy as a failed build.
        case "unabletobuildtransaction", "invalidroute":
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

    /// True when the failure is the top-level "no provider can carry this pair/amount" code —
    /// which SwapKit also reports per provider inside `providerErrors[]`.
    static func isNoRoute(_ rawError: String?) -> Bool {
        code(of: rawError) == noRoutesFoundCode
    }

    /// True when the failure is specifically "under this route's minimum" — the unambiguous half
    /// of [isAmountTooLow]. Routability probing needs this narrower test: a provider-level
    /// `noRoutesFound` really does mean the provider can't carry the asset, whereas a
    /// below-minimum reply only says the probe amount was too small.
    static func isBelowMinimum(_ rawError: String?) -> Bool {
        isBelowMinimumCode(code(of: rawError))
    }

    private static func isBelowMinimumCode(_ code: String) -> Bool {
        code.hasSuffix("amounttoosmall") || code.hasSuffix("amounttoolow")
    }

    /// The SwapKit code carried by a raw error: the leading token before an optional
    /// `": <detail>"`, lowercased, so a bare `validation_error` and `validation_error: <detail>`
    /// both match.
    private static func code(of rawError: String?) -> String {
        rawError?
            .components(separatedBy: ":")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? ""
    }
}
