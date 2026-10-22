import Combine
import Foundation

// Only quote/network dependencies are substituted. Both forms' production
// compatibilityDidChange and routeDidChange methods are inserted unchanged.
@MainActor
class QuoteObservationEnvironment {
    enum Route { case coreToCore, platformToCore, platformToShielded }
    var route: Route? = .platformToCore
    var protocolCompatibility: WalletProtocolCompatibility?
    var isProtocolRuntimeReady = false
    var platformPreparation: SwiftDashSDKHost.PlatformPreparation?
    var subscription: AnyCancellable?
    var preflightTask: Task<Void, Never>?
    var shieldPreflightTask: Task<Void, Never>?
    var withdrawalPreflightTask: Task<Void, Never>?
    var withdrawalPreflight: Int?
    var withdrawalPreflightFailed = false
    var platformShieldCapacity: Int?
    var shieldPreflightFailed = false
    var shieldedSpendCeilingCredits: UInt64?
    var platformIdentityFundableDuffs: UInt64?
    var isIdentitySource = false
    var isIdentityDestination = false
    var quotedVersion: UInt32?
    var quoteRequests = 0

    func refreshWithdrawalPreflight() {
        quoteRequests += 1
        quotedVersion = platformPreparation?.version
    }
    func startWithdrawalPreflightIfNeeded() { refreshWithdrawalPreflight() }
    func clearShieldedMaxSelection() {}
    func clearMaxSelection() {}
    func refreshShieldedSpendCeiling() {}
    func refreshIdentityPlatformCeiling() {}
    func refreshShieldPreflight() {}
    func cancelPlatformShieldPreflight() {}
    func refreshPlatformShieldPreflight() {}
}

@MainActor
final class SendQuoteObservationHarness: QuoteObservationEnvironment {
    init(controller: WalletProtocolCompatibilityController) {
        super.init()
        subscription = controller.$snapshot.combineLatest(controller.$isRuntimeReady)
            .sink { [weak self] snapshot, ready in
                self?.compatibilityDidChange(snapshot, runtimeReady: ready)
            }
    }
    // SEND_METHODS
}

@MainActor
final class InternalQuoteObservationHarness: QuoteObservationEnvironment {
    init(controller: WalletProtocolCompatibilityController) {
        super.init()
        subscription = controller.$snapshot.combineLatest(controller.$isRuntimeReady)
            .sink { [weak self] snapshot, ready in
                self?.compatibilityDidChange(snapshot, runtimeReady: ready)
            }
    }
    // INTERNAL_METHODS
}
