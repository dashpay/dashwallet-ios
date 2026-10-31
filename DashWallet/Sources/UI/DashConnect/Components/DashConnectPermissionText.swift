//
//  DashConnectPermissionText.swift
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

/// The lines that say what an App Connect v2 key lets an app do, shared by
/// the approval sheet and the connection sheet.
enum DashConnectPermissionText {
    /// Whether the lines describe a connection that is on (the approval
    /// sheet, an active connection) or one that ended.
    enum Tense {
        case present
        case past
    }

    /// What one key can do, what it can spend and until when. `isAdministered`:
    /// the group has administrators who can add their own contracts to it.
    static func key(
        bound: AppConnect.StoredBound,
        isCritical: Bool,
        totalBudget: UInt64?,
        expiresAt: UInt64,
        isAdministered: Bool,
        appLabel: String,
        tense: Tense = .present
    ) -> String {
        let expiry = expiryFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1000))
        if case .contractGroup = bound, isCritical, let totalBudget {
            return criticalGroupKey(
                appLabel: appLabel, budget: PlatformCreditsFormatter.dashString(totalBudget), expiry: expiry,
                isAdministered: isAdministered, tense: tense)
        }
        let action: String
        var isGroup = false
        switch bound {
        case .contractGroup:
            isGroup = true
            action = String(
                format: isCritical
                    ? NSLocalizedString(
                        "Act as you in all of %@'s contracts, including claiming and spending its tokens",
                        comment: "DashConnect App Connect v2: the placeholder is the app's name")
                    : NSLocalizedString(
                        "Act as you in all of %@'s contracts",
                        comment: "DashConnect App Connect v2: the placeholder is the app's name"),
                appLabel)
        case .singleContract:
            action = String(
                format: NSLocalizedString(
                    "Act as you in one of %@'s contracts",
                    comment: "DashConnect App Connect v2: the placeholder is the app's name"),
                appLabel)
        case let .documentType(contractId, name):
            if contractId.toBase58String() == AppConnect.dashPayContractId, name == "profile" {
                action = NSLocalizedString("Edit your DashPay profile", comment: "DashConnect App Connect v2")
            } else {
                action = String(
                    format: NSLocalizedString(
                        "Write \"%@\" documents as you",
                        comment: "DashConnect App Connect v2: the placeholder is a document type name"),
                    name)
            }
        }
        var text: String
        if let totalBudget {
            text = String(
                format: NSLocalizedString(
                    "%1$@, spending up to %2$@ of your identity's credits until %3$@",
                    comment: "DashConnect App Connect v2: what a key can do, an amount with its unit (0.5 DASH), a date"),
                action, PlatformCreditsFormatter.dashString(totalBudget), expiry)
        } else {
            // No budget was asked for, and the wallet adds none: the key can
            // spend the identity's credits without a cap.
            text = String(
                format: NSLocalizedString(
                    "%1$@, with no limit on spending your identity's credits, until %2$@",
                    comment: "DashConnect App Connect v2: what a key can do, a date"),
                action, expiry)
        }
        // A budget is in credits: Platform checks a token transfer against
        // the token balance, not against the key's credit budget.
        if isGroup, isCritical {
            text += " " + NSLocalizedString(
                "The credit limit does not limit how many of your tokens it can move.",
                comment: "DashConnect App Connect v2")
        }
        // Group membership is read when the key signs, not when it is granted.
        if isGroup, isAdministered {
            text += " " + NSLocalizedString(
                "Other identities can add their own contracts to this group, and the key will act as you in those too.",
                comment: "DashConnect App Connect v2")
        }
        return text
    }

    /// A CRITICAL key on the app's contract group: it acts in all of the
    /// app's contracts and moves its tokens, which its credit budget does not
    /// limit. Who receives a token purchase is left out: the user approves an
    /// amount, and the limit caps it.
    static func criticalGroupKey(
        appLabel: String,
        budget: String,
        expiry: String,
        isAdministered: Bool,
        tense: Tense
    ) -> String {
        var text: String
        switch tense {
        case .present:
            text = String(
                format: NSLocalizedString(
                    "Act as you in %1$@ until %2$@, including buying and sending its tokens. It can spend up to %3$@ of your identity balance on fees and token purchases, but can send any amount of your %1$@ tokens.",
                    comment: "DashConnect App Connect v2: the app's name, a date (29 Oct 2027), an amount with its unit (0.5 DASH); the app's name again"),
                appLabel, expiry, budget)
        case .past:
            text = String(
                format: NSLocalizedString(
                    "Could act as you in %1$@ until %2$@, including buying and sending its tokens. It could spend up to %3$@ of your identity balance on fees and token purchases, but could send any amount of your %1$@ tokens.",
                    comment: "DashConnect connection sheet, a connection that ended: the app's name, a date, an amount with its unit; the app's name again"),
                appLabel, expiry, budget)
        }
        // Group membership is read when the key signs, not when it is granted.
        if isAdministered {
            text += " " + NSLocalizedString(
                "Other identities can add their own contracts to this group, and the key will act as you in those too.",
                comment: "DashConnect App Connect v2")
        }
        return text
    }

    /// What an approval gave the app, one line each, as its sheet listed it.
    static func granted(_ access: AppConnect.GrantedAccess, appLabel: String, tense: Tense = .present) -> [String] {
        if access.isSessionKeyLogin {
            return sessionKeyGranted(budgets: access.keys.compactMap(\.totalBudget))
        }
        return [NSLocalizedString("See your username", comment: "DashConnect")]
            + access.keys.map {
                key(bound: $0.bound, isCritical: $0.isCritical, totalBudget: $0.totalBudget, expiresAt: $0.expiresAt,
                    isAdministered: $0.isAdministered, appLabel: appLabel, tense: tense)
            }
            + (access.receivesMessages ? [receivesMessages(appLabel: appLabel)] : [])
    }

    static func receivesMessages(appLabel: String) -> String {
        String(
            format: NSLocalizedString(
                "Receive messages encrypted to you in %@",
                comment: "DashConnect App Connect v2: the placeholder is the app's name"),
            appLabel)
    }

    /// What a one-QR login gives the app; one budget line per sign-in.
    static func sessionKeyGranted(budgets: [UInt64]) -> [String] {
        [
            NSLocalizedString("See your username", comment: "DashConnect"),
            NSLocalizedString("Verify your identity", comment: "DashConnect"),
            NSLocalizedString("Act as you in this app without asking each time", comment: "DashConnect one-QR login"),
        ] + budgets.map(sessionKeyBudget)
    }

    /// A one-QR session key's budget, as the login's sheet says it.
    static func sessionKeyBudget(_ credits: UInt64) -> String {
        String(
            format: NSLocalizedString(
                "Spend up to %@ of your identity's credits on those actions. Each sign-in has its own limit.",
                comment: "DashConnect one-QR login: the placeholder is an amount with its unit, e.g. 0.05 DASH"),
            PlatformCreditsFormatter.dashString(credits))
    }

    /// What a one-QR session key never gives an app.
    static var sessionKeyWithheld: [String] {
        [
            NSLocalizedString("Your recovery phrase or wallet keys", comment: "DashConnect one-QR login"),
            NSLocalizedString("Your Dash balance", comment: "DashConnect one-QR login"),
        ]
    }

    /// What an App Connect v2 key never gives an app.
    static var withheld: [String] {
        [
            NSLocalizedString("Your recovery phrase or wallet keys", comment: "DashConnect one-QR login"),
            NSLocalizedString("Your Dash balance", comment: "DashConnect one-QR login"),
            NSLocalizedString("Registering names or changing your keys", comment: "DashConnect App Connect v2"),
        ]
    }

    /// Dates as the design writes them: "29 Oct 2027".
    static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return formatter
    }()
}

