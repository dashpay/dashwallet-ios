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
import DashUIKit
import SafariServices

struct ToolsMenuScreen: View {
    private let vc: UINavigationController

    @StateObject private var viewModel = ToolsMenuViewModel()
    @State private var showCSVExportSheet = false
    @State private var showCSVExportActivity = false
    @State private var showZenLedgerSheet = false
    @State private var showExtendedPublicKeySheet = false

    init(vc: UINavigationController) {
        self.vc = vc
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack {
                vc.popViewController(animated: true)
            }

            TopIntro(title: NSLocalizedString("Tools", comment: ""))
                .padding(.leading, 20)
                .padding(.trailing, 60)
                .padding(.top, 10)
                .padding(.bottom, 20)

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
                .background(Color.dash.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
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
                    .background(Color.dash.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
                    .padding(.horizontal, 20)
                }

                Spacer()
            }
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
        .onReceive(viewModel.$showCSVExportActivity) { show in
            showCSVExportActivity = show
        }
        .sheet(isPresented: $showCSVExportSheet) {
            if #available(iOS 16.4, *) {
                csvExportSheet
                    .presentationDetents([.large])
                    .presentationCornerRadius(32)
                    .presentationDragIndicator(.hidden)
            } else if #available(iOS 16.0, *) {
                csvExportSheet
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            } else {
                csvExportSheet
            }
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
        .sheet(isPresented: $showZenLedgerSheet, onDismiss: {
            if let link = viewModel.safariLink {
                openSafariLink(link)
                viewModel.safariLink = nil
            }
        }) {
            if #available(iOS 16.4, *) {
                zenLedgerSheet
                    .presentationDetents([.large])
                    .presentationCornerRadius(32)
                    .presentationDragIndicator(.hidden)
            } else if #available(iOS 16.0, *) {
                zenLedgerSheet
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            } else {
                zenLedgerSheet
            }
        }
        .sheet(isPresented: $showExtendedPublicKeySheet) {
            if #available(iOS 16.4, *) {
                extendedPublicKeySheet
                    .presentationDetents([.height(640)])
                    .presentationCornerRadius(32)
                    .presentationDragIndicator(.hidden)
            } else if #available(iOS 16.0, *) {
                extendedPublicKeySheet
                    .presentationDetents([.height(640)])
                    .presentationDragIndicator(.hidden)
            } else {
                extendedPublicKeySheet
            }
        }
    }

    private var csvExportSheet: some View {
        DashUIKit.BottomSheet(showBackButton: .constant(false)) {
            CSVExportSheet(onExport: handleCSVExport)
        }
    }

    private var zenLedgerSheet: some View {
        DashUIKit.BottomSheet(showBackButton: .constant(false)) {
            ZenLedgerInfoSheet(safariLink: $viewModel.safariLink)
        }
    }

    private var extendedPublicKeySheet: some View {
        DashUIKit.BottomSheet(showBackButton: .constant(false)) {
            ExtendedPublicKeySheet()
        }
    }
    
    private func handleNavigation(_ destination: ToolsMenuNavigationDestination?) {
        switch destination {
        case .extendedPublicKeys:
            showExtendedPublicKeys()
        case .masternodeKeys:
            showMasternodeKeys()
        case .csvExport:
            showCSVExportSheet = true
        case .zenLedger:
            showZenLedgerSheet = true
        case .storageExplorer:
            showStorageExplorer()
        case .none:
            break
        }

        // Reset navigation destination after handling
        if destination != nil {
            viewModel.resetNavigation()
        }
    }

    private func showStorageExplorer() {
        let coordinator = PlatformAddressSyncCoordinator.shared
        let navController = vc
        let popRoot: () -> Void = { [weak navController] in
            _ = navController?.popViewController(animated: true)
        }

        let hosting: UIHostingController<AnyView>
        if let container = coordinator.swiftDataContainer {
            hosting = UIHostingController(
                rootView: AnyView(
                    NavigationStack {
                        StorageExplorerView()
                            .navigationTitle("Storage Explorer")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(action: popRoot) {
                                        Image(systemName: "chevron.left")
                                    }
                                }
                            }
                    }
                    .modelContainer(container)
                )
            )
        } else {
            hosting = UIHostingController(
                rootView: AnyView(
                    NavigationStack {
                        StorageExplorerUnavailableView()
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(action: popRoot) {
                                        Image(systemName: "chevron.left")
                                    }
                                }
                            }
                    }
                )
            )
        }
        hosting.hidesBottomBarWhenPushed = true
        vc.pushViewController(hosting, animated: true)
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
