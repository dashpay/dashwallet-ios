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
    @Environment(\.openURL) private var openURL
    @Environment(\.presentationMode) private var presentationMode
    
    @Binding var safariLink: String?
    
    var body: some View {
        BottomSheet {
            TextIntro(
                icon: .custom("zenledger_large"),
                buttonLabel: NSLocalizedString("Export all transactions", comment: "ZenLedger"),
                action: { showAlert = true },
                inProgress: $inProgress
            ) {
                FeatureTopText(
                    title: NSLocalizedString("Simplify your crypto taxes", comment: "ZenLedger"),
                    text: NSLocalizedString("Connect your crypto wallets to the ZenLedger platform. Learn more and get started with your Dash Wallet transactions.", comment: "ZenLedger"),
                    label: "zenledger.io",
                    labelIcon: .custom("external.link"),
                    linkAction: {
                        safariLink = "https://app.zenledger.io/new_sign_up/"
                        presentationMode.wrappedValue.dismiss()
                    }
                )
            }
        }
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
                title: Text(NSLocalizedString("Allow send all transactions from Dash Wallet to ZenLedger?", comment: "ZenLedger")),
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
