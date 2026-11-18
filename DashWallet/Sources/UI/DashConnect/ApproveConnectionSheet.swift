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

/// How the DashConnect approval sheets name a request and say that it signs
/// in again to an app that is connected.
extension ConnectionRequest {
    /// The app's name, trimmed, or "Unknown app" when the request names none.
    var resolvedAppLabel: String {
        let trimmed = appLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("Unknown app", comment: "DashConnect") : trimmed
    }

    /// Whether the app is connected already: approving replaces that
    /// connection.
    var isRelogin: Bool {
        existingConnection != nil
    }

    /// The sheet's title: a sign-in again for an app that is connected.
    var approvalTitle: String {
        String(
            format: isRelogin
                ? NSLocalizedString("Sign in to %@ again?", comment: "DashConnect re-login")
                : NSLocalizedString("Approve connection to %@?", comment: "DashConnect"),
            resolvedAppLabel)
    }

    /// What the sheets say over `connectedSinceText`.
    static var alreadyConnectedText: String {
        NSLocalizedString("This connection already exists.", comment: "DashConnect re-login")
    }

    /// Since when the connection this request replaces has been on, e.g.
    /// "Connected since 29 Oct 2026"; `nil` for a first connection.
    var connectedSinceText: String? {
        existingConnection.map {
            String(
                format: NSLocalizedString("Connected since %@", comment: "DashConnect re-login"),
                Self.connectedSinceFormatter.string(from: $0.updatedAt))
        }
    }

    private static let connectedSinceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
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
        // No title in the bar: the intro block below names the request. The
        // close button denies, as a swipe-down does through the presenter's
        // binding; both are blocked while an approval is in flight.
        DashUIKit.BottomSheet(
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!isLoading),
            isCloseButtonEnabled: !isLoading,
            onClose: onDeny,
            background: Color.primaryBackground
        ) {
            VStack(spacing: 0) {
                // The permission list and the app label both grow with Dynamic
                // Type; without a scroll container the actions can be pushed below
                // the bottom of the sheet, leaving the user unable to approve or
                // deny. The actions stay pinned under the scroll area.
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.approvalTitle)
                            .font(.title2)
                            .foregroundColor(.primaryText)

                            Text(resolvedSubtitle)
                                .font(.subhead)
                                .foregroundColor(.secondaryText)

                            // The name above can be one the code or the
                            // contract's owner chose. This id is what the
                            // approval is for: the app's keys are bound to it. Shown
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

                        if let connectedSince = request.connectedSinceText {
                            reloginNotice(connectedSince)
                        }

                        // An App Connect plan gives the app keys with limits of
                        // their own, so its terms are spelled out on a repeat
                        // sign-in too.
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
        }
    }

    private var isRefused: Bool {
        if case .refused = request.login { return true }
        return false
    }

    private var resolvedSubtitle: String {
        let candidates = [
            request.appUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            request.appLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            NSLocalizedString("Unknown app", comment: "DashConnect"),
        ]
        return candidates.first(where: { !$0.isEmpty }) ?? NSLocalizedString("Unknown app", comment: "DashConnect")
    }

    private func permissions(granted: [String], withheld: [String]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("This app will be able to:", comment: "DashConnect"))
                    .font(.subhead)
                    .foregroundColor(.primaryText)

                // By position: two rows can read the same (two encryption keys).
                ForEach(Array(granted.enumerated()), id: \.offset) { _, text in
                    PermissionRow(icon: .custom("dashconnect.check.circle", maxHeight: 18), text: text)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("This app will NOT have access to:", comment: "DashConnect"))
                    .font(.subhead)
                    .foregroundColor(.primaryText)

                // By position: two rows can read the same (two encryption keys).
                ForEach(Array(withheld.enumerated()), id: \.offset) { _, text in
                    PermissionRow(icon: .custom("dashconnect.xmark.circle", maxHeight: 18), text: text)
                }
            }
        }
    }

    private func reloginNotice(_ connectedSince: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ConnectionRequest.alreadyConnectedText)
                .font(.subhead)
                .foregroundColor(.primaryText)

            Text(connectedSince)
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
}

/// One thing an app can or cannot do, with its mark.
struct PermissionRow: View {
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

#Preview("Older Sign-In Refused") {
    ApproveConnectionSheet(
        request: ConnectionRequest(
            loginRequest: MockDashConnectDataSource.sampleLoginRequest,
            appLabel: "Yappr",
            appUrl: "yap.pr",
            walletUsername: "dashuser",
            walletIdentityId: "5DbLwAxEWR695MsqP4KybNQD5n7CUDWydJYNg63FzUo8",
            existingConnection: MockDashConnectDataSource.sample(.active),
            login: .refused(AppConnect.v1Refusal)
        ),
        onApprove: {},
        onDeny: {}
    )
}
