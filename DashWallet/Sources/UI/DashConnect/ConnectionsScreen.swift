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
    /// Weak: this page sits in `vc`'s own stack.
    private weak var vc: UINavigationController?
    /// Starts the app's username creation; `nil` where it cannot be reached.
    private let onCreateUsername: (() -> Void)?
    /// Presents the identity top-up over whatever is on screen; `nil` where
    /// it cannot be reached.
    private let onTopUpIdentity: (() -> Void)?

    @StateObject private var viewModel: ConnectionsViewModel

    init(
        vc: UINavigationController?,
        viewModel: ConnectionsViewModel? = nil,
        onCreateUsername: (() -> Void)? = nil,
        onTopUpIdentity: (() -> Void)? = nil
    ) {
        self.vc = vc
        self.onCreateUsername = onCreateUsername
        self.onTopUpIdentity = onTopUpIdentity
        _viewModel = StateObject(wrappedValue: viewModel ?? ConnectionsViewModel())
    }

    @State private var showsFundingLimitsInfo = false
    /// The Join DashPay sheet, which leads to the username form as More's
    /// does; `createsUsernameAfterSheet` carries the user's choice to it.
    @State private var showsJoinDashPay = false
    @State private var createsUsernameAfterSheet = false
    /// Reconnect closes the connection sheet first: the scanner is
    /// presented once it is gone.
    @State private var scansAfterSheet = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                DashUIKit.NavigationBar(
                    leading: {
                        DashUIKit.NavigationBarElement.back.button { vc?.popViewController(animated: true) }
                    },
                    trailing: {
                        if !viewModel.featureUnavailable, !showsNoUsernameState {
                            // Without a username a new connection starts by
                            // creating one.
                            DashUIKit.NavigationBarElement.plus.button(
                                action: viewModel.needsUsername ? startCreatingUsername : showScanner)
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
        // Another identity may have become active while the screen was away.
        .onAppear { viewModel.refreshUsername() }
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
            } else if viewModel.pendingReturn != nil {
                // The request is answered; the sheet asks before the
                // browser opens an app the wallet does not know.
                DashConnectReturnStep(
                    host: viewModel.pendingReturnHost ?? "",
                    note: viewModel.returnStepNote,
                    onOpen: { viewModel.openPendingReturn() },
                    onStay: { viewModel.stayInWallet() })
                    .approveSheetPresentation()
            }
        }
        .sheet(isPresented: isTokenPurchaseSheetPresented) {
            if let purchase = viewModel.pendingTokenPurchase {
                tokenPurchaseSheet(for: purchase)
            }
        }
        .sheet(item: shownConnectionBinding, onDismiss: {
            showsFundingLimitsInfo = false
            viewModel.connectionSheetDismissed()
            guard scansAfterSheet else { return }
            scansAfterSheet = false
            showScanner()
        }) { item in
            connectionSheet(for: item)
        }
        #if DASHPAY
        .sheet(isPresented: $showsJoinDashPay, onDismiss: {
            guard createsUsernameAfterSheet else { return }
            createsUsernameAfterSheet = false
            onCreateUsername?()
        }) {
            // No detent: the dialog sizes itself (`BottomSheet.selfSizing`).
            JoinDashPayInfoDialog(action: { createsUsernameAfterSheet = true })
        }
        #endif
    }

    // MARK: - States

    /// A wallet without a username and with nothing ever connected: the page
    /// offers to create one. A wallet that has connections keeps its list,
    /// so their keys can still be turned off.
    private var showsNoUsernameState: Bool {
        viewModel.needsUsername && viewModel.hasReadRows && !viewModel.hasConnectionsOrHistory
    }

    /// Creating a username starts on the Join DashPay sheet, as from More.
    private func startCreatingUsername() {
        #if DASHPAY
        showsJoinDashPay = true
        #else
        onCreateUsername?()
        #endif
    }

    @ViewBuilder private var content: some View {
        if viewModel.featureUnavailable {
            title
            ConnectionsUnavailableState()
        } else if !viewModel.hasReadRows {
            // Not known yet whether anything was connected: no empty state
            // that the rows and the history replace a moment later.
            title
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            Spacer()
        } else if showsNoUsernameState {
            title
            ConnectionsEmptyState(
                kind: .noUsername(onCreateUsername: onCreateUsername == nil ? nil : startCreatingUsername))
        } else if !viewModel.hasConnectionsOrHistory {
            title
            ConnectionsEmptyState(kind: .noApps(onScanQR: showScanner, onMockScan: mockScan))
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
        if !rows.isEmpty {
            ConnectionsList(
                items: rows,
                onOpen: { viewModel.showConnection($0) },
                onDisconnect: { viewModel.showConnection($0, asksToDisconnect: true) },
                onRemove: { item in
                    if let connection = item.connection { viewModel.removeConnection(connection) }
                },
                onReconnect: showScanner)
        } else {
            tabNote(Self.emptyTabText(tab))
        }
    }

    private func tabNote(_ text: String) -> some View {
        Text(text)
            .dashFont(.subhead)
            .foregroundColor(Color.dash.secondaryText)
            .multilineTextAlignment(.center)
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
            funding: viewModel.shownFundingLines,
            fundingFailed: viewModel.shownFundingFailed,
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
            disconnectQuestion: viewModel.disconnectQuestion,
            onScan: {
                scansAfterSheet = true
                viewModel.hideConnection()
            },
            onShowFundingLimitsInfo: { showsFundingLimitsInfo = true }
        )
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showsFundingLimitsInfo) {
            FundingLimitsInfoSheet(onClose: { showsFundingLimitsInfo = false })
                // Starts at the tallest it may be, so the first measurement
                // is of the whole text; the sheet then settles at its height.
                .selfSizingSheet(fallback: .greatestFiniteMagnitude, background: Color.dash.secondaryBackground)
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func approveSheet(for request: ConnectionRequest) -> some View {
        if request.login.grantPlan != nil {
            AppConnectApproveSheet(
                viewModel: viewModel, request: request, onTopUp: onTopUpIdentity)
                .approveSheetPresentation(isTall: true)
        } else {
            legacyApproveSheet(for: request)
        }
    }

    private func legacyApproveSheet(for request: ConnectionRequest) -> some View {
        ApproveConnectionSheet(
            request: request,
            isLoading: viewModel.isApproving,
            errorText: viewModel.approveError,
            onApprove: { viewModel.approvePendingRequest() },
            onRetry: { viewModel.retryPendingRequest() },
            onDeny: { viewModel.denyPendingRequest(asksToReturn: true) }
        )
        // Only a request that cannot be answered comes here: its sheet is
        // short.
        .approveSheetPresentation(isTall: false)
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
            get: { viewModel.pendingRequest != nil || viewModel.pendingReturn != nil },
            set: { isPresented in
                guard !isPresented else { return }
                if viewModel.pendingRequest == nil {
                    // Closing the return step stays in the wallet.
                    viewModel.stayInWallet()
                } else if !viewModel.isApproving {
                    // Closing the sheet declines, and stays in the wallet:
                    // the sheet is gone and cannot ask about a return.
                    viewModel.denyPendingRequest(asksToReturn: false)
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
            vc?.dismiss(animated: true) {
                viewModel.onQRScanned(value)
            }
        }
        scanner.onCancel = {
            vc?.dismiss(animated: true)
        }

        vc?.present(scanner, animated: true)
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

#Preview("Expired") {
    ConnectionsScreen(
        vc: UINavigationController(),
        viewModel: ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(initial: [MockDashConnectDataSource.sample(.expired)]),
            featureUnavailable: false
        )
    )
}
