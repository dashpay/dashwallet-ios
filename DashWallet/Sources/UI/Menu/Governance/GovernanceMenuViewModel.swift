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

import Combine
import Foundation

enum GovernanceMenuNavigationDestination {
    case masternodes
    #if DASHPAY
    case voting
    #endif
}

@MainActor
final class GovernanceMenuViewModel: ObservableObject {
    @Published var items: [MenuItemModel] = []
    @Published var navigationDestination: GovernanceMenuNavigationDestination?

    init() {
        setupMenuItems()
    }

    private func setupMenuItems() {
        var allItems: [MenuItemModel] = []

        // Masternodes — not DashPay-gated: masternode ownership is a Core
        // concern and this screen is reachable in every build configuration
        // (it previously lived under Tools with no gate).
        allItems.append(MenuItemModel(
            title: NSLocalizedString("Masternodes", comment: "Masternodes"),
            subtitle: NSLocalizedString(
                "Masternodes and evonodes using this wallet's keys", comment: "Masternodes"),
            icon: .system("server.rack"),
            action: { [weak self] in
                self?.navigationDestination = .masternodes
            }
        ))

        #if DASHPAY
        // Username voting, behind the same preference that gated it on the
        // main menu (Settings → "Username voting").
        if VotingPrefs.shared.votingEnabled {
            allItems.append(MenuItemModel(
                title: NSLocalizedString("Voting", comment: ""),
                subtitle: NSLocalizedString(
                    "Vote on contested usernames", comment: "Voting"),
                icon: .custom("menu_voting", maxHeight: 30),
                action: { [weak self] in
                    self?.navigationDestination = .voting
                }
            ))
        }
        #endif

        items = allItems
    }

    func resetNavigation() {
        navigationDestination = nil
    }
}
