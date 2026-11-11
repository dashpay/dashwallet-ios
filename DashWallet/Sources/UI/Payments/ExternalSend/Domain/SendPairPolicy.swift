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

struct SendBalances: Equatable {
    let core: UInt64
    let shielded: UInt64
    let platform: UInt64

    func balance(of source: SendSource) -> UInt64 {
        switch source {
        case .core: return core
        case .shielded: return shielded
        case .platform: return platform
        case .identity: return 0
        }
    }
}

struct SendPairFacts: Equatable {
    /// The Current identity's ID; nil when the wallet has none.
    let ownIdentityID: String?
}

enum UnavailableReason: Equatable, Hashable {
    case coreToOtherIdentity
    case coreToScriptFormPlatformAddress
    case platformToScriptFormPlatformAddress
    case platformToOtherIdentity
    case identityToOwnIdentity
    case notSupportedYet
    case paymentRequestCoreOnly

    var localizedMessage: String {
        switch self {
        case .coreToOtherIdentity:
            return NSLocalizedString("Core can't pay someone else's identity", comment: "External send")
        case .coreToScriptFormPlatformAddress:
            return NSLocalizedString("Core can't pay this kind of Platform address", comment: "External send")
        case .platformToScriptFormPlatformAddress:
            return NSLocalizedString("Platform can't pay this kind of Platform address", comment: "External send")
        case .platformToOtherIdentity:
            return NSLocalizedString("Platform can't pay someone else's identity yet", comment: "External send")
        case .identityToOwnIdentity:
            return NSLocalizedString("Identity can't top up itself", comment: "External send")
        case .notSupportedYet:
            return NSLocalizedString("Identity can't pay a Shielded address yet", comment: "External send")
        case .paymentRequestCoreOnly:
            return NSLocalizedString("A payment request can only be paid from Core", comment: "External send")
        }
    }
}

enum SendPairDecision: Equatable {
    case route(SendRoute)
    case unavailable(UnavailableReason)
}

struct StartingSource: Equatable {
    let source: SendSource
    /// True when the pinned source could not pay the destination and was replaced.
    let sourceChanged: Bool
}

/// The one rule set for every source and destination pair (ADR-0038, ADR-0041). Pure: no network, no state.
enum SendPairPolicy {
    private static let autoPickOrder: [SendSource] = [.core, .shielded, .platform]

    static func decide(source: SendSource, destination: Destination, facts: SendPairFacts) -> SendPairDecision {
        if isPaymentRequest(destination) {
            return source == .core ? .route(.coreToCore) : .unavailable(.paymentRequestCoreOnly)
        }
        switch source {
        case .core: return decideFromCore(destination, facts)
        case .shielded: return .route(shieldedRoute(destination.type))
        case .platform:
            // The Platform transfer takes only P2PKH outputs; the unshield and the identity transfer take P2SH too.
            if destination.type == .platformAddress && destination.isScriptForm {
                return .unavailable(.platformToScriptFormPlatformAddress)
            }
            // The SDK's top-up from Platform addresses refuses an identity the wallet does not manage.
            if destination.type == .identityID && !isOwnIdentity(destination, facts) {
                return .unavailable(.platformToOtherIdentity)
            }
            return .route(platformRoute(destination.type))
        case .identity: return decideFromIdentity(destination, facts)
        }
    }

    private static func decideFromCore(_ destination: Destination, _ facts: SendPairFacts) -> SendPairDecision {
        switch destination.type {
        case .coreAddress, .paymentRequest: return .route(.coreToCore)
        case .shieldedAddress: return .route(.coreToShielded)
        case .platformAddress:
            return destination.isScriptForm ? .unavailable(.coreToScriptFormPlatformAddress) : .route(.coreToPlatform)
        case .identityID:
            return isOwnIdentity(destination, facts) ? .route(.coreToIdentity) : .unavailable(.coreToOtherIdentity)
        }
    }

    private static func decideFromIdentity(_ destination: Destination, _ facts: SendPairFacts) -> SendPairDecision {
        switch destination.type {
        case .coreAddress, .paymentRequest: return .route(.identityToCore)
        case .shieldedAddress: return .unavailable(.notSupportedYet)
        case .platformAddress: return .route(.identityToPlatform)
        case .identityID:
            let own = isOwnIdentity(destination, facts)
            return own ? .unavailable(.identityToOwnIdentity) : .route(.identityToIdentity)
        }
    }

    private static func shieldedRoute(_ type: Destination.Kind) -> SendRoute {
        switch type {
        case .coreAddress, .paymentRequest: return .shieldedToCore
        case .shieldedAddress: return .shieldedToShielded
        case .platformAddress: return .shieldedToPlatform
        case .identityID: return .shieldedToIdentity
        }
    }

    private static func platformRoute(_ type: Destination.Kind) -> SendRoute {
        switch type {
        case .coreAddress, .paymentRequest: return .platformToCore
        case .shieldedAddress: return .platformToShielded
        case .platformAddress: return .platformToPlatform
        case .identityID: return .platformToIdentity
        }
    }

    /// The first of Core, Shielded, Platform (never Identity) that holds more than zero and can pay; when none
    /// does, the first that can pay, at 0. A pinned source that can pay is kept.
    static func startingSource(destination: Destination, balances: SendBalances, pinned: SendSource?,
                               facts: SendPairFacts) -> StartingSource {
        func canPay(_ source: SendSource) -> Bool {
            if case .route = decide(source: source, destination: destination, facts: facts) { return true }
            return false
        }
        if let pinned, canPay(pinned) {
            return StartingSource(source: pinned, sourceChanged: false)
        }
        let candidates = autoPickOrder.filter(canPay)
        let funded = candidates.first { balances.balance(of: $0) > 0 }
        let picked = funded ?? candidates.first ?? .core
        return StartingSource(source: picked, sourceChanged: pinned != nil)
    }

    /// The Confirm warnings of a pair. `isMax` is the whole-balance send: Core → Shielded drains the wallet and
    /// Platform → Core withdraws the whole balance, though Max fills the balance less the fee.
    static func warnings(source: SendSource, destination: Destination, isMax: Bool) -> [ConfirmWarning] {
        let toCore = destination.type == .coreAddress
        let isCoreDrain = source == .core && destination.type == .shieldedAddress && isMax
        var list: [ConfirmWarning] = []
        if toCore && source == .shielded { list.append(.shieldedNotInstant) }
        if source == .shielded && destination.type != .shieldedAddress { list.append(.shieldedMadePublic) }
        if toCore && source == .platform { list.append(.processingTime) }
        if toCore && source == .platform && isMax { list.append(.fullPlatformWithdrawal) }
        if isCoreDrain { list.append(.emptyingCoreBalance) }
        if !(toCore && source != .core) && !isCoreDrain { list.append(.wrongAddressReminder) }
        return list
    }

    static func isPaymentRequest(_ destination: Destination) -> Bool {
        destination.type == .paymentRequest || destination.paymentRequestURL != nil
    }

    private static func isOwnIdentity(_ destination: Destination, _ facts: SendPairFacts) -> Bool {
        facts.ownIdentityID == destination.text
    }
}
