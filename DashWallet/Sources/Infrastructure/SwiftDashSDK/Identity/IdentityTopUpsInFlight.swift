import Foundation
import SwiftDashSDK

/// The own top-ups of each identity that are running now (ADR-0034).
///
/// Platform raises an identity's balance a little before the top-up call
/// returns and `IdentityTopUpDidComplete` is posted, so the Identity option's
/// watch asks this registry before it takes a rise for a payment.
/// `IdentityTopUpDidComplete.announcing` and `IdentityTopUpViewModel.topUp`
/// register every top-up they run, from before the SDK call until after the
/// event is posted or the call throws.
///
/// `shared` is process-wide on purpose: a top-up can start before the Receive
/// screen that watches its identity exists (the username flow closes while its
/// top-up still runs), so the record cannot belong to that screen. Tests inject
/// their own instance.
@MainActor
final class IdentityTopUpsInFlight {
    struct Key: Hashable {
        let walletId: Data
        let network: Network
        let identityId: Data
    }

    static let shared = IdentityTopUpsInFlight()

    private var counts: [Key: Int] = [:]

    func begin(_ key: Key) {
        counts[key, default: 0] += 1
    }

    func end(_ key: Key) {
        guard let count = counts[key] else { return }
        counts[key] = count > 1 ? count - 1 : nil
    }

    func contains(_ key: Key) -> Bool {
        counts[key] != nil
    }
}
