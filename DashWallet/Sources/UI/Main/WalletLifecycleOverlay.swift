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
/// each failure card owns its recovery actions. The PIN window takes priority
/// except during an explicitly authorized wipe (which can start from PIN
/// recovery). Hiding while locked preserves the card and any support draft.
@MainActor
final class WalletLifecycleOverlayPresenter {
    static let shared = WalletLifecycleOverlayPresenter()

    private(set) var overlayWindow: UIWindow?
    private let state = WalletLifecycleTransitionState.shared
    private var cancellables = Set<AnyCancellable>()
    private var openingDelay: Task<Void, Never>?
    private var lockScreenVisible = false
    private var applicationActive = false
    /// Set around every PIN gate a card runs (the migration card's Export
    /// Logs, the wallet-open card's Backup recovery phrase and Reset). The
    /// PIN prompt presents from a `.normal`-level window, below this
    /// overlay's `.alert + 1`, so the overlay hides for the prompt's duration
    /// exactly as it does behind the lock screen; the card and its state
    /// survive.
    private var authenticationPromptVisible = false

    private init() {}

    /// Idempotent activation: every operation entry point calls this before
    /// starting; the first call subscribes for the process lifetime.
    func ensureActive() {
        guard cancellables.isEmpty else { return }
        applicationActive = UIApplication.shared.applicationState == .active
        state.$phase
            .sink { [weak self] _ in
                // @Published emits before the assignment. Read the settled
                // state rather than presenting an already-obsolete phase.
                Task { @MainActor [weak self] in self?.applyCurrentPhase() }
            }
            .store(in: &cancellables)
        for (notification, active) in [
            (UIApplication.didBecomeActiveNotification, true),
            (UIApplication.willResignActiveNotification, false)
        ] {
            NotificationCenter.default.publisher(for: notification)
                .sink { [weak self] _ in
                    // UIKit sends these notifications on the main thread.
                    MainActor.assumeIsolated {
                        self?.applicationActive = active
                        self?.updateVisibility()
                    }
                }
                .store(in: &cancellables)
        }
    }

    /// Called synchronously by the existing root controller before showing
    /// PIN and after its dismissal, including roots installed after onboarding.
    func setLockScreenVisible(_ visible: Bool) {
        lockScreenVisible = visible
        updateVisibility()
    }

    func setAuthenticationPromptVisible(_ visible: Bool) {
        authenticationPromptVisible = visible
        updateVisibility()
    }

    /// Progress phases that may finish within a blink: a fresh window for
    /// them is delayed so a fast open (or a fast legacy import) never flashes
    /// a modal. An existing window (a failure card during Retry) updates
    /// immediately.
    private static func isDelayedProgress(_ phase: WalletLifecycleTransitionState.Phase) -> Bool {
        phase == .openingWallet || phase == .migratingLegacyWallet
    }

    private func applyCurrentPhase() {
        if Self.isDelayedProgress(state.phase), overlayWindow == nil {
            guard openingDelay == nil else { return }
            openingDelay = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 500_000_000) }
                catch { return }
                guard let self else { return }
                self.openingDelay = nil
                guard Self.isDelayedProgress(self.state.phase) else { return }
                self.presentIfNeeded()
            }
            return
        }
        openingDelay?.cancel()
        openingDelay = nil
        if state.phase == .idle {
            overlayWindow?.isHidden = true
            overlayWindow = nil
        } else {
            presentIfNeeded()
        }
    }

    private func updateVisibility() {
        // Forgot-PIN recovery can start an authorized wipe inside the lock
        // window. Its progress must block Cancel until deletion completes.
        let blockedByLock: Bool
        if case .wiping = state.phase {
            blockedByLock = false
        } else {
            blockedByLock = lockScreenVisible
        }
        // A window created before any scene connected (a background launch,
        // or a failure reported while `didFinishLaunching` is still running)
        // is never shown; attach it once a scene exists.
        if let overlayWindow, overlayWindow.windowScene == nil {
            overlayWindow.windowScene = Self.currentWindowScene()
        }
        overlayWindow?.isHidden = blockedByLock || authenticationPromptVisible || !applicationActive
    }

    private static func currentWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private func presentIfNeeded() {
        // Re-evaluate even when reusing a hidden failure window for a wipe.
        defer { updateVisibility() }
        guard overlayWindow == nil else { return }
        // Without a scene yet, `updateVisibility()` attaches the window later.
        let window = Self.currentWindowScene().map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: WalletLifecycleOverlayView())
        window.rootViewController?.view.backgroundColor = .clear
        window.rootViewController?.view.accessibilityViewIsModal = true
        window.backgroundColor = .clear
        overlayWindow = window
    }
}

