//
//  WalletLifecycleTransitionState.swift
//  DashWallet
//

import Combine
import Foundation

/// Central published state of an interactive wallet-lifecycle operation —
/// a network switch, a runtime wallet switch, or a per-wallet removal. Two
/// explicit roles, and deliberately nothing more:
///
/// 1. **Presentation**: `phase` drives the app-wide blocking overlay
///    (`WalletLifecycleOverlayPresenter`), hosted in its own UIWindow so it
///    survives the root/tab rebuilds these operations trigger.
/// 2. **Admission gate for INTERACTIVE operations**: `tryBegin` is an atomic
///    MainActor check-and-set — every interactive entry point calls it
///    synchronously (no suspension between check and set), so at most one
///    interactive operation is admitted at a time.
///
/// What this type does NOT do: it does not serialize execution — the
/// runtime's `SerialAsyncLifecycleQueue` and the wiper's
/// `WalletWipeSerialExecutor` own that — and non-interactive network writers
/// (reinstall recovery, sole-network selection) bypass it entirely, matching
/// their pre-existing silent behavior.
@MainActor
final class WalletLifecycleTransitionState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case switchingNetwork(from: WalletEnvironment.NetworkKind, to: WalletEnvironment.NetworkKind)
        /// The network switch failed after the old runtime was already torn
        /// down — the app may have no working manager, so the overlay stays
        /// up, blocking, offering Retry toward `target`.
        case failedNetworkSwitch(from: WalletEnvironment.NetworkKind, target: WalletEnvironment.NetworkKind, message: String?)
        /// Runtime wallet switch in flight (same network: stop → rebind →
        /// start). `targetName` is display-only.
        case switchingWallet(targetName: String?)
        /// Per-wallet removal in flight (`deleteLogicalWallet`).
        case removingWallet
        /// The wallet switch failed. The previous wallet is NOT guaranteed
        /// active afterwards (the registry is repointed before the rebuild
        /// and the host may have bound a fallback wallet), so the card
        /// blocks, offering Retry toward `targetId` and Switch Back toward
        /// `previousId`.
        case failedWalletSwitch(targetId: Data, targetName: String?, previousId: Data?, message: String?)
        /// A removal failed with the runtime alive — dismissable (OK → idle);
        /// the wiper leaves wallet state retryable by design.
        case failedWalletRemoval(message: String?)
        /// A full wallet wipe in flight — until the wiper's barrier reports
        /// data deleted AND runtime torn down. Owned by the Obj-C wipe flows
        /// (`DWAppRootViewController` Delete All, `DWRecoverViewController`
        /// phrase-authorized wipe) through `WalletLifecycleOverlayBridge`;
        /// `title` is the flow's progress copy ("Deleting All Wallets…" /
        /// "Deleting Wallet…"). Failure alerts stay UIKit (shown after
        /// `finish()`), so there is no failed-wipe phase.
        case wiping(title: String?)

        /// Compact form for gate/telemetry log lines (no wallet ids beyond
        /// what the operation logs themselves already include).
        var logLabel: String {
            switch self {
            case .idle: return "idle"
            case .switchingNetwork(_, let to): return "switchingNetwork(\(to))"
            case .failedNetworkSwitch(_, let target, _): return "failedNetworkSwitch(\(target))"
            case .switchingWallet: return "switchingWallet"
            case .removingWallet: return "removingWallet"
            case .failedWalletSwitch: return "failedWalletSwitch"
            case .failedWalletRemoval: return "failedWalletRemoval"
            case .wiping: return "wiping"
            }
        }
    }

    static let shared = WalletLifecycleTransitionState()

    @Published private(set) var phase: Phase = .idle

    /// Internal (not private) so the admission-matrix table test can build
    /// fresh instances; production code uses only `shared`.
    init() {}

    /// Atomically admit `next` as the active operation. Admission rules: any
    /// operation may begin from `.idle`; a network switch may also begin from
    /// `.failedNetworkSwitch` (the failure card's Retry / Switch Back); a
    /// wallet switch may also begin from `.failedWalletSwitch` (Retry /
    /// Switch Back); a wipe may begin from ANY failure phase, keeping the
    /// reset route as the universal escape hatch. Every other combination is
    /// rejected and the caller surfaces or logs it.
    func tryBegin(_ next: Phase) -> Bool {
        switch (phase, next) {
        case (.idle, .switchingNetwork),
             (.idle, .switchingWallet),
             (.idle, .removingWallet),
             (.idle, .wiping),
             (.failedNetworkSwitch, .switchingNetwork),
             (.failedWalletSwitch, .switchingWallet),
             // The wipe/reset route stays reachable from EVERY failure card:
             // without this, a persistently failing switch (destination
             // network down) would block the whole app behind the overlay
             // with reinstalling as the only exit.
             (.failedNetworkSwitch, .wiping),
             (.failedWalletSwitch, .wiping),
             (.failedWalletRemoval, .wiping):
            phase = next
            return true
        default:
            DWLogger.log("🚦 LIFECYCLE tryBegin rejected: phase=\(phase.logLabel) next=\(next.logLabel)")
            return false
        }
    }

    /// Move a busy operation to its next in-flight phase (wallet switch →
    /// removal) WITHOUT passing through `.idle`, so the overlay window never
    /// flickers down mid-operation.
    func advance(to next: Phase) {
        guard phase != .idle else {
            // Never legal — but in Release a bare assert would present an
            // overlay phase with no owner left to clear it, so reject
            // instead. The caller's operation continues without the window.
            DWLogger.log("🚦 LIFECYCLE advance rejected from idle: next=\(next.logLabel)")
            assertionFailure("advance(to:) requires an operation in flight")
            return
        }
        phase = next
    }

    func finish() {
        phase = .idle
    }

    func fail(_ failure: Phase) {
        phase = failure
    }
}
