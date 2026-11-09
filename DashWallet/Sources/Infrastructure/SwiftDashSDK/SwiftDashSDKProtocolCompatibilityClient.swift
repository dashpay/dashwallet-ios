import SwiftDashSDK

@MainActor
struct SwiftDashSDKProtocolCompatibilityClient: WalletProtocolCompatibilityClient {
    let sdk: SDK

    func queryEpoch() async throws {
        // The historical epoch's proof carries fresh signed response metadata.
        // getEpochsInfo dispatches blocking FFI on the SDK's query queue.
        _ = try await sdk.getEpochsInfo(startEpoch: 0, count: 1, ascending: true)
    }

    func protocolVersionInfo() throws -> ProtocolVersionInfo {
        try sdk.protocolVersionInfo()
    }
}
