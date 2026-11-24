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

/// An amount below what Platform accepts for the route, refused before anything was built.
struct MinimumAmountRefusal: Error {
    let minimumCredits: UInt64
}

/// A Core asset lock a send broadcast and recorded whose Platform step did not finish: the outpoint and route that
/// `AssetLockRecoveryService.retry` resumes.
struct HeldAssetLock: Equatable {
    /// `PersistentAssetLock.fundingTypeRaw` of the lock: 5 for Core to Shielded, the two-step route External Send has.
    let fundingTypeRaw: Int
    let txidWire: Data
    let vout: UInt32
}

/// What happened to a send. Only `notSent` offers Retry; any error not proven to be before the broadcast is
/// `inFlight` (ADR-0040).
enum SendOutcome {
    case sent
    /// Submitted, its result unknown: it settles with sync.
    case inFlight
    /// The money left the source into an asset lock that is recorded, and the Platform step did not finish: it stays
    /// in the lock until the lock is resumed.
    case lockHeld(HeldAssetLock)
    case notSent(NotSentReason)

    init(error: Error) {
        if let error = error as? ShieldedTransferCoordinator.CoordinatorError {
            self = Self.outcome(for: error)
        } else if let error = error as? SwiftDashSDKTransactionSender.SendError {
            self = Self.outcome(for: error)
        } else if let error = error as? PlatformWalletError {
            self = Self.outcome(for: error)
        } else if let error = error as? PlatformAddressSyncCoordinator.SendError {
            self = Self.outcome(for: error)
        } else if case BIP70Error.failedAfterAcknowledgement = error {
            // The merchant acknowledged the Payment and holds the signed bytes.
            self = .inFlight
        } else if case BIP70Error.expired = error {
            // Thrown before the claim is spent: nothing was POSTed or broadcast.
            self = .notSent(.expired)
        } else if error is MinimumAmountRefusal {
            self = .notSent(.belowMinimum)
        } else if error is AssetLockInputLimit.TooManyInputsError {
            // `AssetLockInputLimit.requireFits` refuses before authorizing and before any lock exists.
            self = .notSent(.failed)
        } else if error is PlatformPaymentIdentityFundingPolicy.PlanningError {
            // The identity top-up from Platform credits plans its inputs before any credits move.
            self = .notSent(.failed)
        } else {
            self = Self.outcome(for: error as NSError)
        }
    }

    /// The outcome as its log line names it.
    var logName: String {
        switch self {
        case .sent: return "sent"
        case .inFlight: return "inFlight"
        case .lockHeld(let lock): return "lockHeld(type=\(lock.fundingTypeRaw))"
        case .notSent(let reason): return "notSent(\(reason.category))"
        }
    }

    private static func outcome(for error: ShieldedTransferCoordinator.CoordinatorError) -> SendOutcome {
        switch error {
        case .authCancelled, .authFailed, .noWallet, .noShieldedAddress, .shieldedBalanceUnavailable,
             .coinJoinDrainRequiresSync:
            return .notSent(.failed)
        // Thrown by the Shielded- and Platform-source `perform*` calls before `authorize()` and before the phase
        // reaches proving or broadcasting; `drainBalanceChanged` is thrown by the Max drain before its operation is
        // prepared.
        case .noReceiveAddress, .noPlatformAddress, .shieldedSweepChanged, .shieldedAmountExceedsBundle,
             .drainBalanceChanged:
            return .notSent(.failed)
        // Thrown while the coordinator resolves its manager, network, storage or fee estimate, or when a removal
        // refuses its funding call, before any asset lock.
        case .noManager, .noNetwork, .noModelContainer, .shieldedPoolFeeUnavailable, .addressFundingFeeUnavailable,
             .walletReloading:
            return .notSent(.failed)
        // Both throw sites are the SDK's Platform-to-shielded capacity preflight, which runs before proof or broadcast.
        case .platformShieldCapacityChanged:
            return .notSent(.failed)
        case .shieldedSweepWaiting:
            return .notSent(.earlierPaymentPending)
        case .transferFailed(let inner):
            return SendOutcome(error: inner)
        default:
            return .inFlight
        }
    }

