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

/// One case per payable source and destination pair; the case names the call the executor makes.
/// There is no Identity to Shielded case: that pair stays unavailable (ADR-0041).
enum SendRoute: Equatable {
    case coreToCore
    case coreToShielded
    /// Core asset lock, then the Platform step.
    case coreToPlatform
    /// Core asset lock, then the Platform step (a top-up of the Current identity).
    case coreToIdentity
    case shieldedToCore
    case shieldedToShielded
    case shieldedToPlatform
    case shieldedToIdentity
    case platformToCore
    case platformToShielded
    case platformToPlatform
    case platformToIdentity
    case identityToCore
    case identityToPlatform
    case identityToIdentity
}

extension SendRoute {
    /// The source the route spends from.
    var source: SendSource {
        switch self {
        case .coreToCore, .coreToShielded, .coreToPlatform, .coreToIdentity: return .core
        case .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity: return .shielded
        case .platformToCore, .platformToShielded, .platformToPlatform, .platformToIdentity: return .platform
        case .identityToCore, .identityToPlatform, .identityToIdentity: return .identity
        }
    }

    /// Whether the fee prepared at Continue is the fee the send pays (ADR-0043). Only Core → Core, which also carries
    /// BIP70 payment requests, is built and signed at Continue; every other route's fee is an estimate.
    var isFeeExact: Bool { self == .coreToCore }
}
