//
//  Created by Roman Chornyi
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

struct IdentityRecipient: Equatable {
    let id: String
    let username: String?
    let isOwnCurrentIdentity: Bool
}

enum IdentityLookupResult: Equatable {
    case found(IdentityRecipient)
    case notFound
    case couldNotCheck
}

protocol IdentityLooking {
    func lookup(id: String, network: WalletEnvironment.NetworkKind) async -> IdentityLookupResult
}

/// The network edge of the lookup. `fetchIdentity` throws `SDKError.notFound` for an identity proven absent;
/// any other error means the check could not be made.
protocol IdentityPlatformReading: Sendable {
    func fetchIdentity(id: String, network: WalletEnvironment.NetworkKind) async throws
    func username(forIdentity id: String, network: WalletEnvironment.NetworkKind) async throws -> String?
}

protocol CurrentIdentityProviding: Sendable {
    /// Base58 ID of the active wallet's Current identity on `network`, or nil when it has none.
    @MainActor
    func currentIdentityID(on network: WalletEnvironment.NetworkKind) -> String?
}

struct IdentityLookupService: IdentityLooking {
    let platform: IdentityPlatformReading
    let currentIdentity: CurrentIdentityProviding

    func lookup(id: String, network: WalletEnvironment.NetworkKind) async -> IdentityLookupResult {
        do {
            try await platform.fetchIdentity(id: id, network: network)
        } catch SDKError.notFound {
            return .notFound
        } catch {
            return .couldNotCheck
        }
        let username = try? await platform.username(forIdentity: id, network: network)
        let ownID = await currentIdentity.currentIdentityID(on: network)
        return .found(IdentityRecipient(id: id, username: username, isOwnCurrentIdentity: ownID == id))
    }
}

// MARK: - Live conformances

/// Reads through `SwiftDashSDKHost`'s SDK, which is bound to the network the host is running; a lookup for
/// any other network throws `SDKError.invalidState`, which the service reports as `.couldNotCheck`.
struct SwiftDashSDKIdentityPlatformReader: IdentityPlatformReading {
    func fetchIdentity(id: String, network: WalletEnvironment.NetworkKind) async throws {
        let sdk = try await Self.sdk(for: network)
        _ = try await sdk.identityGet(identityId: id)
    }

    func username(forIdentity id: String, network: WalletEnvironment.NetworkKind) async throws -> String? {
        let sdk = try await Self.sdk(for: network)
        let usernames = try await sdk.dpnsGetUsername(identityId: id, limit: 1)
        return usernames.first?["label"] as? String
    }

    @MainActor
    private static func sdk(for network: WalletEnvironment.NetworkKind) throws -> SDK {
        guard let sdk = SwiftDashSDKHost.shared.sdk,
              WalletEnvironment.networkKind(for: sdk.network) == network else {
            throw SDKError.invalidState("SDK is not running on the requested network")
        }
        return sdk
    }
}

/// The identity `DWCurrentUserIdentityInfo` resolves for the active wallet, once the host runs the selected network.
struct WalletCurrentIdentityProvider: CurrentIdentityProviding {
    @MainActor
    func currentIdentityID(on network: WalletEnvironment.NetworkKind) -> String? {
        let info = DWCurrentUserIdentityInfo.shared
        guard info.isCurrentNetworkContextReady,
              WalletEnvironment.networkKind == network else { return nil }
        return info.identityId?.toBase58String()
    }
}
