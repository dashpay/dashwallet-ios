import Foundation

enum DashConnectNetwork: String {
    case mainnet = "m"
    case testnet = "t"
    case devnet = "d"
}

struct DashKeyRequest: Equatable {
    let appEphemeralPubKey: Data
    let contractId: Data
    /// Unauthenticated display label from the QR payload. This is spoofable and must
    /// not be treated as a verified app identity.
    let label: String
    let network: DashConnectNetwork
}

struct DashStRequest: Equatable {
    let transitionBytes: Data
    let network: DashConnectNetwork
}
