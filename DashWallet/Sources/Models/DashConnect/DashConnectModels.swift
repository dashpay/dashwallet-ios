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

/// Lifecycle of an app connection.
enum ConnectionStatus: String, Codable, CaseIterable {
    case approved
    case active
    case disconnected
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
    let walletUsername: String
    let walletIdentityId: String
}