/// Obj-C face of the lifecycle overlay for the Obj-C wipe flows —
/// `DWAppRootViewController.beginWipeWalletWithAuthorization:` (Delete All)
/// and `DWRecoverViewController`'s phrase-authorized wipe. It also gives the
/// existing root controller a thin bridge for lock-screen visibility.
/// Wipes keep their UIKit failure alerts (shown after finish).
@objc(DWWalletLifecycleOverlayBridge)
@MainActor
final class WalletLifecycleOverlayBridge: NSObject {
    @objc static func setLockScreenVisible(_ visible: Bool) {
        WalletLifecycleOverlayPresenter.shared.setLockScreenVisible(visible)
    }

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
    /// A refused or failed card action: the action as title, the reason as
    /// message.
    struct ActionFailure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published private(set) var phase: WalletLifecycleTransitionState.Phase
    @Published private(set) var preparationFailure: WalletPreparationFailure?
    @Published var supportFailure: WalletPreparationFailure?
    @Published private(set) var retryPending = false
    @Published private(set) var isExportingLogs = false
    @Published var exportedLogsURL: URL?
    /// One alert for every gated action's refusal: no PIN on record,
    /// authentication failed, export or reset error.
    @Published var actionFailure: ActionFailure?
    /// Reset is offered only for a database failure with an SDK wallet still
    /// in the keychain. Captured on each phase change: `hasSDKWallet` is a
    /// keychain read, not something to evaluate per body render.
    @Published private(set) var canResetWalletData = false
    @Published var isConfirmingReset = false
    @Published private(set) var resetPending = false
    /// True while the overlay window is hidden behind the PIN prompt.
    @Published private(set) var isAuthenticating = false

    /// One operation at a time on a failure card: the share sheet, the PIN
    /// prompt, Try Again and Reset each own the window's presentation stack.
    var isBusy: Bool { retryPending || resetPending || isExportingLogs || isAuthenticating }

    /// The Security menu's recovery-phrase flow with this overlay's PIN gate
    /// injected.
    private(set) lazy var recoveryPhraseFlow = RecoveryPhraseFlowViewModel(authenticate: { [weak self] in
        await self?.authenticateBehindOverlay(biometric: false) ?? .cancelled
    })
    private let recoveryPhraseModal = RecoveryPhraseModalPresenter()
    private var cancellables = Set<AnyCancellable>()

    init() {
        let transitionState = WalletLifecycleTransitionState.shared
        phase = transitionState.phase
        preparationFailure = transitionState.preparationFailure
        apply(transitionState.phase)
        transitionState.$phase
            .sink { [weak self] phase in self?.apply(phase) }
            .store(in: &cancellables)
        transitionState.$preparationFailure
            .sink { [weak self] failure in
                self?.preparationFailure = failure
                self?.updateRecoveryEligibility()
            }
            .store(in: &cancellables)
        recoveryPhraseFlow.$navigationEvent
            .compactMap { $0 }
            .sink { [weak self] event in self?.presentRecoveryPhrase(event) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                // The phrase screen pops itself on resign, which as a modal
                // root has nothing to pop from; the host takes the modal down.
                self?.recoveryPhraseModal.dismiss(animated: false)
            }
            .store(in: &cancellables)
    }

    var showsLocalStoreRecovery: Bool {
        switch phase {
        case .failedWalletOpen: return true
        case .failedNetworkSwitch: return preparationFailure != nil
        default: return false
        }
    }

    private func updateRecoveryEligibility() {
        let failure: WalletPreparationFailure?
        if case let .failedWalletOpen(detail) = phase { failure = detail }
        else { failure = preparationFailure }
        canResetWalletData = showsLocalStoreRecovery
            && failure?.canResetLocalData == true && WalletEnvironment.hasSDKWallet
    }

    private func apply(_ phase: WalletLifecycleTransitionState.Phase) {
        self.phase = phase
        updateRecoveryEligibility()
        if !showsLocalStoreRecovery {
            isConfirmingReset = false
            recoveryPhraseModal.dismiss(animated: false)
        }
    }

    /// The overlay's PIN gate. The prompt anchors on a `.normal`-level
    /// window, below this overlay, so the window hides for the prompt's
    /// duration and the card's actions stay disabled meanwhile.
    private func authenticateBehindOverlay(biometric: Bool) async -> AuthenticationGate.Outcome {
        isAuthenticating = true
        WalletLifecycleOverlayPresenter.shared.setAuthenticationPromptVisible(true)
        let outcome = await AuthenticationGate.authenticate(biometric: biometric)
        WalletLifecycleOverlayPresenter.shared.setAuthenticationPromptVisible(false)
        isAuthenticating = false
        return outcome
    }

