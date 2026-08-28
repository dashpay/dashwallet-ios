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

import SwiftUI

// MARK: - Network choice

/// Picks the chain to run against.
///
/// The work is the caller's: switching networks tears down and rebuilds the
/// wallet runtime, and only the screen knows what it has to refresh afterwards.
private struct NetworkChoiceAlert: ViewModifier {
    @Binding var isPresented: Bool
    let onMainnet: () -> Void
    let onTestnet: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            NSLocalizedString("Network", comment: ""),
            isPresented: $isPresented
        ) {
            Button(NSLocalizedString("Mainnet", comment: ""), action: onMainnet)
            Button(NSLocalizedString("Testnet", comment: ""), action: onTestnet)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        }
    }
}

// MARK: - CoinJoin sweep

/// The confirmation for moving leftover mixed coins, and the failure that can
/// follow it.
///
/// One modifier for both because they are one exchange: the second alert only
/// ever appears as the answer to the first, and `errorMessage` doubles as the
/// presentation flag so a failure cannot be shown without something to say.
private struct CoinJoinSweepAlerts: ViewModifier {
    @Binding var isConfirming: Bool
    /// Pre-formatted leftover balance — this file does no amount formatting.
    let amount: String
    let onConfirm: () -> Void
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .alert(
                NSLocalizedString("Move CoinJoin Funds", comment: "CoinJoin"),
                isPresented: $isConfirming
            ) {
                Button(NSLocalizedString("Move funds", comment: "CoinJoin"), action: onConfirm)
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
            } message: {
                Text(String(
                    format: NSLocalizedString(
                        "Move your %@ in mixed coins to your spendable balance? CoinJoin is no longer supported.",
                        comment: "CoinJoin"),
                    amount))
            }
            .alert(
                NSLocalizedString("Move CoinJoin Funds", comment: "CoinJoin"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                Button(NSLocalizedString("OK", comment: "")) { errorMessage = nil }
            } message: { message in
                Text(message)
            }
    }
}

// MARK: - Call sites

extension View {
    func networkChoiceAlert(
        isPresented: Binding<Bool>,
        onMainnet: @escaping () -> Void,
        onTestnet: @escaping () -> Void
    ) -> some View {
        modifier(NetworkChoiceAlert(
            isPresented: isPresented,
            onMainnet: onMainnet,
            onTestnet: onTestnet))
    }

    func coinJoinSweepAlerts(
        isConfirming: Binding<Bool>,
        amount: String,
        onConfirm: @escaping () -> Void,
        errorMessage: Binding<String?>
    ) -> some View {
        modifier(CoinJoinSweepAlerts(
            isConfirming: isConfirming,
            amount: amount,
            onConfirm: onConfirm,
            errorMessage: errorMessage))
    }
}
