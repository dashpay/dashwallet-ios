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
        expiresAt: UInt64?,
        isAdministered: Bool,
        appLabel: String,
        tense: Tense = .present
    ) -> String {
        let expiry = expiresAt.map { expiryFormatter.string(from: Date(timeIntervalSince1970: TimeInterval($0) / 1000)) }
        if case .contractGroup = bound, isCritical, let totalBudget, let expiry {
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
        switch (totalBudget, expiry) {
        case let (totalBudget?, expiry?):
            text = String(
                format: NSLocalizedString(
                    "%1$@, spending up to %2$@ of your identity's credits until %3$@",
                    comment: "DashConnect App Connect v2: what a key can do, an amount with its unit (0.5 DASH), a date"),
                action, PlatformCreditsFormatter.dashString(totalBudget), expiry)
        case let (nil, expiry?):
            // No budget was asked for, and the wallet adds none: the key can
            // spend the identity's credits without a cap.
            text = String(
                format: NSLocalizedString(
                    "%1$@, with no limit on spending your identity's credits, until %2$@",
                    comment: "DashConnect App Connect v2: what a key can do, a date"),
                action, expiry)
        // Only a key no intent names can have no expiry (an earlier login,
        // or another wallet's): it lasts until it is turned off.
        case let (totalBudget?, nil):
            text = String(
                format: NSLocalizedString(
                    "%1$@, spending up to %2$@ of your identity's credits, with no end date",
                    comment: "DashConnect App Connect v2: what a key with no expiry can do, an amount with its unit (0.5 DASH)"),
                action, PlatformCreditsFormatter.dashString(totalBudget))
        case (nil, nil):
            text = String(
                format: NSLocalizedString(
                    "%@, with no limit on spending your identity's credits and no end date",
                    comment: "DashConnect App Connect v2: what a key with no expiry and no budget can do"),
                action)
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
        [NSLocalizedString("See your username", comment: "DashConnect")]
            + access.keys.map {
                key(bound: $0.bound, isCritical: $0.isCritical, totalBudget: $0.totalBudget, expiresAt: $0.expiresAt,
                    isAdministered: $0.isAdministered, appLabel: appLabel, tense: tense)
            }
            + (access.receivesMessages ? [receivesMessages(appLabel: appLabel)] : [])
    }

    /// What an approval of `plan` would give, one line each, as the approve
    /// sheet lists it. Whether the app gets a key for messages is known only
    /// once the approval reads the identity's current key, so it is said as
    /// a maybe.
    static func requested(_ plan: AppConnect.GrantPlan, appLabel: String) -> [String] {
        granted(AppConnect.GrantedAccess(plan: plan, receivesMessages: false), appLabel: appLabel)
            + (plan.encryption.isEmpty ? [] : [mayReceiveMessages(appLabel: appLabel)])
    }

    static func mayReceiveMessages(appLabel: String) -> String {
        String(
            format: NSLocalizedString(
                "May receive messages encrypted to you in %@",
                comment: "DashConnect App Connect v2: before approval, whether the app gets a key for messages is not known yet; the placeholder is the app's name"),
            appLabel)
    }

    static func receivesMessages(appLabel: String) -> String {
        String(
            format: NSLocalizedString(
                "Receive messages encrypted to you in %@",
                comment: "DashConnect App Connect v2: the placeholder is the app's name"),
            appLabel)
    }

    /// What an App Connect v2 key never gives an app.
    static var withheld: [String] {
        [
            NSLocalizedString("Your recovery phrase or wallet keys", comment: "DashConnect App Connect"),
            NSLocalizedString("Your Dash balance", comment: "DashConnect App Connect"),
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

/// When a v2 request was made, as the approval sheet says it.
enum AppConnectOriginText {
    /// How long ago the request was made, e.g. "14 seconds ago".
    static func age(_ plan: AppConnect.GrantPlan, now: Date = Date()) -> String {
        ageFormatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(plan.createdAt) / 1000), relativeTo: now)
    }

    private static let ageFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
