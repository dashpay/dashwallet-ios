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

import DashUIKit
import SwiftUI
import UIKit

/// The warning shown before wiping the wallet: More → Security → Reset
/// Wallet, and removing the last wallet in Wallets. Continue opens the
/// recovery-phrase check in wipe mode; the wipe itself happens there.
struct ResetWalletInfoScreen: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: {
                    DashUIKit.NavigationBarElement.back.button(action: onCancel)
                },
                central: {
                    Text(NSLocalizedString("Wipe Wallet", comment: ""))
                        .dashFont(.subheadMedium)
                        .foregroundColor(.dash.primaryText)
                        .accessibilityAddTraits(.isHeader)
                })

            Spacer()

            VStack(spacing: 16) {
                Image("icon_warning")
                    .accessibilityHidden(true)

                Text(NSLocalizedString("Warning", comment: ""))
                    .dashFont(.title3)
                    .foregroundColor(.dash.primaryText)

                Text(NSLocalizedString(
                    "You are about to wipe this wallet from this device. Funds associated with this wallet can only be retrieved if you have your recovery phrase.",
                    comment: ""))
                    .dashFont(.callout)
                    .foregroundColor(.dash.secondaryText)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 8) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Continue", comment: ""),
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: onContinue)

                DashUIKit.DashButton(
                    text: NSLocalizedString("Cancel", comment: ""),
                    fillsWidth: true,
                    size: .large,
                    style: .plainBlue,
                    action: onCancel)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.dash.primaryBackground.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

/// Hosts `ResetWalletInfoScreen` in the navigation stack of whichever screen
/// opened it (the Security menu, or Wallets when removing the last wallet) and
/// is the delegate of the recovery-phrase screen it pushes, forwarding a
/// completed wipe to `wipeDelegate`.
final class ResetWalletInfoHostingController: UIHostingController<ResetWalletInfoScreen>,
    DWRecoverViewControllerDelegate {

    /// Lets the screen's buttons, built before `super.init`, reach the
    /// controller without a strong reference back to it.
    private final class ActionTarget {
        weak var controller: ResetWalletInfoHostingController?
    }

    private weak var wipeDelegate: DWWipeDelegate?

    init(wipeDelegate: DWWipeDelegate?) {
        let target = ActionTarget()
        self.wipeDelegate = wipeDelegate
        super.init(rootView: ResetWalletInfoScreen(
            onContinue: { target.controller?.showRecoveryPhraseCheck() },
            onCancel: { target.controller?.navigationController?.popViewController(animated: true) }))
        target.controller = self
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func showRecoveryPhraseCheck() {
        let controller = DWRecoverViewController()
        controller.hidesBottomBarWhenPushed = true
        controller.action = .wipe
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: - DWRecoverViewControllerDelegate

    func recoverViewControllerDidRecoverWallet(_ controller: DWRecoverViewController,
                                               recover recoverCommand: DWRecoverWalletCommand) {
        assertionFailure("The wipe flow never recovers a wallet")
    }

    func recoverViewControllerDidWipe(_ controller: DWRecoverViewController) {
        wipeDelegate?.didWipeWallet()
    }
}
