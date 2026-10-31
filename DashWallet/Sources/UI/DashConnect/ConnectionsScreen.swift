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
    @State private var isConfirmingSharedProfileRevoke = false
    @State private var isConfirmingSharedProfileKeep = false
    /// The access the revoke confirmation was opened for.
    @State private var sharedProfileAccessToRevoke: SharedProfileAccess?
    /// The access the keep confirmation was opened for.
    @State private var sharedProfileAccessToKeep: SharedProfileAccess?

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

                if let message = sharedProfileAccessMessage {
                    message
                        .padding(.horizontal, 40)
                        .padding(.vertical, 20)
                        // "Dismiss" keeps the keys, which cannot be undone
                        // from this device: the actions are named for that.
                        .accessibilityElement(children: .combine)
                        .accessibilityActions {
                            if viewModel.canActOnSharedProfileAccess {
                                Button(NSLocalizedString("Keep shared profile access", comment: "DashConnect"), action: confirmKeep)
                                Button(NSLocalizedString("Revoke shared profile access", comment: "DashConnect"), action: confirmRevoke)
                            }
                        }
                }
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
        .onAppear {
            viewModel.refreshSharedProfileAccess()
            viewModel.refreshConnectionStatus()
        }
        .confirmationDialog(
            NSLocalizedString("Revoke shared profile access?", comment: "DashConnect"),
            isPresented: $isConfirmingSharedProfileRevoke,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Revoke shared profile access", comment: "DashConnect"), role: .destructive) {
                viewModel.revokeSharedProfileAccess(sharedProfileAccessToRevoke)
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "Every app that uses one of these keys, on this or another device, loses access to your DashPay profile and has to ask again.",
                comment: "DashConnect"))
        }
        .confirmationDialog(
            NSLocalizedString("Keep these keys?", comment: "DashConnect"),
            isPresented: $isConfirmingSharedProfileKeep,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Keep", comment: "DashConnect")) {
                if let access = sharedProfileAccessToKeep { viewModel.keepSharedProfileAccess(access) }
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "Keep them only if you recognize every one, for example from an app you connected on another device. This device stops counting them and cannot revoke them afterwards.",
                comment: "DashConnect"))
        }
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
        let rows = viewModel.rows(for: viewModel.selectedTab)
        if viewModel.selectedTab == .disconnected, viewModel.historyIsUnreadable {
            Text(NSLocalizedString("Disconnected apps could not be read.", comment: "DashConnect"))
                .dashFont(.subhead)
                .foregroundColor(Color.dash.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        } else if rows.isEmpty {
            Text(NSLocalizedString("No apps here", comment: "DashConnect: an empty tab of the Connections page"))
                .dashFont(.subhead)
                .foregroundColor(Color.dash.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        } else {
            ConnectionsList(items: rows, onOpen: viewModel.showConnection)
        }
    }

    private static func tabName(_ tab: ConnectionsTab) -> String {
        switch tab {
        case .active: return NSLocalizedString("Active", comment: "DashConnect connection status")
        case .disconnected: return NSLocalizedString("Disconnected", comment: "DashConnect connection status")
        case .expired: return NSLocalizedString("Expired", comment: "DashConnect connection status")
        }
    }

    /// The DashPay profile keys on the active identity that no connection
    /// accounts for, and the way to keep or revoke them, while there are any.
    private var sharedProfileAccessMessage: SystemMessageView? {
        guard viewModel.showsSharedProfileAccess else { return nil }
        let keyCount = viewModel.sharedProfileAccess?.keyCount
        let canAct = viewModel.canActOnSharedProfileAccess
        return SystemMessageView(
            title: NSLocalizedString("Shared profile access", comment: "DashConnect"),
            subtitle: keyCount.map {
                String(
                    format: NSLocalizedString(
                        "Keys not linked to a connection that can update your DashPay profile: %d", comment: "DashConnect"),
                    $0)
            } ?? NSLocalizedString("Keys that can update your DashPay profile could not be checked", comment: "DashConnect"),
            backgroundColor: Color.dash.white,
            buttonName: canAct ? NSLocalizedString("Dismiss", comment: "DashConnect: keep the shared profile keys") : nil,
            onAction: canAct ? confirmKeep : nil,
            secondaryButtonName: canAct ? NSLocalizedString("Revoke", comment: "DashConnect") : nil,
            onSecondaryAction: canAct ? confirmRevoke : nil,
            buttonStyle: .tintedGray)
    }

    private func confirmKeep() {
        sharedProfileAccessToKeep = viewModel.sharedProfileAccess
        isConfirmingSharedProfileKeep = true
    }

    private func confirmRevoke() {
        sharedProfileAccessToRevoke = viewModel.sharedProfileAccess
        isConfirmingSharedProfileRevoke = true
    }

    private func connectionSheet(for item: ConnectionSheetItem) -> some View {
        ConnectionSheet(
            item: item,
            details: viewModel.shownDetails,
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
        .sheet(isPresented: $showsFundingLimitsInfo) {
            FundingLimitsInfoSheet(onClose: { showsFundingLimitsInfo = false })
                .presentationDetents([.medium])
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
