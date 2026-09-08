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
                // Apply synchronously when the emission is already on the
                // main thread — every Swift caller of the state is
                // MainActor-bound — so `.idle` tears the window down before
                // the caller's next statement runs and a screen presented
                // right after `finish()` never lands under the scrim. The
                // Obj-C bridge (`beginWiping` / `finishWiping`) has no
                // compile-time isolation, so an off-main emission hops rather
                // than traps; it merely loses the same-turn teardown.
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        WalletLifecycleOverlayPresenter.shared.apply(phase)
                    }
                } else {
                    Task { @MainActor in
                        WalletLifecycleOverlayPresenter.shared.apply(phase)
                    }
                }
            }
    }

    /// True while a lifecycle card is on screen. The overlay owns a window at
    /// `.alert + 1`, above the level `UIAlertController` presents at, so a
    /// caller about to raise an alert can ask whether it would be drawn under
    /// the card.
    var isPresenting: Bool { overlayWindow != nil }

    private func apply(_ phase: WalletLifecycleTransitionState.Phase) {
        switch phase {
        case .idle, .exportingDiagnostics(dismissed: true, generation: _):
            // A dismissed export is still busy for admission purposes — see
            // the phase doc — but the user has asked to stop waiting, so the
            // window goes; a wipe admitted from here brings a new one.
            //
            // Hidden now (that same-turn teardown is the whole point of
            // applying synchronously), released next turn. This runs on the
            // caller's stack, and for the card's own buttons that stack is the
            // SwiftUI action closure of the view graph this window owns —
            // dropping the last reference here would free the hosting view,
            // and the `@StateObject` view model, out from under the touch
            // still being handled.
            guard let window = overlayWindow else { return }
            overlayWindow = nil
            window.isHidden = true
            DispatchQueue.main.async { withExtendedLifetime(window) {} }
        case .switchingNetwork, .failedNetworkSwitch,
             .switchingWallet, .removingWallet, .addingWallet,
             .failedWalletSwitch, .failedWalletRemoval,
             .wiping, .exportingDiagnostics(dismissed: false, generation: _):
            presentIfNeeded(for: phase)
        }
    }

    /// `phase` is the value being applied, passed down rather than re-read:
    /// `@Published` emits from `willSet`, so the state still holds the
    /// previous phase while this runs, and a view seeded from it would draw
    /// the previous card (or no card, over a full scrim).
    private func presentIfNeeded(for phase: WalletLifecycleTransitionState.Phase) {
        guard overlayWindow == nil else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(
            rootView: WalletLifecycleOverlayView(initialPhase: phase))
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

    /// Seeded from the phase the presenter is applying, not from the state:
    /// this can be created inside `@Published`'s `willSet`, where the state
    /// still holds the previous phase and the projected publisher replays
    /// that previous value to a new subscriber. `dropFirst()` skips exactly
    /// that stale replay.
    ///
    /// It cannot be the whole answer, because this initializer does not
    /// reliably run inside `willSet`: `StateObject.init(wrappedValue:)` takes
    /// an autoclosure that SwiftUI evaluates lazily, at the view's first body
    /// render, which is a later runloop turn. By then the replayed value is
    /// the committed phase — usually the seed, but a LATER phase whenever the
    /// operation already moved on (a wallet switch that fails before its first
    /// real suspension does exactly this), and dropping that would strand the
    /// card on a progress spinner behind a blocking scrim with no way out.
    /// So the committed phase is re-read once the current turn is over: a
    /// no-op in the `willSet` case, and the change that was dropped in the
    /// lazy one.
    init(initialPhase: WalletLifecycleTransitionState.Phase) {
        phase = initialPhase
        phaseCancellable = WalletLifecycleTransitionState.shared.$phase
            .dropFirst()
            .sink { [weak self] phase in
                self?.phase = phase
            }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let committed = WalletLifecycleTransitionState.shared.phase
            if committed != self.phase {
                self.phase = committed
            }
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

    /// Stop waiting for the export: the card goes, the result is discarded
    /// when it arrives. The export itself keeps running and keeps its
    /// admission until it returns — the SDK snapshot cannot be interrupted
    /// and may still hold the persistence queue.
    func cancelDiagnosticsExport() {
        DiagnosticLogExporter.cancelWaiting()
    }
}

struct WalletLifecycleOverlayView: View {
    @StateObject private var viewModel: WalletLifecycleOverlayViewModel

    init(initialPhase: WalletLifecycleTransitionState.Phase) {
        _viewModel = StateObject(wrappedValue: WalletLifecycleOverlayViewModel(initialPhase: initialPhase))
    }

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
            case let .addingWallet(isImport):
                progressCard(
                    title: isImport
                        ? NSLocalizedString("Importing wallet…", comment: "Wallets")
                        : NSLocalizedString("Creating wallet…", comment: "Wallets"),
                    subtitle: NSLocalizedString(
                        "Preparing your wallet. This may take a few seconds.",
                        comment: "Wallets"))
            case let .wiping(title):
                // Falls back to the Delete All copy — the same key the root
                // controller's HUD used, so translations carry over.
                progressCard(
                    title: title ?? NSLocalizedString("Deleting All Wallets…", comment: ""),
                    subtitle: nil)
            case .exportingDiagnostics(dismissed: true, generation: _):
                // No window exists for this phase (the presenter tears it
                // down); nothing to draw if a view is ever asked.
                EmptyView()
            case .exportingDiagnostics(dismissed: false, generation: _):
                // Only the support export takes this phase — the About and
                // Tools exports collect no diagnostics and are not gated — so
                // the copy can say what is actually happening. The one busy
                // phase whose duration the app cannot bound, hence the one
                // busy card with a way out.
                card {
                    SwiftUI.ProgressView()
                        .controlSize(.large)
                    Text(NSLocalizedString("Preparing logs…", comment: "Diagnostic log export overlay"))
                        .font(.headline)
                    Text(NSLocalizedString(
                        "Collecting wallet diagnostics. This may take a few seconds.",
                        comment: "Diagnostic log export overlay"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    actionButton(NSLocalizedString("Cancel", comment: ""), prominent: false) {
                        viewModel.cancelDiagnosticsExport()
                    }
                }
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
