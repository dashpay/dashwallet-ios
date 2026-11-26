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

/// The balances of the auto-picked sources as they were read; nil where the read failed, so an unreadable source
/// is unknown, never empty.
struct SendBalances: Equatable {
    let core: UInt64?
    let shielded: UInt64?
    let platform: UInt64?

    /// The balance held in `source`; nil when its read failed, and for Identity, whose funds are credits that
    /// `SendBalances` does not hold.
    func balance(of source: SendSource) -> UInt64? {
        switch source {
        case .core: return core
        case .shielded: return shielded
        case .platform: return platform
        case .identity: return nil
        }
    }
}

struct SendPairFacts: Equatable {
    /// The Current identity's ID; nil when the wallet has none.
    let ownIdentityID: String?
    /// The raw 43-byte Orchard address of the wallet's bound Shielded account (`shieldedDefaultAddress`); nil when
    /// the wallet has no bound Shielded account.
    let ownShieldedRaw43: Data?

    init(ownIdentityID: String?, ownShieldedRaw43: Data? = nil) {
        self.ownIdentityID = ownIdentityID
        self.ownShieldedRaw43 = ownShieldedRaw43
    }
}

enum UnavailableReason: Equatable, Hashable {
    case coreToPlatformAddress
    case platformToScriptFormPlatformAddress
    case identityToOwnIdentity
    case noCurrentIdentity
    /// The recipient shield records the payment under the wallet's Shielded account, so it needs one bound.
    case identityWithoutShieldedAccount
    case identityToOwnShieldedAddress
    case paymentRequestCoreOnly

    var localizedMessage: String {
        switch self {
        case .coreToPlatformAddress:
            return String(localized: "Core can't pay this kind of Platform address", comment: "External send")
        case .platformToScriptFormPlatformAddress:
            return String(localized: "Platform can't pay this kind of Platform address", comment: "External send")
        case .identityToOwnIdentity:
            return String(localized: "Identity can't top up itself", comment: "External send")
        case .noCurrentIdentity:
            return String(localized: "There is no identity to pay from", comment: "External send")
        case .identityWithoutShieldedAccount:
            return String(localized: "Identity can't pay a Shielded address until Shielded is set up",
                          comment: "External send")
        case .identityToOwnShieldedAddress:
            return String(localized: "Identity can't pay this wallet's own Shielded address", comment: "External send")
        case .paymentRequestCoreOnly:
            return String(localized: "A payment request can only be paid from Core", comment: "External send")
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

/// The one rule set for every source and destination pair (ADR-0062; Identity to Shielded per the feature's ADR-0012,
/// which supersedes ADR-0041). Pure: no network, no state.
enum SendPairPolicy {
    private static let autoPickOrder: [SendSource] = [.core, .shielded, .platform]

    static func decide(source: SendSource, destination: Destination, facts: SendPairFacts) -> SendPairDecision {
        // Only Core → Core calls back the app that opened a link (the pay-ack carries a Core txid), so a link that
        // requires its callback is paid from Core, as a payment request is.
        if isPaymentRequest(destination) || destination.isCallbackRequired {
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
            return .route(platformRoute(destination.type))
        case .identity:
            // Identity pays only from the Current identity: without one, every reader of this decision (Select
            // source, the starting source, a pin) sees the same refusal.
            guard facts.ownIdentityID != nil else { return .unavailable(.noCurrentIdentity) }
            return decideFromIdentity(destination, facts)
        }
    }

    private static func decideFromCore(_ destination: Destination, _ facts: SendPairFacts) -> SendPairDecision {
        switch destination.type {
        case .coreAddress, .paymentRequest: return .route(.coreToCore)
        case .shieldedAddress: return .route(.coreToShielded)
        // The lock records the addresses it pays (dashpay/platform#5930), so an interrupted payment resumes only to
        // them. The SDK's external funding takes P2PKH recipients only.
        case .platformAddress:
            return destination.isScriptForm ? .unavailable(.coreToPlatformAddress) : .route(.coreToPlatform)
        case .identityID:
            // Someone else's identity is paid through a lock that records it (dashpay/platform#5931).
            return .route(.coreToIdentity)
        }
    }

    private static func decideFromIdentity(_ destination: Destination, _ facts: SendPairFacts) -> SendPairDecision {
        switch destination.type {
        case .coreAddress, .paymentRequest: return .route(.identityToCore)
        case .shieldedAddress:
            guard let ownRaw43 = facts.ownShieldedRaw43 else { return .unavailable(.identityWithoutShieldedAccount) }
            return isShieldedAddress(destination, ownRaw43)
                ? .unavailable(.identityToOwnShieldedAddress) : .route(.identityToShielded)
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

    /// The first of Core, Shielded, Platform (never Identity) that can pay and was read to hold more than zero;
    /// when none was, the first that can pay. A balance that could not be read is unknown: never taken for one
    /// that holds funds, and not skipped as an empty one. A pinned source that can pay is kept.
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
        let funded = candidates.first { balances.balance(of: $0).map { $0 > 0 } ?? false }
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

    private static func isShieldedAddress(_ destination: Destination, _ raw43: Data) -> Bool {
        DashAddressClassifier.decodeBech32m(destination.text)?.form == .shielded(raw43: raw43)
    }
}
