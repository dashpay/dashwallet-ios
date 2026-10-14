//
//  ShieldedProverWarmup.swift
//  DashWallet
//
//  Builds the Orchard (Halo 2) proving key before the first shielded proof
//  of the session. The SDK caches the key in a process-global `OnceLock`
//  and builds it inline on first use, so without a warm-up the first send,
//  unshield, withdrawal or shield of every launch pays the key build before
//  its proof even starts.
//
//  The SDK seam lives in `ShieldedProverWarmup+SwiftDashSDK.swift`; this file
//  holds the policy and the warm-up state and has no SDK or UIKit
//  dependency, so it runs under `scripts/test_shielded_state.py`.
//

import Foundation
import OSLog

/// Why a warm-up was requested.
enum ShieldedProverWarmupTrigger: String {
    /// The selected wallet holds spendable shielded funds. Speculative: the
    /// user may not spend them this session.
    case shieldedBalance = "shielded-balance"
    /// A send or transfer screen selected a route that builds an Orchard
    /// proof.
    case shieldedRoute = "shielded-route"
    /// A proving operation was confirmed and is about to run.
    case confirmedOperation = "confirmed-operation"

    /// Speculative triggers are deferred under low power or in the
    /// background. The others reflect a proof the user asked for, which
    /// would pay the same build inline anyway.
    var isSpeculative: Bool { self == .shieldedBalance }
}

struct ShieldedProverWarmupConditions {
    var isLowPowerModeEnabled: Bool
    var isInForeground: Bool
}

enum ShieldedProverWarmupPolicy {
    /// Only a positive spendable balance justifies a speculative build; an
    /// unknown or empty pool waits until a shielded route is chosen.
    static func holdsSpendableShieldedFunds(_ state: ShieldedBalanceState) -> Bool {
        (state.credits ?? 0) > 0
    }

    static func shouldStart(
        _ trigger: ShieldedProverWarmupTrigger,
        conditions: ShieldedProverWarmupConditions
    ) -> Bool {
        guard trigger.isSpeculative else { return true }
        return conditions.isInForeground && !conditions.isLowPowerModeEnabled
    }
}

/// The proving-key cache behind the warm-up.
@MainActor
protocol ShieldedProverBackend {
    /// Whether the proving key is already cached. Must be cheap: it is read
    /// on the main actor at every request and every confirmed proof.
    var isReady: Bool { get }
    /// Starts the key build off the main thread and returns once the key is
    /// cached (`true`) or the backend gave up waiting (`false`).
    func prepare() async -> Bool
}

/// Idempotent, process-wide warm-up of the Orchard proving key, plus the
/// per-operation timing that shows whether a confirmed proof had to wait
/// for it.
@MainActor
final class ShieldedProverWarmup {
    private enum Status {
        case idle
        case preparing
        case ready
    }

    private let backend: ShieldedProverBackend
    private let conditions: () -> ShieldedProverWarmupConditions
    let log: (String) -> Void
    let now: () -> Date

    private var status: Status = .idle
    private var hasLoggedDeferral = false
    /// When the warm-up observed the key as cached. `nil` when the key was
    /// already cached at the first request, or no warm-up has succeeded.
    private(set) var readyAt: Date?

    static let signposter = OSSignposter(subsystem: "org.dashfoundation.dash", category: "shielded-prover")

    init(
        backend: ShieldedProverBackend,
        conditions: @escaping () -> ShieldedProverWarmupConditions,
        now: @escaping () -> Date = Date.init,
        log: @escaping (String) -> Void
    ) {
        self.backend = backend
        self.conditions = conditions
        self.now = now
        self.log = log
    }

    var isReady: Bool { status == .ready || backend.isReady }

    /// Starts the key build unless it is cached, already building, or the
    /// policy defers this trigger. Cheap to call repeatedly. A deferred
    /// speculative request is retried by the next published shielded balance
    /// (each completed sync pass that is not skipped publishes one).
    func request(_ trigger: ShieldedProverWarmupTrigger) {
        guard status == .idle else { return }
        if backend.isReady {
            status = .ready
            return
        }
        let current = conditions()
        guard ShieldedProverWarmupPolicy.shouldStart(trigger, conditions: current) else {
            if !hasLoggedDeferral {
                hasLoggedDeferral = true
                log("SHIELDED-PROVER warm-up deferred trigger=\(trigger.rawValue) "
                    + "low_power=\(current.isLowPowerModeEnabled) foreground=\(current.isInForeground)")
            }
            return
        }

        status = .preparing
        let startedAt = now()
        let interval = Self.signposter.beginInterval("WarmUp")
        log("SHIELDED-PROVER warm-up start trigger=\(trigger.rawValue)")
        Task { [weak self, backend] in
            let ready = await backend.prepare()
            Self.signposter.endInterval("WarmUp", interval)
            self?.finishPreparing(ready: ready, startedAt: startedAt)
        }
    }

