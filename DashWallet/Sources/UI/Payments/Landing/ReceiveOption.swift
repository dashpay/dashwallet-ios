//
//  ReceiveOption.swift
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

/// One choice in the option row of the Receive card.
///
/// Receive's own type, not `ChainNetwork`: the chain options map to their
/// chain, and Identity maps to none, so Identity cannot reach Send, Home or
/// Internal transfer, which keep using `ChainNetwork` (ADR-0035).
enum ReceiveOption: String, CaseIterable, Identifiable {
    case core
    case shielded
    case platform
    case identity

    init(_ network: ChainNetwork) {
        switch network {
        case .core: self = .core
        case .shielded: self = .shielded
        case .platform: self = .platform
        }
    }

    var id: String { rawValue }

    /// The chain this option receives on; nil for Identity, which is not a chain.
    var chainNetwork: ChainNetwork? {
        switch self {
        case .core: return .core
        case .shielded: return .shielded
        case .platform: return .platform
        case .identity: return nil
        }
    }

    var title: String {
        chainNetwork?.title ?? NSLocalizedString("Identity", comment: "")
    }

    /// The balance a Receipt on this option names.
    var balanceName: String {
        chainNetwork?.balanceName ?? NSLocalizedString("Identity", comment: "")
    }
}
