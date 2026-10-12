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

/// A `dash-key:` URI carrying an App Connect request v2.
struct AppConnectUri: Equatable {
    let request: AppConnectRequest
    let network: DashConnectNetwork
    /// The `cb` return URL: absolute `https`, no credentials. Checked for
    /// form only; whether its host belongs to the app is not decided here.
    let callback: URL?
}

struct DashStRequest: Equatable {
    let transitionBytes: Data
    let network: DashConnectNetwork
}
