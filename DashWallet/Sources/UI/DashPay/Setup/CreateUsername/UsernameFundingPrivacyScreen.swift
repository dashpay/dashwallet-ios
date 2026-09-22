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
import DashUIKit

/// Which balance pays for the registration, asked as its own step: shielded
/// funds leave the username unlinkable, transparent ones publish the link on
/// chain. The recommendation lives in the copy — the choice is the user's.
///
/// The pick is a `DWIdentityFundingSource` rather than a private enum of its
/// own, so it hands straight to
/// `DWIdentityRegistrationBridge.shared.preferredFundingSource` with no
/// translation step in between.
struct UsernameFundingPrivacyScreen: View {
    @StateObject private var viewModel: CreateUsernameViewModel

    /// Nothing is preselected on purpose. Picking for the user would make the
    /// privacy consequence something they passed through rather than chose,
    /// so Continue stays disabled until a row is tapped.
    @State private var selection: DWIdentityFundingSource?

    /// A funding source was chosen and the flow may move on.
    var onContinue: (DWIdentityFundingSource) -> Void
    /// Send the user off to shield funds first. Only reachable from the
    /// variant below, where there is nothing shielded to spend. `nil` means
    /// the host has nowhere to send them, and the button is disabled rather
    /// than offered and dead.
    var onShieldFunds: (() -> Void)?

    init(
        onContinue: @escaping (DWIdentityFundingSource) -> Void,
        onShieldFunds: (() -> Void)? = nil
    ) {
        self.onContinue = onContinue
        self.onShieldFunds = onShieldFunds
        // The same shared instance the rest of the flow runs on, so the
        // readiness this screen branches on is the one the form will spend.
        _viewModel = StateObject(wrappedValue: CreateUsernameViewModel.shared)
    }

    #if DEBUG
    /// Preview-only entry point, mirroring `JoinDashPayScreen`: a posed view
    /// model so the canvas never builds `CreateUsernameViewModel.shared`.
    init(
        previewViewModel: CreateUsernameViewModel,
        onContinue: @escaping (DWIdentityFundingSource) -> Void = { _ in },
        onShieldFunds: (() -> Void)? = nil
    ) {
        self.onContinue = onContinue
        self.onShieldFunds = onShieldFunds
        _viewModel = StateObject(wrappedValue: previewViewModel)
    }
    #endif

