//
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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
import SwiftData
import SwiftDashSDK

class ZenLedgerViewModel: ObservableObject {
    private let zenLedger = ZenLedger()

    var isSynced: Bool {
        SyncingActivityMonitor.shared.state == .syncDone
    }

    func export() async throws -> String? {
        let addresses = await Self.walletOutputAddresses()

        return try await zenLedger.createPortfolio(
            addresses: addresses.isEmpty
                ? [SwiftDashSDKReceiveAddressReader.receiveAddress() ?? ""]
                : addresses)
    }

    /// Every address this wallet has ever received to, first-seen order.
    /// `PersistentTxo` rows are exactly the wallet's own outputs, so no
    /// per-transaction decode or ownership check is needed. Deduped —
    /// ZenLedger only needs each address once.
    @MainActor
    private static func walletOutputAddresses() -> [String] {
        guard let container = SwiftDashSDKHost.shared.modelContainer,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId else { return [] }
        let descriptor = FetchDescriptor<PersistentTxo>(
            predicate: #Predicate { $0.walletId == walletId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        guard let rows = try? container.mainContext.fetch(descriptor) else { return [] }

        var seen = Set<String>()
        return rows.compactMap { txo in
            seen.insert(txo.address).inserted ? txo.address : nil
        }
    }
}
