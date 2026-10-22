import Foundation

struct CoreShieldedDrainContext: Equatable { let wallet: Int }
struct CoreShieldedDrainOperation { let context: CoreShieldedDrainContext }
struct Outpoint { let txidWire = Data([1]); let vout: UInt32 = 2 }
struct WalletDrainOutcome {
    enum State { case pending, completed }
    let state: State
    let outpoint: Outpoint? = Outpoint()
}
@MainActor struct CoreShieldedDrainService {
    static var context = CoreShieldedDrainContext(wallet: 1)
    func status(for operation: CoreShieldedDrainOperation) async throws -> WalletDrainOutcome {
        WalletDrainOutcome(state: .pending)
    }
    func operationStatus(_ context: CoreShieldedDrainContext) async throws
        -> (operation: CoreShieldedDrainOperation, outcome: WalletDrainOutcome)? {
        (.init(context: context), .init(state: .pending))
    }
    func manager(for context: CoreShieldedDrainContext) throws -> Int {
        guard context == Self.context else { throw NSError(domain: "changed-context", code: 1) }
        return context.wallet
    }
}
@MainActor final class SwiftDashSDKHost {
    struct PlatformPreparation { let runtime: Int }
    static let shared = SwiftDashSDKHost()
    var runtime = 1
    func preparePlatformOperation() throws -> PlatformPreparation { .init(runtime: runtime) }
}
@MainActor final class Authorizer {
    var onAuthorize: () -> Void = {}
    func authorize() async throws { onAuthorize() }
}
@MainActor enum DWIdentityAuthorizer {
    static func preauthorized(_ work: () async -> Void) async { await work() }
}
@MainActor final class Coordinator {
    var preparation: Result<SwiftDashSDKHost.PlatformPreparation, Error> = .success(.init(runtime: 0))
    var acceptedResumes = 0
    // Deliberately retains the old confirmation, as the production reset does.
    func reset() {}
    func bindConfirmationPreparation(_ value: Result<SwiftDashSDKHost.PlatformPreparation, Error>) { preparation = value }
    func resumeAssetLock(outPointTxidWire: Data, outPointVout: UInt32,
                         expectedDrainContext: CoreShieldedDrainContext, retryUnverifiedConsumption: Bool) async {
        guard (try? preparation.get().runtime) == SwiftDashSDKHost.shared.runtime else { return }
        acceptedResumes += 1
    }
}
@MainActor final class InternalTransferRunner {
    enum StartOutcome: Equatable { case started, busy, notAuthorized, rejected }
    enum Phase: Equatable { case idle, inFlight, success, submittedUnconfirmed, failed(String) }
    enum Notice: Equatable { case started, busy, succeeded, submitted, drainPending, failed(String) }
    let authorizer = Authorizer()
    let coordinator = Coordinator()
    var phase: Phase = .idle
    var notice: Notice?
    var isAwaitingAuthorization = false
    var isCoreDrainRecovery = false
    var startOutcome: StartOutcome = .rejected
    func start(_ request: Int, preparation: Result<SwiftDashSDKHost.PlatformPreparation, Error>) async -> StartOutcome { startOutcome }
    // ANNOUNCE_METHOD
    // RESUME_METHOD
}
@MainActor final class ConfirmationModel {
    enum Mode { case transfer(Int), unavailable }
    var mode: Mode = .transfer(1)
    let runner = InternalTransferRunner()
    let preparation: Result<SwiftDashSDKHost.PlatformPreparation, Error> = .success(.init(runtime: 1))
    // CONFIRM_METHOD
}
