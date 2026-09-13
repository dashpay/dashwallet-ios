import Combine
import Foundation

/// Availability describes a local read, not freshness against the chain tip.
public enum PlatformBalanceState: Equatable, Sendable {
    case unavailable
    case available(UInt64)

    public var credits: UInt64? {
        guard case .available(let credits) = self else { return nil }
        return credits
    }
}

/// Keeps the selected wallet's display snapshot across sync/manager retries.
/// Session tokens also fence Combine deliveries queued before a stop or switch.
@MainActor
final class PlatformBalanceController: ObservableObject {
    struct Scope: Equatable {
        let walletId: Data
        let network: String
    }

    struct Session: Equatable {
        let scope: Scope
        fileprivate let owner: ObjectIdentifier
        fileprivate let generation: UInt64
    }

    @Published private(set) var state: PlatformBalanceState = .unavailable
    private var scope: Scope?
    private var session: Session?
    private var generation: UInt64 = 0

    func begin(scope nextScope: Scope, owner: ObjectIdentifier) -> Session {
        if let session, session.scope == nextScope, session.owner == owner {
            return session
        }
        detach()
        if scope != nextScope { state = .unavailable }
        scope = nextScope
        let next = Session(scope: nextScope, owner: owner, generation: generation)
        session = next
        return next
    }

    func isCurrent(_ candidate: Session) -> Bool {
        session == candidate
    }

    /// A failed fetch never replaces a known amount with zero. `nil` is a
    /// successful lookup proving the wallet/account is not locally available.
    @discardableResult
    func read(using candidate: Session, load: () throws -> UInt64?) rethrows -> Bool {
        guard isCurrent(candidate) else { return false }
        let credits = try load()
        guard isCurrent(candidate) else { return false }
        state = credits.map(PlatformBalanceState.available) ?? .unavailable
        return true
    }

    func detach() {
        generation &+= 1
        session = nil
    }

    func clear() {
        detach()
        scope = nil
        state = .unavailable
    }
}
