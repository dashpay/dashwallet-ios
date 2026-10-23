import Foundation

/// Only the host/FFI boundary is replaced. The fee-cache implementation is
/// extracted unchanged from InternalTransferViewModel.swift by the test runner.
@MainActor
final class SwiftDashSDKHost {
    static let shared = SwiftDashSDKHost()
    struct PlatformPreparation: Equatable {
        let runtime: UUID
        let version: UInt32
    }
    enum Refusal: Error { case changed, estimateFailed }
    final class Manager {
        enum Kind { case transfer }
        var fee: UInt64 = 100
        var calls = 0
        var onEstimate: (() throws -> Void)?

        func estimateShieldedFee(kind: Kind, numActions: Int) throws -> UInt64 {
            calls += 1
            try onEstimate?()
            return fee
        }
    }

    var manager: Manager? = Manager()
    var runtime = UUID()
    var version: UInt32 = 13

    func preparePlatformOperation() throws -> PlatformPreparation {
        return PlatformPreparation(runtime: runtime, version: version)
    }

    func validatePlatformOperation(_ preparation: PlatformPreparation) throws {
        guard try preparation == preparePlatformOperation() else { throw Refusal.changed }
    }

    func reset() {
        runtime = UUID()
        version = 13
        manager = Manager()
    }
}
