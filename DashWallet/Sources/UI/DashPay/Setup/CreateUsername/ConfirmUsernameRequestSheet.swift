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

import SwiftUI
import DashUIKit

/// Last stop before a username registration is submitted: the name, what it
/// costs, and an explicit acknowledgement that it cannot be changed.
///
/// Mirrors Android's `ConfirmUsernameRequestDialogFragment`, including its two
/// messages — the requested name and the instant companion are confirmed by
/// the same sheet, one after the other, and only the sentence differs.
struct ConfirmUsernameRequestSheet: View {
    /// Which name is being confirmed. The instant companion is registered in
    /// the same submission, so it gets its own pass through this sheet rather
    /// than being folded into the contested one's confirmation.
    enum Kind {
        case requested
        case instant
    }

    let kind: Kind
    let username: String
    /// What this pass costs in duffs, or nil when it costs nothing.
    ///
    /// The instant companion is nil by nature: it is a second DPNS name on
    /// the identity the contested submission just funded
    /// (`DWIdentityRegistrationCoordinator`, step 3.6 — `registerDpnsName`
    /// with no asset lock), so it is paid in that identity's credits and no
    /// further DASH is spent. Showing a figure there invented a second charge.
    let amountDuffs: UInt64?
    /// Contested submissions spend the contest fee whatever the vote decides,
    /// which is the one thing about the amount that is not obvious.
    let showsContestFeeNote: Bool
    let onConfirm: () -> Void

    /// Nothing is pre-accepted: the checkbox IS the acknowledgement, so
    /// Confirm stays disabled until it is ticked.
    @State private var hasAccepted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Confirm username request", comment: "Usernames"))
                        .dashFont(.title1)
                        .foregroundStyle(Color.dash.primaryText)

                    Text(message)
                        .dashFont(.body)
                        .foregroundStyle(Color.dash.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if amountDuffs != nil {
                    amountSection
                } else {
                    Text(NSLocalizedString(
                        "No additional Dash is spent — this username is registered to the identity you are already paying for.",
                        comment: "Usernames"))
                        .dashFont(.footnote)
                        .foregroundStyle(Color.dash.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }

            if showsContestFeeNote {
                Text(NSLocalizedString(
                    "The contest fee is spent when you submit and is not returned, even if you do not win the name.",
                    comment: "Usernames"))
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }

            acceptToggle
                .padding(.top, 24)
                .frame(maxWidth: .infinity)

            DashUIKit.DashButton(
                text: NSLocalizedString("Confirm", comment: ""),
                isEnabled: hasAccepted,
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: onConfirm
            )
            .padding(.top, 20)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
    }

    private var message: String {
        switch kind {
        case .requested:
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "You have chosen “%@” as your username. Please note that the username can NOT be changed once it is registered.",
                    comment: "Usernames"),
                username)
        case .instant:
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "You chose “%@” as an instant username. Please note that the username can NOT be changed once it is registered.",
                    comment: "Usernames"),
                username)
        }
    }

    /// The cost, in the design system's amount presentation. `SwapAmountView`
    /// renders the Dash figure with its logo and the converted value under it,
    /// which is the layout the mock asks for; nothing here is editable.
    @ViewBuilder
    private var amountSection: some View {
        if let amountDuffs {
            SwapAmountView(
                amount: amountDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol,
                secondaryText: fiatText,
                showDashLogo: true)
                .frame(maxWidth: .infinity)
        }
    }

    /// nil while rates are unavailable — the sheet then shows the Dash figure
    /// alone rather than a placeholder that looks like a price.
    private var fiatText: String? {
        guard let amountDuffs,
              let fiatAmount = try? CurrencyExchanger.shared.convertDash(
                  amount: amountDuffs.dashAmount,
                  to: App.fiatCurrency) else { return nil }

        return NumberFormatter.fiatFormatter.string(from: fiatAmount as NSNumber)
    }

    private var acceptToggle: some View {
        Button {
            hasAccepted.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(dash: hasAccepted
                    ? DashIcon.Checkbox.checkmarkChecked.source
                    : DashIcon.Checkbox.checkmarkUnchecked.source)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                Text(NSLocalizedString("I accept", comment: "Usernames"))
                    .dashFont(.subheadMedium)
                    .foregroundStyle(Color.dash.primaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.dash.blueAlpha5)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#if DEBUG

/// The contested request: 0.25 DASH and the fee note, nothing accepted yet,
/// so Confirm is greyed out.
#Preview("Requested name — contested") {
    ConfirmUsernameRequestSheet(
        kind: .requested,
        username: "TestUser01",
        amountDuffs: UInt64(DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME),
        showsContestFeeNote: true,
        onConfirm: {})
        .background(Color.dash.primaryBackground)
}

/// The instant companion, confirmed on its own pass: same sheet, its own
/// sentence, and no contest fee to warn about.
#Preview("Instant username") {
    ConfirmUsernameRequestSheet(
        kind: .instant,
        username: "TestUser012",
        amountDuffs: nil,
        showsContestFeeNote: false,
        onConfirm: {})
        .background(Color.dash.primaryBackground)
}

#endif
