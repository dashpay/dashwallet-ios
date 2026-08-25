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

/// Full-screen blocking overlay for an in-flight wallet-lifecycle operation
/// (network switch, wallet switch, per-wallet removal), hosted in its OWN
/// `UIWindow`.
///
/// These operations rebuild or destroy the UI a screen-local loader would
/// live in: a network switch swaps the root (`AppDelegate` reassigns
/// `window.rootViewController`; `DWAppRootViewController` swaps its child on
/// `DWCurrentNetworkDidChange`), and a wallet switch makes
/// `MainTabbarController` rebuild every tab on the active-wallet change it
/// posts. A separate window at `.alert + 1` survives every root swap; it is
/// created lazily when the transition leaves `.idle` and dropped only on
/// `.idle` — never between `advance` transitions (switch → remove), so the
/// window cannot flicker mid-operation. Failure phases keep the window up;
/// each failure card owns its recovery actions.
@MainActor
final class WalletLifecycleOverlayPresenter {
    static let shared = WalletLifecycleOverlayPresenter()

    private var overlayWindow: UIWindow?
    private var phaseCancellable: AnyCancellable?

    private init() {}

    /// Idempotent activation: every operation entry point calls this before
    /// starting; the first call subscribes to the transition state for the
    /// rest of the process lifetime. If a caller forgets, the operation
    /// still works — only the overlay is missing.
    func ensureActive() {
        guard phaseCancellable == nil else { return }
        phaseCancellable = WalletLifecycleTransitionState.shared.$phase
            .sink { phase in
                Task { @MainActor in
                    WalletLifecycleOverlayPresenter.shared.apply(phase)
                }
            }
    }

    private func apply(_ phase: WalletLifecycleTransitionState.Phase) {
        switch phase {
        case .idle:
            overlayWindow?.isHidden = true
            overlayWindow = nil
        case .switchingNetwork, .failedNetworkSwitch,
             .switchingWallet, .removingWallet,
             .failedWalletSwitch, .failedWalletRemoval,
             .wiping:
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
        window.rootViewController = UIHostingController(rootView: WalletLifecycleOverlayView())
        window.rootViewController?.view.backgroundColor = .clear
        window.backgroundColor = .clear
        window.isHidden = false
        overlayWindow = window
    }
}

/// Obj-C face of the lifecycle overlay for the Obj-C wipe flows —
/// `DWAppRootViewController.beginWipeWalletWithAuthorization:` (Delete All)
/// and `DWRecoverViewController`'s phrase-authorized wipe — which used to
/// block with local MBProgressHUDs. Exposes exactly begin/finish; the wipes
/// keep their UIKit failure alerts (shown after finish), so there is no
/// failure phase here.
@objc(DWWalletLifecycleOverlayBridge)
@MainActor
final class WalletLifecycleOverlayBridge: NSObject {
    /// Begin the wipe phase and show its blocking card; nil `title` falls
    /// back to the Delete All copy. Returns false when another interactive
    /// operation holds the admission gate — the caller must NOT start the
    /// wipe then (a concurrent wipe would mutate wallet state under that
    /// operation's teardown/rebuild). `finishWiping` is phase-guarded so it
    /// can never clear a phase it does not own.
    @objc @discardableResult static func beginWiping(title: String?) -> Bool {
        WalletLifecycleOverlayPresenter.shared.ensureActive()
        return WalletLifecycleTransitionState.shared.tryBegin(.wiping(title: title))
    }

    /// Drop the overlay if (and only if) the wiping phase is still active.
    @objc static func finishWiping() {
        let state = WalletLifecycleTransitionState.shared
        if case .wiping = state.phase {
            state.finish()
        }
    }
}

/// Content state + actions of the lifecycle overlay window. Blocks all
/// interaction while an operation is in flight, and owns the failure cards'
/// recovery actions. Deliberately does NOT wait for peers or chain sync —
/// the runtime flips to `.idle` the moment the destination runtime is bound
/// and its services started.
@MainActor
final class WalletLifecycleOverlayViewModel: ObservableObject {
    @Published private(set) var phase: WalletLifecycleTransitionState.Phase

    private var phaseCancellable: AnyCancellable?

