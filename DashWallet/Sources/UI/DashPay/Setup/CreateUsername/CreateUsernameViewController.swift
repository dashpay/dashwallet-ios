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

import UIKit
import SwiftUI
import DashUIKit

class CreateUsernameViewController: UIViewController {
    @objc var completionHandler: ((Bool) -> ())?

    /// Set before presentation by the readiness-interstitial `onProceed`
    /// paths: the user has already been through the shielded checklist
    /// (or its explicit transparent escape), so the form skips the
    /// Private registration teaser. Read once in `viewDidLoad`.
    @objc var suppressShieldedHint: Bool = false

    /// Normalized invitation URI (see `DWInvitationLinkNormalizer`)
    /// when this form is claiming a DIP-13 invitation; nil for the
    /// regular self-funded registration.
    private let invitationURI: String?
    private let definedUsername: String?

    @objc
    init(dashPayModel: DWDashPayProtocol, invitationURL: URL?, definedUsername: String?) {
        // `dashPayModel` is part of the Obj-C navigation contract but
        // the SwiftUI flow drives registration straight through
        // `DWIdentityRegistrationBridge` / the coordinator, so it is
        // not stored here.
        self.invitationURI = invitationURL?.absoluteString
        self.definedUsername = definedUsername
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor.dw_secondaryBackground()

        let content = CreateUsernameView(
            invitationURI: invitationURI,
            definedUsername: definedUsername,
            suppressShieldedHint: suppressShieldedHint
        ) {
            let navigationController = self.navigationController
            #if DASHPAY
            let mainTabController = self.tabBarController as? MainTabbarController
            #endif
            navigationController?.popViewController(animated: true)
            self.completionHandler?(true)
            #if DASHPAY
            if let transitionCoordinator = navigationController?.transitionCoordinator {
                transitionCoordinator.animate(alongsideTransition: nil) { _ in
                    mainTabController?.applyPendingDashPayTabReconfiguration()
                }
            } else {
                mainTabController?.applyPendingDashPayTabReconfiguration()
            }
            #endif
        }
        let swiftUIController = UIHostingController(rootView: content)
        swiftUIController.view.backgroundColor = UIColor.dw_secondaryBackground()
        self.dw_embedChild(swiftUIController)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.applyOpaqueAppearance(with: UIColor.dw_secondaryBackground(), shadowColor: .clear)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}

struct CreateUsernameView: View {
    @StateObject private var viewModel = CreateUsernameViewModel()
    @FocusState private var isTextInputFocused: Bool
    @State private var inProgress: Bool = false
    @State private var screenLockedAfterAuth: Bool = false
    /// Funding source for the SwiftDashSDK identity registration.
    /// Auto-pinned by `syncFundingSourceToViableSource()` to the first
    /// viable source in privacy-descending order (Shielded → Platform →
    /// Core) until the user explicitly picks one; user-selectable via
    /// the segmented picker when two or more sources qualify. Written
    /// into `DWIdentityRegistrationBridge.shared.preferredFundingSource`
    /// in the Continue handler right before the submit call.
    @State private var fundingSource: DWIdentityFundingSource = .core
    /// True once the user has manually changed the picker; auto-pinning
    /// then only corrects a selection that became non-viable, instead
    /// of overriding the user's explicit choice.
    @State private var didUserPickFundingSource: Bool = false
    /// Tracks the contested-name confirmation alert. Continue routes
    /// through this alert (instead of submitting directly) when the
    /// typed name is contested-eligible — `viewModel.isContestedCandidate`.
    @State private var showContestedConfirmation: Bool = false
    /// Tracks the buy-listed-name confirmation alert; the button routes
    /// here when `viewModel.canPurchaseListedNameDirectly`.
    @State private var showPurchaseConfirmation: Bool = false
    /// Terminal success alert of a direct listing purchase; OK finishes
    /// the flow like a completed registration.
    @State private var showPurchaseSuccess: Bool = false
    /// Drives the success alert shown when registration reaches the
    /// terminal `.completed` phase. OK dismisses the screen.
    @State private var showSuccess: Bool = false
    @State private var showVotingSubmitted: Bool = false
    /// Non-nil drives the error alert; holds the coordinator's
    /// human-readable failure message. OK clears it and keeps the
    /// screen up so the user can edit or retry.
    @State private var registrationErrorMessage: String? = nil
    /// Post-claim contact-request failure. The username IS registered
    /// at this point — the alert reports the failed request and its OK
    /// finishes the flow (the request is re-sendable from Contacts).
    @State private var inviterContactErrorMessage: String? = nil
    /// Normalized invitation URI when claiming (invitation mode); nil
    /// for the regular self-funded registration.
    var invitationURI: String? = nil
    /// Username prefill carried by the deep link (`definedUsername`).
    var definedUsername: String? = nil
    /// True when the user arrived through the readiness interstitial —
    /// they either chose the explicit "Use transparent balance instead"
    /// escape or already worked through the shielded checklist there,
    /// so the form must not re-tease private registration.
    var suppressShieldedHint: Bool = false
    var finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("Create your username", comment: "Usernames"))
                .foregroundColor(.dash.primaryText)
                .font(.title1)
                .padding(.top, 12)
            Text(NSLocalizedString("Please note that you will not be able to change it in future", comment: "Usernames"))
                .foregroundColor(.dash.primaryText)
                .font(.system(size: 14))
            TextInput(label: "Username", text: $viewModel.username, isEnabled: !screenLockedAfterAuth)
                .padding(.top, 20)
                .focused($isTextInputFocused)
                .disabled(screenLockedAfterAuth)
                
