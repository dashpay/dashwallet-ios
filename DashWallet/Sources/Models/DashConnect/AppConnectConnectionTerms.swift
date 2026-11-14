//
//  AppConnectConnectionTerms.swift
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

/// The two terms the user sets on the approve sheet for a v2 connection:
/// one funding limit for the whole connection and one expiry for all of its
/// keys. The keys are registered with what these work out to
/// (`AppConnect.applying(_:to:)`).
extension AppConnect {
    struct ConnectionTerms: Equatable {
        /// Credits, for the whole connection.
        var fundingLimit: UInt64
        /// Milliseconds since the epoch, the same for every key.
        var expiresAt: UInt64
    }

    /// The funding presets, in credits: 0.1, 0.5, 2 and 5 DASH.
    static let fundingPresets: [UInt64] = [
        PlatformCreditsFormatter.creditsPerDash / 10,
        PlatformCreditsFormatter.creditsPerDash / 2,
        2 * PlatformCreditsFormatter.creditsPerDash,
        5 * PlatformCreditsFormatter.creditsPerDash,
    ]

    /// The expiry presets, in days.
    static let expiryPresetDays: [Int] = [30, 90, 365]

    /// What a DashPay profile key gets out of the limit: enough for at least
    /// five profile updates (one costs about 0.0002 DASH, a first profile
    /// about 0.0004 DASH).
    static let profileKeyShare: UInt64 = PlatformCreditsFormatter.creditsPerDash / 500

    /// The limit the sheet opens with when the app asks for no budget at all.
    static let defaultFundingLimit: UInt64 = PlatformCreditsFormatter.creditsPerDash / 2

    /// The terms the sheet opens with: the total the app asks for, capped at
    /// `v2BudgetCapCredits`, or `defaultFundingLimit` when it asks for none
    /// (`profileKeyShare` when it asks only for DashPay profile keys); and the
    /// earliest expiry the plan gives a key (the app's request capped at a
    /// year, or the default lifetime), so no key lives longer than the app
    /// asked unless the user chooses so. The limit is raised to
    /// `smallestFundingLimit` when that is more, so every key has a budget.
    static func defaultTerms(for plan: GrantPlan, now: Date) -> ConnectionTerms {
        let requested = totalBudget(of: plan)
        let earliest = plan.auth.map(\.expiresAt).min() ?? milliseconds(now.addingTimeInterval(v2DefaultLifetime))
        let profileOnly = !plan.auth.isEmpty && plan.auth.allSatisfy(isProfileKey)
        let limit = requested == 0 ? defaultFundingLimit : min(requested, v2BudgetCapCredits)
        let shown = profileOnly ? min(limit, profileKeyShare) : limit
        return ConnectionTerms(
            fundingLimit: max(shown, smallestFundingLimit(for: plan) ?? 0),
            expiresAt: earliest)
    }