    init() {
        let transitionState = WalletLifecycleTransitionState.shared
        phase = transitionState.phase
        phaseCancellable = transitionState.$phase
            .sink { [weak self] phase in
                self?.phase = phase
            }
    }

    func retryNetworkSwitch(to target: WalletEnvironment.NetworkKind) {
        Task {
            try? await SwiftDashSDKWalletRuntime.shared.switchNetwork(to: target)
        }
    }

    /// Retry of a failed wallet switch — the same gated helper every
    /// interactive wallet switch uses (admission from `.failedWalletSwitch`
    /// exists exactly for this card's actions).
    func retryWalletSwitch(to targetId: Data, targetName: String?) {
        Task {
            try? await WalletsViewModel.gatedSwitchWallet(
                targetId: targetId,
                targetName: targetName)
        }
    }

    /// Switch Back toward the wallet that was active before the failed
    /// switch began (captured by the gated helper before the registry was
    /// repointed).
    func switchBack(to previousId: Data) {
        let name = WalletsViewModel.displayName(for: previousId)
        Task {
            try? await WalletsViewModel.gatedSwitchWallet(
                targetId: previousId,
                targetName: name)
        }
    }

    func dismissRemovalFailure() {
        WalletLifecycleTransitionState.shared.finish()
    }
}

struct WalletLifecycleOverlayView: View {
    @StateObject private var viewModel = WalletLifecycleOverlayViewModel()

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            switch viewModel.phase {
            case .idle:
                EmptyView()
            case let .switchingNetwork(_, to):
                progressCard(
                    title: String(
                        format: NSLocalizedString("Switching to %@…", comment: "Network switch overlay"),
                        Self.displayName(of: to)),
                    subtitle: NSLocalizedString(
                        "Preparing the wallet on the selected network…",
                        comment: "Network switch overlay"))
            case let .switchingWallet(targetName):
                progressCard(
                    title: NSLocalizedString("Switching wallet…", comment: "Wallets"),
                    subtitle: targetName)
            case .removingWallet:
                progressCard(
                    title: NSLocalizedString("Removing wallet…", comment: "Wallets"),
                    subtitle: nil)
            case let .wiping(title):
                // Falls back to the Delete All copy — the same key the root
                // controller's HUD used, so translations carry over.
                progressCard(
                    title: title ?? NSLocalizedString("Deleting All Wallets…", comment: ""),
                    subtitle: nil)
            case let .failedNetworkSwitch(target, message):
                card {
                    failureHeader(
                        title: String(
                            format: NSLocalizedString("Switching to %@ failed", comment: "Network switch overlay"),
                            Self.displayName(of: target)),
                        message: message)
                    actionButton(NSLocalizedString("Retry", comment: ""), prominent: true) {
                        viewModel.retryNetworkSwitch(to: target)
                    }
                }
            case let .failedWalletSwitch(targetId, targetName, previousId, message):
                card {
                    failureHeader(
                        title: NSLocalizedString("Switching wallet failed", comment: "Wallets"),
                        message: message)
                    actionButton(NSLocalizedString("Retry", comment: ""), prominent: true) {
                        viewModel.retryWalletSwitch(to: targetId, targetName: targetName)
                    }
                    if let previousId {
                        actionButton(NSLocalizedString("Switch Back", comment: "Wallets"), prominent: false) {
                            viewModel.switchBack(to: previousId)
                        }
                    }
                }
            case let .failedWalletRemoval(message):
                card {
                    failureHeader(
                        title: NSLocalizedString("Removing wallet failed", comment: "Wallets"),
                        message: message)
                    actionButton(NSLocalizedString("OK", comment: ""), prominent: true) {
                        viewModel.dismissRemovalFailure()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func progressCard(title: String, subtitle: String?) -> some View {
        card {
            // Explicit SwiftUI qualifier: the app has its own UIKit
            // `ProgressView` (UI/Views/ProgressView.swift) shadowing it.
            SwiftUI.ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func failureHeader(title: String, message: String?) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.largeTitle)
            .foregroundColor(.orange)
        Text(title)
            .font(.headline)
        if let message, !message.isEmpty {
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func actionButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let label = Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        let button = Button(action: action) { label }
        return Group {
            if prominent {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
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
