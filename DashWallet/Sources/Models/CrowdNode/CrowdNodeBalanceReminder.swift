//
//  Created by OpenAI Codex
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

@MainActor
final class CrowdNodeBalanceReminder: ObservableObject {
    static let shared = CrowdNodeBalanceReminder()

    @Published private(set) var hasBalance: Bool
    @Published private(set) var balance: UInt64
    @Published private(set) var activeScreenReminderDismissed: Bool = false
    /// Set once the active-screen reminder has been shown this session. Never reset, so the
    /// reminder sheet appears at most once per app launch (unlike the dismissed flag, which
    /// resets when the balance clears).
    @Published private(set) var didShowActiveScreenReminder: Bool = false

    private let crowdNode: CrowdNode
    private var cancellableBag = Set<AnyCancellable>()

    var formattedBalance: String {
        balance.formattedDashAmount
    }

    var shouldShowOnActiveScreen: Bool {
        hasBalance && !activeScreenReminderDismissed && !didShowActiveScreenReminder
    }

    var shouldShowOnExplore: Bool {
        hasBalance
    }

    private init(crowdNode: CrowdNode = .shared) {
        self.crowdNode = crowdNode
        self.balance = crowdNode.balance
        self.hasBalance = crowdNode.balance > 0

        crowdNode.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] balance in
                self?.update(balance: balance)
            }
            .store(in: &cancellableBag)
    }

    func dismissActiveScreenReminder() {
        // TODO(product): persist dismissal per account if this should survive app restarts.
        activeScreenReminderDismissed = true
    }

    /// Mark the active-screen reminder as shown so it isn't presented again this session.
    func markActiveScreenReminderShown() {
        didShowActiveScreenReminder = true
    }

    private func update(balance: UInt64) {
        self.balance = balance
        hasBalance = balance > 0

        if balance == 0 {
            activeScreenReminderDismissed = false
        }
    }
}
