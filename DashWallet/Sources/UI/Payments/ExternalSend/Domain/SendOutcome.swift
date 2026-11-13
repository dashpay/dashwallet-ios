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

/// What happened to a send. Only `notSent` offers Retry; any error not proven to be before the broadcast is
/// `inFlight` (ADR-0040).
enum SendOutcome {
    case sent
    case inFlight
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
        } else {
            self = Self.outcome(for: error as NSError)
        }
    }

    func log() {
        switch self {
        case .sent:
            DWLogger.log("External send outcome: sent")
        case .inFlight:
            DWLogger.log("External send outcome: inFlight")
        case .notSent(let reason):
            DWLogger.log("External send outcome: notSent(\(reason.category))")
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
                localized: "This identity was not found in your wallet. Your funds were not sent.",
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
