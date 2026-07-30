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

import SwiftUI

struct ApproveConnectionSheet: View {
    let request: ConnectionRequest
    var isLoading: Bool = false
    var onApprove: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.gray300Alpha50)
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        String(
                            format: NSLocalizedString("Approve connection to %@?", comment: "DashConnect"),
                            resolvedAppLabel
                        )
                    )
                    .font(.title2)
                    .foregroundColor(.primaryText)

                    Text(resolvedSubtitle)
                        .font(.subhead)
                        .foregroundColor(.secondaryText)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("This app will be able to:", comment: "DashConnect"))
                        .font(.subhead)
                        .foregroundColor(.primaryText)

                    PermissionRow(
                        icon: .custom("dashconnect.check.circle", maxHeight: 18),
                        text: NSLocalizedString("See your username", comment: "DashConnect")
                    )
                    PermissionRow(
                        icon: .custom("dashconnect.check.circle", maxHeight: 18),
                        text: NSLocalizedString("Verify your identity", comment: "DashConnect")
                    )
                }

                VStack(spacing: 4) {
                    DetailRow(
                        label: NSLocalizedString("Username", comment: "DashConnect"),
                        value: request.walletUsername
                    )
                    DetailRow(
                        label: NSLocalizedString("Identity", comment: "DashConnect"),
                        value: truncateMiddle(request.walletIdentityId)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray300, lineWidth: 1.5)
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("This app will NOT have access to:", comment: "DashConnect"))
                        .font(.subhead)
                        .foregroundColor(.primaryText)

                    PermissionRow(
                        icon: .custom("dashconnect.xmark.circle", maxHeight: 18),
                        text: NSLocalizedString("Your private keys", comment: "DashConnect")
                    )
                    PermissionRow(
                        icon: .custom("dashconnect.xmark.circle", maxHeight: 18),
                        text: NSLocalizedString("Withdraw funds", comment: "DashConnect")
                    )
                }

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    DashButton(
                        text: NSLocalizedString("Approve", comment: "DashConnect"),
                        style: .filledBlue,
                        size: .large,
                        stretch: true,
                        isEnabled: !isLoading,
                        isLoading: isLoading,
                        action: onApprove
                    )

                    DashButton(
                        text: NSLocalizedString("Deny", comment: "DashConnect"),
                        style: .tintedBlue,
                        size: .large,
                        stretch: true,
                        isEnabled: !isLoading,
                        action: onDeny
                    )
                }
            }
            // Figma uses a much wider horizontal inset here; 20pt matches the
            // phone sheets already used in this iOS app and avoids over-compressing the content.
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.primaryBackground)
    }

    private var resolvedAppLabel: String {
        let trimmed = request.appLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("Unknown app", comment: "DashConnect") : trimmed
    }

    private var resolvedSubtitle: String {
        let candidates = [
            request.appUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            request.appLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            NSLocalizedString("Unknown app", comment: "DashConnect"),
        ]
        return candidates.first(where: { !$0.isEmpty }) ?? NSLocalizedString("Unknown app", comment: "DashConnect")
    }

    /// Truncates a long identifier in the middle, keeping `prefix` leading and
    /// `suffix` trailing characters (e.g. "5DbLwAx…7zUo8").
    fileprivate func truncateMiddle(_ value: String, prefix: Int = 7, suffix: Int = 5) -> String {
        guard value.count > prefix + suffix + 1 else { return value }
        return "\(value.prefix(prefix))…\(value.suffix(suffix))"
    }
}

private struct PermissionRow: View {
    let icon: IconName
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Icon(name: icon)
                .frame(width: 18, height: 18)

            Text(text)
                .font(.subhead)
                .foregroundColor(.primaryText)
        }
    }
}

private struct DetailRow: View {
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
    let sheet = ApproveConnectionSheet(
        request: MockDashConnectDataSource.sampleRequest,
        onApprove: {},
        onDeny: {}
    )
    assert(
        sheet.truncateMiddle("5DbLwAxEWR695MsqP4KybNQD5n7CUDWydJYNg63FzUo8") == "5DbLwAx…zUo8"
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
