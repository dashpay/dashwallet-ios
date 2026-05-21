//
//  DWRegistrationPhaseAdapter.swift
//  DashWallet
//
//  Pure mapping function bridging the SwiftDashSDK 5-phase identity
//  registration model onto the dashwallet 3-state UI enum
//  (DWDPRegistrationState_*).
//
//  Kept as a top-level enum with a static `map(...)` so it can be
//  exercised by unit tests without instantiating any of the wallet /
//  SDK machinery.
//

import Foundation

/// Adapter that collapses the SDK's 5 internal phases onto the existing
/// 3-state DashPay registration UI.
///
/// The SDK reports progress through two channels:
///   1. `DWIdentityRegistrationController.@Published phase` —
///      idle / preparingKeys / inFlight / completed / failed
///   2. `PersistentAssetLock.statusRaw` — 0=Built, 1=Broadcast,
///      2=InstantSendLocked, 3=ChainLocked, 4=Consumed
///
/// The existing UI expects `DWDPRegistrationState_ProcessingPayment`
/// (1/3) → `_CreatingID` (2/3) → `_RegistrationUsername` (3/3) →
/// `_Done` (100%). This adapter funnels the two-channel SDK signal
/// onto that single linear axis.
///
/// `failedAtPhase` is consulted on `.failed` so error messaging stays
/// accurate to where the failure occurred (asset-lock failure should
/// show "couldn't process payment", DPNS failure should show
/// "couldn't register username", etc.).
enum DWRegistrationPhaseAdapter {

    static func map(
        phase: DWIdentityRegistrationController.Phase,
        assetLockStatus: Int,
        failedAtPhase: DWDPRegistrationState? = nil
    ) -> DWDPRegistrationState {
        // NS_ENUM(NSUInteger, DWDPRegistrationState) imports into Swift
        // with the `DWDPRegistrationState_` prefix stripped and the
        // first letter lowercased per the Cocoa importer rules:
        //   DWDPRegistrationState_ProcessingPayment → .processingPayment
        //   DWDPRegistrationState_CreatingID        → .creatingID
        //   DWDPRegistrationState_RegistrationUsername → .registrationUsername
        //   DWDPRegistrationState_Done              → .done
        switch phase {
        case .idle, .preparingKeys:
            // Pre-FFI — keys are still being derived, no on-chain
            // activity yet. UI shows the first progress step.
            return .processingPayment

        case .inFlight:
            // Stage within `.inFlight` is read from the matching
            // `PersistentAssetLock.statusRaw` row.
            //   0 = Built      → asset-lock tx built, not broadcast
            //   1 = Broadcast  → broadcast, waiting for IS/CL
            //   2 = InstantSendLocked → IS proof received
            //   3 = ChainLocked       → CL proof received (fallback)
            //   4 = Consumed   → asset-lock used by IdentityCreate ST
            if assetLockStatus < 2 {
                return .processingPayment
            }
            if assetLockStatus < 4 {
                return .creatingID
            }
            return .registrationUsername

        case .completed:
            return .done

        case .failed:
            // Stamp the phase where the failure happened so the UI
            // can show the right error copy. Default to CreatingID
            // when the coordinator didn't record one (covers the
            // edge case of an unexpected pre-submit failure).
            return failedAtPhase ?? .creatingID
        }
    }
}
