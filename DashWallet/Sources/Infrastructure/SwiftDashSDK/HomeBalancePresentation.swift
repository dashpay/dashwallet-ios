/// The home header uses available amounts independently of sync readiness.
struct HomeBalancePresentation {
    let transparentDuffs: UInt64?
    let platformState: PlatformBalanceState
    let shieldedCredits: UInt64?
    let showsPlatformBalance: Bool

    var platformDuffs: UInt64? { platformState.credits.map { $0 / 1_000 } }
    var shieldedDuffs: UInt64? { shieldedCredits.map { $0 / 1_000 } }
    var isPartial: Bool {
        transparentDuffs == nil || shieldedDuffs == nil
            || (showsPlatformBalance && platformDuffs == nil)
    }
    /// Wait for Core even if Platform or shielded restores first or survives
    /// a runtime restart. Their amounts cannot establish the transparent balance.
    /// Once Core is known, the total includes the other known, visible amounts.
    var totalDuffs: UInt64? {
        guard let transparentDuffs else { return nil }
        return transparentDuffs + (shieldedDuffs ?? 0)
            + (showsPlatformBalance ? (platformDuffs ?? 0) : 0)
    }
}
