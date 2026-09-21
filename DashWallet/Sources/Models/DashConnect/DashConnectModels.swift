//
//  DashConnectModels.swift
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
import SwiftDashSDK

enum DashConnectQr: Equatable {
    case login(DashKeyRequest)
    /// A `dash-st:` payload — a serialized state transition whose kind is
    /// only known once the wallet parses it (key registration or token
    /// purchase).
    case stateTransition(DashStRequest)
}

/// What the wallet did — or still needs the user to do — with a scanned
/// `dash-st:` state transition.
enum DashConnectStAction: Equatable {
    /// Key registration was validated and published (or the derived keys
    /// were already on the identity).
    case keyRegistrationCompleted
    /// The payload is a token purchase; nothing was signed or sent yet — it
    /// awaits explicit user approval via `approveTokenPurchase(_:)`.
    case tokenPurchaseApprovalRequired(DashConnectTokenPurchaseRequest)
}

/// A pending token purchase parsed from a `dash-st:` payload, awaiting user
/// approval. Carries the raw values the purchase is rebuilt from and the
/// display fields the approval sheet renders.
struct DashConnectTokenPurchaseRequest: Equatable {
    /// Name of an already-connected app whose contract id matches the
    /// purchase's data contract, when one is stored locally. Display only.
    let appName: String?
    /// Identity the purchase debits — validated to be the wallet's own both
    /// when the request is built and again on approve.
    let ownerId: Data
    let dataContractId: Data
    let tokenId: Data
    let tokenContractPosition: UInt16
    /// The quantity as the payload asked for it: BASE UNITS, which is also
    /// what `tokenPurchase(amount:)` spends. It is a display quantity only
    /// once `tokenDecimals` says how to scale it.
    let tokenCount: UInt64
    /// Decimal places declared by the token's contract, when the wallet holds
    /// that contract locally. `nil` means the wallet cannot say — never
    /// assume zero: for an eight-decimal token that turns one token into a
    /// hundred million on an authorization screen.
    let tokenDecimals: Int?
    /// The token's declared name, when known locally. Display only.
    let tokenName: String?
    /// Total price in Platform credits, as the payload asked for it. Passed
    /// to `tokenPurchase(...)` as `expectedTotalCost`, which is the MAXIMUM
    /// the user approves: Platform rejects the transition if the current
    /// price is higher, and charges the lower amount if it is lower.
    let totalAgreedPriceCredits: UInt64
    let walletUsername: String?
    let walletIdentityId: String
}

extension DashConnectTokenPurchaseRequest {
    /// The total price converted to DASH for display, over the one
    /// credits-per-DASH definition this module already has. A second copy of
    /// the divisor is how a money display drifts from the money.
    var totalPriceDash: Decimal {
        Decimal(totalAgreedPriceCredits) / Decimal(PlatformCreditsFormatter.creditsPerDash)
    }

    /// The total price rendered for the approval sheet, at the full credit
    /// precision. Credits are 1e11 per DASH, so an eight-digit rendering
    /// silently rounds away a sub-duff remainder that is nevertheless
    /// charged — not something a money-authorization surface should hide.
    var totalPriceDashText: String {
        totalPriceDashText(locale: .current)
    }

    func totalPriceDashText(locale: Locale) -> String {
        PlatformCreditsFormatter.dashString(totalAgreedPriceCredits, locale: locale)
    }

    /// The quantity as the user should read it, and whether it is a real
    /// token amount or the raw base units the wallet could not scale.
    ///
    /// `tokenCount` is base units. Rendering it as "Tokens" without the
    /// contract's decimals states a quantity that can be wrong by orders of
    /// magnitude — 100,000,000 base units of an eight-decimal token is one
    /// token. When the decimals are unknown the number is still shown, but
    /// named for what it is rather than dressed as something else.
    var tokenQuantity: (text: String, isBaseUnits: Bool) {
        tokenQuantity(locale: .current)
    }

