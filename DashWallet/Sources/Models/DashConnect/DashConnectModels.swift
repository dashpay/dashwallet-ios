//
//  DashConnectModels.swift
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

enum DashConnectQr: Equatable {
    case login(DashKeyRequest)
    case keyRegistration(DashStRequest)
}

/// Lifecycle of an app connection.
///
/// `approved` means the wallet knows about the app, but it may not be ready to
/// sign in yet: either the required login keys are not on the identity yet, or
/// the user locally turned the connection off from the wallet UI.
///
/// `active` means the app's login keys are registered on the identity and the
/// wallet has already published the matching `loginKeyResponse`.
enum ConnectionStatus: String, Codable, CaseIterable {
    case approved
    case active

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let status = ConnectionStatus(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown DashConnect status: \(rawValue)"
            )
        }
        self = status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A connected app identified by its stable contract id.
struct DAppConnection: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let url: String
    let status: ConnectionStatus
    let updatedAt: Date
}

/// A pending request derived from a scanned login QR code.
struct ConnectionRequest: Equatable {
    let appLabel: String
    let appUrl: String
    let appContractId: String
    let walletUsername: String?
    let walletIdentityId: String?
    let existingConnection: DAppConnection?
}

extension ConnectionRequest {
    /// Declaring an initializer inside the struct body would suppress the memberwise one,
    /// so this convenience lives in an extension.
    init(loginRequest: DashKeyRequest) {
        let contractId = loginRequest.contractId.toBase58String()
        let branding = DashConnectFallbackAppMetadata.resolve(
            contractId: contractId,
            unauthenticatedLabel: loginRequest.label
        )
        self.init(
            appLabel: branding.name,
            appUrl: branding.url,
            appContractId: contractId,
            walletUsername: nil,
            walletIdentityId: nil,
            existingConnection: nil
        )
    }

    init(
        loginRequest: DashKeyRequest,
        appLabel: String,
        appUrl: String,
        walletUsername: String?,
        walletIdentityId: String?,
        existingConnection: DAppConnection?
    ) {
        self.init(
            appLabel: appLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            appUrl: appUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            appContractId: loginRequest.contractId.toBase58String(),
            walletUsername: walletUsername,
            walletIdentityId: walletIdentityId,
            existingConnection: existingConnection
        )
    }
}