            if viewModel.uiState.lengthRule != .hidden {
                ValidationCheck(
                    validationResult: viewModel.uiState.lengthRule,
                    text: NSLocalizedString("Between 3 and 23 characters", comment: "Usernames")
                ).padding(.top, 20)
            }
            
            if viewModel.uiState.allowedCharactersRule != .hidden {
                ValidationCheck(
                    validationResult: viewModel.uiState.allowedCharactersRule,
                    text: NSLocalizedString("Letter, numbers and hyphens only", comment: "Usernames")
                ).padding(.top, 20)
            }
            
            if viewModel.uiState.costRule != .hidden {
                ValidationCheck(
                    validationResult: viewModel.uiState.costRule,
                    text: String.localizedStringWithFormat(NSLocalizedString("You need to have more %@ Dash to create this username", comment: "Usernames"), viewModel.uiState.requiredDash.dashAmount.formattedDashAmountWithoutCurrencySymbol)
                ).padding(.top, 20)
            }
            
            if viewModel.uiState.usernameBlockedRule != .hidden {
                ValidationCheck(
                    validationResult: viewModel.uiState.usernameBlockedRule,
                    text: getMessageForBlockedRule()
                ).padding(.top, 20)
            }

            // Contested-name warning. Shown when the typed label is
            // ≤19 chars + only [a-zA-Z0-9-] AND otherwise passes the
            // local validators — EXCEPT when the name is plainly taken:
            // an owned name will never go to a vote, so the warning
            // would contradict the "taken" row (`showContestedWarning`).
            // Submitting a contested name triggers masternode voting
            // (~45 min testnet, ~2 weeks mainnet) before the name is
            // actually claimed — the user gets a separate confirmation
            // alert on Continue. Mirrors the example app's
            // `RegisterNameView.swift:277-293` styling.
            if viewModel.showContestedWarning {
                contestedNameWarning
                    .padding(.top, 20)
            }

            // Taken-but-listed pointer: the owner has put the name up for
            // sale in the Username Marketplace, so "taken" isn't the end
            // of the road — affordable listings under the direct-purchase
            // ceiling are buyable right here via the Buy button below.
            if let salePriceCredits = viewModel.takenNameSalePriceCredits {
                forSaleHint(priceCredits: salePriceCredits)
                    .padding(.top, 20)
            }

