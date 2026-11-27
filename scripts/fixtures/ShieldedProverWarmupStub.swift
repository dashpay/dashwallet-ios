import Foundation

// The harnesses compile the real ShieldedProverWarmup.swift, whose proof
// timing is diagnostic here: the proving key is always cached.
struct ShieldedBalanceState { let credits: UInt64? }

private struct CachedProverBackend: ShieldedProverBackend {
    var isReady: Bool { true }
    func prepare() async -> Bool { true }
}

extension ShieldedProverWarmup {
    static let shared = ShieldedProverWarmup(
        backend: CachedProverBackend(),
        conditions: { ShieldedProverWarmupConditions(isLowPowerModeEnabled: false, isInForeground: true) },
        log: { _ in })
}