    private func finishPreparing(ready: Bool, startedAt: Date) {
        let finishedAt = now()
        let milliseconds = Self.milliseconds(from: startedAt, to: finishedAt)
        if ready {
            status = .ready
            readyAt = finishedAt
            log("SHIELDED-PROVER warm-up ready duration_ms=\(milliseconds)")
        } else {
            // Leave the next request free to try again.
            status = .idle
            log("SHIELDED-PROVER warm-up gave up duration_ms=\(milliseconds)")
        }
    }

    /// Call when the user confirms an operation that builds an Orchard proof.
    /// Starts the warm-up if nothing has yet, so authorization and any
    /// pre-proof network work overlap the key build.
    func beginProofOperation(_ operation: ShieldedProofOperation) -> ShieldedProofTiming {
        let readyAtConfirm = isReady
        request(.confirmedOperation)
        return ShieldedProofTiming(
            operation: operation,
            warmup: self,
            confirmedAt: now(),
            readyAtConfirm: readyAtConfirm)
    }

    static func milliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }
}

enum ShieldedProofOperation: String {
    case coreToShielded = "core-to-shielded"
    case resumeCoreToShielded = "resume-core-to-shielded"
    case platformToShielded = "platform-to-shielded"
    case shieldedToCore = "shielded-to-core"
    case shieldedToPlatform = "shielded-to-platform"
    case shieldedToShielded = "shielded-to-shielded"
    case shieldedToIdentity = "shielded-to-identity"
    case identityFromShieldedPool = "identity-from-shielded-pool"
}

/// One confirmed proving operation. `measure` logs a single line when the
/// SDK call returns, so before/after builds can be compared from the shared
/// app log.
@MainActor
struct ShieldedProofTiming {
    let operation: ShieldedProofOperation
    let warmup: ShieldedProverWarmup
    let confirmedAt: Date
    let readyAtConfirm: Bool

    /// Runs the SDK call that builds the proof and logs whether it had to wait
    /// for the proving key. Errors pass through unchanged.
    func measure<T>(_ call: () async throws -> T) async rethrows -> T {
        let callStartedAt = warmup.now()
        let readyAtCall = warmup.isReady
        let interval = ShieldedProverWarmup.signposter.beginInterval("ProofCall")
        var succeeded = false
        defer {
            ShieldedProverWarmup.signposter.endInterval("ProofCall", interval)
            let readyAfterCall = Self.readyAfterCallDescription(
                readyAtCall: readyAtCall, callStartedAt: callStartedAt, readyAt: warmup.readyAt)
            warmup.log("SHIELDED-PROVER op=\(operation.rawValue)"
                + " ready_at_confirm=\(readyAtConfirm)"
                + " ready_at_call=\(readyAtCall)"
                + " ready_after_call_ms=\(readyAfterCall)"
                + " confirm_to_call_ms=\(ShieldedProverWarmup.milliseconds(from: confirmedAt, to: callStartedAt))"
                + " call_ms=\(ShieldedProverWarmup.milliseconds(from: callStartedAt, to: warmup.now()))"
                + " succeeded=\(succeeded)")
        }
        let value = try await call()
        succeeded = true
        return value
    }

    /// How long after the SDK call started the warm-up saw the key cached: an
    /// upper bound on how long the proof waited for the key build, late by up
    /// to one readiness poll. For the Core → Shielded routes the call also
    /// covers the asset lock, so this overlaps lock confirmation rather than
    /// measuring a wait. `0` when the key was cached already; `unknown` when
    /// no warm-up observed it.
    private static func readyAfterCallDescription(readyAtCall: Bool, callStartedAt: Date, readyAt: Date?) -> String {
        if readyAtCall { return "0" }
        guard let readyAt else { return "unknown" }
        return String(ShieldedProverWarmup.milliseconds(from: callStartedAt, to: readyAt))
    }
}
