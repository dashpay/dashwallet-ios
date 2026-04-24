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
import Combine

struct SettingsScreen: View {
    private let vc: UINavigationController
    private let onDidRescan: () -> ()

    @StateObject private var viewModel = SettingsMenuViewModel()
    @State private var showNetworkAlert = false
    @State private var showRescanWarningAlert = false
    @State private var showRescanActionAlert = false
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

            // Menu list
            VStack(spacing: 2) {
                ForEach(viewModel.items) { item in
                    if let cjItem = item as? CoinJoinMenuItemModel {
                        MenuItem(
                            title: cjItem.title,
                            subtitleView: AnyView(CoinJoinSubtitle(cjItem)),
                            icon: .custom("image.coinjoin.menu", maxHeight: 30),
                            badgeText: nil,
                            action: cjItem.action
                        )
                        .frame(minHeight: 56)
                    } else {
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
                        .frame(minHeight: 56)
                    }
                }
            }
            .padding(6)
            .background(Color.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.primaryBackground)
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
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        }
        .alert(NSLocalizedString("You will lose all your manually reclassified transactions types", comment: ""), isPresented: $showRescanWarningAlert) {
            Button(NSLocalizedString("Export CSV", comment: "")) {
                handleCSVExport()
            }
            Button(NSLocalizedString("Continue", comment: "")) {
                showRescanActionAlert = true
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("If you would like to save manually reclassified types for transactions you should export a CSV transaction file.", comment: ""))
        }
        .alert(NSLocalizedString("Rescan Blockchain", comment: ""), isPresented: $showRescanActionAlert) {
            Button(NSLocalizedString("Rescan Transactions (Suggested)", comment: "")) {
                viewModel.rescanTransactions()
                onDidRescan()
            }
            Button(NSLocalizedString("Full Resync", comment: "")) {
                viewModel.fullResync()
                onDidRescan()
            }
            #if DEBUG
            Button(NSLocalizedString("Resync Masternode List", comment: "")) {
                viewModel.resyncMasternodeList()
                onDidRescan()
            }
            #endif
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        }
        .sheet(isPresented: $showCSVExportActivity) {
            if let csvData = viewModel.csvExportData {
                ActivityView(activityItems: [csvData.file])
            }
        }
    }
    
    private func handleNavigation(_ destination: SettingsMenuNavigationDestination?) {
        switch destination {
        case .coinjoin:
            showCoinJoinController()
        case .currencySelector:
            showCurrencySelector()
        case .network:
            showNetworkAlert = true
        case .rescan:
            showRescanWarningAlert = true
        case .about:
            showAboutController()
        case .exportCSV:
            handleCSVExport()
        case .none:
            break
        }
        
        // Reset navigation destination after handling
        if destination != nil {
            viewModel.resetNavigation()
        }
    }
    
    private func showCoinJoinController() {
        let nextVC: UIViewController
        
        if CoinJoinLevelViewModel.shared.infoShown {
            nextVC = CoinJoinLevelsViewController.controller()
        } else {
            nextVC = CoinJoinInfoViewController.controller()
        }
        nextVC.hidesBottomBarWhenPushed = true
        vc.pushViewController(nextVC, animated: true)
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
        let controller = DWAboutViewController.create()
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
    
    @ViewBuilder
    private func CoinJoinSubtitle(_ cjItem: CoinJoinMenuItemModel) -> some View {
        if cjItem.isOn {
            CoinJoinProgressInfo(state: cjItem.state, progress: cjItem.progress, mixed: cjItem.mixed, total: cjItem.total, showBalance: !viewModel.isBalanceHidden, textColor: .tertiaryText, font: .caption)
                .padding(.top, 2)
        } else {
            Text(NSLocalizedString("Turned off", comment: "CoinJoin"))
                .font(.caption)
                .foregroundColor(.tertiaryText)
                .padding(.top, 2)
        }
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