    /// Fails closed when no PIN is on record: `AuthenticationService` would
    /// otherwise pass without a prompt.
    private func requirePin(for actionTitle: String, message: String) -> Bool {
        guard AuthenticationService.shared.hasPin() else {
            actionFailure = ActionFailure(title: actionTitle, message: message)
            return false
        }
        return true
    }

    func retryWalletOpen() {
        guard !isBusy else { return }
        retryPending = true
        // A Core-only Restart requires an already-open wallet and cannot
        // recover a database failure. Re-enter the complete serialized start.
        Task {
            await SwiftDashSDKWalletRuntime.shared.retryWalletPreparation()
            retryPending = false
        }
    }

    /// `authenticated` is the migration card's mode: it shows before the
    /// lock screen (no SDK wallet yet, so `shouldShowLockScreen` is false),
    /// yet the archive carries the previous generation's wallet history. The
    /// upgrading user's PIN is read in place by `PinStore`, so it gates the
    /// export; with no PIN on record the export fails closed.
    func exportDiagnosticLogs(authenticated: Bool = false) {
        guard !isBusy else { return }
        let title = NSLocalizedString("Export Logs", comment: "Log export")
        if authenticated,
           !requirePin(for: title, message: NSLocalizedString(
               "Unlock with your wallet PIN to export logs.", comment: "Log export")) {
            return
        }
        isExportingLogs = true
        Task { [weak self] in
            guard let self else { return }
            if authenticated {
                let outcome = await self.authenticateBehindOverlay(biometric: true)
                guard outcome == .ok else {
                    self.isExportingLogs = false
                    if outcome != .cancelled {
                        self.actionFailure = ActionFailure(
                            title: title, message: NSLocalizedString("Authentication failed", comment: ""))
                    }
                    return
                }
            }
            let result = await DiagnosticLogExporter.exportArchive()
            self.isExportingLogs = false
            switch result {
            case .success(let url):
                self.exportedLogsURL = url
            case .failure(let error):
                self.actionFailure = ActionFailure(title: title, message: error.localizedDescription)
            }
        }
    }

    func showPreparationHelp() {
        supportFailure = preparationFailure
    }

    /// Backup recovery phrase on the wallet-open failure card: the Security
    /// menu's flow (PIN, then one phrase or a wallet picker), hosted modally
    /// in the overlay window because the card has no navigation stack.
    func backupRecoveryPhrase() {
        guard !isBusy,
              requirePin(
                  for: NSLocalizedString("Backup recovery phrase", comment: "Wallet preparation"),
                  message: NSLocalizedString("Unlock with your wallet PIN to continue.", comment: "Wallet preparation"))
        else { return }
        recoveryPhraseFlow.beginGlobal()
    }

    private func presentRecoveryPhrase(_ event: RecoveryPhraseFlowViewModel.NavigationEvent) {
        // @Published emits before the assignment; consume once it has
        // settled, as the Security menu and Wallets hosts do.
        defer {
            Task { @MainActor [recoveryPhraseFlow] in
                recoveryPhraseFlow.consumeNavigationEvent(id: event.id)
            }
        }
        guard showsLocalStoreRecovery,
              let anchor = WalletLifecycleOverlayPresenter.shared.overlayWindow?.rootViewController
        else { return }
        recoveryPhraseModal.show(event.destination, from: anchor, flowModel: recoveryPhraseFlow)
    }

    /// Reset starts with the confirmation alert; the PIN comes after Confirm,
    /// so a user who backs out never sees a prompt.
    func requestResetWalletData() {
        guard !isBusy, canResetWalletData else { return }
        isConfirmingReset = true
    }