            if viewModel.hasPendingRegistrationRecovery {
                registrationRecoveryBanner
                    .padding(.top, 20)
            }

            // Invitation-claim mode: the voucher funds the registration,
            // so the shielded readiness hint and the funding-source
            // picker below don't apply and stay hidden. A short banner
            // states the funding instead.
            if viewModel.isInvitationMode {
                invitationFundingBanner
                    .padding(.top, 20)
            }

            // Shielded readiness hint. Shown while the privacy-preserving
            // funding path is NOT yet available (needs funds / maturing /
            // pool below the consensus minimum) so the user learns what
            // the wait is for without being blocked — the transparent
            // sources below remain an explicit choice. Suppressed when the
            // user already answered this question on the readiness
            // interstitial (`suppressShieldedHint`).
            if !viewModel.isInvitationMode,
               !viewModel.hasPendingRegistrationRecovery,
               !suppressShieldedHint {
                shieldedReadinessHint
            }

            // Funding source picker. Visible when two or more sources
            // can cover the identity-registration cost. When only one
            // is viable, the picker stays hidden and `fundingSource` is
            // auto-pinned by `syncFundingSourceToViableSource()` so the
            // Continue handler routes correctly without UI clutter.
            if !viewModel.isInvitationMode,
               !viewModel.hasPendingRegistrationRecovery,
               viableFundingSources.count >= 2 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Pay with", comment: "Usernames"))
                        .foregroundColor(.dash.secondaryText)
                        .font(.caption)
                    Picker("", selection: userFundingSourceBinding) {
                        ForEach(viableFundingSources, id: \.rawValue) { source in
                            Text(fundingSourceLabel(source)).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(screenLockedAfterAuth)
                    fundingPrivacyFootnote
                }
                .padding(.top, 20)
            }

            Spacer()

