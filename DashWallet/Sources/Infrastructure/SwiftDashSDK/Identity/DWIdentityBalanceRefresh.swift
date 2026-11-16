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

    /// The read was skipped or its answer dropped: the wallet, network or
    /// identity it was for is no longer current, or the task was cancelled.
    struct Superseded: Error {}

    /// Returns the balance read from the network, or why there is none — never
    /// the stored balance and never zero in place of a failed read.
    @discardableResult
    static func run(
        isCurrent: () -> Bool,
        previousBalance: () -> UInt64? = { nil },
        refresh: () async throws -> UInt64,
        publish: (UInt64) -> Void,
        onFailure: (Error) -> Void
    ) async -> Result<UInt64, Error> {
        guard !Task.isCancelled, isCurrent() else { return .failure(Superseded()) }
        let previous = previousBalance()
        do {
            let balance = try await refresh()
            guard !Task.isCancelled, isCurrent() else { return .failure(Superseded()) }
            // Still perform the SDK read and persistence flush when unchanged.
            if previous != balance {
                publish(balance)
            }
            return .success(balance)
        } catch {
            // A failed read must not turn a confirmed DPNS registration into
            // a failure or replace the last known balance with zero.
            onFailure(error)
            return .failure(error)
        }
    }
}
