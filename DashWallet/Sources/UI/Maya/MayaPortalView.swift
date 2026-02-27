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

struct MayaPortalView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Top intro section
                VStack(spacing: 16) {
                    // Maya logo container
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(red: 0.08, green: 0.11, blue: 0.25))
                            .frame(width: 79, height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(Color(white: 0.6, opacity: 0.5), lineWidth: 1)
                            )

                        Image("maya.logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 20)
                    }

                    VStack(spacing: 4) {
                        Text(NSLocalizedString("Maya", comment: "Maya Portal"))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.primaryText)

                        Text(NSLocalizedString("Convert Dash from Dash Wallet to any crypto that is supported on Maya and send it to any wallet", comment: "Maya Portal"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 20)
                }

                // Menu card
                VStack(spacing: 0) {
                    Button(action: {
                        // Placeholder — Convert Dash action not yet implemented
                    }) {
                        HStack(spacing: 16) {
                            Image("convert.crypto")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 26, height: 26)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(NSLocalizedString("Convert Dash", comment: "Maya Portal"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primaryText)

                                Text(NSLocalizedString("From Dash Wallet to any crypto", comment: "Maya Portal"))
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.secondaryText)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .frame(minHeight: 56)
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .shadow(color: .shadow, radius: 10, x: 0, y: 5)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryBackground.ignoresSafeArea())
    }
}