    /// The smallest funding limit that gives every key of `plan` a budget
    /// (`keyBudgets`); nil when no limit within the cap does.
    static func smallestFundingLimit(for plan: GrantPlan) -> UInt64? {
        guard !plan.auth.isEmpty else { return 1 }
        var low: UInt64 = 1
        var high = v2BudgetCapCredits
        guard keyBudgets(for: plan, limit: high) != nil else { return nil }
        while low < high {
            let mid = low + (high - low) / 2
            if keyBudgets(for: plan, limit: mid) != nil { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// Whether `credits` is a funding limit the user may set: above zero and
    /// at most `v2BudgetCapCredits`.
    static func isValidFundingLimit(_ credits: UInt64) -> Bool {
        credits > 0 && credits <= v2BudgetCapCredits
    }

    /// Whether `expiresAt` is an expiry the user may set at `now`: after it
    /// and at most `v2LifetimeCap` past it.
    static func isValidExpiry(_ expiresAt: UInt64, now: Date) -> Bool {
        expiresAt > milliseconds(now) && expiresAt <= milliseconds(now.addingTimeInterval(v2LifetimeCap))
    }

    /// The expiry `days` after `now`.
    static func expiry(days: Int, from now: Date) -> UInt64 {
        milliseconds(now.addingTimeInterval(TimeInterval(days) * 24 * 60 * 60))
    }

    /// Whether `grant` is a key for the DashPay profile.
    static func isProfileKey(_ grant: AuthGrant) -> Bool {
        grant.binding.kind == .documentType
            && allowedForeignDocumentTypes.contains("\(grant.binding.id.toBase58String())/\(grant.binding.documentTypeName ?? "")")
    }

    /// Each key's budget, in the order of `plan.auth`, for a connection
    /// limit of `limit`.
    ///
    /// The DashPay profile keys take `profileKeyShare` between them, or half
    /// of a limit under twice that; the app's own keys share the rest
    /// (`appKeyBudgets`). With no app key, the profile keys take
    /// `profileKeyShare`, or the whole limit when it is smaller.
    /// Nil when a key would get nothing: Platform needs a budget on every
    /// key.
    static func keyBudgets(for plan: GrantPlan, limit: UInt64) -> [UInt64]? {
        let profile = plan.auth.indices.filter { isProfileKey(plan.auth[$0]) }
        let app = plan.auth.indices.filter { !isProfileKey(plan.auth[$0]) }
        var budgets = [UInt64](repeating: 0, count: plan.auth.count)
        let profileTotal: UInt64
        if profile.isEmpty {
            profileTotal = 0
        } else if app.isEmpty {
            profileTotal = min(limit, profileKeyShare)
        } else {
            profileTotal = limit < 2 * profileKeyShare ? limit / 2 : profileKeyShare
        }
        for (index, share) in zip(profile, evenShares(of: profileTotal, count: profile.count)) {
            budgets[index] = share
        }
        // What the plan gives each key is the app's ask, already capped.
        let requested = app.map { plan.auth[$0].totalBudget ?? 0 }
        for (index, share) in zip(app, appKeyBudgets(of: limit - profileTotal, requested: requested)) {
            budgets[index] = share
        }
        return budgets.contains(0) ? nil : budgets
    }

    /// How the app's own keys share `total`: one credit each first, since
    /// Platform needs a budget on every key, then the rest in proportion to
    /// what each asked for (each at most `v2BudgetCapCredits`). A key that
    /// asked for nothing weighs as much as the smallest ask, and all of them
    /// evenly when none asked. The remainder of the division goes to the
    /// first key. A `total` below the number of keys gives each nothing.
    /// TODO(dashconnect-app-key-split): the product rule for several app keys
    /// is not decided yet; this is the one place to change it.
    static func appKeyBudgets(of total: UInt64, requested: [UInt64]) -> [UInt64] {
        guard !requested.isEmpty else { return [] }
        let count = UInt64(requested.count)
        guard total >= count else { return [UInt64](repeating: 0, count: requested.count) }
        let rest = total - count
        let asked = requested.map { min($0, v2BudgetCapCredits) }
        let smallest = asked.filter { $0 > 0 }.min() ?? 1
        let weights = asked.map { $0 == 0 ? smallest : $0 }
        // At most a few keys at the cap each: no overflow.
        let weightTotal = weights.reduce(UInt64(0), +)
        var shares = weights.map { weight -> UInt64 in
            let product = rest.multipliedFullWidth(by: weight)
            return 1 + weightTotal.dividingFullWidth((high: product.high, low: product.low)).quotient
        }
        let given = shares.reduce(UInt64(0), +)
        if given < total { shares[0] += total - given }
        return shares
    }

    private static func evenShares(of total: UInt64, count: Int) -> [UInt64] {
        guard count > 0 else { return [] }
        var shares = [UInt64](repeating: total / UInt64(count), count: count)
        shares[0] += total % UInt64(count)
        return shares
    }

    /// `plan` with `terms` applied: every auth key gets its share of the
    /// limit (`keyBudgets`) and the one expiry. Nil when the terms are out
    /// of bounds at `now` or a key would get no budget.
    static func applying(_ terms: ConnectionTerms, to plan: GrantPlan, now: Date) -> GrantPlan? {
        guard isValidFundingLimit(terms.fundingLimit), isValidExpiry(terms.expiresAt, now: now),
              let budgets = keyBudgets(for: plan, limit: terms.fundingLimit) else { return nil }
        var applied = plan
        applied.auth = zip(plan.auth, budgets).map { grant, budget in
            AuthGrant(bindingIndex: grant.bindingIndex, binding: grant.binding, totalBudget: budget,
                      expiresAt: terms.expiresAt)
        }
        return applied
    }

    /// Whether every key of `plan` carries terms a user could have set: a
    /// budget, an expiry in bounds at `now`, and a total within
    /// `v2BudgetCapCredits`. The approval checks the plan it is handed with
    /// this, whatever the sheet did.
    static func hasValidTerms(_ plan: GrantPlan, now: Date) -> Bool {
        var total: UInt64 = 0
        for grant in plan.auth {
            guard let budget = grant.totalBudget, budget > 0,
                  isValidExpiry(grant.expiresAt, now: now) else { return false }
            let (sum, overflow) = total.addingReportingOverflow(budget)
            guard !overflow else { return false }
            total = sum
        }
        return plan.auth.isEmpty || isValidFundingLimit(total)
    }

    /// Why an approval refuses `plan` at `now`, or `nil` when its terms are
    /// valid (`hasValidTerms`):
    /// - `approvalTermsExpired` when a key's expiry has gone by, which the
    ///   user can change on the sheet;
    /// - `approvalOutOfDate` for any other term out of bounds.
    static func termsFailure(of plan: GrantPlan, now: Date) -> DashConnectPlatformError? {
        guard !hasValidTerms(plan, now: now) else { return nil }
        return plan.auth.contains { $0.expiresAt <= milliseconds(now) }
            ? .approvalTermsExpired : .approvalOutOfDate
    }

    /// `termsFailure` at the proved Platform time `platformTimeMs`, the clock
    /// the plan's expiries were made from; `approvalTermsUncheckable`
    /// without one: the phone's clock does not stand in for it.
    static func termsFailure(of plan: GrantPlan, platformTimeMs: UInt64?) -> DashConnectPlatformError? {
        guard let platformTimeMs else { return .approvalTermsUncheckable }
        return termsFailure(of: plan, now: Date(timeIntervalSince1970: TimeInterval(platformTimeMs) / 1000))
    }

    /// The sum of every key's budget, saturating.
    static func totalBudget(of plan: GrantPlan) -> UInt64 {
        plan.auth.reduce(UInt64(0)) { total, grant in
            let (sum, overflow) = total.addingReportingOverflow(grant.totalBudget ?? 0)
            return overflow ? .max : sum
        }
    }

    /// The consensus code of Platform's `IdentityInsufficientBalanceError`:
    /// a refused identity update that topping up the identity would let
    /// through.
    static let identityInsufficientBalanceCode: UInt32 = 40210

    /// Whether Platform refused an identity update because the identity's
    /// balance cannot pay for it. The identity update reports the broadcast
    /// failure as text ("Failed to broadcast identity update: … Insufficient
    /// identity <id> balance …"), so the text is matched; the typed
    /// `insufficientIdentityCredits` is matched for when it carries one.
    static func isInsufficientBalance(_ error: Error) -> Bool {
        if case .insufficientIdentityCredits? = error as? PlatformWalletError { return true }
        if case .networkRefused(let code)? = error as? DashConnectPlatformError,
           code == identityInsufficientBalanceCode { return true }
        let text = "\(error) \(error.localizedDescription)".lowercased()
        return text.contains("insufficient identity") || text.contains("identityinsufficientbalance")
    }
}