    /// `tokenQuantity` with the locale fixed. Every branch goes through
    /// `tokenAmountText`, so a whole count and a raw base-unit count are
    /// rendered ungrouped exactly like a scaled one; only the decimal
    /// separator follows the locale.
    func tokenQuantity(locale: Locale) -> (text: String, isBaseUnits: Bool) {
        guard let decimals = tokenDecimals, decimals > 0 else {
            return (Self.tokenAmountText(baseUnits: tokenCount, decimals: 0, locale: locale),
                    tokenDecimals == nil)
        }
        return (Self.tokenAmountText(baseUnits: tokenCount, decimals: decimals, locale: locale), false)
    }

    /// Base units rendered at the token's declared precision, with no grouping
    /// and trailing zeros trimmed.
    ///
    /// Digit placement on the integer, not `Decimal` division rendered through
    /// `NumberFormatter`: the formatter keeps ~15 significant digits, so a
    /// 16-decimal token of 9_007_199_254_740_993 base units came out as
    /// 0.900719925474099 — three base units short of the amount
    /// `tokenPurchase` actually submits. Same exact-integer approach as
    /// `PlatformCreditsFormatter.dashString`.
    private static func tokenAmountText(baseUnits: UInt64, decimals: Int, locale: Locale) -> String {
        guard decimals > 0 else { return String(baseUnits) }

        var digits = String(baseUnits)
        if digits.count <= decimals {
            digits = String(repeating: "0", count: decimals - digits.count + 1) + digits
        }
        let split = digits.index(digits.endIndex, offsetBy: -decimals)
        let whole = String(digits[..<split])
        var fraction = String(digits[split...])
        while fraction.hasSuffix("0") {
            fraction.removeLast()
        }
        guard !fraction.isEmpty else { return whole }
        return "\(whole)\(locale.decimalSeparator ?? ".")\(fraction)"
    }
}

/// Lifecycle of an app connection.
///
/// `approved` means the wallet knows about the app, but it may not be ready to
/// sign in yet: either the required login keys are not on the identity yet, or
/// the user locally turned the connection off from the wallet UI.
///
/// `active` means the app's login keys are registered on the identity and the
/// wallet has already published the matching `loginKeyResponse`.
enum ConnectionStatus: String, Codable, CaseIterable {
    case approved
    case active

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let status = ConnectionStatus(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown DashConnect status: \(rawValue)"
            )
        }
        self = status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A connected app identified by its stable contract id.
struct DAppConnection: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let url: String
    let status: ConnectionStatus
    let updatedAt: Date
}

/// A pending request derived from a scanned login QR code.
struct ConnectionRequest: Equatable {
    let appLabel: String
    let appUrl: String
    let appContractId: String
    let walletUsername: String?
    let walletIdentityId: String?
    let existingConnection: DAppConnection?
}

extension ConnectionRequest {
    /// Declaring an initializer inside the struct body would suppress the memberwise one,
    /// so this convenience lives in an extension.
    init(loginRequest: DashKeyRequest) {
        let contractId = loginRequest.contractId.toBase58String()
        let branding = DashConnectFallbackAppMetadata.resolve(
            contractId: contractId,
            unauthenticatedLabel: loginRequest.label
        )
        self.init(
            appLabel: branding.name,
            appUrl: branding.url,
            appContractId: contractId,
            walletUsername: nil,
            walletIdentityId: nil,
            existingConnection: nil
        )
    }

    init(
        loginRequest: DashKeyRequest,
        appLabel: String,
        appUrl: String,
        walletUsername: String?,
        walletIdentityId: String?,
        existingConnection: DAppConnection?
    ) {
        self.init(
            appLabel: appLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            appUrl: appUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            appContractId: loginRequest.contractId.toBase58String(),
            walletUsername: walletUsername,
            walletIdentityId: walletIdentityId,
            existingConnection: existingConnection
        )
    }
}
