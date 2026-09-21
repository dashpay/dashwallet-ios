//
//  Created by Claude
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

import OSLog
import SwiftUI

#if DASHPAY

/// The identity's credit balance, read against the cost of one Platform
/// operation.
///
/// Credits pay for state transitions — a profile update, a contact request —
/// and an identity that runs out can still receive payments but cannot write
/// anything. Android answers this with `CreditBalanceInfo`; the thresholds
/// here are its thresholds, so both wallets warn at the same point.
enum IdentityCreditBalance {
    private static let logger = Logger(subsystem: "org.dash.wallet", category: "identity-credits")

    /// The most expensive single operation, from Android's measurements (July
    /// 2024): a contact request cost 80–90M credits, a profile update 10–100M.
    /// A balance below this cannot pay for one write at all.
    static let maxOperationCost: UInt64 = 100_000_000
    /// Ten operations' worth. Above it nothing is said; below it the user is
    /// told while they still have room to act.
    static let lowBalance: UInt64 = maxOperationCost * 10

    struct Info {
        let credits: UInt64

        /// Enough for one write.
        var isEnough: Bool { credits >= IdentityCreditBalance.maxOperationCost }
        /// Running out — warn, but let the write through.
        var isWarning: Bool { credits <= IdentityCreditBalance.lowBalance }
        /// Not enough for even one write.
        var isEmpty: Bool { !isEnough }
    }

    /// The live balance, or `nil` when it cannot be read — no identity yet, or
    /// the SDK host is not up. `nil` is not "zero": Android refuses the write
    /// and says so rather than guessing, and so does the caller here.
    @MainActor
    static func current() -> Info? {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let identityId = DWCurrentUserIdentityInfo.shared.identityId else {
            return nil
        }

        do {
            let credits = try wallet.managedIdentity(identityId: identityId).getBalance()
            return Info(credits: credits)
        } catch {
            logger.error("💳 CREDITS :: balance read failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

extension UIViewController {
    /// The credit gate Android runs on Save (`EditProfileActivity.saveButton`),
    /// as one call: returns whether the write may go ahead, having shown
    /// whatever the balance requires the user to answer first.
    ///
    /// - A balance that cannot be read stops the write with an error, because
    ///   an unknown balance is not a safe one to spend from.
    /// - Empty: the warning is the answer — "Maybe later" does not write.
    /// - Low: the user is warned and "Maybe later" writes anyway, since the
    ///   balance still covers this one operation.
    @MainActor
    func confirmAgainstIdentityCredits() async -> Bool {
        guard let balance = IdentityCreditBalance.current() else {
            _ = await showModalDialog(
                style: .warning,
                icon: .system("exclamationmark.triangle.fill"),
                heading: NSLocalizedString("Platform credits error", comment: "Credits"),
                textBlock1: NSLocalizedString(
                    "Your credit balance could not be read. Check your connection and try again.",
                    comment: "Credits"),
                positiveButtonText: NSLocalizedString("OK", comment: ""))
            return false
        }

        guard balance.isWarning || balance.isEmpty else { return true }

        let buysCredits = await showModalDialog(
            style: .warning,
            icon: .system("exclamationmark.triangle.fill"),
            heading: balance.isEmpty
                ? NSLocalizedString("Your credit balance has been fully depleted", comment: "Credits")
                : NSLocalizedString("Your credit balance is low", comment: "Credits"),
            textBlock1: balance.isEmpty
                ? NSLocalizedString(
                    "You can continue to use DashPay for payments but you cannot update your profile or add more contacts until you top up your credit balance",
                    comment: "Credits")
                : NSLocalizedString(
                    "Top-up your credits to continue making changes to your profile and adding contacts",
                    comment: "Credits"),
            positiveButtonText: NSLocalizedString("Buy credits", comment: ""),
            negativeButtonText: NSLocalizedString("Maybe later", comment: ""))

        if buysCredits {
            // The real top-up: Core or Platform funds into the identity's
            // credit balance, which is what the identity actually spends.
            let controller = InternalTransferHostingController(transferTo: .identity)
            controller.hidesBottomBarWhenPushed = true
            if let navigationController {
                navigationController.pushViewController(controller, animated: true)
            } else {
                present(BaseNavigationController(rootViewController: controller), animated: true)
            }
            return false
        }

        // Warned but still able to pay for this one: let it through, as Android
        // does. Empty means there is nothing to pay with.
        return balance.isWarning && !balance.isEmpty
    }
}

#endif
