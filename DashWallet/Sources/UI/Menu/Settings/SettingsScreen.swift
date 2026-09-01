//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

import UIKit
import SwiftUI
import DashUIKit
import Combine
import MessageUI

struct SettingsScreen: View {
    private let vc: UINavigationController
    // Retained solely for the frozen MainMenuViewController call site; the
    // rescan controls were removed with the dead DashSync rescan actions
    // (post-M6 there is no SDK rescan API), so this closure is never invoked.
    private let onDidRescan: () -> ()

    @StateObject private var viewModel = SettingsMenuViewModel()
    @State private var showNetworkAlert = false
    @State private var showCSVExportActivity = false

    init(vc: UINavigationController, onDidRescan: @escaping () -> ()) {
        self.vc = vc
        self.onDidRescan = onDidRescan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack {
                vc.popViewController(animated: true)
            }

            TopIntro(title: NSLocalizedString("Settings", comment: ""))
                .padding(.leading, 20)
                .padding(.trailing, 60)
                .padding(.top, 10)
                .padding(.bottom, 20)

            // Menu list
            VStack(spacing: 2) {
                ForEach(viewModel.items) { item in
                    MenuItem(
                        title: item.title,
                        subtitle: item.subtitle,
                        details: item.details,
                        icon: item.icon,
                        showInfo: item.showInfo,
                        showChevron: false,
                        showToggle: item.showToggle,
                        isToggled: item.isToggled,
                        action: item.action
                    )
                    .frame(minHeight: 60)
                }
            }
            .padding(6)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
        .onReceive(viewModel.$showCSVExportActivity) { show in
            showCSVExportActivity = show
        }
        .alert(NSLocalizedString("Network", comment: ""), isPresented: $showNetworkAlert) {
            Button(NSLocalizedString("Mainnet", comment: "")) {
                Task {
                    let success = await viewModel.switchToMainnet()
                    if success {
                        updateView()
                    }
                }
            }
            Button(NSLocalizedString("Testnet", comment: "")) {
                Task {
                    let success = await viewModel.switchToTestnet()
                    if success {
                        updateView()
                    }
                }
            }
            Button(NSLocalizedString("Devnet", comment: "")) {
                Task {
                    let success = await viewModel.switchToDevnet()
                    if success {
                        updateView()
                    }
                }
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        }
        .alert(
            NSLocalizedString("Network", comment: ""),
            isPresented: Binding(
                get: { viewModel.networkSwitchErrorMessage != nil },
                set: { if !$0 { viewModel.networkSwitchErrorMessage = nil } }
            ),
            presenting: viewModel.networkSwitchErrorMessage
        ) { _ in
            Button(NSLocalizedString("OK", comment: "")) { viewModel.networkSwitchErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert(NSLocalizedString("Move CoinJoin Funds", comment: "CoinJoin"), isPresented: $viewModel.showCoinJoinSweepConfirmation) {
            Button(NSLocalizedString("Move funds", comment: "CoinJoin")) {
                Task { await viewModel.performCoinJoinSweep() }
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(String(format: NSLocalizedString("Move your %@ in mixed coins to your spendable balance? CoinJoin is no longer supported.", comment: "CoinJoin"), viewModel.coinJoinLeftoverFormatted))
        }
        .alert(
            NSLocalizedString("Move CoinJoin Funds", comment: "CoinJoin"),
            isPresented: Binding(
                get: { viewModel.coinJoinSweepErrorMessage != nil },
                set: { if !$0 { viewModel.coinJoinSweepErrorMessage = nil } }
            ),
            presenting: viewModel.coinJoinSweepErrorMessage
        ) { _ in
            Button(NSLocalizedString("OK", comment: "")) { viewModel.coinJoinSweepErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $showCSVExportActivity) {
            if let csvData = viewModel.csvExportData {
                ActivityView(activityItems: [csvData.file])
            }
        }
    }
    
    private func handleNavigation(_ destination: SettingsMenuNavigationDestination?) {
        switch destination {
        case .currencySelector:
            showCurrencySelector()
        case .network:
            showNetworkAlert = true
        case .about:
            showAboutController()
        case .exportCSV:
            handleCSVExport()
        case .devnetSettings:
            showDevnetSettings()
        case .none:
            break
        }
        
        // Reset navigation destination after handling
        if destination != nil {
            viewModel.resetNavigation()
        }
    }
    
    private func showCurrencySelector() {
        let view = LocalCurrencyView(
            currencyCode: nil,
            onSelect: { [weak vc] _ in
                vc?.popViewController(animated: true)
            },
            onBack: { [weak vc] in
                vc?.popViewController(animated: true)
            }
        )
        let controller = LocalCurrencyHostingViewController(rootView: view)
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    
    private func showAboutController() {
        let controller = AboutDashHostingViewController()
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }

    private func showDevnetSettings() {
        let controller = DevnetSettingsHostingViewController(vc: vc)
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    
    private func handleCSVExport() {
        Task {
            do {
                try await viewModel.exportCSV()
            } catch {
                // Handle error display if needed
            }
        }
    }
    
    private func updateView() {
        // Trigger view refresh after network change
        viewModel.resetNavigation()
    }
}


struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class LocalCurrencyHostingViewController: BaseViewController {
    private let rootView: LocalCurrencyView

    init(rootView: LocalCurrencyView) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_background()

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        dw_embedChild(hostingController)
    }
}

extension LocalCurrencyHostingViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}

private final class AboutDashHostingViewController: BaseViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_background()

        let rootView = AboutDashView(
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onContactSupport: { [weak self] in
                self?.presentSupportEmailController()
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        dw_embedChild(hostingController)
    }
}

extension AboutDashHostingViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}

extension AboutDashHostingViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}
