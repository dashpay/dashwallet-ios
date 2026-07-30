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
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack {
                vc.popViewController(animated: true)
            }

            TopIntro(title: NSLocalizedString("Connections", comment: "DashConnect"))
                .padding(.leading, 20)
                .padding(.trailing, 60)
                .padding(.top, 10)
                .padding(.bottom, 20)

            content
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
        .alert(NSLocalizedString("Error", comment: ""), isPresented: errorIsPresented) {
            Button(NSLocalizedString("OK", comment: "")) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: isApproveSheetPresented) {
            if let request = viewModel.pendingRequest {
                approveSheet(for: request)
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
        }
    }

    private func approveSheet(for request: ConnectionRequest) -> some View {
        ApproveConnectionSheet(
            request: request,
            isLoading: viewModel.isApproving,
            onApprove: { viewModel.approvePendingRequest() },
            onDeny: { viewModel.denyPendingRequest() }
        )
        .approveSheetPresentation(isLoading: viewModel.isApproving)
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

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    // MARK: - Actions

    private func showScanner() {
        let scanner = GenericQRScannerController()

        // The mock UI flow accepts any scanned payload for now; MO-945 will
        // replace this with real login-QR parsing.
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
        viewModel.onQRScanned("dash-key:mock")
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

#Preview("Disconnected") {
    ConnectionsScreen(
        vc: UINavigationController(),
        viewModel: ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(initial: [MockDashConnectDataSource.sample(.disconnected)]),
            featureUnavailable: false
        )
    )
}
