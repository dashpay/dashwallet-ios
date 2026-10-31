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
