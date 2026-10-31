//
//  ConnectionsScreen.swift
//  DashWallet
//
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
import UIKit
import DashUIKit

/// Lists the apps connected to this wallet. The states it can be in live in
/// `Components/`; this type owns navigation, the QR scanner and the approval
/// sheet.
struct ConnectionsScreen: View {
    private let vc: UINavigationController

    @StateObject private var viewModel: ConnectionsViewModel

    init(vc: UINavigationController, viewModel: ConnectionsViewModel? = nil) {
        self.vc = vc
        _viewModel = StateObject(wrappedValue: viewModel ?? ConnectionsViewModel())
    }

    @State private var showsFundingLimitsInfo = false
    /// Reconnect closes the connection sheet first: the scanner is
    /// presented once it is gone.
    @State private var scansAfterSheet = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                DashUIKit.NavigationBar(
                    leading: {
                        DashUIKit.NavigationBarElement.back.button { vc.popViewController(animated: true) }
                    },
                    trailing: {
                        if !viewModel.featureUnavailable {
                            DashUIKit.NavigationBarElement.plus.button(action: showScanner)
                                .accessibilityLabel(Text(NSLocalizedString("Connect an app", comment: "DashConnect")))
                        }
                    }
                )

                content
            }

            if viewModel.isProcessingStateTransition || viewModel.isDisconnecting {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()

                // The app declares its own `ProgressView: UIView`, which shadows
                // SwiftUI's in any file importing both.
                SwiftUI.ProgressView(NSLocalizedString("Completing DashConnect request…", comment: "DashConnect"))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.primaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
        // Another identity may have become active while the screen was away.
        .onAppear { viewModel.refreshConnectionStatus() }
        .alert(item: messageBinding) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.text),
                dismissButton: .default(Text(NSLocalizedString("OK", comment: ""))) {
                    viewModel.message = nil
                }
            )
        }
        .sheet(isPresented: isApproveSheetPresented) {
            if let request = viewModel.pendingRequest {
                approveSheet(for: request)
            }
        }
        .sheet(isPresented: isTokenPurchaseSheetPresented) {
            if let purchase = viewModel.pendingTokenPurchase {
                tokenPurchaseSheet(for: purchase)
            }
        }
        .sheet(item: shownConnectionBinding, onDismiss: {
            showsFundingLimitsInfo = false
            guard scansAfterSheet else { return }
            scansAfterSheet = false
            showScanner()
        }) { item in
            connectionSheet(for: item)
        }
    }

    // MARK: - States

    @ViewBuilder private var content: some View {
        if viewModel.featureUnavailable {
            title
            ConnectionsUnavailableState()
        } else if !viewModel.hasConnectionsOrHistory, viewModel.isLoadingHistory {
            // Not known yet whether anything was connected: no empty state
            // that the history may replace a moment later.
            title
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            Spacer()
        } else if !viewModel.hasConnectionsOrHistory {
            title
            ConnectionsEmptyState(onScanQR: showScanner, onMockScan: mockScan)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    title
                    SegmentedControl(
                        options: ConnectionsTab.allCases,
                        selection: $viewModel.selectedTab,
                        label: Self.tabName)
                    tabContent
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var title: some View {
        TopIntro(title: NSLocalizedString("Connections", comment: "DashConnect"))
            .padding(.horizontal, viewModel.hasConnectionsOrHistory && !viewModel.featureUnavailable ? 0 : 20)
            .padding(.top, 10)
    }

    @ViewBuilder private var tabContent: some View {
        let tab = viewModel.selectedTab
        let rows = viewModel.rows(for: tab)
        if tab == .disconnected, viewModel.historyIsUnreadable {
            tabNote(NSLocalizedString("Disconnected apps could not be read.", comment: "DashConnect"), retries: false)
        } else if !rows.isEmpty {
            ConnectionsList(items: rows, onOpen: viewModel.showConnection)
            if tab == .expired, viewModel.isCheckingStatus { checking }
        } else if (tab == .disconnected && viewModel.isLoadingHistory)
            || (tab == .expired && viewModel.isCheckingStatus) {
            checking
        } else if tab == .expired, !viewModel.expiriesAreKnown {
            tabNote(
                NSLocalizedString("Which connections expired could not be checked.", comment: "DashConnect"),
                retries: true)
        } else {
            tabNote(Self.emptyTabText(tab), retries: false)
        }
    }

    private var checking: some View {
        SwiftUI.ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .accessibilityLabel(Text(NSLocalizedString("Checking connections", comment: "DashConnect")))
    }

    private func tabNote(_ text: String, retries: Bool) -> some View {
        VStack(spacing: 12) {
            Text(text)
                .dashFont(.subhead)
                .foregroundColor(Color.dash.secondaryText)
                .multilineTextAlignment(.center)
            if retries {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Retry", comment: "DashConnect"),
                    size: .small, style: .tintedBlue, action: viewModel.refreshConnectionStatus)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private static func emptyTabText(_ tab: ConnectionsTab) -> String {
        switch tab {
        case .active: return NSLocalizedString("No active connections", comment: "DashConnect: an empty tab")
        case .disconnected: return NSLocalizedString("No disconnected connections", comment: "DashConnect: an empty tab")
        case .expired: return NSLocalizedString("No expired connections", comment: "DashConnect: an empty tab")
        }
    }

    private static func tabName(_ tab: ConnectionsTab) -> String {
        switch tab {
        case .active: return NSLocalizedString("Active", comment: "DashConnect connection status")
        case .disconnected: return NSLocalizedString("Disconnected", comment: "DashConnect connection status")
        case .expired: return NSLocalizedString("Expired", comment: "DashConnect connection status")
        }
    }

    private func connectionSheet(for item: ConnectionSheetItem) -> some View {
        ConnectionSheet(
            item: item,
            details: viewModel.shownDetails,
            detailsFailed: viewModel.shownDetailsFailed,
            granted: viewModel.shownGrantedLines,
            withheld: viewModel.shownWithheldLines,
            isBusy: viewModel.isDisconnecting,
            isCheckingStatus: viewModel.isCheckingStatus,
            message: viewModel.connectionSheetMessage,
            onClose: viewModel.hideConnection,
            onDisconnect: {
                if let connection = item.connection { viewModel.disconnect(connection) }
            },
            onReconnect: {
                scansAfterSheet = true
                viewModel.hideConnection()
            },
            onMockScan: mockScan,
            onShowFundingLimitsInfo: { showsFundingLimitsInfo = true }
        )
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showsFundingLimitsInfo) {
            FundingLimitsInfoSheet(onClose: { showsFundingLimitsInfo = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func approveSheet(for request: ConnectionRequest) -> some View {
        ApproveConnectionSheet(
            request: request,
            isLoading: viewModel.isApproving,
            errorText: viewModel.approveError,
            onApprove: { viewModel.approvePendingRequest() },
            onRetry: { viewModel.retryPendingRequest() },
            onDeny: { viewModel.denyPendingRequest() }
        )
        // The one-QR terms make the sheet longer than the fixed height
        // shows; who pays and when access ends must not sit below the fold.
        .approveSheetPresentation(isLoading: viewModel.isApproving, isTall: request.login.sessionKeyTerms != nil || request.login.grantPlan != nil)
    }

    private func tokenPurchaseSheet(for purchase: DashConnectTokenPurchaseRequest) -> some View {
        ApproveTokenPurchaseSheet(
            request: purchase,
            isLoading: viewModel.isApprovingPurchase,
            errorText: viewModel.purchaseApproveError,
            onApprove: { viewModel.approvePendingTokenPurchase() },
            onDeny: { viewModel.denyPendingTokenPurchase() }
        )
        .approveSheetPresentation(isLoading: viewModel.isApprovingPurchase)
    }

    // MARK: - Presentation bindings

    private var isApproveSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingRequest != nil },
            set: { isPresented in
                if !isPresented && !viewModel.isApproving {
                    viewModel.denyPendingRequest()
                }
            }
        )
    }

    private var isTokenPurchaseSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingTokenPurchase != nil },
            set: { isPresented in
                if !isPresented && !viewModel.isApprovingPurchase {
                    viewModel.denyPendingTokenPurchase()
                }
            }
        )
    }

    private var shownConnectionBinding: Binding<ConnectionSheetItem?> {
        Binding(
            get: { viewModel.shownConnection },
            set: { if $0 == nil { viewModel.hideConnection() } }
        )
    }

    private var messageBinding: Binding<ConnectionsScreenMessage?> {
        Binding(
            get: { viewModel.message },
            set: { viewModel.message = $0 }
        )
    }

    // MARK: - Actions

    private func showScanner() {
        let scanner = GenericQRScannerController()

        scanner.onQRCodeScanned = { value in
            vc.dismiss(animated: true) {
                viewModel.onQRScanned(value)
            }
        }
        scanner.onCancel = {
            vc.dismiss(animated: true)
        }

        vc.present(scanner, animated: true)
    }

    private func mockScan() {
        viewModel.onQRScanned(MockDashConnectDataSource.sampleLoginQRCode)
    }
}

// MARK: - Previews

#Preview("Unavailable") {
    ConnectionsScreen(
        vc: UINavigationController(),
        viewModel: ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(),
            featureUnavailable: true
        )
    )
}

#Preview("Empty") {
    ConnectionsScreen(
        vc: UINavigationController(),
        viewModel: ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(),
            featureUnavailable: false
        )
    )
}

#Preview("Approved") {
    ConnectionsScreen(
        vc: UINavigationController(),
        viewModel: ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(initial: [.init(
                id: MockDashConnectDataSource.sample(.approved).id,
                name: MockDashConnectDataSource.sample(.approved).name,
                url: MockDashConnectDataSource.sample(.approved).url,
                status: .approved,
                updatedAt: MockDashConnectDataSource.sample(.approved).updatedAt
            )]),
            featureUnavailable: false
        )
    )
}

#Preview("Active") {
    ConnectionsScreen(
        vc: UINavigationController(),
        viewModel: ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(initial: [MockDashConnectDataSource.sample(.active)]),
            featureUnavailable: false
        )
    )
}
