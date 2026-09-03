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

import SwiftUI
import DashUIKit

struct AboutDashView: View {

    @StateObject private var viewModel = AboutDashViewModel()

    var onBack: (() -> Void)? = nil
    var onContactSupport: (() -> Void)? = nil

    init(onBack: (() -> Void)? = nil, onContactSupport: (() -> Void)? = nil) {
        self.onBack = onBack
        self.onContactSupport = onContactSupport
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationBar(
                leading: { NavigationBarElement.back.button { onBack?() } }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(dash: .custom("logo"))
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    List1View(label: NSLocalizedString("App version", comment: "AboutDash"), value: viewModel.appVersion)
                }
                .modifier(MenuViewModifier())

                VStack(alignment: .leading, spacing: 2) {
                    List1View(label: NSLocalizedString("Explore Dash", comment: "AboutDash"), value: viewModel.exploreStatus)
                    List1View(label: NSLocalizedString("Last device sync", comment: "AboutDash"), value: viewModel.lastDeviceSync)
                    List1View(label: NSLocalizedString("Last device update", comment: "AboutDash"), value: viewModel.lastDeviceUpdate)
                }
                .modifier(MenuViewModifier())

                VStack(alignment: .leading, spacing: 2) {
                    MenuItem(
                        title: NSLocalizedString("Review app", comment: "AboutDash"),
                        icon: .custom("app-review"),
                        action: { viewModel.reviewApp() }
                    )
                    MenuItem(
                        title: NSLocalizedString("Contact support", comment: "AboutDash"),
                        icon: .custom("support"),
                        action: { onContactSupport?() }
                    )
                }
                .modifier(MenuViewModifier())

                VStack(alignment: .center, spacing: 2) {
                    VStack(alignment: .center, spacing: 2) {
                        Text(NSLocalizedString("Dash Wallet is an open sourced app forked from Bitcoin Wallet", comment: "AboutDash"))
                            .dashFont(.footnote)
                            .foregroundStyle(Color.dash.tertiaryText)
                            .multilineTextAlignment(.center)

                        repositoryLink
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Text(NSLocalizedString("Copyright © 2026 Dash Core Group", comment: "AboutDash"))
                        .dashFont(.footnote)
                        .foregroundStyle(Color.dash.tertiaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .shadow(color: Color.dash.shadow, radius: 10, x: 0, y: 5)
                .padding(.horizontal, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color.dash.primaryBackground)
        .alert(
            "",
            isPresented: Binding(
                get: { viewModel.techInfo != nil },
                set: { if !$0 { viewModel.techInfo = nil } }
            ),
            presenting: viewModel.techInfo
        ) { _ in
            Button(NSLocalizedString("Copy", comment: "")) {
                viewModel.copyTechInfo()
                viewModel.techInfo = nil
            }
            Button(NSLocalizedString("Copy Logs", comment: "Log export")) {
                viewModel.techInfo = nil
                viewModel.exportLogs()
            }
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {
                viewModel.techInfo = nil
            }
        } message: { techInfo in
            Text(techInfo)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.exportedLogsURL != nil },
                set: { if !$0 { viewModel.exportedLogsURL = nil } }
            )
        ) {
            if let url = viewModel.exportedLogsURL {
                ActivityView(activityItems: [url])
            }
        }
        .alert(
            NSLocalizedString("Export Logs", comment: "Log export"),
            isPresented: Binding(
                get: { viewModel.logExportErrorMessage != nil },
                set: { if !$0 { viewModel.logExportErrorMessage = nil } }
            ),
            presenting: viewModel.logExportErrorMessage
        ) { _ in
            Button(NSLocalizedString("OK", comment: "")) { viewModel.logExportErrorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var repositoryLink: some View {
        guard let url = URL(string: viewModel.repositoryURL) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            Link(destination: url) {
                Text(viewModel.repositoryURL)
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.blueText)
                    .multilineTextAlignment(.center)
            }
        )
    }
}

#Preview {
    AboutDashView()
}
