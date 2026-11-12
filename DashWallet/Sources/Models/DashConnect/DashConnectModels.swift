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
    /// only known once the wallet parses it (a token purchase is the only
    /// one it takes).
    case stateTransition(DashStRequest)
}

/// What the wallet did — or still needs the user to do — with a scanned
/// `dash-st:` state transition.
enum DashConnectStAction: Equatable {
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

/// Lifecycle of an app connection. `active` means an approval's keys are
/// live on an identity of this wallet; `undelivered` means they are live but
/// the app never got its response; `confirming` means an identity update may
/// still land.
enum ConnectionStatus: String, Codable, CaseIterable {
    /// An App Connect approval whose identity update may still land.
    case confirming
    case active
    /// The app's keys are live, but its response was never published: the
    /// app holds keys it cannot use. Only a disconnect or a new QR helps.
    case undelivered
    /// Platform refused the identity update for good; the keys can never land.
    case refused
    /// The connection's keys have expired on the identity.
    case expired
    /// The user disconnected the app and no key of it is live.
    case disconnected

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
    init(id: String, name: String, url: String, status: ConnectionStatus, updatedAt: Date, seenOn: Set<String> = []) {
        self.id = id
        self.name = name
        self.url = url
        self.status = status
        self.updatedAt = updatedAt
        self.seenOn = seenOn
    }

    /// `row` with another status, as of `updatedAt`, and `seenOn`.
    init(_ row: DAppConnection, status: ConnectionStatus? = nil, seenOn: Set<String>, at updatedAt: Date? = nil) {
        self.init(
            id: row.id, name: row.name, url: row.url, status: status ?? row.status,
            updatedAt: updatedAt ?? row.updatedAt, seenOn: seenOn)
        scope = row.scope
    }

    let id: String
    let name: String
    let url: String
    let status: ConnectionStatus
    let updatedAt: Date
    /// The identities (Base58) whose last read showed the app live keys no
    /// approval of this wallet names. The wallet reads one identity at a
    /// time, so access seen on another stays known until that one is read.
    let seenOn: Set<String>
    /// Names the wallet and network a data source published this row for;
    /// `nil` on a row that was built or read from a store. Not stored. It
    /// goes back with a disconnect or a remove, so a row picked from a list
    /// that has since changed wallets is not acted on in the new one.
    var scope: String? = nil
}

/// What a disconnect left on the active identity besides the app's keys it
/// turned off.
struct DashConnectDisconnectResult: Equatable {
    /// How many of the app's keys it turned off. Each key id it fenced counts
    /// too: the fence keeps the pending sign-in's key from ever landing,
    /// which is access this disconnect took away.
    var keysTurnedOff = 0
    /// Keys a disconnect meant to turn off that are still live: an update
    /// that failed stopped it, or a read after it still shows them. A sign-in
    /// that landed under an id the disconnect meant to fence counts here too.
    /// The connection stays and Disconnect can run again.
    var keysStillLive = 0
    /// Live App Connect keys that may be the app's but could not be checked:
    /// their bound is not in the key store yet, or an owner that decides
    /// whose they are could not be read. None of them was turned off.
    var keysNotChecked = 0
    /// Live keys of the app's owner that another app with an approval here
    /// has too: they may be that app's, and none was turned off.
    var keysNotAttributable = 0
    /// Fence keys of the wallet that a disconnect placed (the read after it
    /// shows the wallet's own fence key live, or with no read the submission
    /// reports it added) and did not turn off. The sign-in they guard can no
    /// longer land; the next disconnect turns them off. Not an error.
    var fencesLeftOn = 0
    /// Fence keys of the wallet that a disconnect meant to add and the read
    /// after it does not show (with no read: whose update was not placed):
    /// they may not be placed yet, so the sign-in can still land. Disconnect
    /// can run again.
    var fencesNotPlaced = 0
    /// A read of another identity of this wallet saw keys of the app no
    /// approval names. They can be turned off only while that identity is
    /// the active one.
    var keysOnAnotherIdentity = false
}

/// What a connection gives its app, from the intents of one identity that
/// hold it, as the connection sheet shows it.
struct ConnectionAccess: Equatable {
    /// What each key can do.
    let keys: [AppConnect.GrantedAccess.Key]
    /// The most the keys can spend together, in credits: Platform counts
    /// each key's budget apart, so it is their sum. `nil` when no key has a
    /// budget (see `hasUnlimitedKey`).
    let budgetLimit: UInt64?
    /// A key with no spending limit.
    let hasUnlimitedKey: Bool
    /// When the last of the keys stops working.
    let expiresAt: Date?
    /// The connection can receive messages encrypted to this identity.
    let receivesMessages: Bool

