//
//  DashConnectNetworkConfiguration.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import SwiftDashSDK

/// What DashConnect needs to know about each network, in one place.
///
/// Data-contract ids are per network: a contract registered on testnet does not
/// exist on mainnet or on a devnet, and each chain gets its own id when the
/// contract is registered there. Whether DashConnect is available on a network
/// is therefore a question of whether that network has a `loginKeyResponse`
/// (key-exchange) contract — not of whether the network is a test network.
enum DashConnectNetworkConfiguration {
    /// The pinned TESTNET `loginKeyResponse` contract id. Compile-time
    /// constant, so the length check can never fire at runtime.
    static let testnetLoginKeyExchangeContractId: Data = {
        guard let data = Data.identifier(fromBase58: "7UaqHGBJBbRLJ4fUWS45cnud8PPUugJWoGTt1SKwHJ2P"),
              data.count == 32 else {
            fatalError("DashConnect loginKeyResponse contract id must be a 32-byte identifier.")
        }
        return data
    }()

    /// The MAINNET `loginKeyResponse` contract id.
    ///
    /// TODO(dashconnect-mainnet): the key-exchange contract is not deployed on
    /// mainnet, so there is no id to pin and DashConnect stays unavailable
    /// there. Pinning the id here is what makes the feature available.
    static let mainnetLoginKeyExchangeContractId: Data? = nil

    /// Fallback-only branding keyed by the trustworthy contract id, not the
    /// spoofable QR label. Per network, because an app's contract id differs
    /// on every chain it is registered on.
    private static let knownApps: [DashConnectNetwork: [String: DashConnectAppMetadata]] = [
        .testnet: [
            "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F": .init(name: "Yappr", url: "yap.pr"),
        ],
    ]

    /// Whether DashConnect can run on `network`: testnet has a pinned contract,
    /// devnet takes the id from Devnet Settings (a missing id surfaces as an
    /// error when it is used, where the settings screen can fix it), and
    /// mainnet has one only once `mainnetLoginKeyExchangeContractId` is pinned.
    static func isAvailable(on network: DashConnectNetwork) -> Bool {
        switch network {
        case .testnet, .devnet:
            return true
        case .mainnet:
            return mainnetLoginKeyExchangeContractId != nil
        }
    }

    /// The `loginKeyResponse` contract id for `network`.
    ///
    /// Throws a normal, user-visible error when the network has no usable id —
    /// never a crash on user input, never a guessed id.
    static func loginKeyExchangeContractId(
        for network: DashConnectNetwork,
        devnetContractId: String? = DevnetConfiguration.dashConnectContractId
    ) throws -> Data {
        switch network {
        case .testnet:
            return testnetLoginKeyExchangeContractId
        case .devnet:
            guard let raw = devnetContractId,
                  let data = Data.identifier(fromBase58: raw),
                  data.count == 32 else {
                throw DashConnectPlatformError.devnetLoginContractNotConfigured
            }
            return data
        case .mainnet:
            guard let data = mainnetLoginKeyExchangeContractId else {
                throw DashConnectPlatformError.loginContractUnavailable
            }
            return data
        }
    }

    /// The SDK runtime network a DashConnect network publishes through.
    static func runtimeNetwork(for network: DashConnectNetwork) -> Network {
        switch network {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        }
    }

    /// The DashConnect network matching the app's current network selection.
    static func currentNetwork() -> DashConnectNetwork {
        switch WalletEnvironment.networkKind {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        }
    }

    /// Display metadata for an app contract: the known branding for this
    /// network, else the QR's unauthenticated label with no URL.
    static func appMetadata(
        contractId: String,
        unauthenticatedLabel: String,
        on network: DashConnectNetwork
    ) -> DashConnectAppMetadata {
        if let known = knownApps[network]?[contractId] {
            return known
        }
        return DashConnectAppMetadata(
            name: unauthenticatedLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            url: ""
        )
    }
}