            DashButton(
                text: primaryButtonText,
                isEnabled: (viewModel.uiState.canContinue || viewModel.canPurchaseListedNameDirectly)
                    && !screenLockedAfterAuth,
                isLoading: inProgress
            ) {
                // `viewModel.uiState.canContinue` is only true after
                // `checkIfBlocked` flips `usernameBlockedRule` to
                // `.valid`, so the registration branches are gated on the
                // same condition. A taken-but-listed name never reaches
                // `.valid`; its buyable state enables the button through
                // `canPurchaseListedNameDirectly` and routes to the
                // purchase confirmation instead.
                //
                // Contested-name submissions go through a confirmation
                // alert first so the user explicitly acknowledges the
                // ~45 min testnet / ~2 weeks mainnet voting wait and
                // the locked Dash. Non-contested names submit directly.
                if viewModel.canPurchaseListedNameDirectly {
                    showPurchaseConfirmation = true
                } else if viewModel.isContestedCandidate {
                    showContestedConfirmation = true
                } else {
                    performSubmit()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            isTextInputFocused = true
            viewModel.refreshRegistrationRecoveryState()
            if let invitationURI {
                viewModel.configureInvitationMode(uri: invitationURI)
            }
            if let definedUsername, !definedUsername.isEmpty, viewModel.username.isEmpty {
                viewModel.username = definedUsername
            }
            // Seed the picker selection so a wallet with only one
            // viable source (typical case) doesn't default to a
            // non-viable Core path.
            syncFundingSourceToViableSource()
        }
        .onChange(of: viewModel.hasMinimumRequiredCoreBalance) { _ in
            syncFundingSourceToViableSource()
        }
        .onChange(of: viewModel.hasMinimumRequiredPlatformBalance) { _ in
            syncFundingSourceToViableSource()
        }
        .onChange(of: viewModel.shieldedReadiness) { _ in
            syncFundingSourceToViableSource()
        }
        .onChange(of: viewModel.hasPendingRegistrationRecovery) { _ in
            syncFundingSourceToViableSource()
        }
        .alert(
            NSLocalizedString("Contested name", comment: "Usernames"),
            isPresented: $showContestedConfirmation
        ) {
            Button(NSLocalizedString("Submit anyway", comment: "Usernames"), role: .destructive) {
                // The alert can sit open across the join-window boundary.
                // Re-check at the moment of confirmation: a submission the
                // network would refuse is replaced by a fresh availability
                // answer (which shows the join-closed state) instead of a
                // broadcast failure.
                if viewModel.activeContestContenders != nil, viewModel.activeContestJoinClosed {
                    showContestedConfirmation = false
                    viewModel.refreshRegistrationRecoveryState()
                    return
                }
                performSubmit()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            // The join-the-vote wording only holds while the join window is
            // still open; past it (or with no known contest) the generic
            // contested message is the honest one.
            Text(viewModel.activeContestContenders != nil && !viewModel.activeContestJoinClosed
                ? NSLocalizedString(
                    "A vote for this name is already in progress — your request will join it as a contender. Your Dash will be locked until voting completes.",
                    comment: "Usernames")
                : NSLocalizedString(
                    "This name requires voting. Your Dash will be locked until voting completes.",
                    comment: "Usernames"))
        }
        .alert(
            NSLocalizedString("Buy username", comment: "Usernames"),
            isPresented: $showPurchaseConfirmation
        ) {
            Button(NSLocalizedString("Buy", comment: "")) {
                performPurchase()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(String.localizedStringWithFormat(
                NSLocalizedString(
                    "“%1$@” will be purchased for %2$@ Dash. The price is paid from your wallet balance.",
                    comment: "Usernames"),
                viewModel.username,
                ((viewModel.takenNameSalePriceCredits ?? 0) / 1_000).dashAmount.formattedDashAmountWithoutCurrencySymbol))
        }
        .alert(
            NSLocalizedString("Username purchased", comment: "Usernames"),
            isPresented: $showPurchaseSuccess
        ) {
            Button(NSLocalizedString("OK", comment: "")) { finish() }
        } message: {
            Text(String.localizedStringWithFormat(
                NSLocalizedString("“%@” is now your username.", comment: "Usernames"),
                viewModel.username))
        }
        .alert(
            NSLocalizedString("Username registered", comment: "Usernames"),
            isPresented: $showSuccess
        ) {
            if let inviter = viewModel.invitationInviterUsername {
                // Invitation claim with a known inviter: offer the
                // contact-bootstrap (mirrors Android, where the request
                // is sent after registration; here the user opts in).
                Button(String.localizedStringWithFormat(
                    NSLocalizedString("Add %@ as a contact", comment: "DashPay Invitations"),
                    inviter)) {
                    sendInviterContactRequest(inviter)
                }
                Button(NSLocalizedString("Not now", comment: ""), role: .cancel) { finish() }
            } else {
                Button(NSLocalizedString("OK", comment: "")) { finish() }
            }
        } message: {
            if viewModel.invitationInviterUsername != nil {
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("“%@” has been registered. Send a contact request to the person who invited you?", comment: "DashPay Invitations"),
                    viewModel.username))
            } else {
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("“%@” has been registered.", comment: "Usernames"),
                    viewModel.username))
            }
        }
        .alert(
            NSLocalizedString("Username submitted", comment: "Usernames"),
            isPresented: $showVotingSubmitted
        ) {
            Button(NSLocalizedString("OK", comment: "")) { finish() }
        } message: {
            Text(votingSubmittedMessage)
        }
        .alert(
            NSLocalizedString("Contact request failed", comment: "DashPay Invitations"),
            isPresented: Binding(
                get: { inviterContactErrorMessage != nil },
                set: { if !$0 { inviterContactErrorMessage = nil; finish() } }
            )
        ) {
            Button(NSLocalizedString("OK", comment: "")) {
                inviterContactErrorMessage = nil
                finish()
            }
        } message: {
            Text(inviterContactErrorMessage ?? "")
        }
        .alert(
            NSLocalizedString("Registration failed", comment: "Usernames"),
            isPresented: Binding(
                get: { registrationErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        registrationErrorMessage = nil
                        screenLockedAfterAuth = false
                    }
                }
            )
        ) {
            Button(NSLocalizedString("OK", comment: "")) {
                registrationErrorMessage = nil
                screenLockedAfterAuth = false
            }
        } message: {
            Text(registrationErrorMessage ?? "")
        }
    }

    private var registrationRecoveryBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundColor(.dash.blue)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString(
                    "Finish your registration",
                    comment: "DashPay registration recovery"))
                    .font(.subheadline.bold())
                    .foregroundColor(.dash.primaryText)
                Text(NSLocalizedString(
                    "Your previous payment was found. Continue to finish creating the identity and username without paying again.",
                    comment: "DashPay registration recovery"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dash.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Blue informational callout shown while the shielded funding
    /// path is not yet available, explaining which gate is unmet and
    /// what will unlock it. Purely informative — the transparent
    /// sources stay selectable.
    @ViewBuilder
    private var shieldedReadinessHint: some View {
        if let snapshot = viewModel.shieldedReadiness, snapshot.state != .ready {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.blue)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Private registration", comment: "Usernames"))
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)
                    Text(shieldedHintText(for: snapshot))
                        .font(.caption)
                        .foregroundColor(.dash.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dash.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.top, 20)
        }
    }

    private func shieldedHintText(for snapshot: ShieldedIdentityFundingReadiness.Snapshot) -> String {
        switch snapshot.state {
        case .needsFunding(let shortfallCredits):
            // Credits → duffs (÷1000) for display.
            let shortfallDash = (shortfallCredits / 1_000).dashAmount.formattedDashAmountWithoutCurrencySymbol
            return String.localizedStringWithFormat(
                NSLocalizedString("Add %@ Dash to your Shielded balance and let it rest a few hours to register without linking your username to your other funds.", comment: "Usernames"),
                shortfallDash)
        case .maturing(let readyAt):
            let time = DateFormatter.localizedString(from: readyAt, dateStyle: .none, timeStyle: .short)
            return String.localizedStringWithFormat(
                NSLocalizedString("Your Shielded balance is almost ready — you can register privately around %@.", comment: "Usernames"),
                time)
        case .poolTooSmall(let current):
            return String.localizedStringWithFormat(
                NSLocalizedString("The shared privacy pool is still growing (%ld of %ld deposits). Private registration unlocks once it reaches the minimum.", comment: "Usernames"),
                Int(current), Int(ShieldedIdentityFundingReadiness.minimumPoolNotes))
        case .ready:
            return ""
        }
    }

    /// Primary button label: registration recovery > direct listing
    /// purchase (priced) > plain Continue.
    private var primaryButtonText: String {
        if viewModel.hasPendingRegistrationRecovery {
            return NSLocalizedString("Finish registration", comment: "DashPay registration recovery")
        }
        if viewModel.canPurchaseListedNameDirectly,
           let credits = viewModel.takenNameSalePriceCredits {
            return String.localizedStringWithFormat(
                NSLocalizedString("Buy for %@ Dash", comment: "Usernames"),
                (credits / 1_000).dashAmount.formattedDashAmountWithoutCurrencySymbol)
        }
        return NSLocalizedString("Continue", comment: "")
    }

    /// Deadline as "Today 20:33"-style text (DWDateFormatter's relative
    /// short date + time). Testnet contest windows are minutes long, so
    /// the time matters; a locale-formatted full date alone would bury it.
    private static func contestDeadlineText(_ date: Date) -> String {
        let formatter = DWDateFormatter.sharedInstance
        return "\(formatter.shortStringFromDate(date)) \(formatter.timeOnly(from: date))"
    }

    /// Orange warning callout shown above the Continue button when
    /// the typed name is contested-eligible. Styled to match the
    /// example app's `RegisterNameView.swift:277-293`. When the view
    /// model reports a vote already running for this name
    /// (`activeContestContenders`), the copy switches from "requires
    /// a vote" to "a vote is in progress — a request joins it", with
    /// the deadline when the network reports one; past the deadline
    /// it reports the vote as ended and finalizing instead.
    private var contestedNameWarning: some View {
        let voteInProgress = viewModel.activeContestContenders != nil
        let title: String
        let body: String
        if voteInProgress, viewModel.activeContestHasEnded {
            title = NSLocalizedString("Vote ended", comment: "Usernames")
            body = NSLocalizedString(
                "The masternode vote for this name has ended and the result is being finalized. Check back soon.",
                comment: "Usernames")
        } else if voteInProgress, let endsAt = viewModel.activeContestEndsAt, viewModel.activeContestJoinClosed {
            title = NSLocalizedString("Vote in progress", comment: "Usernames")
            body = String.localizedStringWithFormat(
                NSLocalizedString(
                    "A masternode vote for this name is in progress — voting ends around %@. New contenders can no longer join this vote.",
                    comment: "Usernames"),
                Self.contestDeadlineText(endsAt))
        } else if voteInProgress, let endsAt = viewModel.activeContestEndsAt {
            title = NSLocalizedString("Vote in progress", comment: "Usernames")
            body = String.localizedStringWithFormat(
                NSLocalizedString(
                    "A masternode vote for this name is already in progress — voting ends around %@. Submitting a request joins the vote as a contender.",
                    comment: "Usernames"),
                Self.contestDeadlineText(endsAt))
        } else if voteInProgress {
            title = NSLocalizedString("Vote in progress", comment: "Usernames")
            body = NSLocalizedString(
                "A masternode vote for this name is already in progress. Submitting a request joins the vote as a contender.",
                comment: "Usernames")
        } else {
            title = NSLocalizedString("Contested name", comment: "Usernames")
            body = NSLocalizedString(
                "This name requires a masternode vote.",
                comment: "Usernames")
        }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: voteInProgress ? "person.2.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                Text(body)
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Blue informational callout when the typed name is taken but its
    /// owner has listed it in the Username Marketplace. Three variants:
    /// buyable right here (under the ceiling, wallet covers it), listed
    /// at or above the direct-purchase ceiling (pointed at the
    /// marketplace, with the suggestion to pick another name for now),
    /// or listed but not currently affordable (plain pointer).
    private func forSaleHint(priceCredits: UInt64) -> some View {
        let priceText = (priceCredits / 1_000).dashAmount.formattedDashAmountWithoutCurrencySymbol
        let body: String
        if viewModel.canPurchaseListedNameDirectly {
            body = String.localizedStringWithFormat(
                NSLocalizedString(
                    "The owner of this username has listed it for %@ Dash. You can buy it right now — the price is paid from your wallet balance.",
                    comment: "Usernames"),
                priceText)
        } else if viewModel.listedNameExceedsDirectPurchaseLimit {
            body = String.localizedStringWithFormat(
                NSLocalizedString(
                    "The owner of this username has listed it for %1$@ Dash. Purchases over %2$@ Dash must be made from the Username Marketplace — choose another username for now; you can decide on buying this one later.",
                    comment: "Usernames"),
                priceText,
                CreateUsernameViewModel.directPurchaseMaxDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)
        } else {
            body = String.localizedStringWithFormat(
                NSLocalizedString(
                    "The owner of this username has listed it in the Username Marketplace for %@ Dash. You can buy it there instead.",
                    comment: "Usernames"),
                priceText)
        }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tag.fill")
                .foregroundColor(.dash.blue)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("For sale", comment: "Usernames"))
                    .font(.subheadline.bold())
                    .foregroundColor(.dash.blue)
                Text(body)
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dash.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Invitation-claim funding banner (invitation mode only).
    private var invitationFundingBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "envelope.open")
                .foregroundColor(.dash.blue)
                .font(.system(size: 20))
            Text(NSLocalizedString("Your invitation pays the registration fee for this username.", comment: "DashPay Invitations"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dash.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Post-claim contact-bootstrap: resolve the `du` inviter and send
    /// them a request. The username is already registered — a failure
    /// here is reported (and re-sendable from Contacts) but never
    /// unwinds the claim.
    private func sendInviterContactRequest(_ inviter: String) {
        Task {
            inProgress = true
            defer { inProgress = false }
            do {
                try await DWInvitationService.shared.sendContactRequestToInviter(username: inviter)
                finish()
            } catch {
                inviterContactErrorMessage = error.localizedDescription
            }
        }
    }

    /// Buy the listed name at its captured price. Mirrors
    /// `performSubmit`'s spinner discipline: `inProgress` keeps the
    /// screen alive across the PIN gate, funding, and the purchase
    /// itself; the outcome drives the purchase-success / error alert.
    private func performPurchase() {
        Task {
            inProgress = true
            screenLockedAfterAuth = false
            let outcome = await viewModel.purchaseListedUsername()
            inProgress = false
            switch outcome {
            case .success:
                showPurchaseSuccess = true
            case .cancelled:
                break
            case .failure(let message):
                registrationErrorMessage = message
            case .submittedForVoting:
                // A purchase never enters a vote; the outcome enum is
                // shared with registration, this arm is unreachable.
                break
            }
        }
    }

    /// Encapsulates the submit-to-bridge dance so both the direct
    /// Continue path and the contested-name alert's "Submit anyway"
    /// button can share the code. Writes the funding-source pick
    /// into the bridge right before submit. The bridge resets to
    /// `.core` on every terminal phase, so a stale picker value
    /// can't leak into a future attempt; this single write is the
    /// only synchronization needed.
    private func performSubmit() {
        if !viewModel.isInvitationMode {
            DWIdentityRegistrationBridge.shared.preferredFundingSource =
                viewModel.hasPendingRegistrationRecovery ? .core : fundingSource
        }
        Task {
            // `inProgress` keeps the Continue spinner up — and the screen
            // alive — across the PIN gate and the whole registration. The
            // bridge completion resolves the outcome at the terminal phase.
            inProgress = true
            screenLockedAfterAuth = false
            let outcome = await viewModel.submitUsernameRequest {
                isTextInputFocused = false
                screenLockedAfterAuth = true
            }
            inProgress = false

            switch outcome {
            case .success:
                showSuccess = true
            case .submittedForVoting:
                showVotingSubmitted = true
            case .cancelled:
                screenLockedAfterAuth = false
                break // user backed out of the PIN — stay on screen, allow retry
            case .failure(let message):
                registrationErrorMessage = message
            }
        }
    }

    /// Post-submit copy for a contested name. The deadline is a conservative
    /// submission-time estimate until Platform indexes the contest and
    /// `checkPendingContestResolution` swaps in `ContestVoteState.endTime`,
    /// hence "around". Falls back to the date-less wording when no pending
    /// bookmark exists rather than inventing a deadline.
    private var votingSubmittedMessage: String {
        guard let endTime = DWContestedNameStatusService.shared.pendingVotingEndTime else {
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "“%@” has been submitted for voting. It is not registered to you yet. We will notify you when voting ends.",
                    comment: "Usernames"),
                viewModel.username)
        }
        return String.localizedStringWithFormat(
            NSLocalizedString(
                "“%1$@” has been submitted for voting. It is not registered to you yet. Voting ends around %2$@ — we will notify you with the result.",
                comment: "Usernames"),
            viewModel.username,
            DWDateFormatter.sharedInstance.dateAndTime(from: endTime))
    }

    /// Viable funding sources in privacy-descending priority order.
    /// Shielded leads: it is the default whenever its readiness gates
    /// (funding, maturity, pool minimum) all pass.
    private var viableFundingSources: [DWIdentityFundingSource] {
        var sources: [DWIdentityFundingSource] = []
        if viewModel.hasReadyShieldedFunding {
            sources.append(.shielded)
        }
        if viewModel.hasMinimumRequiredPlatformBalance {
            sources.append(.platformPayment)
        }
        if viewModel.hasMinimumRequiredCoreBalance {
            sources.append(.core)
        }
        return sources
    }

    /// Picker binding that records an explicit user pick, so the
    /// auto-pinning in `syncFundingSourceToViableSource()` stops
    /// overriding the selection. Programmatic assignments write
    /// `fundingSource` directly and deliberately bypass this.
    private var userFundingSourceBinding: Binding<DWIdentityFundingSource> {
        Binding(
            get: { fundingSource },
            set: { newValue in
                didUserPickFundingSource = true
                fundingSource = newValue
            })
    }

    private func fundingSourceLabel(_ source: DWIdentityFundingSource) -> String {
        switch source {
        case .shielded:
            return "Shielded (\(viewModel.shieldedBalance) Dash)"
        case .platformPayment:
            return "Platform (\(viewModel.platformPaymentBalance) Dash)"
        case .core:
            return "Core (\(viewModel.balance) Dash)"
        case .invitation:
            // Never user-pickable — `viableFundingSources` never
            // contains it and the picker is hidden in invitation mode.
            return ""
        }
    }

    /// One-line privacy consequence of the current pick, shown under
    /// the picker whenever it is visible.
    private var fundingPrivacyFootnote: some View {
        Text(fundingSource == .shielded
            ? NSLocalizedString("Funded from your Shielded balance — your username can't be linked to your other Dash.", comment: "Usernames")
            : NSLocalizedString("Transparent funding publicly links your username to these funds.", comment: "Usernames"))
            .font(.caption2)
            .foregroundColor(.dash.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Keep `fundingSource` pointing at a viable source. Until the
    /// user explicitly picks one, pin to the highest-priority viable
    /// source (Shielded → Platform → Core); after an explicit pick,
    /// only correct a selection that is no longer viable.
    private func syncFundingSourceToViableSource() {
        let viable = viableFundingSources
        guard let preferred = viable.first else {
            // Nothing viable — leave the selection alone; the Continue
            // button is disabled by the cost rule anyway.
            return
        }
        if !viable.contains(fundingSource) || !didUserPickFundingSource {
            fundingSource = preferred
        }
    }

    private func getMessageForBlockedRule() -> String {
        // States set by `CreateUsernameViewModel.checkIfBlocked` (the real
        // debounced DPNS availability check). The first four strings reuse
        // the exact legacy literals from DWCheckExistenceUsernameValidationRule
        // so translations stay unified.
        switch viewModel.uiState.usernameBlockedRule {
        case .loading:
            return NSLocalizedString("Validating username…", comment: "Usernames")
        case .valid:
            return NSLocalizedString("Username available", comment: "Usernames")
        case .invalidCritical:
            // A locked contest is not "taken" — nobody owns the name, and
            // nobody can. Saying "taken" would send the user off to wait for
            // it to free up, which never happens.
            if viewModel.isLockedContestedName {
                return NSLocalizedString(
                    "Username locked by masternode vote — it cannot be registered",
                    comment: "Usernames")
            }
            // Mid-vote with the join window closed — also not "taken":
            // the vote decides the owner, and no request can be made
            // until it resolves. The orange callout carries the detail.
            if viewModel.activeContestContenders != nil {
                return NSLocalizedString(
                    "Username is in a network vote — new contenders can no longer join",
                    comment: "Usernames")
            }
            return NSLocalizedString("Username taken", comment: "Usernames")
        case .error:
            return NSLocalizedString("Validating username failed", comment: "Usernames")
        case .warning:
            // The user's own contested submission — taken on-chain while
            // masternode voting decides the owner.
            return NSLocalizedString("Username is in voting. You will be notified when voting ends.", comment: "Usernames")
        case .empty, .invalid, .hidden:
            return "" // rule row is hidden for these states
        }
    }
}
