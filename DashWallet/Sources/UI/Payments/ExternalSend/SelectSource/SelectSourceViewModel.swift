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

import Combine
import Foundation

/// The Current identity as Select source needs it: its ID and DPNS username (nil when it has none).
struct SelectSourceIdentity: Equatable {
    let id: String
    let username: String?
}

/// The one place Select source reads the Current identity of the active wallet. Faked in tests.
protocol CurrentIdentityReading {
    func currentIdentity() async -> SelectSourceIdentity?
}

/// The identity `DWCurrentUserIdentityInfo` resolves for the active wallet, once its network context is ready
/// (the same gate as `WalletCurrentIdentityProvider`).
struct WalletCurrentIdentityReader: CurrentIdentityReading {
    @MainActor
    func currentIdentity() async -> SelectSourceIdentity? {
        let info = DWCurrentUserIdentityInfo.shared
        guard info.isCurrentNetworkContextReady else { return nil }
        let snapshot = info.refreshedSnapshot()
        guard let id = snapshot.identityId?.toBase58String() else { return nil }
        return SelectSourceIdentity(id: id, username: snapshot.username)
    }
}

/// SCR-05 Select source: every source with its balance, the ones that cannot pay this destination shown with
/// the pair policy's reason and not pickable. Identity is offered only with a Current identity that has a username.
@MainActor
final class SelectSourceViewModel: ObservableObject {
    struct Row: Equatable, Identifiable {
        let source: SendSource
        let title: String
        /// Duffs; the Identity row's credits are already converted. Nil when the balance could not be read.
        let balanceDuffs: UInt64?
        /// The balance in local currency; nil without an exchange rate or a readable balance.
        let balanceFiatText: String?
        let unavailableReason: UnavailableReason?
        let isSelected: Bool

        var id: SendSource { source }
        var balanceText: String? { balanceDuffs?.formattedDashAmount }
        var reasonText: String? { unavailableReason?.localizedMessage }
        var isSelectable: Bool { unavailableReason == nil }
    }

    @Published private(set) var rows: [Row] = []
    /// The rows are being read; the sheet shows its loading state.
    @Published private(set) var isLoading = false
    @Published private(set) var selected: SendSource

    /// Called with the source the holder picked; only available rows report.
    var onPick: ((SendSource) -> Void)?

    private let destination: Destination
    private let balances: ExternalSendBalanceReading
    private let currentIdentity: CurrentIdentityReading
    private let converter: SendAmountConverting

    init(destination: Destination, selected: SendSource, balances: ExternalSendBalanceReading,
         currentIdentity: CurrentIdentityReading = WalletCurrentIdentityReader(),
         converter: SendAmountConverting = LiveSendAmountConverter()) {
        self.destination = destination
        self.selected = selected
        self.balances = balances
        self.currentIdentity = currentIdentity
        self.converter = converter
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let identity = await currentIdentity.currentIdentity()
        let offersIdentity = identity?.username?.isEmpty == false
        let facts = SendPairFacts(ownIdentityID: identity?.id)
        var built: [Row] = []
        for source in SendSource.allCases where source != .identity || offersIdentity {
            let raw = await balances.spendableBalance(of: source)
            let duffs = source == .identity ? raw.map(AmountRules.dashValue(of:)) : raw
            var reason: UnavailableReason?
            if case .unavailable(let found) = SendPairPolicy.decide(source: source, destination: destination,
                                                                    facts: facts) {
                reason = found
            }
            built.append(Row(source: source, title: SendAmountViewModel.title(of: source), balanceDuffs: duffs,
                             balanceFiatText: duffs.flatMap { converter.fiatText(forDuffs: $0) },
                             unavailableReason: reason, isSelected: false))
        }
        rows = built
        markSelection()
    }

    func select(_ source: SendSource) {
        guard rows.contains(where: { $0.source == source && $0.isSelectable }) else { return }
        selected = source
        markSelection()
        onPick?(source)
    }

    #if DEBUG
    /// Lets a SwiftUI preview show rows without driving the balance and identity readers.
    func setPreviewRows(_ newRows: [Row], loading: Bool = false) {
        rows = newRows
        isLoading = loading
        markSelection()
    }
    #endif

    private func markSelection() {
        rows = rows.map {
            Row(source: $0.source, title: $0.title, balanceDuffs: $0.balanceDuffs,
                balanceFiatText: $0.balanceFiatText, unavailableReason: $0.unavailableReason,
                isSelected: $0.isSelectable && $0.source == selected)
        }
    }
}
