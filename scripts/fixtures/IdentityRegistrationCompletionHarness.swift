import Foundation
import OSLog

// Stand-ins for the Foundation harness only. The completion method body is
// extracted verbatim from DWIdentityRegistrationCoordinator by the runner.
@MainActor
final class CompletionWallet {
    let walletId = Data([1])
}

@MainActor
final class CompletionController {
    var completedIdentity: Data?
    func enterCompleted(identityId: Data) { completedIdentity = identityId }
}

@MainActor
final class DWCurrentUserIdentityInfo {
    static let shared = DWCurrentUserIdentityInfo()
    var refresh: () async -> Void = {}
    func refreshFromSDK() {}
    func refreshBalanceFromNetwork(identityId: Data, wallet: CompletionWallet, network: String) async {
        await refresh()
    }
}

@MainActor
final class DWContestedNameStatusService {
    static let shared = DWContestedNameStatusService()
    var didClearPending = false
    func clearPending(label: String, for network: String, walletId: Data) { didClearPending = true }
}

@MainActor
struct UsernameRegistrationDraftStore {
    static var didClear = false
    func clear(for scope: String) { Self.didClear = true }
}

@MainActor
final class RegistrationCompletionHarness {
    static let logger = Logger(subsystem: "test", category: "completion")
    enum NameState { case owned }
    let nameState = NameState.owned
    let username = "alice"
    let network = "testnet"
    let wallet = CompletionWallet()
    let draftScope = "original-wallet-testnet"
    var temporaryUsernameError: String?
    let identityId = Data([2])
    let newController = CompletionController()
    var completedRegistrationContextMessage: String?
    var validateContext: () throws -> Void = {}
    func validateRegistrationContext(walletId: Data, network: String) throws { try validateContext() }
    func resetState() {}

    func completeRegistration() async throws -> Data {
        // PRODUCTION_COMPLETION_BLOCK
    }
}
