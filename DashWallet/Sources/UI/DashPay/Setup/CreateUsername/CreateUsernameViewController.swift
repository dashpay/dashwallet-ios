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
    @ObservedObject private var coreSpendAvailability = CoreSpendAvailability.shared
    @ObservedObject private var assetLockProofAvailability = AssetLockProofAvailability.shared
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
    /// Tracks the contested-name confirmation sheet. Continue routes
    /// through this sheet (instead of submitting directly) when the
    /// typed name is contested-eligible — `viewModel.isContestedCandidate`.
    /// Besides acknowledging the vote wait, the sheet prompts for a
    /// non-contested temporary username registered in the same flow.
    @State private var showContestedConfirmation: Bool = false
    /// Companion ("temporary") username that the completed contested
    /// submission actually registered — read by `votingSubmittedMessage`
    /// (the live `viewModel.temporaryUsername` field must not be read
    /// there: the sheet is gone and its state can be edited or reset).
    @State private var registeredTemporaryUsername: String? = nil
    /// Companion username that was requested but failed to register —
    /// the contested submission itself succeeded, so the voting alert
    /// carries the partial-outcome note instead of an error popup.
    @State private var failedTemporaryUsername: String? = nil
    /// Tracks the buy-listed-name confirmation alert; the button routes
    /// here when `viewModel.canPurchaseListedNameDirectly`.
    @State private var showPurchaseConfirmation: Bool = false
    /// Terminal success alert of a direct listing purchase; OK finishes
    /// the flow like a completed registration.
    @State private var showPurchaseSuccess: Bool = false
    /// The name captured when the purchase started — the text field stays
    /// editable across the PIN gate + funding + purchase, so the success
    /// alert must not read the live field.
    @State private var purchasedUsername: String = ""
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(NSLocalizedString("Create your username", comment: "Usernames"))
                        .foregroundColor(.dash.primaryText)
                        .font(.title1)
                        .padding(.top, 12)
                    Text(NSLocalizedString("Please note that you will not be able to change it in future", comment: "Usernames"))
                        .foregroundColor(.dash.primaryText)
                        .font(.system(size: 14))
                    TextInput(
                        label: "Username",
                        text: $viewModel.username,
                        isEnabled: !screenLockedAfterAuth,
                        onSubmit: { isTextInputFocused = false },
                        focus: $isTextInputFocused
                    )
                    .padding(.top, 20)
                    .submitLabel(.done)
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

                    // Keep the contested-name disclosure immediately before the
                    // action it qualifies. Because both live in this ScrollView,
                    // the user can always reveal the full warning and Continue
                    // above the keyboard, even on compact screens.
                    if viewModel.showContestedWarning {
                        contestedNameWarning
                            .padding(.top, 20)
                    }

                    DashButton(
                        text: primaryButtonText,
                        isEnabled: (viewModel.uiState.canContinue || viewModel.canPurchaseListedNameDirectly)
                            && !screenLockedAfterAuth
                            && !isFreshCoreRegistrationBlocked,
                        isLoading: inProgress
                    ) {
                        isTextInputFocused = false

                        // `viewModel.uiState.canContinue` is only true after
                        // `checkIfBlocked` flips `usernameBlockedRule` to
                        // `.valid`, so the registration branches are gated on the
                        // same condition. A taken-but-listed name never reaches
                        // `.valid`; its buyable state enables the button through
                        // `canPurchaseListedNameDirectly` and routes to the
                        // purchase confirmation instead.
                        //
                        // Contested-name submissions go through a confirmation
                        // sheet first so the user explicitly acknowledges the
                        // voting wait and the locked Dash. Non-contested names
                        // submit directly.
                        if viewModel.canPurchaseListedNameDirectly {
                            showPurchaseConfirmation = true
                        } else if viewModel.isContestedCandidate {
                            showContestedConfirmation = true
                        } else {
                            performSubmit()
                        }
                    }
                    .padding(.top, 20)

                    if isFreshCoreRegistrationBlocked {
                        SyncGateNote(message: usernameCoreSpendBlockedMessage)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
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
        .sheet(isPresented: $showContestedConfirmation) {
            ContestedNameConfirmationSheet(
                viewModel: viewModel,
                temporaryField: viewModel.temporaryField,
                onSubmit: { temporaryUsername in
                    confirmContestedSubmission(temporaryUsername: temporaryUsername)
                },
                onCancel: { showContestedConfirmation = false })
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
                purchasedUsername))
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
        purchasedUsername = viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            inProgress = true
            screenLockedAfterAuth = false
            let outcome = await viewModel.purchaseListedUsername(name: purchasedUsername)
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

    /// Confirmation handler for both of the contested-name sheet's
    /// submit buttons (`temporaryUsername` nil = "without a temporary
    /// username"). The sheet can sit open across the join-window
    /// boundary, so re-check at the moment of confirmation: a submission
    /// the network would refuse is replaced by a fresh availability
    /// answer (which shows the join-closed state) instead of a
    /// broadcast failure.
    private func confirmContestedSubmission(temporaryUsername: String?) {
        showContestedConfirmation = false
        if viewModel.activeContestContenders != nil, viewModel.activeContestJoinClosed {
            viewModel.refreshRegistrationRecoveryState()
            return
        }
        performSubmit(temporaryUsername: temporaryUsername)
    }

    /// Encapsulates the submit-to-bridge dance so the direct Continue
    /// path and the contested sheet's confirmation can share the code.
    /// Writes the funding-source pick into the bridge right before
    /// submit. The bridge resets to `.core` on every terminal phase, so
    /// a stale picker value can't leak into a future attempt; this
    /// single write is the only synchronization needed.
    private func performSubmit(temporaryUsername: String? = nil) {
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
            let outcome = await viewModel.submitUsernameRequest(temporaryUsername: temporaryUsername) {
                isTextInputFocused = false
                screenLockedAfterAuth = true
            }
            inProgress = false

            switch outcome {
            case .success:
                showSuccess = true
            case let .submittedForVoting(registeredTemporary, temporaryError):
                registeredTemporaryUsername = registeredTemporary
                failedTemporaryUsername = temporaryError != nil ? temporaryUsername : nil
                showVotingSubmitted = true
            case .cancelled:
                screenLockedAfterAuth = false
                break // user backed out of the PIN — stay on screen, allow retry
            case .failure(let message):
                registrationErrorMessage = message
            }
        }
    }

    /// Fresh Core funding needs both gates; recovery is exempt from the
    /// restore gate but still needs quorum data for the existing proof.
    /// Invitation, Platform and Shielded funding need neither app-side gate.
    private var isFreshCoreRegistrationBlocked: Bool {
        if viewModel.canPurchaseListedNameDirectly {
            return viewModel.directPurchaseRequiresCoreFunding
                && (coreSpendAvailability.isBlocked || assetLockProofAvailability.isBlocked)
        }
        guard !viewModel.isInvitationMode else { return false }
        if viewModel.hasPendingRegistrationRecovery {
            return assetLockProofAvailability.isBlocked
        }
        return fundingSource == .core
            && (coreSpendAvailability.isBlocked || assetLockProofAvailability.isBlocked)
    }

    private var usernameCoreSpendBlockedMessage: String {
        let isFreshCoreFunding = viewModel.canPurchaseListedNameDirectly
            ? viewModel.directPurchaseRequiresCoreFunding
            : !viewModel.hasPendingRegistrationRecovery && fundingSource == .core
        if isFreshCoreFunding && coreSpendAvailability.isBlocked,
           viewModel.canPurchaseListedNameDirectly {
            return NSLocalizedString(
                "Your restored wallet is completing its initial sync. A Core-funded username purchase will be available once it finishes.",
                comment: "Core-funded username purchase blocked during initial restore sync")
        }
        if isFreshCoreFunding && coreSpendAvailability.isBlocked {
            return NSLocalizedString(
                "Your restored wallet is completing its initial sync. Core-funded identity registration will be available once it finishes.",
                comment: "Core-funded identity registration blocked during initial restore sync")
        }
        return AssetLockProofAvailabilityError.masternodeSync.localizedDescription
    }

    /// Post-submit copy for a contested name. The deadline is a conservative
    /// submission-time estimate until Platform indexes the contest and
    /// `checkPendingContestResolution` swaps in `ContestVoteState.endTime`,
    /// hence "around". Falls back to the date-less wording when no pending
    /// bookmark exists rather than inventing a deadline.
    private var votingSubmittedMessage: String {
        var message: String
        if let endTime = DWContestedNameStatusService.shared.pendingVotingEndTime {
            message = String.localizedStringWithFormat(
                NSLocalizedString(
                    "“%1$@” has been submitted for voting. It is not registered to you yet. Voting ends around %2$@ — we will notify you with the result.",
                    comment: "Usernames"),
                viewModel.username,
                DWDateFormatter.sharedInstance.dateAndTime(from: endTime))
        } else {
            message = String.localizedStringWithFormat(
                NSLocalizedString(
                    "“%@” has been submitted for voting. It is not registered to you yet. We will notify you when voting ends.",
                    comment: "Usernames"),
                viewModel.username)
        }
        // Companion-name outcome from the same flow: registered (the
        // user is reachable right away, and keeps the name past the
        // vote) or requested-but-failed (partial outcome — the contested
        // submission itself succeeded).
        if let temporary = registeredTemporaryUsername {
            message += " " + String.localizedStringWithFormat(
                NSLocalizedString(
                    "In the meantime you are reachable at “%1$@”, which is yours to keep. If the vote awards you “%2$@”, you will be reachable at both usernames.",
                    comment: "Usernames"),
                temporary,
                viewModel.username)
        } else if let failed = failedTemporaryUsername {
            message += " " + String.localizedStringWithFormat(
                NSLocalizedString(
                    "Your temporary username “%@” could not be registered. You can register another username later.",
                    comment: "Usernames"),
                failed)
        }
        return message
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

/// Contested-name confirmation sheet. Replaces the old plain
/// "Submit anyway" alert: besides acknowledging the vote wait and the
/// locked Dash, it prompts the user to register a non-contested
/// temporary username to the same identity in the same flow (one PIN
/// prompt) — they are reachable at it while the vote runs, and keep it
/// permanently afterwards. Skipping is an explicit secondary action;
/// swiping the sheet down cancels the submission entirely.
private struct ContestedNameConfirmationSheet: View {
    @ObservedObject var viewModel: CreateUsernameViewModel
    @ObservedObject var temporaryField: TemporaryUsernameFieldModel
    /// Called with the validated temporary username, or nil for
    /// "continue without one". The caller dismisses the sheet.
    let onSubmit: (String?) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(NSLocalizedString("Contested name", comment: "Usernames"))
                        .foregroundColor(.dash.primaryText)
                        .font(.title2.bold())
                        .padding(.top, 24)
                    Text(voteMessage)
                        .foregroundColor(.dash.secondaryText)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    Text(NSLocalizedString("Add a temporary username", comment: "Usernames"))
                        .foregroundColor(.dash.primaryText)
                        .font(.subheadline.bold())
                        .padding(.top, 24)
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString(
                            "While the vote is in progress, “%@” does not belong to you yet and other users cannot find you by it. Add a non-contested username to use DashPay right away. It stays yours permanently — if the vote awards you the contested name, you will be reachable at both usernames.",
                            comment: "Usernames"),
                        viewModel.username))
                        .foregroundColor(.dash.secondaryText)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                    TemporaryUsernameField(model: temporaryField)
                        .padding(.top, 16)
                }
            }

            DashButton(
                text: NSLocalizedString("Submit both usernames", comment: "Usernames"),
                isEnabled: temporaryField.check == .available
            ) {
                onSubmit(temporaryField.trimmedText)
            }
            .padding(.top, 8)

            DashButton(
                text: NSLocalizedString("Continue without a temporary username", comment: "Usernames"),
                style: .plain
            ) {
                onSubmit(nil)
            }
            .padding(.top, 4)

            DashButton(
                text: NSLocalizedString("Cancel", comment: ""),
                style: .plain
            ) {
                onCancel()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .presentationDetents([.large])
        .onAppear {
            temporaryField.seedSuggestion(from: viewModel.username)
        }
    }

    /// The join-the-vote wording only holds while the join window is
    /// still open; past it (or with no known contest) the generic
    /// contested message is the honest one — same rule as the alert
    /// this sheet replaced. Both variants state the real fee semantics:
    /// the contest fee is SPENT at submission (it prefunds the vote
    /// poll's specialized balance, whose leftover goes to the network's
    /// processing pools at poll end — see rs-drive-abci's
    /// `clean_up_after_contested_resources_vote_polls_end`), never
    /// locked-and-returned.
    private var voteMessage: String {
        viewModel.activeContestContenders != nil && !viewModel.activeContestJoinClosed
            ? NSLocalizedString(
                "A vote for this name is already in progress — your request will join it as a contender. The contest fee is spent when you submit and is not returned, even if you do not win the name.",
                comment: "Usernames")
            : NSLocalizedString(
                "This name requires a masternode vote. The contest fee is spent when you submit and is not returned, even if you do not win the name.",
                comment: "Usernames")
    }
}

