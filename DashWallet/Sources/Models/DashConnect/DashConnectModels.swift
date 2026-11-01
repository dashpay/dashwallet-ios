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
/// wallet has already published the matching `loginKeyResponse`. For a one-QR
/// connection it means the app holds a session key on an identity of this
/// wallet that this wallet has not disabled: the row is made once the key is
/// seen on the identity, before its response is published, and stays
/// whether or not the publish is confirmed.
///
/// `confirming` is an App Connect v2 connection whose identity update was
/// submitted and whose outcome is not known yet: its keys may be on the
/// identity, so it offers a disconnect like an active one. The disconnect
/// turns off the app's live auth keys on the active identity, including the
/// ones a waiting record holds. It is refused (`registrationPending`) while
/// a waiting record still holds a live key after that; otherwise the row
/// goes and the record stays, and an update that lands after all shows the
/// app again. A build without this
/// status drops the row on load; the grant record stays.
enum ConnectionStatus: String, Codable, CaseIterable {
    case approved
    case active
    case confirming

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

/// Which login made a connection. It decides what turning it off means:
/// a one-QR connection has a session key on the identity to disable, a
/// two-QR connection does not (see `DashConnectDataSource.disconnect`).
enum DashConnectLoginKind: String, Codable {
    case twoQR
    case oneQR
}

/// A connected app identified by its stable contract id.
struct DAppConnection: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let url: String
    let status: ConnectionStatus
    let updatedAt: Date
    var loginKind: DashConnectLoginKind = .twoQR
    /// Names the wallet and network a data source published this row for;
    /// `nil` on a row that was built or read from a store. Not stored. It
    /// goes back with a disconnect or a remove, so a row picked from a list
    /// that has since changed wallets is not acted on in the new one.
    var scope: String? = nil
}

/// What a disconnect did with the active identity's DashPay profile keys
/// that no grant record names, besides turning off the app's own keys.
struct DashConnectDisconnectResult: Equatable {
    /// How many of them it turned off.
    var profileKeysTurnedOff = 0
    /// They could not be told apart, so none was turned off; the app's own
    /// keys were.
    var profileKeysUnchecked = false
}

/// What a connection gives its app, from the grant records of one
/// identity, as the connection sheet shows it.
struct ConnectionAccess: Codable, Equatable {
    /// What each key can do; `nil` when a record predates
    /// `AppConnectGrant.grantedAccess`, and only the limits are known.
    let keys: [AppConnect.GrantedAccess.Key]?
    /// The largest budget among the keys, in credits; `nil` when no key has
    /// one (see `hasUnlimitedKey`) or none is known.
    let largestBudget: UInt64?
    /// A key with no spending limit.
    let hasUnlimitedKey: Bool
    /// When the last of the keys stops working; `nil` when a key has no
    /// expiry noted, or the records do not say for every key.
    let expiresAt: Date?
    /// The connection can receive messages encrypted to this identity.
    let receivesMessages: Bool
    /// Every grant is a one-QR login's session key.
    let isSessionKeyLogin: Bool

    /// `nil` with no grant.
    init?(grants: [AppConnectGrant]) {
        guard !grants.isEmpty else { return nil }
        let recorded = grants.compactMap(\.grantedAccess).filter { !$0.isUnreadable }
        let keys = recorded.count == grants.count ? recorded.flatMap(\.keys) : nil
        self.keys = keys
        // An older record names its primary key's limits only: with other
        // keys, its largest budget and last expiry are not known.
        func readable(_ grant: AppConnectGrant) -> AppConnect.GrantedAccess? {
            grant.grantedAccess.flatMap { $0.isUnreadable ? nil : $0 }
        }
        let isPartial = grants.contains { readable($0) == nil && !($0.additionalKeyIds ?? []).isEmpty }
        let budgets = grants.flatMap { readable($0)?.keys.map(\.totalBudget) ?? [$0.totalBudget] }
        largestBudget = isPartial ? nil : budgets.compactMap { $0 }.max()
        // An older record's primary key without a budget has no limit.
        hasUnlimitedKey = budgets.contains(where: { $0 == nil })
        // A record with no expiry noted (a key that never expires, or an
        // older record that did not note it) leaves the connection with no
        // end date to show: another key's date would not be its end.
        let expiries = grants.flatMap { grant -> [UInt64?] in
            readable(grant)?.keys.map(\.expiresAt) ?? [grant.expiresAt]
        }
        expiresAt = isPartial || expiries.contains(nil)
            ? nil : expiries.compactMap { $0 }.max().map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        receivesMessages = recorded.contains(where: \.receivesMessages)
        isSessionKeyLogin = recorded.count == grants.count && recorded.allSatisfy(\.isSessionKeyLogin)
    }
}