    /// Whether the shielded balance can pay for this registration *now* —
    /// funded, matured and past the pool minimum. Anything less takes the
    /// shield-first variant, whose tip is what explains the wait.
    private var canPayFromShielded: Bool {
        viewModel.hasReadyShieldedFunding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Spacer()
                .frame(maxHeight: 20)

            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Make your username private", comment: "Usernames"))
                        .dashFont(.title1)
                        .foregroundStyle(Color.dash.primaryText)
                        // Both lines wrap rather than truncate: the sheet that
                        // hosts this screen cross-fades its pages in a ZStack,
                        // which proposes an ideal width first, and the title is
                        // wider than the sheet on one line.
                        .fixedSize(horizontal: false, vertical: true)

                    Text(NSLocalizedString("To help keep your payment activity private, we recommend paying for the username from your shielded balance", comment: "Usernames"))
                        .dashFont(.body)
                        .foregroundStyle(Color.dash.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 20)

            if !canPayFromShielded {
                Spacer()
                    .frame(maxHeight: 20)
            }

            if canPayFromShielded {
                fundingOptions
            } else {
                shieldFirstTip
            }

            if canPayFromShielded {
                Spacer()
                    .frame(maxHeight: 20)
            }

            if canPayFromShielded {
                continueButton
            } else {
                shieldFirstButtons
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Shielded funds are spendable: let the user choose

    private var fundingOptions: some View {
        VStack(spacing: 20) {
            DashUIKit.SimpleSelect(
                title: NSLocalizedString("Shielded balance", comment: "Usernames"),
                description: NSLocalizedString("Keeps your username private", comment: "Usernames"),
                isSelected: selection == .shielded,
                action: { selection = .shielded })

            DashUIKit.SimpleSelect(
                title: NSLocalizedString("Dash balance", comment: "Usernames"),
                description: NSLocalizedString("Funds will be traceable to your username", comment: "Usernames"),
                isSelected: selection == .core,
                action: { selection = .core })

            if offersPlatformBalance {
                DashUIKit.SimpleSelect(
                    title: NSLocalizedString("Platform balance", comment: "Usernames"),
                    // With the amount: this is the one balance the user cannot
                    // see anywhere but the advanced-mode breakdown, so "is
                    // there enough in it" is not a question the row can leave
                    // open.
                    description: String.localizedStringWithFormat(
                        NSLocalizedString("Pays from your %@ Dash already on Platform", comment: "Usernames"),
                        viewModel.platformPaymentBalance),
                    isSelected: selection == .platformPayment,
                    action: { selection = .platformPayment })
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 20)
        .onChange(of: offersPlatformBalance) { offers in
            // The mode can be switched off from another screen while this one
            // is up. Leaving the pick on a row that is no longer offered would
            // fund the registration from a balance the user can no longer see.
            if !offers, selection == .platformPayment { selection = nil }
        }
    }

    /// Platform credits are an advanced-mode balance: the mode is what shows
    /// it on Home at all, so paying a username from it is offered only there —
    /// and only when there is enough of it to cover this registration.
    /// The transparent source to record when the user forgoes privacy: Core
    /// when it can cover the registration, Platform credits when only they
    /// can. Core remains the answer when neither can — the form then states
    /// the shortfall against the source the user would expect to use.
    private var transparentSourceThatCanPay: DWIdentityFundingSource {
        if viewModel.hasMinimumRequiredCoreBalance { return .core }
        if viewModel.hasMinimumRequiredPlatformBalance { return .platformPayment }
        return .core
    }

    private var offersPlatformBalance: Bool {
        viewModel.isAdvancedMode && viewModel.hasMinimumRequiredPlatformBalance
    }

    private var continueButton: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Continue", comment: ""),
            isEnabled: selection != nil,
            fillsWidth: true,
            size: .large,
            style: .filledBlue,
            action: {
                guard let selection else { return }
                // Recorded on the shared model, not just handed to the
                // callback: the create form reads it from there, because the
                // route to that form passes through a dispatcher that carries
                // no payload.
                viewModel.chooseFundingSource(selection)
                onContinue(selection)
            }
        )
        .padding(.vertical, 20)
    }

    // MARK: - Nothing shielded to spend: offer to shield first

    /// No picker here on purpose: with nothing spendable behind it, a
    /// "Shielded balance" row would be an option that cannot be taken. The
    /// choice becomes shield-now versus go-without, and the tip carries the
    /// part the user cannot see — that shielding is fast but privacy is not
    /// immediate.
    private var shieldFirstTip: some View {
        DashUIKit.SystemMessageView(
            title: tipTitle,
            subtitle: tipMessage,
            icon: tipIcon,
            backgroundColor: tipBackground
        )
        // The sheet sizes itself to what it measures, and hands the content
        // back that same height — so anything that can be squeezed settles
        // squeezed. The message must report its full height instead, or a
        // three-line tip renders as two and an ellipsis.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 20)
    }

    /// The readiness state this screen is explaining. `.ready` never reaches
    /// here — `canPayFromShielded` takes the picker branch instead — so the
    /// three blockers below are the whole vocabulary: no funds yet, funds
    /// still resting, or a shared pool under the consensus minimum. They are
    /// the rows the retired "Get ready to join DashPay" checklist showed.
    private var readinessState: ShieldedIdentityFundingReadiness.State? {
        viewModel.shieldedReadiness?.state
    }

    private var tipTitle: String {
        switch readinessState {
        case .maturing:
            return NSLocalizedString("Funds are resting", comment: "Usernames")
        case .poolTooSmall:
            return NSLocalizedString("Privacy pool too small", comment: "Usernames")
        case .needsFunding where shieldedCredits > 0:
            // Something IS shielded, just not enough: a generic privacy tip
            // reads as "nothing happened" to someone who just shielded funds.
            return NSLocalizedString("Not enough shielded funds", comment: "Usernames")
        default:
            return NSLocalizedString("Privacy tip", comment: "Usernames")
        }
    }

    /// What the wallet holds shielded, in credits. Drives whether the funding
    /// blocker is "you have none" or "you have some, but short".
    private var shieldedCredits: UInt64 {
        viewModel.shieldedReadiness?.unspentCredits ?? 0
    }

    /// What a private registration for this name costs, in credits: 0.1 DASH
    /// for a standard name, 0.25 for a contested one.
    private var requiredCredits: UInt64 {
        viewModel.shieldedReadiness?.requiredCredits
            ?? ShieldedIdentityFundingReadiness.standardDenominationCredits
    }

    /// Credits → the DASH text the rest of the flow prints (÷1000 to duffs).
    private static func dashText(_ credits: UInt64) -> String {
        (credits / 1_000).dashAmount.formattedDashAmountWithoutCurrencySymbol
    }

    private var tipIcon: DashIconSource {
        switch readinessState {
        case .maturing:
            // The message is about when, not about what to do.
            return DashIcon.SystemMessage.timerSmall.source
        case .poolTooSmall:
            return DashIcon.SystemMessage.warningTriangle.source
        default:
            return DashIcon.SystemMessage.infoRectSmall.source
        }
    }

    /// Only the pool blocker is styled as a warning: it is the one state the
    /// user cannot clear by doing anything in this wallet.
    private var tipBackground: Color {
        if case .poolTooSmall = readinessState {
            return Color.dash.orangeAlpha10
        }

        return Color.dash.blueAlpha5
    }

    /// Each blocker says what is missing and, where the wallet knows it, the
    /// number behind it: the readiness snapshot carries the actual `readyAt`
    /// minute and the actual pool count, so neither has to be vague.
    private var tipMessage: String {
        switch readinessState {
        case .maturing(let readyAt):
            let time = DateFormatter.localizedString(from: readyAt, dateStyle: .none, timeStyle: .short)
            return String.localizedStringWithFormat(
                NSLocalizedString("Your shielded funds are resting. They will be ready around %@ — creating your username before then links it to where the funds came from.", comment: "Usernames"),
                time)

        case .poolTooSmall(let current):
            // Shielding more of your own funds does not move this number, so
            // the copy says what the wait is actually on.
            return String.localizedStringWithFormat(
                NSLocalizedString("The shared privacy pool holds %@ of the %@ notes a private registration needs. That count comes from everyone's shielded activity, so it grows on its own — try again later.", comment: "Usernames"),
                Self.noteCount(current),
                Self.noteCount(ShieldedIdentityFundingReadiness.minimumPoolNotes))

        case .needsFunding(let shortfallCredits) where shieldedCredits > 0:
            // The case this screen used to answer with silence: funds were
            // shielded, the screen looked identical, and nothing said how
            // much was still missing.
            return String.localizedStringWithFormat(
                NSLocalizedString("Your shielded balance holds %@ of the %@ Dash a private registration needs. Add %@ Dash more, then let it rest a few hours.", comment: "Usernames"),
                Self.dashText(shieldedCredits),
                Self.dashText(requiredCredits),
                Self.dashText(shortfallCredits))

        default:
            // Nothing shielded yet (or no snapshot at all): name the amount
            // rather than only the wait.
            return String.localizedStringWithFormat(
                NSLocalizedString("Paying privately takes at least %@ Dash in your shielded balance. Funds move there in seconds, then rest a few hours before they can pay for a username.", comment: "Usernames"),
                Self.dashText(requiredCredits))
        }
    }

    private static func noteCount(_ value: UInt64) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    /// Shielding helps only when funds are what is missing. While they rest,
    /// or while the shared pool is short, the button would send the user off
    /// to do something that changes nothing — so it is offered disabled
    /// rather than acted on and silently wasted.
    private var canShieldFundsNow: Bool {
        guard onShieldFunds != nil else { return false }

        switch readinessState {
        case .maturing, .poolTooSmall:
            return false
        default:
            return true
        }
    }

    private var shieldFirstButtons: some View {
        VStack(spacing: 20) {
            DashUIKit.DashButton(
                text: NSLocalizedString("Shield your funds first", comment: "Usernames"),
                isEnabled: canShieldFundsNow,
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: { onShieldFunds?() }
            )

            // Transparent funding is the way forward when shielded funds are
            // not spendable, so the choice is recorded rather than left unset —
            // but it is recorded as a source that can actually pay. Naming
            // `.core` for a wallet whose Core balance is short pinned the form
            // to a source it had to refuse.
            DashUIKit.DashButton(
                text: NSLocalizedString("Continue without privacy", comment: "Usernames"),
                fillsWidth: true,
                size: .large,
                style: .tintedBlue,
                action: {
                    let source = transparentSourceThatCanPay
                    viewModel.chooseFundingSource(source)
                    onContinue(source)
                }
            )

            // Platform credits are a third way forward, and this variant used
            // to state there were only two. It matters because the form no
            // longer offers a funding choice of its own: without this button an
            // advanced-mode wallet holding Platform credits but nothing
            // shielded would be walked into Core funding it never picked.
            if offersPlatformBalance {
                DashUIKit.DashButton(
                    text: String.localizedStringWithFormat(
                        NSLocalizedString("Pay from Platform balance (%@ Dash)", comment: "Usernames"),
                        viewModel.platformPaymentBalance),
                    fillsWidth: true,
                    size: .large,
                    style: .tintedGray,
                    action: {
                        viewModel.chooseFundingSource(.platformPayment)
                        onContinue(.platformPayment)
                    }
                )
            }
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Previews

#if DEBUG

/// Shielded funds are spendable: both rows offered, nothing chosen yet, so
/// Continue is greyed out.
#Preview("Shielded ready — nothing picked") {
    UsernameFundingPrivacyScreen(
        previewViewModel: .makeForPreview(
            balance: "0.30999774",
            hasMinimumRequiredBalance: true,
            shieldedReadiness: ShieldedIdentityFundingReadiness.Snapshot(
                state: .ready,
                requiredCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                matureCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                unspentCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                poolNoteCount: 8)))
        .background(Color.dash.primaryBackground)
}

/// Nothing shielded to spend: the picker gives way to the tip and the
/// shield-first pair. Shielding is exactly what is missing, so the button is
/// live (the host passes `onShieldFunds`).
#Preview("Nothing shielded — shield first") {
    UsernameFundingPrivacyScreen(
        previewViewModel: .makeForPreview(
            balance: "0.30999774",
            hasMinimumRequiredBalance: true),
        onShieldFunds: {})
        .background(Color.dash.primaryBackground)
}

/// Some funds are shielded, but not the whole denomination — the state that
/// used to look identical to having shielded nothing at all.
#Preview("Partly shielded — 0.01 of 0.1") {
    UsernameFundingPrivacyScreen(
        previewViewModel: .makeForPreview(
            balance: "0.29786659",
            hasMinimumRequiredBalance: true,
            shieldedReadiness: ShieldedIdentityFundingReadiness.Snapshot(
                state: .needsFunding(shortfallCredits: 9_000_000_000),
                requiredCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                matureCredits: 0,
                unspentCredits: 1_000_000_000,
                poolNoteCount: 400)),
        onShieldFunds: {})
        .background(Color.dash.primaryBackground)
}

/// Funds are in but still resting — the timer tip names the minute they are
/// ready, and shielding more would not shorten it, so that button is off.
#Preview("Funds resting — wait it out") {
    UsernameFundingPrivacyScreen(
        previewViewModel: .makeForPreview(
            balance: "0.30999774",
            hasMinimumRequiredBalance: true,
            shieldedReadiness: ShieldedIdentityFundingReadiness.Snapshot(
                state: .maturing(readyAt: Date().addingTimeInterval(2 * 60 * 60)),
                requiredCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                matureCredits: 0,
                unspentCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                poolNoteCount: 400)),
        onShieldFunds: {})
        .background(Color.dash.primaryBackground)
}

/// The one blocker the user cannot clear from this wallet: the shared pool is
/// under the consensus minimum. Warning styling, real counts, shield-first off.
#Preview("Privacy pool too small") {
    UsernameFundingPrivacyScreen(
        previewViewModel: .makeForPreview(
            balance: "0.30999774",
            hasMinimumRequiredBalance: true,
            shieldedReadiness: ShieldedIdentityFundingReadiness.Snapshot(
                state: .poolTooSmall(current: 180),
                requiredCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                matureCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                unspentCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                poolNoteCount: 180)),
        onShieldFunds: {})
        .background(Color.dash.primaryBackground)
}

#endif