    /// `nil` when `intents` add no auth key; with `snapshot`, no auth key
    /// that gives access on it (`GrantedAccess(intents:snapshot:)`).
    init?(intents: [AppConnect.ConnectionIntent], snapshot: AppConnect.IdentitySnapshot? = nil) {
        let access = AppConnect.GrantedAccess(intents: intents, snapshot: snapshot)
        guard !access.keys.isEmpty else { return nil }
        self.init(access)
    }

    init(_ access: AppConnect.GrantedAccess) {
        keys = access.keys
        let budgets = access.keys.compactMap(\.totalBudget)
        budgetLimit = budgets.isEmpty ? nil : budgets.reduce(0) { sum, budget in
            let (total, overflow) = sum.addingReportingOverflow(budget)
            return overflow ? .max : total
        }
        hasUnlimitedKey = access.keys.contains { $0.totalBudget == nil }
        expiresAt = access.keys.map(\.expiresAt).max().map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        receivesMessages = access.receivesMessages
    }

    var granted: AppConnect.GrantedAccess {
        AppConnect.GrantedAccess(keys: keys, receivesMessages: receivesMessages)
    }
}

/// A connection as its sheet shows it: the app, the identity it is
/// connected on, and what it was given.
struct ConnectionDetails: Equatable {
    let appId: String
    let identityId: String?
    let username: String?
    let access: ConnectionAccess?
    /// When the connection was made: the latest of its approvals, so a
    /// renewal from a new code counts as the connection it made.
    var connectedAt: Date? = nil
    /// What is left of each key's budget, read from Platform; `nil` when it
    /// was not read (the connection is on another identity) or could not be
    /// (`fundingReadFailed`).
    var keyFunding: [KeyFunding]? = nil
    var fundingReadFailed = false
}

/// One of a connection's keys, with what is left of its budget.
struct KeyFunding: Equatable {
    /// The key is bound to the DashPay profile, not to the app's data.
    let isProfileKey: Bool
    /// What the key may spend over its life; `nil` with no limit.
    let totalBudget: UInt64?
    /// What is left of it; `nil` with no limit, or when Platform did not say.
    let remaining: UInt64?

    /// The auth keys of `intents` that are on `snapshot` and not disabled,
    /// in their order, each with its budget as Platform holds it now and
    /// what `remaining` (by key id) says is left. A key two intents name is
    /// listed once.
    static func of(
        intents: [AppConnect.ConnectionIntent], snapshot: AppConnect.IdentitySnapshot, remaining: [UInt32: UInt64?]
    ) -> [KeyFunding] {
        var listed = Set<UInt32>()
        return intents.flatMap(\.authKeys).compactMap { key in
            guard [.live, .expired].contains(AppConnect.presence(of: key, in: snapshot)),
                  let actual = snapshot.keys.first(where: { $0.id == key.id }),
                  listed.insert(key.id).inserted else { return nil }
            return KeyFunding(
                isProfileKey: key.bound.map(AppConnect.isProfileBound) ?? false,
                totalBudget: actual.totalBudget,
                remaining: remaining[key.id] ?? nil)
        }
    }

    /// The ids `of(intents:snapshot:remaining:)` lists, whose remaining
    /// budgets are read from Platform.
    static func keyIds(of intents: [AppConnect.ConnectionIntent], snapshot: AppConnect.IdentitySnapshot) -> [UInt32] {
        Array(Set(intents.flatMap(\.authKeys)
            .filter { [.live, .expired].contains(AppConnect.presence(of: $0, in: snapshot)) }.map(\.id))).sorted()
    }
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
        // The label the request gives: the wallet knows no app's name or
        // website of its own.
        self.init(
            appLabel: loginRequest.label.trimmingCharacters(in: .whitespacesAndNewlines),
            appUrl: "",
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
