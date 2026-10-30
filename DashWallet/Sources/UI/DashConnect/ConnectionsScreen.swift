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
                    }
                )

                TopIntro(title: NSLocalizedString("Connections", comment: "DashConnect"))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 20)

                content

                if !viewModel.featureUnavailable, let access = viewModel.sharedProfileAccess {
                    SharedProfileAccessRow(
                        keyCount: access.keyCount,
                        onRevoke: access.identityId == nil ? nil : { isConfirmingSharedProfileRevoke = true })
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
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
        .onAppear { viewModel.refreshSharedProfileAccess() }
        .confirmationDialog(
            NSLocalizedString("Revoke shared profile access?", comment: "DashConnect"),
            isPresented: $isConfirmingSharedProfileRevoke,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Revoke shared profile access", comment: "DashConnect"), role: .destructive) {
                viewModel.revokeSharedProfileAccess()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "Every app that uses one of these keys, on this or another device, loses access to your DashPay profile and has to ask again.",
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
    }

    // MARK: - States

    @ViewBuilder private var content: some View {
        if viewModel.featureUnavailable {
            ConnectionsUnavailableState()
        } else if viewModel.connections.isEmpty {
            ConnectionsEmptyState(onScanQR: showScanner, onMockScan: mockScan)
        } else {
            ConnectionsList(
                connections: viewModel.connections,
                onScanQR: showScanner,
                onMockScan: mockScan,
                onDisconnect: viewModel.disconnect
            )
            .padding(.horizontal, 20)
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

/// The DashPay profile keys on the active identity that no connection
/// accounts for, and the way to turn them all off. A disconnect leaves them,
/// since their bound does not say which app was given them.
private struct SharedProfileAccessRow: View {
    /// `nil` when the store could not be read.
    let keyCount: Int?
    /// `nil` when the identity could not be read: nothing to revoke on.
    let onRevoke: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Shared profile access", comment: "DashConnect"))
                    .dashFont(.subhead)
                    .foregroundStyle(Color.dash.primaryText)
                Text(keyCount.map {
                    String(
                        format: NSLocalizedString("DashPay profile keys no connection accounts for: %d", comment: "DashConnect"),
                        $0)
                } ?? NSLocalizedString("DashPay profile keys could not be checked", comment: "DashConnect"))
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onRevoke {
                Button(NSLocalizedString("Revoke", comment: "DashConnect"), role: .destructive, action: onRevoke)
                    .dashFont(.subhead)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
