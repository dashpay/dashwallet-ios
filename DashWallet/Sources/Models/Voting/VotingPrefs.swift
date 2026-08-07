//  
//  Created by Andrei Ashikhmin
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

private let kVotingEnabled = "votingEnabledKey"
private let kVoteWithAllNodes = "voteWithAllNodesKey"

// MARK: - VotingPrefs

/// Whether the Voting entry appears in the More menu (Settings → Enable
/// Voting). Defaults on for DASHPAY builds.
class VotingPrefs {
    public static let shared: VotingPrefs = .init()
    
    init() {
        // Voting one node at a time is the default on purpose: casting every
        // node's vote in one action publicly links those masternodes to each
        // other, which is a privacy loss the user cannot undo afterwards.
        UserDefaults.standard.register(defaults: [
            kVotingEnabled: true,
            kVoteWithAllNodes: false,
        ])
    }
    
    private var _votingEnabled: Bool? = nil
    var votingEnabled: Bool {
        get {
            let result = _votingEnabled ?? UserDefaults.standard.bool(forKey: kVotingEnabled)
            return result
        }
        set(value) {
            _votingEnabled = value
            UserDefaults.standard.set(value, forKey: kVotingEnabled)
        }
    }

    /// `false` (default) casts one masternode's vote per tap; `true` casts
    /// with every votable node at once.
    ///
    /// Voting all at once broadcasts several `MasternodeVote` transitions for
    /// the same poll in quick succession, which lets an observer group those
    /// nodes as one operator. One at a time keeps that correlation the user's
    /// choice rather than a side effect of the default.
    var voteWithAllNodes: Bool {
        get { UserDefaults.standard.bool(forKey: kVoteWithAllNodes) }
        set { UserDefaults.standard.set(newValue, forKey: kVoteWithAllNodes) }
    }
}
