//
//  DWIdentityRegistrationController.swift
//  DashWallet
//
//  Phase state holder for SwiftDashSDK-backed DashPay identity
//  registration. Inspired by the SwiftExampleApp reference impl at
//  /Users/bartoszrozwarski/Documents/Developer/platform/packages/swift-sdk/
//  SwiftExampleApp/SwiftExampleApp/Services/IdentityRegistrationController.swift
//
//  Differences from the upstream reference:
//   1. **Pure state holder, no Task spawning.** The upstream version
//      spawns a `Task { ... }` inside `submit(body:)` so it can be
//      called from synchronous SwiftUI code while the registration
//      survives view dismissal. The dashwallet coordinator
//      (`DWIdentityRegistrationCoordinator`) is itself an
//      app-scoped singleton with an `async` entry point, so the
//      Task-spawning indirection is redundant — the coordinator
//      drives `phase` transitions explicitly.
//   2. **No walletId / identityIndex storage.** v1 has one
//      registration at a time, with `identityIndex` pinned at 0;
//      the coordinator owns that context.
//

import Foundation

/// `@Published` phase state for a single identity + DPNS registration
/// attempt. Owned by `DWIdentityRegistrationCoordinator`; observed by
/// the Obj-C bridge so the existing `DWDPRegistrationStatusViewController`
/// progress UI can update on every transition.
@MainActor
final class DWIdentityRegistrationController: ObservableObject {

    /// Registration lifecycle. The transition graph driven by the
    /// coordinator is:
    ///
    ///   `.idle` → `.preparingKeys` → `.inFlight` →
    ///   `.completed(id)` | `.failed(message)`
    ///
    /// `.failed` is a re-entry point — the coordinator's `retry(_:)`
    /// path walks back through `.preparingKeys` → `.inFlight`.
    enum Phase: Equatable {
        /// Pre-submit. No FFI work has fired yet.
        case idle
        /// Identity public keys are being pre-derived and Keychain-
        /// persisted via `prePersistIdentityKeysForRegistration`.
        case preparingKeys
        /// The asset-lock + IdentityCreate + DPNS register chain is
        /// in flight. Sub-step is read from the matching
        /// `PersistentAssetLock.statusRaw` row by the coordinator
        /// and exposed via `@Published assetLockStatus`.
        case inFlight
        /// Terminal success. `identityId` is the 32-byte identifier.
        case completed(identityId: Data)
        /// Terminal failure. `message` is human-readable; the
        /// coordinator's `failedAtPhase` records which sub-step
        /// failed so the existing UI's 3 error copies stay accurate.
        case failed(String)

        /// True while the controller is holding the registration
        /// slot. Used by the coordinator to gate retries: `.idle`,
        /// `.completed`, and `.failed` are safe restart points.
        var isActive: Bool {
            switch self {
            case .preparingKeys, .inFlight:
                return true
            case .idle, .completed, .failed:
                return false
            }
        }
    }

    /// Current phase. Set by the coordinator's transition methods.
    @Published private(set) var phase: Phase = .idle

    init() {}

    // MARK: - Transitions (called by the coordinator)

    /// Move to `.preparingKeys` ahead of `prePersistIdentityKeysForRegistration`.
    /// No-op if the controller is already in a terminal-success state.
    func enterPreparingKeys() {
        guard case .completed = phase else {
            phase = .preparingKeys
            return
        }
    }

    /// Move to `.inFlight` ahead of the FFI registration chain.
    func enterInFlight() {
        phase = .inFlight
    }

    /// Move to terminal `.completed`. Carries the 32-byte identity id
    /// for downstream consumers (DWGlobalOptions mirror, the Obj-C
    /// bridge's completion callback).
    func enterCompleted(identityId: Data) {
        phase = .completed(identityId: identityId)
    }

    /// Move to terminal `.failed`. `message` is surfaced verbatim to
    /// the registration UI's error overlay.
    func enterFailed(_ message: String) {
        phase = .failed(message)
    }

    /// Reset to `.idle`. Used by the coordinator's `cancel()` path.
    /// Safe at any phase — cancel-during-inFlight stops phase updates
    /// from being observed, even if the FFI call is still racing to
    /// terminal in the background.
    func resetToIdle() {
        phase = .idle
    }
}
