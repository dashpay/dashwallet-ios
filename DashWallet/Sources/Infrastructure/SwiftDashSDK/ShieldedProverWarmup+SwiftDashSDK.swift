//
//  ShieldedProverWarmup+SwiftDashSDK.swift
//  DashWallet
//
//  Connects `ShieldedProverWarmup` to SwiftDashSDK's process-global Orchard
//  proving-key cache and to the app's power/foreground state.
//

import Foundation
import SwiftDashSDK
import UIKit

/// The SDK's warm-up entry point starts the key build on a Rust blocking
/// worker and returns immediately, so readiness is polled until the key is
/// cached. Concurrent proofs share the same `OnceLock`, so a proof that
/// starts mid-build waits for this build rather than starting a second one.
///
/// TODO(sdk-prepare-prover): when SwiftDashSDK exposes an awaitable prepare
/// call, `prepare()` becomes that single await and the polling goes away.
/// The SDK starts today's build from a `.background`-priority task, so a
/// proof confirmed mid-build may wait on a low-priority thread; the
/// awaitable call is where the build priority belongs.
struct SwiftDashSDKShieldedProverBackend: ShieldedProverBackend {
    private static let pollInterval: Duration = .milliseconds(250)
    /// Generous next to the SDK's documented ~30 s worst case; a give-up only
    /// means the next request retries.
    private static let timeout: Duration = .seconds(180)

    var isReady: Bool { PlatformWalletManager.isShieldedProverReady }

    func prepare() async -> Bool {
        await PlatformWalletManager.warmUpShieldedProver()
        let clock = ContinuousClock()
        let deadline = clock.now + Self.timeout
        while !isReady {
            guard clock.now < deadline else { return false }
            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch {
                return isReady
            }
        }
        return true
    }
}

extension ShieldedProverWarmup {
    /// One instance per process because the proving key it warms is cached
    /// once per process by the SDK. Tests construct their own instance with
    /// a fake `ShieldedProverBackend`.
    static let shared = ShieldedProverWarmup(
        backend: SwiftDashSDKShieldedProverBackend(),
        conditions: {
            ShieldedProverWarmupConditions(
                isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
                isInForeground: UIApplication.shared.applicationState != .background)
        },
        log: { DWLogger.log($0) })
}
