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

// MARK: - MayaPortalView

struct MayaPortalView: View {
    var onBack: () -> Void
    var onConvertDash: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            NavigationBar(leading: {
                NavigationBarElement.back.button { onBack() }
            })

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
        }
        .background(Color.primaryBackground.ignoresSafeArea())
    }

    // MARK: - Sections

    private var introSection: some View {
        VStack(spacing: 20) {
            logoContainer
            descriptionBlock
        }
        .padding(.bottom, 20)
    }

    private var actionsCard: some View {
        MenuItem(
            title: NSLocalizedString("Convert Dash", comment: "Maya Portal"),
            subtitle: NSLocalizedString("From Dash Wallet to any crypto", comment: "Maya Portal"),
            icon: .custom("convert.crypto"),
            action: { onConvertDash?() }
        )
        .modifier(MayaMenuCardStyle())
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
}

#Preview {
    MayaPortalView(onBack: {}, onConvertDash: {})
}
