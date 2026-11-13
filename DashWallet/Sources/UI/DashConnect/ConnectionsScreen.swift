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
        .task { await viewModel.refreshConnections() }
        .alert(item: messageBinding) { message in
            return Alert(
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
            viewModel.connectionSheetDismissed()
        }) { item in
            connectionSheet(for: item)
        }
    }

    // MARK: - States

    @ViewBuilder private var content: some View {
        if viewModel.featureUnavailable {
            title
            ConnectionsUnavailableState()
        } else if !viewModel.hasReadRows {
            // No empty state that the rows replace a moment later.
            title
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            Spacer()
        } else if viewModel.connections.isEmpty {
            title
            ConnectionsEmptyState(onScanQR: showScanner, onMockScan: mockScan)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    title
                    ConnectionsList(
                        items: viewModel.rows,
                        onOpen: { viewModel.showConnection($0) },
                        onDisconnect: { viewModel.showConnection($0, asksToDisconnect: true) },
                        onRemove: { item in
                            if let connection = item.connection { viewModel.removeConnection(connection) }
                        })
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var title: some View {
        TopIntro(title: NSLocalizedString("Connections", comment: "DashConnect"))
            .padding(.horizontal, !viewModel.connections.isEmpty && !viewModel.featureUnavailable ? 0 : 20)
            .padding(.top, 10)
    }

    private func connectionSheet(for item: ConnectionSheetItem) -> some View {
        ConnectionSheet(
            item: item,
            details: viewModel.shownDetails,
            detailsFailed: viewModel.shownDetailsFailed,
            withheld: viewModel.shownWithheldLines,
            connectedAt: viewModel.shownConnectedAt,
            isBusy: viewModel.isDisconnecting,
            message: viewModel.connectionSheetMessage,
            onClose: viewModel.hideConnection,
            onDisconnect: viewModel.disconnectShown,
            onRemove: {
                if let connection = item.connection { viewModel.removeConnection(connection) }
                viewModel.hideConnection()
            },
            takeDisconnectQuestion: viewModel.takeDisconnectQuestion,
            disconnectQuestion: viewModel.disconnectQuestion
        )
        .presentationDragIndicator(.visible)
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
        // An App Connect plan makes the sheet longer than the fixed height
        // shows; who pays and when access ends must not sit below the fold.
        .approveSheetPresentation(isTall: request.login.grantPlan != nil)
    }

    private func tokenPurchaseSheet(for purchase: DashConnectTokenPurchaseRequest) -> some View {
        ApproveTokenPurchaseSheet(
            request: purchase,
            isLoading: viewModel.isApprovingPurchase,
            errorText: viewModel.purchaseApproveError,
            onApprove: { viewModel.approvePendingTokenPurchase() },
            onDeny: { viewModel.denyPendingTokenPurchase() }
        )
        .approveSheetPresentation()
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
        // Not while something signs or an approval is up: the scanner would
        // cover it.
        guard viewModel.mayScan() else { return }
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

#Preview("Confirming") {
    ConnectionsScreen(
        vc: UINavigationController(),
        viewModel: ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(initial: [MockDashConnectDataSource.sample(.confirming)]),
            featureUnavailable: false
        )
    )
}

#Preview("Not Delivered") {
    ConnectionsScreen(
        vc: UINavigationController(),
        viewModel: ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(initial: [MockDashConnectDataSource.sample(.undelivered)]),
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
