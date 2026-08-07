//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

/// Fabricated transactions for the pre-wallet onboarding demo. Pure synthetic
/// `.sdk`-shaped wrappers — no DashSync objects, no persisted rows. Amounts,
/// directions and date spacing mirror the legacy `DWTransactionStub` fixture.
class StubTransactionSource: TransactionSource {
    /// (duffs, isSent) fixture rows, newest first.
    private static let fixtures: [(amount: Int64, sent: Bool)] = [
        (314_000_000, true),    // 3.14 sent
        (271_000_000, false),   // 2.71 received
        (161_800_000, true),    // 1.618 sent
        (4_404_800_000, false), // 44.048 received
    ]

    /// The fixture list is four rows, so the window is the whole of it —
    /// the onboarding demo has no history to page through.
    func recentTransactions(limit: Int) -> [Transaction] {
        Array(allTransactions.prefix(limit))
    }

    var allTransactions: Array<Transaction> {
        Self.fixtures.enumerated().map { index, fixture in
            Transaction(
                syntheticTxid: Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }),
                directionRaw: fixture.sent ? 1 : 0,
                netAmount: fixture.sent ? -fixture.amount : fixture.amount,
                fee: nil,
                contextRaw: 3, // chainLocked — demo rows render as settled
                date: Date(timeIntervalSinceNow: -Double(index) * 100_000)
            )
        }
    }
}
