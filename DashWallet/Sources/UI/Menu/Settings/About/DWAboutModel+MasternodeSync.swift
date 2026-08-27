//
//  Created by Bartosz Rozwarski
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

// Co-located @objc extension (pattern: DWPreviewSeedPhraseModel+Mnemonic.swift)
// so the ObjC About model can render SwiftDashSDK sync state.
extension DWAboutModel {
    /// The masternode-list line of the About tech-info status, sourced from
    /// SwiftDashSDK's SPV sync progress. Replaces the DashSync
    /// "Quorums validated x/y" row, which read a masternode list that no
    /// longer syncs post-M6 (it rendered 0/0 on fresh installs).
    @objc(masternodeListSyncLine)
    func masternodeListSyncLine() -> String {
        guard let masternodes = SwiftDashSDKSPVCoordinator.shared.syncProgress.masternodes else {
            return NSLocalizedString("Masternode list: not synced", comment: "About screen tech info")
        }
        if masternodes.targetHeight > masternodes.currentHeight {
            return String(format: NSLocalizedString("Masternode list: %u of %u", comment: "About screen tech info"),
                          masternodes.currentHeight, masternodes.targetHeight)
        }
        return String(format: NSLocalizedString("Masternode list: synced at %u", comment: "About screen tech info"),
                      masternodes.currentHeight)
    }

    /// The block line of the About tech-info status, sourced from SwiftDashSDK
    /// SPV state. Replaces the DashSync `lastSyncBlockHeight`/
    /// `estimatedBlockHeight` read, frozen post-M6.
    @objc(blockSyncLine)
    func blockSyncLine() -> String {
        let spv = SwiftDashSDKSPVCoordinator.shared
        return String(format: NSLocalizedString("Block #%d of %d", comment: ""),
                      spv.tipHeight, spv.bestPeerHeight)
    }

    /// The SPV connection line of the About tech-info status. Replaces the
    /// DashSync "Connected peers" + "Download peer" rows — those read
    /// `DSPeerManager`, dead post-M6 (0 / nil), and the SDK exposes no peer
    /// count or identity, so the honest diagnostic is its sync state.
    @objc(spvConnectionLine)
    func spvConnectionLine() -> String {
        let spv = SwiftDashSDKSPVCoordinator.shared
        let stateName: String
        switch spv.state {
        case .idle: stateName = NSLocalizedString("idle", comment: "About screen tech info: SPV state")
        case .waitingForConnections: stateName = NSLocalizedString("connecting", comment: "About screen tech info: SPV state")
        case .syncing: stateName = NSLocalizedString("syncing", comment: "About screen tech info: SPV state")
        // dash-spv's steady state when fully synced is waitForEvents
        // (`.synced` is a transient window) — render both as synced.
        case .synced, .waitForEvents: stateName = NSLocalizedString("synced", comment: "About screen tech info: SPV state")
        case .error: stateName = NSLocalizedString("error", comment: "About screen tech info: SPV state")
        case .unknown: stateName = NSLocalizedString("unknown", comment: "About screen tech info: SPV state")
        }
        return String(format: NSLocalizedString("SPV: %@ (%d%%)", comment: "ex., SPV: syncing (87%)"),
                      stateName, Int((spv.progress * 100).rounded()))
    }
}
