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
    @State private var showCSVExportSheet = false
    @State private var showCSVExportActivity = false
    @State private var showZenLedgerSheet = false
    @State private var showImportPrivateKeySheet = false
    @State private var showExtendedPublicKeySheet = false

    init(vc: UINavigationController, onImportPrivateKey: @escaping () -> ()) {
        self.vc = vc
        self.onImportPrivateKey = onImportPrivateKey
        self.delegateInternal = DelegateInternal(onImportPrivateKey: onImportPrivateKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack {
                vc.popViewController(animated: true)
            }

            TopIntro(title: NSLocalizedString("Tools", comment: ""))

            VStack(alignment: .leading, spacing: 20) {
                // Menu list - First group (4 buttons)
                VStack(spacing: 2) {
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
                        .frame(minHeight: 56)
                    }
                }
                .padding(6)
                .background(Color.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
                .padding(.horizontal, 20)

                // Menu list - ZenLedger
                if let zenLedgerItem = viewModel.items.last {
                    VStack(spacing: 2) {
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
                        .frame(minHeight: 56)
                    }
                    .padding(6)
                    .background(Color.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
                    .padding(.horizontal, 20)
                }

                Spacer()
            }
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
        .onReceive(viewModel.$showCSVExportActivity) { show in
            showCSVExportActivity = show
        }
        .sheet(isPresented: $showCSVExportSheet) {
            if #available(iOS 16.4, *) {
                CSVExportSheet(onExport: handleCSVExport)
                    .presentationDetents([.large])
                    .presentationCornerRadius(32)
            } else if #available(iOS 16.0, *) {
                CSVExportSheet(onExport: handleCSVExport)
                    .presentationDetents([.large])
            } else {
                CSVExportSheet(onExport: handleCSVExport)
            }
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
            if #available(iOS 16.4, *) {
                ZenLedgerInfoSheet(safariLink: $viewModel.safariLink)
                    .presentationDetents([.large])
                    .presentationCornerRadius(32)
            } else if #available(iOS 16.0, *) {
                ZenLedgerInfoSheet(safariLink: $viewModel.safariLink)
                    .presentationDetents([.large])
            } else {
                ZenLedgerInfoSheet(safariLink: $viewModel.safariLink)
            }
        }
        .sheet(isPresented: $showImportPrivateKeySheet) {
            if #available(iOS 16.4, *) {
                ImportPrivateKeySheet(onScanPrivateKey: onImportPrivateKey)
                    .presentationDetents([.height(460)])
                    .presentationCornerRadius(32)
            } else if #available(iOS 16.0, *) {
                ImportPrivateKeySheet(onScanPrivateKey: onImportPrivateKey)
                    .presentationDetents([.height(460)])
            } else {
                ImportPrivateKeySheet(onScanPrivateKey: onImportPrivateKey)
            }
        }
        .sheet(isPresented: $showExtendedPublicKeySheet) {
            if #available(iOS 16.4, *) {
                ExtendedPublicKeySheet()
                    .presentationDetents([.height(640)])
                    .presentationCornerRadius(32)
            } else if #available(iOS 16.0, *) {
                ExtendedPublicKeySheet()
                    .presentationDetents([.height(640)])
            } else {
                ExtendedPublicKeySheet()
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
            showCSVExportSheet = true
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
        showImportPrivateKeySheet = true
    }
    
    private func showExtendedPublicKeys() {
        showExtendedPublicKeySheet = true
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
