//
//  ApproveConnectionSheet.swift
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

import DashUIKit
import SwiftUI

/// Truncates long identifiers in the middle for display, keeping `prefix`
/// leading and `suffix` trailing characters (e.g. "5DbLwAx…FzUo8"). Shared
/// by the DashConnect approval sheets.
enum DashConnectIdentifierFormatting {
    static func truncateMiddle(_ value: String, prefix: Int = 7, suffix: Int = 5) -> String {
        guard value.count > prefix + suffix + 1 else { return value }
        return "\(value.prefix(prefix))…\(value.suffix(suffix))"
    }
}

struct ApproveConnectionSheet: View {
    let request: ConnectionRequest
    var isLoading: Bool = false
    /// Why the last approve attempt failed. Shown here rather than as a screen alert:
    /// an alert on the presenting screen cannot appear over this sheet, so the user
    /// would otherwise see nothing at all.
    var errorText: String?
    var onApprove: () -> Void
    /// Asks again which login this would be. The sheet offers it in place of
    /// Approve while that is unresolved.
    var onRetry: () -> Void = {}
    var onDeny: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.gray300Alpha50)
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 20)

            // The permission list and the app label both grow with Dynamic
            // Type; without a scroll container the actions can be pushed below
            // the bottom of the sheet, leaving the user unable to approve or
            // deny. The actions stay pinned under the scroll area.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            String(format: titleFormat, resolvedAppLabel)
                        )
                        .font(.title2)
                        .foregroundColor(.primaryText)

                        Text(resolvedSubtitle)
                            .font(.subhead)
                            .foregroundColor(.secondaryText)

                        // The name above can be one the code or the
                        // contract's owner chose. This id is what the
                        // approval is for: a one-QR key is bound to it. Shown
                        // in full and selectable, so it can be compared with
                        // the one the app publishes.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("App contract", comment: "DashConnect"))
                                .font(.footnote)
                                .foregroundColor(.secondaryText)
                            Text(request.appContractId)
                                .font(.footnote.monospaced())
                                .foregroundColor(.primaryText)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 6)
                        .accessibilityElement(children: .combine)
                    }

                    if let existingConnection = request.existingConnection {
                        reloginNotice(existingConnection)
                    }

                    // The one-QR login gives the app a key with limits of its
                    // own, so its terms are spelled out on a repeat sign-in
                    // too, and when it replaces a two-QR connection.
                    if request.login == .unresolved {
                        Text(NSLocalizedString(
                            "This wallet could not check what this sign-in would give the app.",
                            comment: "DashConnect"))
                            .font(.subhead)
                            .foregroundColor(.primaryText)
                        if let reason = request.unresolvedLoginReason {
                            Text(reason)
                                .font(.footnote)
                                .foregroundColor(.secondaryText)
                        }
                    } else if case .refused(let refusal) = request.login {
                        Text(NSLocalizedString(
                            "This wallet will not answer this sign-in request.",
                            comment: "DashConnect App Connect v2"))
                            .font(.subhead)
                            .foregroundColor(.primaryText)
                        Text(refusal.reason)
                            .font(.footnote)
                            .foregroundColor(.secondaryText)
                    } else if let plan = request.login.grantPlan {
                        appConnectPermissions(plan)
                    } else if let terms = request.login.sessionKeyTerms {
                        sessionKeyPermissions(terms)
                    } else if isRelogin {
                        reloginPermissionsSummary
                    } else {
                        fullPermissions
                    }

                    if request.walletUsername != nil || request.walletIdentityId != nil {
                        VStack(spacing: 4) {
                            if let walletUsername = request.walletUsername {
                                DashConnectDetailRow(
                                    label: NSLocalizedString("Username", comment: "DashConnect"),
                                    value: walletUsername
                                )
                            }
                            if let walletIdentityId = request.walletIdentityId {
                                DashConnectDetailRow(
                                    label: NSLocalizedString("Identity", comment: "DashConnect"),
                                    value: DashConnectIdentifierFormatting.truncateMiddle(walletIdentityId)
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.gray300, lineWidth: 1.5)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Figma uses a much wider horizontal inset here; 20pt matches the
                // phone sheets already used in this iOS app and avoids over-compressing the content.
                .padding(.horizontal, 20)
            }

            VStack(spacing: 8) {
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundColor(Color.dash.errorText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)
                }

                // A refused request has nothing to approve or try again.
                if !isRefused {
                    DashButton(
                        // With the login unresolved there is nothing to approve.
                        text: request.login == .unresolved
                            ? NSLocalizedString("Try again", comment: "")
                            : NSLocalizedString("Approve", comment: "DashConnect"),
                        style: .filledBlue,
                        size: .large,
                        stretch: true,
                        isEnabled: !isLoading,
                        isLoading: isLoading,
                        action: request.login == .unresolved ? onRetry : onApprove
                    )
                }

                DashButton(
                    text: NSLocalizedString("Deny", comment: "DashConnect"),
                    style: .tintedBlue,
                    size: .large,
                    stretch: true,
                    isEnabled: !isLoading,
                    action: onDeny
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Color.primaryBackground)
    }

    private var resolvedAppLabel: String {
        let trimmed = request.appLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("Unknown app", comment: "DashConnect") : trimmed
    }

    private var isRelogin: Bool {
        request.existingConnection != nil
    }

    private var isRefused: Bool {
        if case .refused = request.login { return true }
        return false
    }

    private var titleFormat: String {
        if isRelogin {
            return NSLocalizedString("Sign in to %@ again?", comment: "DashConnect re-login")
        } else {
            return NSLocalizedString("Approve connection to %@?", comment: "DashConnect")
        }
    }

    private var resolvedSubtitle: String {
        let candidates = [
            request.appUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            request.appLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            NSLocalizedString("Unknown app", comment: "DashConnect"),
        ]
        return candidates.first(where: { !$0.isEmpty }) ?? NSLocalizedString("Unknown app", comment: "DashConnect")
    }

    private var fullPermissions: some View {
        permissions(
            granted: [
                NSLocalizedString("See your username", comment: "DashConnect"),
                NSLocalizedString("Verify your identity", comment: "DashConnect"),
            ],
            withheld: [
                NSLocalizedString("Your private keys", comment: "DashConnect"),
                NSLocalizedString("Withdraw funds", comment: "DashConnect"),
            ]
        )
    }

    /// The one-QR login gives the app a key of its own on the identity, so
    /// the sheet names what that key can spend and when it stops working.
    private func sessionKeyPermissions(_ terms: AppConnect.SessionKeyTerms) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            permissions(
                granted: [
                    NSLocalizedString("See your username", comment: "DashConnect"),
                    NSLocalizedString("Verify your identity", comment: "DashConnect"),
                    NSLocalizedString("Act as you in this app without asking each time", comment: "DashConnect one-QR login"),
                    // Per sign-in: an earlier sign-in to the app keeps its
                    // own key and limit until the app is disconnected.
                    String(
                        format: NSLocalizedString(
                            "Spend up to %@ of your identity's credits on those actions. Each sign-in has its own limit.",
                            comment: "DashConnect one-QR login: the placeholder is an amount with its unit, e.g. 0.05 DASH"),
                        terms.budgetText
                    ),
                ],
                withheld: [
                    NSLocalizedString("Your recovery phrase or wallet keys", comment: "DashConnect one-QR login"),
                    NSLocalizedString("Your Dash balance", comment: "DashConnect one-QR login"),
                ]
            )

            Text(
                String(
                    format: NSLocalizedString(
                        "This access ends after %d days, or when you disconnect the app.",
                        comment: "DashConnect one-QR login"),
                    terms.lifetimeDays
                )
            )
            .font(.footnote)
            .foregroundColor(.secondaryText)
        }
    }

    /// An App Connect request v2: one line per key the app is given, with
    /// what it can spend and until when, then how old the request is and
    /// where the wallet returns. A draft: per-binding toggles and budget and
    /// lifetime presets are left to the wallet's design.
    private func appConnectPermissions(_ plan: AppConnect.GrantPlan) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            permissions(
                granted: [NSLocalizedString("See your username", comment: "DashConnect")]
                    + plan.auth.map { authGrantText($0, administered: plan.administeredGroupIds.contains($0.binding.id)) }
                    + plan.encryption.map { _ in
                        String(
                            format: NSLocalizedString(
                                "Receive messages encrypted to you in %@",
                                comment: "DashConnect App Connect v2: the placeholder is the app's name"),
                            resolvedAppLabel)
                    },
                withheld: [
                    NSLocalizedString("Your recovery phrase or wallet keys", comment: "DashConnect one-QR login"),
                    NSLocalizedString("Your Dash balance", comment: "DashConnect one-QR login"),
                    NSLocalizedString("Registering names or changing your keys", comment: "DashConnect App Connect v2"),
                ]
            )

            VStack(alignment: .leading, spacing: 4) {
                if let warning = originWarning(plan) {
                    Text(warning)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.primaryText)
                }
                Text(requestOrigin(plan))
                    .font(.footnote)
                    .foregroundColor(.secondaryText)
                Text(
                    String(
                        format: NSLocalizedString(
                            "Only approve if you just started signing in on %@.",
                            comment: "DashConnect App Connect v2: the placeholder is the app's website or name"),
                        plan.brandHost ?? plan.callbackHost ?? resolvedAppLabel)
                )
                .font(.footnote)
                .foregroundColor(.secondaryText)
            }
        }
    }

    /// What one key can do, what it can spend and until when. `administered`:
    /// the group has administrators who can add their own contracts to it.
    private func authGrantText(_ grant: AppConnect.AuthGrant, administered: Bool) -> String {
        let binding = grant.binding
        let action: String
        switch binding.kind {
        case .contractGroup:
            action = String(
                format: grant.securityLevel == .critical
                    ? NSLocalizedString(
                        "Act as you in all of %@'s contracts, including claiming and spending its tokens",
                        comment: "DashConnect App Connect v2: the placeholder is the app's name")
                    : NSLocalizedString(
                        "Act as you in all of %@'s contracts",
                        comment: "DashConnect App Connect v2: the placeholder is the app's name"),
                resolvedAppLabel)
        case .singleContract:
            action = String(
                format: NSLocalizedString(
                    "Act as you in one of %@'s contracts",
                    comment: "DashConnect App Connect v2: the placeholder is the app's name"),
                resolvedAppLabel)
        case .documentType:
            if binding.id.toBase58String() == AppConnect.dashPayContractId, binding.documentTypeName == "profile" {
                action = NSLocalizedString("Edit your DashPay profile", comment: "DashConnect App Connect v2")
            } else {
                action = String(
                    format: NSLocalizedString(
                        "Write \"%@\" documents as you",
                        comment: "DashConnect App Connect v2: the placeholder is a document type name"),
                    binding.documentTypeName ?? "")
            }
        }
        let expiry = Self.expiryFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(grant.expiresAt) / 1000))
        var text: String
        if let budget = grant.totalBudget {
            text = String(
                format: NSLocalizedString(
                    "%1$@, spending up to %2$@ of your identity's credits until %3$@",
                    comment: "DashConnect App Connect v2: what a key can do, an amount with its unit (0.5 DASH), a date"),
                action, PlatformCreditsFormatter.dashString(budget), expiry)
        } else {
            // The app asked for no budget, and the wallet adds none: the key
            // can spend the identity's credits without a cap, so the sheet
            // says so.
            text = String(
                format: NSLocalizedString(
                    "%1$@, with no limit on spending your identity's credits, until %2$@",
                    comment: "DashConnect App Connect v2: what a key can do, a date"),
                action, expiry)
        }
        // A budget is in credits: Platform checks a token transfer against
        // the token balance, not against the key's credit budget.
        if binding.kind == .contractGroup, grant.securityLevel == .critical {
            text += " " + NSLocalizedString(
                "The credit limit does not limit how many of your tokens it can move.",
                comment: "DashConnect App Connect v2")
        }
        // Group membership is read when the key signs, not when it is granted.
        if binding.kind == .contractGroup, administered {
            text += " " + NSLocalizedString(
                "Other identities can add their own contracts to this group, and the key will act as you in those too.",
                comment: "DashConnect App Connect v2")
        }
        return text
    }

    /// The profile's warnings. Nothing in a request proves where it came
    /// from: an app the wallet does not know is named by the request alone,
    /// and a known app's request that does not return to its website may
    /// come from a page that is not the app's. A known app's request that
    /// returns elsewhere is refused before it gets here.
    private func originWarning(_ plan: AppConnect.GrantPlan) -> String? {
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

    private func requestOrigin(_ plan: AppConnect.GrantPlan) -> String {
        let requested = Self.ageFormatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(plan.createdAt) / 1000), relativeTo: Date())
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

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private static let ageFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func permissions(granted: [String], withheld: [String]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("This app will be able to:", comment: "DashConnect"))
                    .font(.subhead)
                    .foregroundColor(.primaryText)

                ForEach(granted, id: \.self) { text in
                    PermissionRow(icon: .custom("dashconnect.check.circle", maxHeight: 18), text: text)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("This app will NOT have access to:", comment: "DashConnect"))
                    .font(.subhead)
                    .foregroundColor(.primaryText)

                ForEach(withheld, id: \.self) { text in
                    PermissionRow(icon: .custom("dashconnect.xmark.circle", maxHeight: 18), text: text)
                }
            }
        }
    }

    private var reloginPermissionsSummary: some View {
        HStack(spacing: 8) {
            Icon(name: .custom("dashconnect.check.circle", maxHeight: 18))
                .frame(width: 18, height: 18)

            Text(NSLocalizedString("Same permissions as before", comment: "DashConnect re-login"))
                .font(.subhead)
                .foregroundColor(.primaryText)
        }
    }

    private func reloginNotice(_ existingConnection: DAppConnection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("This connection already exists.", comment: "DashConnect re-login"))
                .font(.subhead)
                .foregroundColor(.primaryText)

            Text(
                String(
                    format: NSLocalizedString("Connected since %@", comment: "DashConnect re-login"),
                    Self.connectedSinceFormatter.string(from: existingConnection.updatedAt)
                )
            )
            .font(.footnote)
            .foregroundColor(.secondaryText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.gray300, lineWidth: 1.5)
        )
    }

    private static let connectedSinceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct PermissionRow: View {
    let icon: IconName
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Icon(name: icon)
                .frame(width: 18, height: 18)

            Text(text)
                .font(.subhead)
                .foregroundColor(.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Label/value row used inside the bordered detail boxes of the DashConnect
/// approval sheets.
struct DashConnectDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subhead)
                .foregroundColor(.primaryText)

            Spacer(minLength: 12)

            Text(value)
                .font(.subhead)
                .foregroundColor(.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

#if DEBUG
private let dashConnectTruncateMiddleCheck: Bool = {
    assert(
        DashConnectIdentifierFormatting.truncateMiddle(
            "5DbLwAxEWR695MsqP4KybNQD5n7CUDWydJYNg63FzUo8"
        ) == "5DbLwAx…FzUo8"
    )
    return true
}()
#endif

#Preview("Approve") {
    ApproveConnectionSheet(
        request: MockDashConnectDataSource.sampleRequest,
        onApprove: {},
        onDeny: {}
    )
}

#Preview("Approve Loading") {
    ApproveConnectionSheet(
        request: MockDashConnectDataSource.sampleRequest,
        isLoading: true,
        onApprove: {},
        onDeny: {}
    )
}

#Preview("Approve One-QR") {
    ApproveConnectionSheet(
        request: ConnectionRequest(
            loginRequest: MockDashConnectDataSource.sampleLoginRequest,
            appLabel: "Yappr",
            appUrl: "yap.pr",
            walletUsername: "dashuser",
            walletIdentityId: "5DbLwAxEWR695MsqP4KybNQD5n7CUDWydJYNg63FzUo8",
            existingConnection: nil,
            login: .oneQR(.current)
        ),
        onApprove: {},
        onDeny: {}
    )
}

#Preview("Approve Re-Login") {
    ApproveConnectionSheet(
        request: ConnectionRequest(
            loginRequest: MockDashConnectDataSource.sampleLoginRequest,
            appLabel: "Yappr",
            appUrl: "yap.pr",
            walletUsername: "dashuser",
            walletIdentityId: "5DbLwAxEWR695MsqP4KybNQD5n7CUDWydJYNg63FzUo8",
            existingConnection: MockDashConnectDataSource.sample(.active),
            login: .twoQR
        ),
        onApprove: {},
        onDeny: {}
    )
}
