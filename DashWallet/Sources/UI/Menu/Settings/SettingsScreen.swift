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
import DashUIKit
import Combine
import MessageUI

struct SettingsScreen: View {
    private let vc: UINavigationController
    // Retained solely for the frozen MainMenuViewController call site; the
    // rescan controls were removed with the dead DashSync rescan actions
    // (post-M6 there is no SDK rescan API), so this closure is never invoked.
    private let onDidRescan: () -> ()

    @StateObject private var viewModel = SettingsMenuViewModel()
    @State private var showNetworkAlert = false
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
                .padding(.leading, 20)
                .padding(.trailing, 60)
                .padding(.top, 10)
                .padding(.bottom, 20)

            // Menu list
            VStack(spacing: 2) {
                ForEach(viewModel.items) { item in
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
                    .frame(minHeight: 60)
                }
            }
            .padding(6)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.dash.primaryBackground)
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
    }
    
    private func handleNavigation(_ destination: SettingsMenuNavigationDestination?) {
        switch destination {
        case .currencySelector:
            showCurrencySelector()
        case .network:
            showNetworkAlert = true
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
        let controller = AboutDashHostingViewController()
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
    
    private func updateView() {
        // Trigger view refresh after network change
        viewModel.resetNavigation()
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

private final class AboutDashHostingViewController: BaseViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_background()

        let rootView = AboutDashView(
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onContactSupport: { [weak self] in
                self?.presentSupportEmailController()
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        dw_embedChild(hostingController)
    }
}

extension AboutDashHostingViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}

extension AboutDashHostingViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}

// MARK: - Network switch overlay (app-wide)
//
// Colocated with the settings screen (the user-facing switch trigger) per the
// repo's append-to-existing-file convention, but app-scoped: the presenter
// owns a dedicated UIWindow, not a child of any screen.

/// Full-screen blocking overlay for an in-flight network switch, hosted in
/// its OWN `UIWindow`.
///
/// A network switch rebuilds the root UI (`AppDelegate` reassigns
/// `window.rootViewController`; `DWAppRootViewController` swaps its child on
/// `DWCurrentNetworkDidChange`), so any overlay mounted as a child view
/// controller would be torn down mid-switch. A separate window at
/// `.alert + 1` survives every root swap; it is created lazily when the
/// transition enters `.switching` and dropped only on `.idle`. The `.failed`
/// phase keeps the window up — the old runtime is already torn down at that
/// point, so the app may have no working manager and the only ways forward
/// are Retry (or force-quit).
@MainActor
final class NetworkSwitchOverlayPresenter {
    static let shared = NetworkSwitchOverlayPresenter()

    private var overlayWindow: UIWindow?
    private var phaseCancellable: AnyCancellable?

    private init() {}

    /// Idempotent activation: every switch entry point calls this before
    /// starting the switch; the first call subscribes to the transition
    /// state for the rest of the process lifetime. If a caller forgets, the
    /// switch still works — only the overlay is missing.
    func ensureActive() {
        guard phaseCancellable == nil else { return }
        phaseCancellable = NetworkTransitionState.shared.$phase
            .sink { phase in
                Task { @MainActor in
                    NetworkSwitchOverlayPresenter.shared.apply(phase)
                }
            }
    }

    private func apply(_ phase: NetworkTransitionState.Phase) {
        switch phase {
        case .idle:
            overlayWindow?.isHidden = true
            overlayWindow = nil
        case .switching, .failed:
            presentIfNeeded()
        }
    }

    private func presentIfNeeded() {
        guard overlayWindow == nil else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: NetworkSwitchOverlayView())
        window.rootViewController?.view.backgroundColor = .clear
        window.backgroundColor = .clear
        window.isHidden = false
        overlayWindow = window
    }
}

/// Content of the network-switch overlay window. Blocks all interaction while
/// `.switching` (spinner + destination) and while `.failed` (error + Retry).
/// Deliberately does NOT wait for peers or chain sync — the runtime flips to
/// `.idle` the moment the destination runtime is bound and its services
/// started.
@MainActor
final class NetworkSwitchOverlayViewModel: ObservableObject {
    @Published private(set) var phase: NetworkTransitionState.Phase

    private var phaseCancellable: AnyCancellable?

    init() {
        let transitionState = NetworkTransitionState.shared
        phase = transitionState.phase
        phaseCancellable = transitionState.$phase
            .sink { [weak self] phase in
                self?.phase = phase
            }
    }

    func retrySwitch(to target: WalletEnvironment.NetworkKind) {
        Task {
            try? await SwiftDashSDKWalletRuntime.shared.switchNetwork(to: target)
        }
    }
}

struct NetworkSwitchOverlayView: View {
    @StateObject private var viewModel = NetworkSwitchOverlayViewModel()

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            switch viewModel.phase {
            case .idle:
                EmptyView()
            case let .switching(_, to):
                card {
                    // Explicit SwiftUI qualifier: the app has its own UIKit
                    // `ProgressView` (UI/Views/ProgressView.swift) shadowing it.
                    SwiftUI.ProgressView()
                        .controlSize(.large)
                    Text(String(
                        format: NSLocalizedString("Switching to %@…", comment: "Network switch overlay"),
                        Self.displayName(of: to)))
                        .font(.headline)
                    Text(NSLocalizedString(
                        "Preparing the wallet on the selected network…",
                        comment: "Network switch overlay"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            case let .failed(target, message):
                card {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(String(
                        format: NSLocalizedString("Switching to %@ failed", comment: "Network switch overlay"),
                        Self.displayName(of: target)))
                        .font(.headline)
                    if let message, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        viewModel.retrySwitch(to: target)
                    } label: {
                        Text(NSLocalizedString("Retry", comment: ""))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 16) {
            content()
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .padding(32)
    }

    private static func displayName(of kind: WalletEnvironment.NetworkKind) -> String {
        switch kind {
        case .mainnet: return "Mainnet"
        case .testnet: return "Testnet"
        case .devnet: return "Devnet"
        }
    }
}
