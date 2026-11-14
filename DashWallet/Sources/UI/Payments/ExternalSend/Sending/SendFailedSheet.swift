//
//  Created by Roman Chornyi
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

/// SCR-10 Send failed. Draws the content the router produced; Close and Retry are the flow's callbacks. While
/// `isRetrying` (a payment request is fetched again) Retry is disabled and shows its progress.
struct SendFailedSheet: View {
    let content: SendFailedContent
    var isRetrying = false
    let onClose: () -> Void
    let onRetry: () -> Void

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: content.title,
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(true),
            showsCloseButton: false,
            onClose: onClose,
            content: {
                ViewThatFits(in: .vertical) {
                    sheetBody
                    ScrollView { sheetBody }
                }
            })
    }

    private var sheetBody: some View {
        VStack(spacing: 16) {
            ErrorIllustration()
            Text(content.reason)
                .dashFont(.subhead)
                .foregroundStyle(Color.dash.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            DashUIKit.SystemMessageView(
                title: content.info,
                icon: DashIcon.SystemMessage.infoRectSmall.source,
                backgroundColor: Color.dash.blueAlpha5)
            HStack(spacing: 8) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Close", comment: "External send"),
                    fillsWidth: true,
                    size: .large,
                    style: .tintedGray,
                    action: onClose)
                    .accessibilityIdentifier("send_failed_close")
                DashUIKit.DashButton(
                    text: NSLocalizedString("Retry", comment: "External send"),
                    isEnabled: !isRetrying,
                    isLoading: isRetrying,
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: onRetry)
                    .accessibilityIdentifier("send_failed_retry")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

#if DEBUG

private func previewSheet(_ reason: NotSentReason, source: String = "Core") -> some View {
    let content = SendFailedContent(
        title: "Send failed", reason: reason.localizedMessage,
        info: "Nothing was sent. Your money is still in your \(source) balance.")
    return Color.dash.primaryBackground.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) { SendFailedSheet(content: content, onClose: {}, onRetry: {}) }
}

#Preview("Failed, offline, Core") { previewSheet(.offline) }

#Preview("Failed, below minimum, Platform") { previewSheet(.belowMinimum, source: "Platform") }

#Preview("Failed, rejected, Shielded") { previewSheet(.rejected, source: "Shielded") }

#Preview("Failed, signing key, Identity") { previewSheet(.signingKeyUnavailable, source: "Identity") }

#Preview("Failed, earlier payment pending") { previewSheet(.earlierPaymentPending) }

#Preview("Failed, generic") { previewSheet(.failed) }

#Preview("Long text, large Dynamic Type") {
    previewSheet(.belowMinimum, source: "Shielded")
        .dynamicTypeSize(.accessibility3)
}

#endif
