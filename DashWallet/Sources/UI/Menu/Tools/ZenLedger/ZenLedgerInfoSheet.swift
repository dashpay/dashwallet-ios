//
//  Created by Andrei Ashikhmin
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

struct ZenLedgerInfoSheet: View {
    @ObservedObject private var viewModel = ZenLedgerViewModel()
    @State private var showAlert: Bool = false
    @State private var errorAlert: Bool = false
    @State private var inProgress: Bool = false
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.colorScheme) private var colorScheme

    @Binding var safariLink: String?

    var body: some View {
        VStack(spacing: 0) {
            // Grabber
            Capsule()
                .fill(colorScheme == .dark ? Color.whiteAlpha20 : Color.gray300Alpha50)
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 6)

            // Close button
            NavBarClose {
                presentationMode.wrappedValue.dismiss()
            }

            // Content
            VStack(spacing: 0) {
                // Icon
                Image("zenledger-large")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 94, height: 100)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                // Text content
                VStack(alignment: .center, spacing: 6) {
                    Text(NSLocalizedString("Simplify your crypto taxes", comment: "ZenLedger"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(NSLocalizedString("Connect your crypto wallets to the ZenLedger platform. Learn more and get started with your Dash Wallet transactions.", comment: "ZenLedger"))
                        .font(.system(size: 15))
                        .foregroundColor(Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    // zenledger.io link
                    Button(action: {
                        safariLink = "https://app.zenledger.io/new_sign_up/"
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("zenledger.io")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }

            Spacer()

            // Button
            VStack(spacing: 0) {
                DashButton(
                    text: NSLocalizedString("Export all transactions", comment: "ZenLedger"),
                    style: .filledBlue,
                    size: .large,
                    stretch: true,
                    isEnabled: true,
                    isLoading: inProgress,
                    action: { showAlert = true }
                )
                .padding(.horizontal, 60)
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .background(Color.secondaryBackground)
        .alert(isPresented: $showAlert) {
            resolveAlert()
        }
    }

    private func resolveAlert() -> Alert {
        if errorAlert {
            Alert(
                title: Text(NSLocalizedString("Error", comment: "")),
                message: Text(NSLocalizedString("There was an error when exporting your transaction history to ZenLedger", comment: "ZenLedger")),
                dismissButton: .cancel(Text(NSLocalizedString("Close", comment: "ZenLedger"))) {
                    errorAlert = false
                }
            )
        } else if !viewModel.isSynced {
            Alert(
                title: Text(NSLocalizedString("The chain is syncing…", comment: "ZenLedger")),
                message: Text(NSLocalizedString("Wait until the chain is fully synced, so we can review your transaction history.", comment: "ZenLedger")),
                dismissButton: .cancel(Text(NSLocalizedString("Close", comment: "ZenLedger")))
            )
        } else {
            Alert(
                title: Text(NSLocalizedString("Allow sending all transactions from Dash Wallet to Zenledger?", comment: "ZenLedger")),
                primaryButton: .default(Text(NSLocalizedString("Allow", comment: "ZenLedger"))) {
                    export()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func export() {
        Task {
            inProgress = true

            do {
                if let signupLink = try await viewModel.export() {
                    safariLink = signupLink
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                DSLogger.log("ZenLedger error: \(error)")
                errorAlert = true
                showAlert = true
            }

            inProgress = false
        }
    }
}