/// A connection as its sheet shows it: the app, the identity it is
/// connected on, and what it was given.
struct ConnectionDetails: Equatable {
    let appId: String
    let identityId: String?
    let username: String?
    let access: ConnectionAccess?
    /// When the connection was made: the latest of its grants' approvals,
    /// so a renewal from a new code counts as the connection it made.
    var connectedAt: Date? = nil
    /// What is left of each key's budget, read from Platform; `nil` when it
    /// was not read (a disconnected app, or the connection is on another
    /// identity) or could not be (`fundingReadFailed`).
    var keyFunding: [KeyFunding]? = nil
    var fundingReadFailed = false
}

/// One of a connection's keys, with what is left of its budget.
struct KeyFunding: Equatable {
    /// The key is bound to the DashPay profile, not to the app's data.
    let isProfileKey: Bool
    /// What the key may spend over its life; `nil` with no limit or when
    /// not known (`isBudgetKnown`).
    let totalBudget: UInt64?
    /// The record says what the key's budget is (or that it has none). An
    /// older record names its primary key's only.
    var isBudgetKnown = true
    /// What is left of it; `nil` with no limit, or when Platform did not say.
    let remaining: UInt64?

    /// The keys of `grants` in their order, each with its budget as the
    /// grant recorded it and what `remaining` (by key id) says is left. A
    /// record from before `grantedAccess` knows its primary key's budget
    /// only, and no key of it as the DashPay profile's.
    /// A key two grants name is listed once.
    static func of(grants: [AppConnectGrant], remaining: [UInt32: UInt64?]) -> [KeyFunding] {
        var listed = Set<UInt32>()
        return grants.flatMap { grant -> [KeyFunding] in
            let keys = grant.grantedAccess.flatMap { $0.isUnreadable ? nil : $0.keys }
            return grant.keyIds.enumerated().compactMap { index, keyId -> KeyFunding? in
                guard listed.insert(keyId).inserted else { return nil }
                let key = keys.flatMap { index < $0.count ? $0[index] : nil }
                let isProfileKey: Bool
                if case .documentType(let contractId, let name)? = key?.bound {
                    isProfileKey = contractId.toBase58String() == AppConnect.dashPayContractId && name == "profile"
                } else {
                    isProfileKey = false
                }
                let isBudgetKnown = key != nil || index == 0
                return KeyFunding(
                    isProfileKey: isProfileKey,
                    totalBudget: key.map(\.totalBudget) ?? (index == 0 ? grant.totalBudget : nil),
                    isBudgetKnown: isBudgetKnown,
                    remaining: remaining[keyId] ?? nil)
            }
        }
    }
}

/// Whether an app's keys are past their expiry on Platform but still on.
enum ConnectionExpiry: Equatable {
    /// Every key of the app's grants on the active identity is past its
    /// expiry and still enabled: it can no longer sign, and a disconnect
    /// turns the keys off.
    case expired
    case current
    /// The identity could not be read, or the view lacks one of the keys:
    /// reading again may tell.
    case unknown
    /// The app's recorded keys are all off on Platform while its records
    /// say it is connected (turned off elsewhere): reading again tells the
    /// same.
    case keysOff
    /// The app has no live grant on the active identity: there is nothing
    /// of this identity's to judge.
    case notJudged
}

/// A pending request derived from a scanned login QR code.
struct ConnectionRequest: Equatable {
    let appLabel: String
    let appUrl: String
    let appContractId: String
    let walletUsername: String?
    let walletIdentityId: String?
    let existingConnection: DAppConnection?
    /// The login approving this request would run.
    var login: AppConnect.Login = .unresolved
    /// Why the login is unresolved, when the wallet knows.
    var unresolvedLoginReason: String? = nil
    /// Names the wallet and network this request was resolved for; `nil`
    /// when it was not resolved against one. An approval runs only while it
    /// is still the active one.
    var scope: String? = nil
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
        existingConnection: DAppConnection?,
        login: AppConnect.Login = .unresolved,
        unresolvedLoginReason: String? = nil,
        scope: String? = nil
    ) {
        self.init(
            appLabel: appLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            appUrl: appUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            appContractId: loginRequest.contractId.toBase58String(),
            walletUsername: walletUsername,
            walletIdentityId: walletIdentityId,
            existingConnection: existingConnection,
            login: login,
            unresolvedLoginReason: unresolvedLoginReason,
            scope: scope
        )
    }

    /// Whether this request, as a sheet showed it, was resolved for the
    /// identity, wallet and network an approval is about to run for.
    func wasResolved(forIdentityId identityId: String, scope: String) -> Bool {
        walletIdentityId == identityId && self.scope == scope
    }
}

extension AppConnect.SessionKeyTerms {
    /// The budget as DASH at full credit precision, e.g. "0.05 DASH".
    var budgetText: String {
        PlatformCreditsFormatter.dashString(budgetCredits)
    }

    /// The lifetime in whole days.
    var lifetimeDays: Int {
        Int(lifetime / (24 * 60 * 60))
    }
}
