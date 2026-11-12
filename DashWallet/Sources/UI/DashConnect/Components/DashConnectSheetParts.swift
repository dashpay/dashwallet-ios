//
//  DashConnectSheetParts.swift
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
import UIKit

/// A caption over its value, as the DashConnect sheets list details.
struct DashConnectDetailLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .dashFont(.caption1)
                .foregroundColor(Color.dash.tertiaryText)
            Text(value)
                .dashFont(.callout)
                .foregroundColor(Color.dash.primaryText)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A bordered card with a title that opens and closes its content, as the
/// DashConnect sheets list what an app can and cannot do.
struct DashConnectCollapsibleCard<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 20) {
                    Text(title)
                        .dashFont(.subhead)
                        .foregroundColor(Color.dash.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ChevronIcon(direction: isExpanded ? .up : .down, size: 10, color: Color.dash.primaryText)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.dash.gray300Alpha10))
                }
                .padding(.leading, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(Text(isExpanded
                ? NSLocalizedString("Expanded", comment: "Accessibility: a section that is open")
                : NSLocalizedString("Collapsed", comment: "Accessibility: a section that is closed")))

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) { content() }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.dash.gray300Alpha20, lineWidth: 2))
    }
}

extension View {
    /// A sheet as tall as its content, like DashUIKit's `selfSizingSheet`,
    /// for content that switches between views of different heights (a list
    /// of presets and a keypad or a calendar): the new height is applied in
    /// an animation, so the sheet grows or shrinks with the switch instead
    /// of jumping once the new content is measured. The first height is
    /// applied as is; before it, the sheet opens at its tallest, as
    /// `selfSizingSheet(fallback: .greatestFiniteMagnitude)` does.
    /// DashUIKit's modifier applies a new height outside any animation and
    /// has no option for one; this is the animated variant, kept here.
    func animatedSelfSizingSheet(background: Color) -> some View {
        modifier(AnimatedSelfSizingSheet(background: background))
    }
}

private struct AnimatedSelfSizingSheet: ViewModifier {
    let background: Color
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // `BottomSheet(fillsHeight: false)` reports its ideal height,
            // without the home-indicator inset the height detent adds back.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
                let resolved = min(measured, Self.maxHeight)
                guard resolved > 0, abs(resolved - height) > 0.5 else { return }
                if height == 0 {
                    height = resolved
                } else {
                    withAnimation(.smooth(duration: 0.3)) { height = resolved }
                }
            }
            .presentationDetents([.height(height > 0 ? height : Self.maxHeight)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(background)
    }

    /// The tallest the sheet may be: 95% of the window, as DashUIKit's
    /// `selfSizingSheet` allows.
    private static var maxHeight: CGFloat {
        let windowHeight = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.bounds.height
        return (windowHeight ?? UIScreen.main.bounds.height) * 0.95
    }
}

extension View {
    /// An error shown as a DashUIKit toast at the bottom of this view while
    /// `message` is set, and read out by VoiceOver when it appears or
    /// changes.
    func dashConnectErrorToast(_ message: String?) -> some View {
        modifier(DashConnectErrorToast(message: message))
    }
}

private struct DashConnectErrorToast: ViewModifier {
    let message: String?
    /// The last message, kept while the toast fades out so it does not go
    /// blank on its way.
    @State private var shown = ""

    func body(content: Content) -> some View {
        content
            .conditionToast(isVisible: message != nil, style: .error, message: message ?? shown)
            .onAppear {
                guard let message else { return }
                shown = message
                UIAccessibility.post(notification: .announcement, argument: message)
            }
            .onChange(of: message) { _, message in
                guard let message else { return }
                shown = message
                UIAccessibility.post(notification: .announcement, argument: message)
            }
    }
}

/// An error as a DashUIKit toast in its own place in a layout (under an
/// amount, above a button), where an overlay would cover what the user is
/// correcting; nothing while `message` is `nil`. VoiceOver reads it out
/// when it appears or changes.
struct DashConnectInlineErrorToast: View {
    let message: String?

    var body: some View {
        Group {
            if let message {
                DashUIKit.Toast(style: .error, message: message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message)
        .onAppear { announce(message) }
        .onChange(of: message) { _, message in announce(message) }
    }

    private func announce(_ message: String?) {
        guard let message else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

#Preview("Detail lines") {
    VStack(spacing: 2) {
        DashConnectDetailLine(title: "App ID", value: "AyWK6nDVfb8d1ZmkM5MmZZrThbUyWyso1aMeGuuVSfxf")
        DashConnectDetailLine(title: "Username", value: "alice")
    }
    .background(Color.dash.secondaryBackground)
}

#Preview("Collapsible card, open and closed") {
    VStack(spacing: 12) {
        DashConnectCollapsibleCard(title: "See what Yappr will be able to do", isExpanded: .constant(true)) {
            Text("See your username")
        }
        DashConnectCollapsibleCard(title: "See what Yappr will NOT have access to", isExpanded: .constant(false)) {
            Text("Your Dash balance")
        }
    }
    .padding(20)
    .background(Color.dash.secondaryBackground)
}

#Preview("Inline error toast") {
    VStack(spacing: 12) {
        DashConnectInlineErrorToast(message: "Could not complete the DashConnect request: the network did not answer.")
        DashConnectInlineErrorToast(message: nil)
    }
    .padding(20)
}