    private static func outcome(for error: SwiftDashSDKTransactionSender.SendError) -> SendOutcome {
        switch error {
        case .transactionRejected:
            return .notSent(.rejected)
        case .walletNotReady, .invalidInput:
            return .notSent(.failed)
        default:
            return .inFlight
        }
    }

    /// The cases the Platform routes throw while they resolve the destination and its own addresses, before the asset
    /// lock is built or anything is signed or submitted.
    private static func outcome(for error: PlatformAddressSyncCoordinator.SendError) -> SendOutcome {
        switch error {
        case .coordinatorNotReady, .invalidDestination, .p2shNotSupported, .noPlatformReceiveAddress, .invalidAmount,
             .noFundedAddress:
            return .notSent(.failed)
        default:
            return .inFlight
        }
    }

    private static func outcome(for error: PlatformWalletError) -> SendOutcome {
        switch error {
        case .transactionBroadcastRejected:
            return .notSent(.rejected)
        case .signingKeyUnavailable:
            return .notSent(.signingKeyUnavailable)
        case .staleReservationToken, .coreInsufficientFunds, .shieldedNoRecordedAnchor:
            return .notSent(.failed)
        // Refusals of an asset lock's coin selection: nothing was built or broadcast.
        case .assetLockInsufficientFunds, .noSelectableInputs, .assetLockTooManyInputs:
            return .notSent(.failed)
        // The external identity top-up throws it, before anything is signed, for an identity Platform does not know.
        case .identityNotFound:
            return .notSent(.identityNotFound)
        // The address top-ups read the identity from Platform before they sign (dashpay/platform#5860): a failed
        // read (80) sent nothing.
        case .identityLookupFailed:
            return .notSent(.failed)
        // The Platform withdrawal's address network check runs before signing; the Platform-to-shielded capacity
        // checks run during input selection and the input fetch, before the proof is built.
        case .invalidNetwork, .shieldedInsufficientBalance:
            return .notSent(.failed)
        // The SDK documents it as definitively not executed, with any note reservations released and retry safe.
        case .shieldedBroadcastFailed:
            return .notSent(.failed)
        // Stays maybe-sent: the SDK's coming Rust-owned delivery class (dashpay/platform#5928) classes it so.
        case .addressNonceMismatch:
            return .inFlight
        default:
            return .inFlight
        }
    }

    private static func outcome(for error: NSError) -> SendOutcome {
        guard error.domain == WalletSendService.errorDomain else { return .inFlight }
        switch WalletSendService.ErrorCode(rawValue: error.code) {
        case .offline:
            return .notSent(.offline)
        case .broadcastRejected:
            return .notSent(.rejected)
        case .authenticationCancelled, .authenticationFailed:
            return .notSent(.failed)
        // Thrown before any transaction is built: the restored wallet's initial sync, an empty CoinJoin balance, a
        // swap memo the builder refuses.
        case .initialRestoreSync, .coinJoinSweepUnavailable, .invalidSwapMemo:
            return .notSent(.failed)
        default:
            return .inFlight
        }
    }
}

/// A send's outcome and what decided it, written as the send's one log line.
struct SendDecision {
    /// What makes an error's outcome known whatever the error says.
    enum Fact {
        /// The coordinator recorded the asset lock it built: the money left the source.
        case assetLockRecorded
        /// The seam handed the spend over: the money left the source.
        case handedOver
        /// The asset lock holding the money is known.
        case lockHeld(HeldAssetLock)

        var logName: String {
            switch self {
            case .assetLockRecorded: return "assetLockRecorded"
            case .handedOver: return "handedOver"
            case .lockHeld: return "lockHeld"
            }
        }
    }

    let outcome: SendOutcome
    /// What decided `outcome`: the deciding error's `errorName`, with ` after=<Fact>` when a fact overrode it, or the
    /// name of the step that decided it without an error. Nil for a send that went through.
    let cause: String?

    init(_ outcome: SendOutcome, cause: String? = nil) {
        self.outcome = outcome
        self.cause = cause
    }

