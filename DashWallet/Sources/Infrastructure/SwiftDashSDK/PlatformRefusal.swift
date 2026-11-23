//
//  PlatformRefusal.swift
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

/// The rs-dpp consensus codes the app branches on
/// (`packages/rs-dpp/src/errors/consensus/codes.rs` in dashpay/platform).
/// Each constant is named after the rs-dpp error it numbers.
enum PlatformConsensusCode {
    /// `IdentityAssetLockTransactionOutPointAlreadyConsumedError`
    static let assetLockOutPointAlreadyConsumed: UInt32 = 10504
    /// `DocumentNotFoundError`
    static let documentNotFound: UInt32 = 40101
    /// `DuplicateUniqueIndexError`
    static let duplicateUniqueIndex: UInt32 = 40105
    /// `IdentityInsufficientBalanceError`
    static let identityInsufficientBalance: UInt32 = 40210
    /// `MasternodeNotFoundError`
    static let masternodeNotFound: UInt32 = 40300
    /// `VotePollNotFoundError`
    static let votePollNotFound: UInt32 = 40301
    /// `VotePollNotAvailableForVotingError`
    static let votePollNotAvailableForVoting: UInt32 = 40302
    /// `MasternodeVotedTooManyTimesError`
    static let masternodeVotedTooManyTimes: UInt32 = 40303
    /// `MasternodeVoteAlreadyPresentError`
    static let masternodeVoteAlreadyPresent: UInt32 = 40304
    /// `MasternodeIncorrectVotingAddressError`
    static let masternodeIncorrectVotingAddress: UInt32 = 40305
    /// `MasternodeIncorrectVoterIdentityIdError`
    static let masternodeIncorrectVoterIdentityId: UInt32 = 40306
    /// `AddressNotEnoughFundsError`
    static let addressNotEnoughFunds: UInt32 = 40601
    /// `AddressesNotEnoughFundsError`
    static let addressesNotEnoughFunds: UInt32 = 40602
}

/// What Platform refused a state transition for, read from the consensus code
/// the SDK error carries and never from its rendered text.
///
/// A code this table does not name is `.other(code:)`, and an error that
/// carries no consensus code has no `PlatformRefusal` at all: neither is
/// folded into a named case.
enum PlatformRefusal: Equatable {
    /// The asset lock's output was already spent on Platform.
    case assetLockOutPointConsumed
    /// The document a replace or delete names does not exist.
    case documentNotFound
    /// A document with the same unique-index values already exists.
    case duplicateUniqueIndex
    /// The identity's credit balance cannot pay for the transition.
    case identityBalanceTooLow
    /// The Platform addresses funding the transition hold too little.
    case addressBalanceTooLow
    /// The voting masternode is not known to Platform.
    case voterNotFound
    /// The vote poll does not exist.
    case votePollNotFound
    /// The vote poll no longer takes votes.
    case votePollNotAvailable
    /// The masternode has used all its votes on this poll.
    case votedTooManyTimes
    /// The masternode already holds this exact vote.
    case voteAlreadyPresent
    /// The voting key does not match the masternode's voting address.
    case incorrectVotingAddress
    /// The voter identity id does not match the masternode.
    case incorrectVoterIdentityId
    /// A consensus code this table does not name.
    case other(code: UInt32)

    init(code: UInt32) {
        switch code {
        case PlatformConsensusCode.assetLockOutPointAlreadyConsumed: self = .assetLockOutPointConsumed
        case PlatformConsensusCode.documentNotFound: self = .documentNotFound
        case PlatformConsensusCode.duplicateUniqueIndex: self = .duplicateUniqueIndex
        case PlatformConsensusCode.identityInsufficientBalance: self = .identityBalanceTooLow
        case PlatformConsensusCode.addressNotEnoughFunds,
             PlatformConsensusCode.addressesNotEnoughFunds: self = .addressBalanceTooLow
        case PlatformConsensusCode.masternodeNotFound: self = .voterNotFound
        case PlatformConsensusCode.votePollNotFound: self = .votePollNotFound
        case PlatformConsensusCode.votePollNotAvailableForVoting: self = .votePollNotAvailable
        case PlatformConsensusCode.masternodeVotedTooManyTimes: self = .votedTooManyTimes
        case PlatformConsensusCode.masternodeVoteAlreadyPresent: self = .voteAlreadyPresent
        case PlatformConsensusCode.masternodeIncorrectVotingAddress: self = .incorrectVotingAddress
        case PlatformConsensusCode.masternodeIncorrectVoterIdentityId: self = .incorrectVoterIdentityId
        default: self = .other(code: code)
        }
    }

    /// The consensus rejection `error` carries, from the SDK or from the
    /// wallet layer; `nil` for any other error. Only the error itself is
    /// examined: a caller holding a wrapped error unwraps it first.
    static func consensusError(in error: Error) -> PlatformConsensusError? {
        switch error {
        case let error as SDKError: error.consensusError
        case let error as PlatformWalletError: error.consensusError
        default: nil
        }
    }

    /// The refusal `error` carries, or `nil` when it carries no consensus
    /// code. Only the error itself is examined, as in `consensusError(in:)`.
    static func of(_ error: Error) -> PlatformRefusal? {
        consensusError(in: error).map { PlatformRefusal(code: $0.code) }
    }
}
