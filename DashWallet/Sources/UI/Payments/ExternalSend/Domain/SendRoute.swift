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
enum SendRoute: Equatable {
    case coreToCore
    case coreToShielded
    /// Core asset lock, then the Platform step (a top-up of the Current identity).
    case coreToIdentity
    /// Core asset lock paying someone else's Platform address; the lock records its recipients (platform#5930).
    case coreToPlatform
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
    /// The Current identity's credits shielded to someone else's Shielded address (the feature's ADR-0012 in
    /// docs/features/external-send-redesign/adr, which supersedes ADR-0041).
    case identityToShielded
}

extension SendRoute {
    /// The source the route spends from.
    var source: SendSource {
        switch self {
        case .coreToCore, .coreToShielded, .coreToIdentity, .coreToPlatform: return .core
        case .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity: return .shielded
        case .platformToCore, .platformToShielded, .platformToPlatform, .platformToIdentity: return .platform
        case .identityToCore, .identityToPlatform, .identityToIdentity, .identityToShielded: return .identity
        }
    }

    /// Whether the fee prepared at Continue is the fee the send pays (ADR-0043): Core → Core (which also carries
    /// BIP70 payment requests) is built and signed at Continue, and a Shielded source runs the SDK plan made there.
    /// Every other route's fee is an estimate.
    var isFeeExact: Bool { self == .coreToCore || source == .shielded }
}