    /// Confirm on the alert: PIN gate, then the runtime's delete-and-reopen.
    /// The runtime owns `.resettingLocalStores` until `.idle`
    /// or a failure card with the current diagnostic.
    func resetWalletData() {
        guard !isBusy, canResetWalletData else { return }
        let title = NSLocalizedString("Reset wallet data and rescan", comment: "Wallet preparation")
        guard requirePin(
            for: title,
            message: NSLocalizedString("Unlock with your wallet PIN to continue.", comment: "Wallet preparation"))
        else { return }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.authenticateBehindOverlay(biometric: false)
            guard outcome == .ok else {
                if outcome != .cancelled {
                    self.actionFailure = ActionFailure(
                        title: title, message: NSLocalizedString("Authentication failed", comment: ""))
                }
                return
            }
            self.resetPending = true
            do {
                let result = try await SwiftDashSDKWalletRuntime.shared.resetLocalStoresAndRetry()
                if case let .failed(failure) = result {
                    self.actionFailure = ActionFailure(title: title, message: failure.message)
                }
            } catch {
                // Deletion stopped at an item; nothing was reopened and the
                // card is unchanged, so Reset and Try Again stay available.
                self.actionFailure = ActionFailure(
                    title: title,
                    message: NSLocalizedString(
                        "The wallet data on this device could not be reset. Try again or contact support for help.",
                        comment: "Wallet preparation"))
            }
            self.resetPending = false
        }
    }

    /// Try Again on the legacy-migration failure card: the launch hold
    /// re-runs the key migrator and keeps waiting. The card's phase change
    /// (back to progress) is the visible acknowledgement.
    func retryLegacyMigration() {
        // A successful retry releases the hold and drops this window, and
        // with it an export's share sheet or error alert.
        guard !isExportingLogs else { return }
        LegacyWalletMigrationLaunchCoordinator.shared.retry()
    }

    /// A failed switch can carry a preparation failure, so its card offers
    /// Export Logs next to Retry/Switch Back. The export's share sheet and
    /// error alert belong to that card; a switch started meanwhile would swap
    /// the card underneath them. Retry/Switch Back are disabled while an
    /// export runs, and these guards back the disabled state up.
    func retryNetworkSwitch(to target: WalletEnvironment.NetworkKind) {
        guard !isBusy else { return }
        Task {
            try? await SwiftDashSDKWalletRuntime.shared.switchNetwork(to: target)
        }
    }

    /// Retry of a failed wallet switch — the same gated helper every
    /// interactive wallet switch uses (admission from `.failedWalletSwitch`
    /// exists exactly for this card's actions).
    func retryWalletSwitch(to targetId: Data, targetName: String?) {
        guard !isExportingLogs else { return }
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
        guard !isExportingLogs else { return }
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
            case .resettingLocalStores:
                progressCard(
                    title: NSLocalizedString("Resetting wallet data…", comment: "Wallet preparation"),
                    subtitle: NSLocalizedString("Please keep the app open.", comment: "Wallet preparation"))
            case .openingWallet, .migratingLegacyWallet:
                progressCard(
                    title: NSLocalizedString("Preparing your wallet…", comment: "Wallet preparation"),
                    subtitle: NSLocalizedString("Please keep the app open.", comment: "Wallet preparation"))
            case let .failedWalletOpen(failure):
                card {
                    failureHeader(title: failure.title, message: failure.message)
                    actionButton(NSLocalizedString("Try Again", comment: ""), prominent: true) {
                        viewModel.retryWalletOpen()
                    }
                    .disabled(viewModel.isBusy)
                    walletRecoveryActions
                    preparationHelp
                }
            case let .failedLegacyMigration(failure):
                // No Create/Recover here: the wallet is still in the keychain.
                card {
                    failureHeader(title: failure.title, message: failure.message)
                    actionButton(NSLocalizedString("Try Again", comment: ""), prominent: true) {
                        viewModel.retryLegacyMigration()
                    }
                    .disabled(viewModel.isExportingLogs)
                    preparationHelp(authenticatedExport: true)
                }
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
            case let .failedNetworkSwitch(from, target, message):
                card {
                    preparationFailureHeader(
                        title: String(
                            format: NSLocalizedString("Switching to %@ failed", comment: "Network switch overlay"),
                            Self.displayName(of: target)),
                        message: message)
                    actionButton(NSLocalizedString("Retry", comment: ""), prominent: true) {
                        viewModel.retryNetworkSwitch(to: target)
                    }
                    .disabled(viewModel.isBusy)
                    // Escape hatch: the origin network was working when the
                    // switch began, so a way back must exist even when the
                    // destination keeps failing.
                    if from != target {
                        actionButton(NSLocalizedString("Switch Back", comment: "Wallets"), prominent: false) {
                            viewModel.retryNetworkSwitch(to: from)
                        }
                        .disabled(viewModel.isBusy)
                    }
                    if viewModel.showsLocalStoreRecovery { walletRecoveryActions }
                    preparationHelp
                }
            case let .failedWalletSwitch(targetId, targetName, previousId, message):
                card {
                    preparationFailureHeader(
                        title: NSLocalizedString("Switching wallet failed", comment: "Wallets"),
                        message: message)
                    actionButton(NSLocalizedString("Retry", comment: ""), prominent: true) {
                        viewModel.retryWalletSwitch(to: targetId, targetName: targetName)
                    }
                    .disabled(viewModel.isExportingLogs)
                    if let previousId {
                        actionButton(NSLocalizedString("Switch Back", comment: "Wallets"), prominent: false) {
                            viewModel.switchBack(to: previousId)
                        }
                        .disabled(viewModel.isExportingLogs)
                    }
                    preparationHelp
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
        .sheet(item: $viewModel.supportFailure) { failure in
            WalletPreparationSupportView(failure: failure)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.exportedLogsURL != nil },
            set: { if !$0 { viewModel.exportedLogsURL = nil } }
        )) {
            if let url = viewModel.exportedLogsURL {
                ActivityView(activityItems: [url])
            }
        }
        .alert(viewModel.actionFailure?.title ?? "", isPresented: Binding(
            get: { viewModel.actionFailure != nil },
            set: { if !$0 { viewModel.actionFailure = nil } }
        )) {
            Button(NSLocalizedString("OK", comment: "")) { viewModel.actionFailure = nil }
        } message: {
            Text(viewModel.actionFailure?.message ?? "")
        }
        .alert(
            NSLocalizedString("Reset wallet data and rescan?", comment: "Wallet preparation"),
            isPresented: $viewModel.isConfirmingReset
        ) {
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Reset and Rescan", comment: "Wallet preparation"), role: .destructive) {
                viewModel.resetWalletData()
            }
        } message: {
            Text(NSLocalizedString(
                "Resets local wallet data for every network. Your wallet keys stay on this device, and a full rescan restores your funds and transaction history. Custom wallet names and manually tracked masternodes and their labels must be recreated; a recovery phrase backup does not preserve them. The rescan can take a while.",
                comment: "Wallet preparation"))
        }
        .recoveryPhraseFlowAlert(viewModel.recoveryPhraseFlow)
    }

    @ViewBuilder
    private var walletRecoveryActions: some View {
        actionButton(NSLocalizedString("Backup recovery phrase", comment: "Wallet preparation"), prominent: false) {
            viewModel.backupRecoveryPhrase()
        }
        .disabled(viewModel.isBusy)
        if viewModel.canResetWalletData {
            actionButton(
                NSLocalizedString("Reset wallet data and rescan", comment: "Wallet preparation"),
                prominent: false, role: .destructive
            ) {
                viewModel.requestResetWalletData()
            }
            .disabled(viewModel.isBusy)
        }
    }

    private var preparationHelp: some View {
        preparationHelp(authenticatedExport: false)
    }

    /// `authenticatedExport`: the card shows before the lock screen, so
    /// Export Logs authenticates first (see `exportDiagnosticLogs`).
    @ViewBuilder
    private func preparationHelp(authenticatedExport: Bool) -> some View {
        if viewModel.preparationFailure != nil {
            if viewModel.isExportingLogs {
                SwiftUI.ProgressView(NSLocalizedString("Preparing logs…", comment: "Log export progress"))
            } else {
                actionButton(NSLocalizedString("Export Logs", comment: "Log export"), prominent: false) {
                    viewModel.exportDiagnosticLogs(authenticated: authenticatedExport)
                }
                .disabled(viewModel.isBusy)
            }
            actionButton(NSLocalizedString("Help", comment: ""), prominent: false) {
                viewModel.showPreparationHelp()
            }
            .disabled(viewModel.isBusy)
        }
    }

    @ViewBuilder
    private func preparationFailureHeader(title: String, message: String?) -> some View {
        if let failure = viewModel.preparationFailure {
            failureHeader(title: failure.title, message: failure.message)
        } else {
            failureHeader(title: title, message: message)
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
            .accessibilityHidden(true)
        Text(title)
            .font(.headline)
            .multilineTextAlignment(.center)
        if let message, !message.isEmpty {
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// `role: .destructive` renders red under `.bordered`; no tint needed.
    private func actionButton(
        _ title: String,
        prominent: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        let button = Button(role: role, action: action) { label }
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
        let contents = VStack(spacing: 16) { content() }
        GeometryReader { viewport in
            ScrollView {
                contents
                    .padding(24)
                    .frame(maxWidth: 320)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .padding(32)
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private static func displayName(of kind: WalletEnvironment.NetworkKind) -> String {
        switch kind {
        case .mainnet: return "Mainnet"
        case .testnet: return "Testnet"
        case .devnet: return "Devnet"
        }
    }
}