/// What the approval sheets say about where a v2 request came from. Nothing
/// in a request proves it: an app the wallet does not know is named by the
/// request alone, and a known app's request that does not return to its
/// website may come from a page that is not the app's. A known app's request
/// that returns elsewhere is refused before a sheet shows it.
enum AppConnectOriginText {
    static func warning(_ plan: AppConnect.GrantPlan) -> String? {
        guard let brandHost = plan.brandHost else {
            return NSLocalizedString(
                "This wallet does not know this app, so it cannot confirm the name shown or where the request came from.",
                comment: "DashConnect App Connect v2")
        }
        guard plan.callbackHost == nil else { return nil }
        return String(
            format: NSLocalizedString(
                "This request does not return to %@. It may not come from the app's website.",
                comment: "DashConnect App Connect v2: the placeholder is the app's website, e.g. yap.pr"),
            brandHost)
    }

    static func origin(_ plan: AppConnect.GrantPlan, now: Date = Date()) -> String {
        let requested = ageFormatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(plan.createdAt) / 1000), relativeTo: now)
        guard let host = plan.callbackHost else {
            return String(
                format: NSLocalizedString(
                    "Requested %@",
                    comment: "DashConnect App Connect v2: the placeholder is a relative time, e.g. 12 seconds ago"),
                requested)
        }
        return String(
            format: NSLocalizedString(
                "Requested %1$@ · returns to %2$@",
                comment: "DashConnect App Connect v2: a relative time (12 seconds ago), then a website (yap.pr)"),
            requested, host)
    }

    static func onlyApprove(_ plan: AppConnect.GrantPlan, appLabel: String) -> String {
        String(
            format: NSLocalizedString(
                "Only approve if you just started signing in on %@.",
                comment: "DashConnect App Connect v2: the placeholder is the app's website or name"),
            plan.brandHost ?? plan.callbackHost ?? appLabel)
    }

    private static let ageFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
