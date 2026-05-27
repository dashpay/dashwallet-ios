//
//  MayaPortalView.swift
//  DashWallet
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

// MARK: - MenuItemButtonStyle

private struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - MayaPortalView

struct MayaPortalView: View {
    var onConvertDash: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                introSection
                actionsCard
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryBackground.ignoresSafeArea())
    }

    // MARK: - Sections

    private var introSection: some View {
        VStack(spacing: 16) {
            logoContainer
            descriptionBlock
        }
    }

    private var actionsCard: some View {
        convertDashButton
            .padding(6)
            .background(Color.secondaryBackground)
            .cornerRadius(20)
            .shadow(color: .shadow, radius: 10, x: 0, y: 5)
    }

    // MARK: - Subviews

    private var logoContainer: some View {
        Icon(name: .custom("maya-illustration", maxHeight: 90))
            .frame(width: 90, height: 90)
    }

    private var descriptionBlock: some View {
        VStack(spacing: 6) {
            Text(NSLocalizedString("Maya", comment: "Maya Portal"))
                .font(.title2)
                .foregroundColor(.primaryText)

            Text(NSLocalizedString("Convert Dash from Dash Wallet to any crypto that is supported on Maya and send it to any wallet", comment: "Maya Portal"))
                .font(.footnote)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 20)
    }

    private var convertDashButton: some View {
        Button(action: { onConvertDash?() }) {
            BuySellMenuItem(
                iconName: "convert.crypto",
                title: NSLocalizedString("Convert Dash", comment: "Maya Portal"),
                description: NSLocalizedString("From Dash Wallet to any crypto", comment: "Maya Portal")
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MayaPortalView(onConvertDash: {})
}
