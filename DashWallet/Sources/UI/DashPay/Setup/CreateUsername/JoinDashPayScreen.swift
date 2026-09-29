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

import SwiftUI
import DashUIKit

public struct JoinDashPayScreen: View {
    @StateObject private var viewModel: CreateUsernameViewModel
    /// Continue was tapped. The sheet that hosts this screen owns what comes
    /// next — `JoinDashPayInfoDialog` turns it into its voting-info page.
    var action: () -> Void
    /// Non-nil renders the "Have an invitation?" entry — the
    /// install-then-paste redeem path for invited users (DIP-13).
    var onClaimInvitation: (() -> Void)? = nil

    init(action: @escaping () -> Void, onClaimInvitation: (() -> Void)? = nil) {
        self.action = action
        self.onClaimInvitation = onClaimInvitation
        // Same shared instance the form itself runs on — the sheet must read
        // the balance the next screen will spend, not a second tally of it.
        _viewModel = StateObject(wrappedValue: CreateUsernameViewModel.shared)
    }

    #if DEBUG
    /// Preview-only entry point: takes a posed view model so the canvas never
    /// builds `CreateUsernameViewModel.shared`, whose init subscribes to the
    /// SDK wallet state and the registration coordinator.
    init(previewViewModel: CreateUsernameViewModel,
         action: @escaping () -> Void = {},
         onClaimInvitation: (() -> Void)? = nil) {
        self.action = action
        self.onClaimInvitation = onClaimInvitation
        _viewModel = StateObject(wrappedValue: previewViewModel)
    }
    #endif

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(maxHeight: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Create username", comment: ""))
                    .dashFont(.title1)
                    .foregroundStyle(Color.dash.primaryText)

                Text(NSLocalizedString("Forget about long crypto addresses, create the username, find friends and add them to your contacts", comment: ""))
                    .dashFont(.body)
                    .foregroundStyle(Color.dash.secondaryText)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 16) {
                SheetFeature(
                    title: NSLocalizedString("Pay to usernames", comment: ""),
                    description: NSLocalizedString("No more alphanumeric addresses", comment: ""),
                    icon: DashIcon.Features.username.source
                )
                SheetFeature(
                    title: NSLocalizedString("Add your friends & family", comment: ""),
                    description: NSLocalizedString("Invite your family, find your friends by searching their usernames", comment: ""),
                    icon: DashIcon.Features.friends.source
                )
                SheetFeature(
                    title: NSLocalizedString("Personalize profile", comment: ""),
                    description: NSLocalizedString("Upload your picture, personalize your identity", comment: ""),
                    icon: DashIcon.Features.profile.source
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)
            .padding(.bottom, 20)

            Spacer()
                .frame(maxHeight: 20)

            VStack(spacing: 20) {
                if let balanceNote {
                    Text(balanceNote)
                        .dashFont(.caption1)
                        .foregroundStyle(Color.dash.secondaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    // Nothing spendable on either route: the form behind this
                    // button has nothing to fund a registration with, so the
                    // label drops back to a neutral "Continue" that reads as
                    // "not yet" rather than promising a registration.
                    DashUIKit.DashButton(
                        text: canProceed
                            ? NSLocalizedString("Create username", comment: "")
                            : NSLocalizedString("Continue", comment: ""),
                        isEnabled: canProceed,
                        fillsWidth: true,
                        size: .large,
                        style: .filledBlue,
                        action: action
                    )

                    // A scanned invitation funds the registration itself, so
                    // this stays tappable while the button above is greyed
                    // out.
                    if let onClaimInvitation {
                        DashUIKit.DashButton(
                            text: NSLocalizedString("Scan invitation QR", comment: ""),
                            fillsWidth: true,
                            size: .large,
                            style: .tintedBlue,
                            action: onClaimInvitation
                        )
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
    }
    
    /// The single question this screen asks: can the registration be paid for
    /// right now — by a transparent balance that clears the minimum, or by a
    /// shielded balance that is actually `.ready`.
    ///
    /// Deliberately NOT `shieldedReadiness != nil`: that snapshot is assigned
    /// unconditionally once the readiness pass runs
    /// (`CreateUsernameViewModel.updateUsernameValidity`), so it is non-nil
    /// with a `.needsFunding` state and an empty shielded balance. Testing it
    /// asks whether the wallet has hydrated, not whether there is anything to
    /// spend — which left the button inviting while the line above it said
    /// the balance was short.
    private var canProceed: Bool {
        viewModel.hasMinimumRequiredBalance || viewModel.hasReadyShieldedFunding
    }

    /// The caption above the button. One slot, two different things to say:
    ///
    /// - Below the minimum, it names the minimum — same predicate as the
    ///   button, so a line saying the balance is short can never sit over a
    ///   button offering to spend it.
    /// - Above the minimum but below what a contested name costs, it names
    ///   that ceiling. The user picks the name on the NEXT screen, and by then
    ///   a short balance reads as the name being refused rather than as a
    ///   price they were never told.
    private var balanceNote: String? {
        if !canProceed {
            return String.localizedStringWithFormat(
                NSLocalizedString("You should have at least %@ Dash to create a username", comment: "Usernames"),
                viewModel.minimumRequiredBalance)
        }

        if !viewModel.hasRecommendedBalance {
            // "available", not "you have": the figure is what can actually be
            // spent — `coreSpendableDuffs`, i.e. confirmed inputs less the
            // miner fee an ordinary send still needs. Home's header shows the
            // total, so without saying which is which the two numbers read as
            // a bug (0.25 in the header, 0.24999661 here).
            return String.localizedStringWithFormat(
                NSLocalizedString("You have %@ Dash available (network fee reserved).\nSome usernames cost up to %@ Dash.", comment: "Usernames"),
                viewModel.balance,
                viewModel.recommendedBalance)
        }

        return nil
    }
}

// MARK: - Previews

#if DEBUG

/// Enough for a contested name (0.25 DASH, `DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME`):
/// no info line at all, Continue enabled. This is the state the redesign's
/// "has enough balance" sheet starts from.
#Preview("Enough for a contested name") {
    JoinDashPayScreen(
        previewViewModel: .makeForPreview(
            balance: "0.30000000",
            hasMinimumRequiredBalance: true,
            hasRecommendedBalance: true),
        onClaimInvitation: {})
}

/// Enough for a standard name but not for a contested one — the info line
/// names both numbers ("You have 0.05 Dash. Some usernames cost up to 0.25 Dash.").
#Preview("Standard balance only") {
    JoinDashPayScreen(
        previewViewModel: .makeForPreview(
            balance: "0.05000000",
            hasMinimumRequiredBalance: true),
        onClaimInvitation: {})
}

/// No transparent funds and a shielded route that is known but NOT funded
/// (`.needsFunding`). Nothing is spendable on either route, so the shortfall
/// line shows and the button is the greyed-out "Continue" — the snapshot
/// merely existing no longer counts as a funding source.
#Preview("No funds — shielded route not ready") {
    JoinDashPayScreen(
        previewViewModel: .makeForPreview(
            balance: "0.00999774",
            shieldedReadiness: ShieldedIdentityFundingReadiness.Snapshot(
                state: .needsFunding(shortfallCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits),
                requiredCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                matureCredits: 0,
                unspentCredits: 0,
                poolNoteCount: nil)),
        onClaimInvitation: {})
}

/// Wallet not hydrated yet: no balance and no readiness snapshot at all.
/// Greyed out for the same reason as the preview above. No invitation entry
/// here, so the sheet's short form is visible too.
#Preview("Wallet not hydrated — Continue disabled") {
    JoinDashPayScreen(previewViewModel: .makeForPreview())
}

/// The same greyed-out state with an invitation entry: the only way forward
/// for a wallet with nothing in it, since the voucher funds the registration.
#Preview("No funds — invitation is the only route") {
    JoinDashPayScreen(previewViewModel: .makeForPreview(), onClaimInvitation: {})
}

#endif
