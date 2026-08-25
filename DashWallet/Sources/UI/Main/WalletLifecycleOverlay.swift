//
//  WalletLifecycleOverlay.swift
//  DashWallet
//
//  App-wide blocking overlay for wallet-lifecycle operations (network
//  switch, wallet switch, per-wallet removal, full wipe): the
//  dedicated-UIWindow presenter, the Obj-C bridge used by the wipe flows,
//  and the overlay view model + card view. Driven by
//  WalletLifecycleTransitionState.
//

import Combine
import SwiftUI
import UIKit

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
            case let .failedNetworkSwitch(from, target, message):
                card {
                    failureHeader(
                        title: String(
                            format: NSLocalizedString("Switching to %@ failed", comment: "Network switch overlay"),
                            Self.displayName(of: target)),
                        message: message)
                    actionButton(NSLocalizedString("Retry", comment: ""), prominent: true) {
                        viewModel.retryNetworkSwitch(to: target)
                    }
                    // Escape hatch: the origin network was working when the
                    // switch began, so a way back must exist even when the
                    // destination keeps failing.
                    if from != target {
                        actionButton(NSLocalizedString("Switch Back", comment: "Wallets"), prominent: false) {
                            viewModel.retryNetworkSwitch(to: from)
                        }
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
