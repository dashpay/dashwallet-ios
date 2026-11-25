//
//  VoteErrorMessage.swift
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

/// Turns the errors a vote can fail with into one short sentence in plain
/// words. Platform's own text is never passed through: an error that is not
/// mapped here reads as the generic "try again" message.
enum VoteErrorMessage {
    /// Platform refused the vote because the masternode has spent its votes here.
    static func isNoVotesLeft(_ error: Error) -> Bool {
        guard let sdkError = error as? SDKError else { return false }
        return PlatformRefusal.of(sdkError) == .votedTooManyTimes
    }

    /// The SDK could not confirm the broadcast: the vote may have landed.
    static func isUnconfirmed(_ error: Error) -> Bool {
        if case .stateTransitionResultUnconfirmed = error as? SDKError { return true }
        return false
    }

    static func plain(for error: Error) -> String {
        if let castError = error as? MasternodeVoteCaster.CastError {
            switch castError {
            case .authenticationCancelled, .authenticationFailed, .noNodesSelected, .sdkUnavailable:
                // The app's own sentences, already in plain words.
                return castError.errorDescription ?? generic
            case .contestClosed:
                return closed
            }
        }

        if let sdkError = error as? SDKError {
            switch sdkError {
            case .networkError, .timeout:
                return connection
            case .consensusRejection(let consensus, _):
                return message(for: PlatformRefusal(code: consensus.code))
            default:
                return generic
            }
        }

        if error is URLError {
            return connection
        }
        return generic
    }

    private static func message(for refusal: PlatformRefusal) -> String {
        switch refusal {
        case .votedTooManyTimes:
            return String(localized: "No votes left", comment: "Voting")
        case .votePollNotAvailable, .votePollNotFound:
            return closed
        case .voteAlreadyPresent:
            // A vote this device has no record of (another device, a reinstall):
            // the same refusal comes back on every try.
            return String(localized: "The vote was not cast. This masternode already holds this vote.", comment: "Voting")
        case .voterNotFound, .incorrectVotingAddress, .incorrectVoterIdentityId:
            return String(
                localized: "The vote was not cast. This voting key does not belong to an active masternode.",
                comment: "Voting")
        default:
            return generic
        }
    }

    private static var connection: String {
        String(localized: "The vote was not cast. Check your connection and try again.", comment: "Voting")
    }

    private static var closed: String {
        String(localized: "The vote was not cast. Voting on this name has closed.", comment: "Voting")
    }

    private static var generic: String {
        String(localized: "The vote was not cast. Please try again.", comment: "Voting")
    }
}
