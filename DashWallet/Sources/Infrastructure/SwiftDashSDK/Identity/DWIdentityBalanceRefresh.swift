import Foundation

/// Best-effort read after a successful spend, also used when opening a profile.
/// The SDK refresh must update both managed state and persistence before publish.
@MainActor
enum IdentityBalanceRefresh {
    struct Context: Hashable {
        let network: String
        let walletId: Data
        let identityId: Data
    }

    static func run(
        isCurrent: () -> Bool,
        previousBalance: () -> UInt64? = { nil },
        refresh: () async throws -> UInt64,
        publish: (UInt64) -> Void,
        onFailure: (Error) -> Void
    ) async {
        guard !Task.isCancelled, isCurrent() else { return }
        let previous = previousBalance()
        do {
            let balance = try await refresh()
            guard !Task.isCancelled, isCurrent() else { return }
            // Still perform the SDK read and persistence flush when unchanged.
            guard previous != balance else { return }
            publish(balance)
        } catch {
            // A failed read must not turn a confirmed DPNS registration into
            // a failure or replace the last known balance with zero.
            onFailure(error)
        }
    }
}
