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
    /// A partial total contains only known, visible amounts. Before any of
    /// those reads succeeds there is no total to display, even as zero.
    var totalDuffs: UInt64? {
        guard transparentDuffs != nil || shieldedDuffs != nil
            || (showsPlatformBalance && platformDuffs != nil) else { return nil }
        return (transparentDuffs ?? 0) + (shieldedDuffs ?? 0)
            + (showsPlatformBalance ? (platformDuffs ?? 0) : 0)
    }
}
