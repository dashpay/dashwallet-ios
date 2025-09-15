//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import SafariServices

struct ToolsMenuScreen: View {
    private let vc: UINavigationController
    private let delegateInternal: DelegateInternal
    private let onImportPrivateKey: () -> ()
    
    @StateObject private var viewModel = ToolsMenuViewModel()
    @State private var showCSVExportAlert = false
    @State private var showCSVExportActivity = false
    @State private var showZenLedgerSheet = false
    
    init(vc: UINavigationController, onImportPrivateKey: @escaping () -> ()) {
        self.vc = vc
        self.onImportPrivateKey = onImportPrivateKey
        self.delegateInternal = DelegateInternal(onImportPrivateKey: onImportPrivateKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back button
            HStack {
                Button(action: {
                    vc.popViewController(animated: true)
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1)
                        )
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)
            
            // Header
            HStack {
                Text(NSLocalizedString("Tools", comment: ""))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
            
            VStack(alignment: .leading, spacing: 16) {
                // First group - all items except ZenLedger  
                VStack(spacing: 0) {
                ForEach(viewModel.items.dropLast()) { item in
                    MenuItem(
                        title: item.title,
                        subtitle: item.subtitle,
                        details: item.details,
                        icon: item.icon,
                        showInfo: item.showInfo,
                        showChevron: false,
                        isToggled: item.isToggled,
                        action: item.action
                    )
                    .frame(minHeight: 60)
                }
            }
            .padding(.vertical, 5)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
            
            // Second group - ZenLedger
            if let zenLedgerItem = viewModel.items.last {
                VStack(spacing: 0) {
                    MenuItem(
                        title: zenLedgerItem.title,
                        subtitle: zenLedgerItem.subtitle,
                        details: zenLedgerItem.details,
                        icon: zenLedgerItem.icon,
                        showInfo: zenLedgerItem.showInfo,
                        showChevron: false,
                        isToggled: zenLedgerItem.isToggled,
                        action: zenLedgerItem.action
                    )
                    .frame(minHeight: 60)
                }
                .padding(.vertical, 5)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
            }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
        .onReceive(viewModel.$showCSVExportActivity) { show in
            showCSVExportActivity = show
        }
        .alert(NSLocalizedString("CSV Export", comment: ""), isPresented: $showCSVExportAlert) {
            Button(NSLocalizedString("Continue", comment: "")) {
                handleCSVExport()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("All payments will be considered as an Expense and all incoming transactions will be Income. The owner of this wallet is responsible for making any cost basis adjustments in their chosen tax reporting system.", comment: ""))
        }
        .sheet(isPresented: $showCSVExportActivity) {
            if let csvData = viewModel.csvExportData {
                ActivityView(activityItems: [csvData.file])
            }
        }
        .sheet(isPresented: $showZenLedgerSheet, onDismiss: {
            if let link = viewModel.safariLink {
                openSafariLink(link)
                viewModel.safariLink = nil
            }
        }) {
            if #available(iOS 16.0, *) {
                ZenLedgerInfoSheet(safariLink: $viewModel.safariLink)
                    .presentationDetents([.height(450)])
            } else {
                ZenLedgerInfoSheet(safariLink: $viewModel.safariLink)
            }
        }
    }
    
    private func handleNavigation(_ destination: ToolsMenuNavigationDestination?) {
        switch destination {
        case .importPrivateKey:
            showImportPrivateKey()
        case .extendedPublicKeys:
            showExtendedPublicKeys()
        case .masternodeKeys:
            showMasternodeKeys()
        case .csvExport:
            showCSVExportAlert = true
        case .zenLedger:
            showZenLedgerSheet = true
        case .none:
            break
        }
        
        // Reset navigation destination after handling
        if destination != nil {
            viewModel.resetNavigation()
        }
    }
    
    private func showImportPrivateKey() {
        let controller = DWImportWalletInfoViewController.createController()
        controller.delegate = delegateInternal
        vc.pushViewController(controller, animated: true)
    }
    
    private func showExtendedPublicKeys() {
        let controller = ExtendedPublicKeysViewController()
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    
    private func showMasternodeKeys() {
        let controller = KeysOverviewViewController()
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
    
    private func openSafariLink(_ link: String) {
        if let url = URL(string: link) {
            let controller = SFSafariViewController(url: url)
            vc.present(controller, animated: true, completion: nil)
        }
    }
}

extension DWImportWalletInfoViewController {
    static func createController() -> DWImportWalletInfoViewController {
        let storyboard = UIStoryboard(name: "ImportWalletInfo", bundle: nil)
        let controller = storyboard.instantiateInitialViewController() as! DWImportWalletInfoViewController
        controller.hidesBottomBarWhenPushed = true
        return controller
    }
}

extension ToolsMenuScreen {
    class DelegateInternal: NSObject, DWImportWalletInfoViewControllerDelegate {
        let onImportPrivateKey: () -> ()
        
        init(onImportPrivateKey: @escaping () -> ()) {
            self.onImportPrivateKey = onImportPrivateKey
        }
        
        @objc func importWalletInfoViewControllerScanPrivateKeyAction(_ controller: DWImportWalletInfoViewController) { onImportPrivateKey() }
    }
}