// MARK: - TemporaryUsernameField

/// TextInput + single validation rule row for a temporary-username
/// field, bound to a `TemporaryUsernameFieldModel`. Shared by the
/// contested confirmation sheet above and `UsernameRequestStatusScreen`'s
/// register section so the two surfaces render the same rules.
struct TemporaryUsernameField: View {
    @ObservedObject var model: TemporaryUsernameFieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextInput(
                label: NSLocalizedString("Temporary username", comment: "Usernames"),
                text: $model.text,
                autocapitalization: .never)

            if ruleResult != .hidden {
                ValidationCheck(
                    validationResult: ruleResult,
                    text: ruleText
                ).padding(.top, 16)
            }
        }
    }

    private var ruleResult: UsernameValidationRuleResult {
        switch model.check {
        case .empty:
            return .hidden
        case .invalidLength, .invalidCharacters, .stillContested:
            return .invalid
        case .checking:
            return .loading
        case .available:
            return .valid
        case .taken:
            return .invalidCritical
        case .error:
            return .error
        }
    }

    private var ruleText: String {
        switch model.check {
        case .empty:
            return ""
        case .invalidLength:
            return NSLocalizedString("Between 3 and 23 characters", comment: "Usernames")
        case .invalidCharacters:
            return NSLocalizedString("Letter, numbers and hyphens only", comment: "Usernames")
        case .stillContested:
            return NSLocalizedString(
                "This username would also require voting — try adding a digit between 2 and 9",
                comment: "Usernames")
        case .checking:
            return NSLocalizedString("Validating username…", comment: "Usernames")
        case .available:
            return NSLocalizedString("Username available", comment: "Usernames")
        case .taken:
            return NSLocalizedString("Username taken", comment: "Usernames")
        case .error:
            return NSLocalizedString("Validating username failed", comment: "Usernames")
        }
    }
}
