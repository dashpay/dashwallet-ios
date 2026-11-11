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

/// SCR-05 Select source: every source by icon and name, no balances. A source that cannot pay this destination
/// stays listed but cannot be picked; a tap on it raises the pair policy's reason as a Toast. Identity is offered
/// only with a Current identity that has a username.
@MainActor
final class SelectSourceViewModel: ObservableObject {
    struct Row: Equatable, Identifiable {
        let source: SendSource
        let title: String
        let unavailableReason: UnavailableReason?
        let isSelected: Bool

        var id: SendSource { source }
        var reasonText: String? { unavailableReason?.localizedMessage }
        var isSelectable: Bool { unavailableReason == nil }
    }

    @Published private(set) var rows: [Row] = []
    /// The rows are being read; the sheet shows its loading state.
    @Published private(set) var isLoading = false
    @Published private(set) var selected: SendSource
    /// The reason of the unavailable row tapped last, shown as a Toast; nil when no Toast is up.
    @Published private(set) var toastMessage: String?

    /// Called with the source the holder picked; only available rows report.
    var onPick: ((SendSource) -> Void)?

    private let destination: Destination
    private let currentIdentity: CurrentIdentityReading

    init(destination: Destination, selected: SendSource,
         currentIdentity: CurrentIdentityReading = WalletCurrentIdentityReader()) {
        self.destination = destination
        self.selected = selected
        self.currentIdentity = currentIdentity
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let identity = await currentIdentity.currentIdentity()
        let offersIdentity = identity?.username?.isEmpty == false
        let facts = SendPairFacts(ownIdentityID: identity?.id)
        var built: [Row] = []
        for source in SendSource.allCases where source != .identity || offersIdentity {
            var reason: UnavailableReason?
            if case .unavailable(let found) = SendPairPolicy.decide(source: source, destination: destination,
                                                                    facts: facts) {
                reason = found
            }
            built.append(Row(source: source, title: SendAmountViewModel.title(of: source), unavailableReason: reason,
                             isSelected: false))
        }
        rows = built
        markSelection()
    }

    /// A tap anywhere on a row: an available row is picked; an unavailable one raises its reason and stays unpicked.
    func tap(_ source: SendSource) {
        guard let row = rows.first(where: { $0.source == source }) else { return }
        guard row.isSelectable else {
            toastMessage = row.reasonText
            return
        }
        toastMessage = nil
        selected = source
        markSelection()
        onPick?(source)
    }

    func dismissToast() {
        toastMessage = nil
    }

    #if DEBUG
    /// Lets a SwiftUI preview show rows and a Toast without driving the identity reader.
    func setPreviewRows(_ newRows: [Row], loading: Bool = false, toastMessage: String? = nil) {
        rows = newRows
        isLoading = loading
        self.toastMessage = toastMessage
        markSelection()
    }
    #endif

    private func markSelection() {
        rows = rows.map {
            Row(source: $0.source, title: $0.title, unavailableReason: $0.unavailableReason,
                isSelected: $0.isSelectable && $0.source == selected)
        }
    }
}
