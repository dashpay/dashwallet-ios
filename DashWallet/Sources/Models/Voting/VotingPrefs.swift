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
private let kVotingNodeSelection = "votingNodeSelectionKey"
private let kVotingSetUp = "votingSetUpKey"

// MARK: - VotingPrefs

/// Whether the Voting entry appears in the More menu (Settings → Enable
/// Voting). Defaults on for DASHPAY builds.
class VotingPrefs {
    public static let shared: VotingPrefs = .init()

    private let defaults: UserDefaults
    /// The Platform network the voting choice belongs to; read on every
    /// access, so a network switch reads that network's choice.
    private let network: () -> String

    init(defaults: UserDefaults = .standard,
         network: @escaping () -> String = { MasternodeVoteCaster.networkKey }) {
        self.defaults = defaults
        self.network = network
        UserDefaults.standard.register(defaults: [
            kVotingEnabled: true,
        ])
    }

    /// The masternode choice and "voting set up" are kept per network: a
    /// testnet masternode is not a mainnet one. Mainnet keeps the plain key,
    /// so a selection saved before the split stays mainnet's.
    private func scoped(_ key: String) -> String {
        let network = network()
        return network == "mainnet" ? key : "\(key).\(network)"
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

    /// proTxHashes of the masternodes the user last voted with, so the next
    /// contest opens with the same nodes ticked.
    ///
    /// Empty means "never chosen": callers fall back to a single node rather
    /// than every node. That default is deliberate — casting with every node
    /// at once broadcasts several `MasternodeVote` transitions for the same
    /// poll in quick succession, which lets an observer group those nodes as
    /// one operator. Linking them stays something the user opts into and
    /// cannot be an accident of the first vote.
    ///
    /// Local only: this is a UI convenience, never consulted to decide what a
    /// node is permitted to do.
    var votingNodeSelection: Set<Data> {
        get {
            let stored = defaults.array(forKey: scoped(kVotingNodeSelection)) as? [String] ?? []
            return Set(stored.compactMap { Data(base64Encoded: $0) })
        }
        set {
            defaults.set(
                newValue.map { $0.base64EncodedString() }.sorted(),
                forKey: scoped(kVotingNodeSelection))
        }
    }

    /// Whether the user confirmed "Add your voting keys" once, with its Block
    /// or Approve button. Until then the default tick is not a choice and a
    /// vote opens that screen first (AC-12).
    var isVotingSetUp: Bool {
        get { defaults.bool(forKey: scoped(kVotingSetUp)) }
        set { defaults.set(newValue, forKey: scoped(kVotingSetUp)) }
    }

    /// Forget the masternode choice and "voting set up" on every network, as
    /// a wallet wipe does: the next wallet starts at "Add your voting keys".
    func forgetVotingSetup() {
        for key in defaults.dictionaryRepresentation().keys
            where [kVotingNodeSelection, kVotingSetUp].contains(where: { key == $0 || key.hasPrefix("\($0).") }) {
            defaults.removeObject(forKey: key)
        }
    }
}
