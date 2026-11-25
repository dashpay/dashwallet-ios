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
    /// Devnet is offered only by internal builds, so the caller passes `nil`
    /// where the network does not exist and the button is not drawn at all.
    let onDevnet: (() -> Void)?

    func body(content: Content) -> some View {
        content.alert(
            String(localized: "Network", comment: ""),
            isPresented: $isPresented
        ) {
            Button(WalletEnvironment.displayName(of: WalletEnvironment.NetworkKind.mainnet), action: onMainnet)
            Button(WalletEnvironment.displayName(of: WalletEnvironment.NetworkKind.testnet), action: onTestnet)
            if let onDevnet {
                Button(WalletEnvironment.displayName(of: WalletEnvironment.NetworkKind.devnet), action: onDevnet)
            }
            Button(String(localized: "Cancel", comment: ""), role: .cancel) { }
        }
    }
}

/// A network switch refused before anything was torn down — today only devnet
/// selected without its coordinates.
///
/// Separate from `NetworkChoiceAlert` because it is not part of the choice: a
/// failure *during* a switch renders in the lifecycle overlay's failure card,
/// and only a refusal that never started has nowhere else to go. `message`
/// doubles as the presentation flag, so there is no way to show it empty.
private struct NetworkSwitchErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            String(localized: "Network", comment: ""),
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            ),
            presenting: message
        ) { _ in
            Button(String(localized: "OK", comment: "")) { message = nil }
        } message: { text in
            Text(text)
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
                String(localized: "Move CoinJoin Funds", comment: "CoinJoin"),
                isPresented: $isConfirming
            ) {
                Button(String(localized: "Move funds", comment: "CoinJoin"), action: onConfirm)
                Button(String(localized: "Cancel", comment: ""), role: .cancel) { }
            } message: {
                Text(String(localized: "Move your \(amount) in mixed coins to your spendable balance? CoinJoin is no longer supported.", comment: "CoinJoin"))
            }
            .alert(
                String(localized: "Move CoinJoin Funds", comment: "CoinJoin"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                Button(String(localized: "OK", comment: "")) { errorMessage = nil }
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
        onTestnet: @escaping () -> Void,
        onDevnet: (() -> Void)? = nil
    ) -> some View {
        modifier(NetworkChoiceAlert(
            isPresented: isPresented,
            onMainnet: onMainnet,
            onTestnet: onTestnet,
            onDevnet: onDevnet))
    }

    func networkSwitchErrorAlert(message: Binding<String?>) -> some View {
        modifier(NetworkSwitchErrorAlert(message: message))
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

#Preview("Network choice") {
    Text(verbatim: "Settings")
        .networkChoiceAlert(isPresented: .constant(true), onMainnet: { }, onTestnet: { })
}

#Preview("Network choice with devnet") {
    Text(verbatim: "Settings")
        .networkChoiceAlert(isPresented: .constant(true), onMainnet: { }, onTestnet: { }, onDevnet: { })
}