    /// The one place an error becomes a send's outcome: `SendOutcome(error:)`, or what `fact` makes it.
    static func decided(by error: Error, after fact: Fact? = nil) -> SendDecision {
        let outcome: SendOutcome
        switch fact {
        case nil:
            outcome = SendOutcome(error: error)
        case .assetLockRecorded?, .handedOver?:
            outcome = .inFlight
        case .lockHeld(let lock)?:
            outcome = .lockHeld(lock)
        }
        let cause = errorName(error) + (fact.map { " after=\($0.logName)" } ?? "")
        return SendDecision(outcome, cause: cause)
    }

    /// `External send outcome: <outcome> route=<route> max=<isMax>[ cause=<cause>]`. It names no address, amount,
    /// key or error text.
    func logLine(route: SendRoute, isMax: Bool) -> String {
        var line = "External send outcome: \(outcome.logName) route=\(route) max=\(isMax)"
        if let cause { line += " cause=\(cause)" }
        return line
    }

    /// The error's type and case, as `PlatformWalletError.walletOperation`, never its payload (Platform's raw text). A
    /// case's associated error is named the same way in parentheses; an `NSError` is its domain and code.
    static func errorName(_ error: Error) -> String {
        if type(of: error) is NSError.Type {
            let error = error as NSError
            return "NSError(\(error.domain):\(error.code))"
        }
        // The module and any `(unknown context …)` of a private type are dropped.
        let typeName = String(reflecting: type(of: error)).split(separator: ".").dropFirst()
            .filter { !$0.hasPrefix("(") }.joined(separator: ".")
        let mirror = Mirror(reflecting: error)
        guard mirror.displayStyle == .enum else { return typeName }
        if let payload = mirror.children.first, let caseName = payload.label {
            if let inner = payload.value as? Error { return "\(typeName).\(caseName)(\(errorName(inner)))" }
            return "\(typeName).\(caseName)"
        }
        // A case without a payload describes itself by its name, unless the type describes itself otherwise.
        let caseName = String(describing: error)
        guard !caseName.isEmpty, caseName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return typeName
        }
        return "\(typeName).\(caseName)"
    }
}

enum NotSentReason {
    case offline
    case rejected
    case earlierPaymentPending
    case signingKeyUnavailable
    case identityNotFound
    case belowMinimum
    case expired
    /// The balance a whole-balance send pays changed after Confirm showed it; nothing was sent, Send plans Max again.
    case balanceChanged
    case failed

    var category: String {
        switch self {
        case .offline: return "offline"
        case .rejected: return "rejected"
        case .earlierPaymentPending: return "earlierPaymentPending"
        case .signingKeyUnavailable: return "signingKeyUnavailable"
        case .identityNotFound: return "identityNotFound"
        case .belowMinimum: return "belowMinimum"
        case .expired: return "expired"
        case .balanceChanged: return "balanceChanged"
        case .failed: return "failed"
        }
    }

    var localizedMessage: String {
        switch self {
        case .offline:
            return String(
                localized: "You are offline. Check your connection and try again.",
                comment: "External send")
        case .rejected:
            return String(
                localized: "The network rejected the payment. Your funds were not sent.",
                comment: "External send")
        case .earlierPaymentPending:
            return String(
                localized: "An earlier payment is still being processed. Try again in a moment.",
                comment: "External send")
        case .signingKeyUnavailable:
            return String(
                localized: "The signing key is unavailable. Your funds were not sent.",
                comment: "External send")
        case .identityNotFound:
            return String(
                localized: "This identity could not be found. Your funds were not sent.",
                comment: "External send")
        case .belowMinimum:
            return String(
                localized: "The amount is below the minimum for this payment. Your funds were not sent.",
                comment: "External send")
        case .expired:
            return String(
                localized: "The payment request has expired. Your funds were not sent.",
                comment: "External send")
        case .balanceChanged:
            return String(
                localized: "Your balance changed. Check the amount and try again. Your funds were not sent.",
                comment: "External send")
        case .failed:
            return String(
                localized: "The payment failed. Your funds were not sent.",
                comment: "External send")
        }
    }
}
