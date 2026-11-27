import Foundation
import SwiftDashSDK

/// Posted once after a top-up of an identity from this wallet completes, with
/// the balance its transition returned and the credits it was handed
/// (ADR-0034): by `IdentityTopUpViewModel.topUp`, by
/// `DWIdentityRegistrationCoordinator` for the top-ups it makes before a
/// registration or a name purchase, and by `AssetLockRecoveryService` for a
/// top-up retried from its asset lock. Always posted on the main actor.
struct IdentityTopUpDidComplete: Equatable {
    static let name = Notification.Name("IdentityTopUpDidComplete")

    let walletId: Data
    let network: Network
    let identityId: Data
    /// The identity's balance the top-up's transition returned.
    let balanceAfter: UInt64
    /// The credits handed to the transition, the most it can have added.
    let suppliedCredits: UInt64

    init(walletId: Data, network: Network, identityId: Data, balanceAfter: UInt64, suppliedCredits: UInt64) {
        self.walletId = walletId
        self.network = network
        self.identityId = identityId
        self.balanceAfter = balanceAfter
        self.suppliedCredits = suppliedCredits
    }

    init?(notification: Notification) {
        guard notification.name == Self.name, let event = notification.object as? Self else { return nil }
        self = event
    }

    @MainActor
    func post(to center: NotificationCenter = .default) {
        center.post(name: Self.name, object: self)
    }

    /// Posts the event for a completed top-up (`balanceAfter` non-nil) and
    /// nothing for a cancelled or failed one.
    @MainActor
    static func announce(
        balanceAfter: UInt64?,
        suppliedCredits: UInt64,
        walletId: Data,
        network: Network,
        identityId: Data,
        center: NotificationCenter = .default
    ) {
        guard let balanceAfter else { return }
        IdentityTopUpDidComplete(
            walletId: walletId, network: network, identityId: identityId,
            balanceAfter: balanceAfter, suppliedCredits: suppliedCredits)
            .post(to: center)
    }

    /// Runs `topUp`, which returns the identity's balance after it, and
    /// announces it when it returns; a top-up that throws announces nothing.
    /// The top-up is in `inFlight` from before `topUp` runs until after the
    /// event is posted or `topUp` throws.
    @MainActor
    static func announcing(
        walletId: Data,
        network: Network,
        identityId: Data,
        suppliedCredits: UInt64,
        center: NotificationCenter = .default,
        inFlight: IdentityTopUpsInFlight = .shared,
        _ topUp: () async throws -> UInt64
    ) async rethrows -> UInt64 {
        let key = IdentityTopUpsInFlight.Key(walletId: walletId, network: network, identityId: identityId)
        inFlight.begin(key)
        defer { inFlight.end(key) }
        let balanceAfter = try await topUp()
        announce(
            balanceAfter: balanceAfter, suppliedCredits: suppliedCredits,
            walletId: walletId, network: network, identityId: identityId, center: center)
        return balanceAfter
    }
}
