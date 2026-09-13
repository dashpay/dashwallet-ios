/// The home header uses available amounts independently of sync readiness.
struct HomeBalancePresentation {
    let transparentDuffs: UInt64
    let platformState: PlatformBalanceState
    let shieldedCredits: UInt64?
    let showsPlatformBalance: Bool

    var platformDuffs: UInt64? { platformState.credits.map { $0 / 1_000 } }
    var shieldedDuffs: UInt64? { shieldedCredits.map { $0 / 1_000 } }
    var showsBreakdown: Bool { showsPlatformBalance || shieldedDuffs != nil }
    var isPartial: Bool {
        shieldedDuffs == nil || (showsPlatformBalance && platformDuffs == nil)
    }
    var totalDuffs: UInt64 {
        transparentDuffs + (shieldedDuffs ?? 0)
            + (showsPlatformBalance ? (platformDuffs ?? 0) : 0)
    }
}
