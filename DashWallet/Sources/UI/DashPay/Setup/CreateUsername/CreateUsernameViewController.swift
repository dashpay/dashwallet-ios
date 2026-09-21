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

        // Unwinding is shared; reporting an outcome is not. `finish` ends a
        // registration whose result is known here, `handOffToStatusRow` leaves
        // a running one to the More row without claiming anything about it.
        let leaveFlow: (_ showMore: Bool) -> Void = { [weak self] showMore in
            guard let self else { return }
            let navigationController = self.navigationController
            #if DASHPAY
            let mainTabController = self.tabBarController as? MainTabbarController
            #endif
            // Pop the whole registration stack, not one level. The invitation
            // entry pushes this screen ON TOP of the redeem screen, so popping
            // once lands the freshly-registered user back on "Claim your
            // invitation" — a flow they just completed and cannot repeat.
            // Every push site roots this flow at a tab's own screen, so
            // unwinding to that root is the correct destination for all of
            // them (Home for the home/deep-link entries, More for the menu).
            navigationController?.popToRootViewController(animated: true)
            #if DASHPAY
            // A submitted request is reported on More, so that is where the
            // flow ends regardless of which tab it started from. Selected
            // after the pop, so the tab arrives at its own root rather than
            // mid-stack.
            if showMore {
                mainTabController?.showMore()
            }
            if let transitionCoordinator = navigationController?.transitionCoordinator {
                transitionCoordinator.animate(alongsideTransition: nil) { _ in
                    mainTabController?.applyPendingDashPayTabReconfiguration()
                }
            } else {
                mainTabController?.applyPendingDashPayTabReconfiguration()
            }
            #endif
        }

        let content = CreateUsernameView(
            invitationURI: invitationURI,
            definedUsername: definedUsername,
            finish: { [weak self] in
                leaveFlow(false)
                self?.completionHandler?(true)
            },
            handOffToStatusRow: { leaveFlow(true) },
            // One level, not the whole stack: this is the plain "go back to
            // where I came from" gesture the UIKit bar used to provide.
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
        let swiftUIController = UIHostingController(rootView: content)
        swiftUIController.view.backgroundColor = UIColor.dw_secondaryBackground()
        self.dw_embedChild(swiftUIController)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}

// MARK: - NavigationBarDisplayable

/// The screen carries its own `DashUIKit.NavigationBar`, so the stack's bar
/// would be a second, differently styled back button above it.
///
/// This protocol, not `setNavigationBarHidden` in `viewWillAppear`:
/// `BaseNavigationController.willShow` reads `isNavigationBarHidden` on every
/// push and pop, so a call made here is overwritten by whatever that read
/// returns — which is how the two back buttons ended up on screen together.
extension CreateUsernameViewController: NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }
}

struct CreateUsernameView: View {
    @StateObject private var viewModel = CreateUsernameViewModel()
    /// Requests focus on the username field rather than holding it: the field
    /// owns the `@FocusState` and mirrors this flag both ways. Setting it false
    /// is how the screen gets the keyboard out of the way before presenting a
    /// sheet or the PIN prompt.
    @State private var isTextInputFocused: Bool = false
    @State private var inProgress: Bool = false
    @State private var screenLockedAfterAuth: Bool = false
    /// Funding source for the SwiftDashSDK identity registration.
    ///
    /// Chosen a screen earlier, on the Join DashPay sheet's privacy page, and
    /// adopted on appear. This screen does not ask again — it used to carry a
    /// segmented picker, which asked the same question twice. For the paths
    /// that skip that page (invitation, recovery, a retry from the Home row)
    /// `syncFundingSourceToViableSource()` pins the first viable source in
    /// privacy-descending order (Shielded → Platform → Core). Written into
    /// `DWIdentityRegistrationBridge.shared.preferredFundingSource` in the
    /// Continue handler right before the submit call.
    @State private var fundingSource: DWIdentityFundingSource = .core
    /// True once a choice made by the user has been adopted; auto-pinning
    /// then only corrects a selection that became non-viable, instead
    /// of overriding it.
    @State private var didUserPickFundingSource: Bool = false
    /// Tracks the contested-name confirmation sheet. Continue routes
    /// through this sheet (instead of submitting directly) when the
    /// typed name is contested-eligible — `viewModel.isContestedCandidate`.
    /// Besides acknowledging the vote wait, the sheet prompts for a
    /// non-contested temporary username registered in the same flow.
    /// Step 1 of the contested submission: confirm the requested name, its
    /// cost and that it cannot be changed.
    @State private var showConfirmRequest: Bool = false
    /// Step 2, shown only when no instant companion has been named yet: the
    /// offer to register one.
    @State private var showCreateInstantOffer: Bool = false
    /// Step 3: the form itself is naming the instant companion. Android
    /// returns to its request screen for this; the same screen does it here,
    /// with the companion's own field and validation.
    @State private var isNamingInstantUsername: Bool = false
    /// Step 0 of a contested submission: the offer to publish a
    /// proof-of-identity link before the request goes out. Android asks the
    /// same thing on Continue, and a link only counts while the vote is open.
    @State private var showVerifyOffer: Bool = false
    /// The screen that captures the link.
    @State private var showVerifyIdentity: Bool = false

    /// What to do once the sheet that asked for it has actually left the
    /// screen.
    ///
    /// Nothing here may run while a sheet is still up or mid-dismissal: the
    /// PIN host cannot be presented over one, and `PinPromptPresenter` resolves
    /// the rejected attempt as `.failed` after its 0.5 s watchdog — the form
    /// then reported "Authentication failed" for a prompt the user never saw
    /// (`🔐 PINPROMPT :: presentation rejected`). Presenting the next sheet
    /// straight from the previous one's button races the same animation.
    @State private var sheetFollowUp: SheetFollowUp?

    /// The three things a sheet in this flow can hand back.
    private enum SheetFollowUp: Equatable {
        case verifyIdentity
        case confirmRequest
        case offerInstantUsername
        case nameInstantUsername
        case submit(temporaryUsername: String?)
    }
    /// The voting explainer, opened from the contested disclosure's
    /// "See details". Explains and closes; it starts nothing.
    @State private var showVotingInfo: Bool = false
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
    var finish: () -> Void
    /// Leaves the flow WITHOUT reporting an outcome. A handoff happens while
    /// the registration is still running — `preparingKeys`/`inFlight`, before
    /// payment has even settled — so routing it through `finish` showed
    /// "Username was successfully requested" for an attempt that can still
    /// fail, and the later failure would arrive only on the Home row,
    /// contradicting a HUD the user had already seen.
    var handOffToStatusRow: () -> Void
    /// Pops this screen. Wired to the `NavigationBar`'s back element, which
    /// replaced the UIKit bar's own button.
    var onBack: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.NavigationBar(
                leading: { DashUIKit.NavigationBarElement.back.button(action: goBack) })

            // The companion pass replaces the form rather than sitting under it:
            // it asks for a different name, by different rules, and the requested
            // one is already confirmed by the time it appears.
            if isNamingInstantUsername {
                instantUsernameForm
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        DashUIKit.TopIntroView(
                            title: NSLocalizedString("Create username", comment: "Usernames"),
                            mainDescription: NSLocalizedString("Please note that you will not be able to change it in the future", comment: "Usernames"))
                            .padding(.top, 12)

                        usernameCard
                            .padding(.top, 20)

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

                        DashButton(
                            text: primaryButtonText,
                            isEnabled: (viewModel.uiState.canContinue || viewModel.canPurchaseListedNameDirectly)
                                && !screenLockedAfterAuth,
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
                                // The verification offer comes first, as on
                                // Android: a link published with the request is
                                // what masternode owners weigh, and after the
                                // submission that window is already narrower.
                                showVerifyOffer = true
                            } else {
                                performSubmit()
                            }
                        }
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
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
            // The funding source is chosen on the Join DashPay sheet's privacy
            // page, one screen back. Adopting it counts as an explicit pick, so
            // the auto-pinning below only corrects a choice that is no longer
            // viable instead of overriding it.
            if let chosen = viewModel.consumeChosenFundingSource() {
                fundingSource = chosen
                didUserPickFundingSource = true
            }
            // Paths that never pass that page — an invitation claim, a
            // recovery, a retry from the Home row — arrive with no choice, so
            // pin to the highest-priority viable source rather than defaulting
            // to Core on a wallet that has no Core balance.
            syncFundingSourceToViableSource()
        }
        .onChange(of: fundingSource) { source in
            // The cost rule is judged against the source that will pay, so the
            // model has to be told which one that is.
            viewModel.setActiveFundingSource(source)
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
        .sheet(isPresented: $showVotingInfo) {
            DashUIKit.BottomSheet.selfSizing(
                showBackButton: .constant(false),
                fallback: 600
            ) {
                VotingInfoScreen(
                    action: { showVotingInfo = false },
                    buttonLabel: NSLocalizedString("Close", comment: ""))
            }
        }
        .sheet(isPresented: $showVerifyOffer, onDismiss: runSheetFollowUp) {
            DashUIKit.BottomSheet.selfSizing(
                showBackButton: .constant(false),
                showsCloseButton: false,
                fallback: 420
            ) {
                VerifyIdentityOfferSheet(
                    onVerify: {
                        sheetFollowUp = .verifyIdentity
                        showVerifyOffer = false
                    },
                    onSkip: {
                        sheetFollowUp = .confirmRequest
                        showVerifyOffer = false
                    })
            }
        }
        .sheet(isPresented: $showVerifyIdentity, onDismiss: runSheetFollowUp) {
            DashUIKit.BottomSheet.selfSizing(
                showBackButton: .constant(false),
                fallback: 600
            ) {
                VerifyIdentityScreen(
                    username: viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines),
                    onConfirmed: { url in
                        // The link travels with the submission and is published
                        // by the coordinator once the identity exists — no
                        // second PIN, same as Android.
                        DWIdentityRegistrationBridge.shared.pendingVerificationURL = url
                        sheetFollowUp = .confirmRequest
                        showVerifyIdentity = false
                    })
            }
        }
        .sheet(isPresented: $showConfirmRequest, onDismiss: runSheetFollowUp) {
            DashUIKit.BottomSheet.selfSizing(
                showBackButton: .constant(false),
                showsCloseButton: false,
                fallback: 520
            ) {
                ConfirmUsernameRequestSheet(
                    kind: isNamingInstantUsername ? .instant : .requested,
                    username: isNamingInstantUsername
                        ? viewModel.temporaryField.trimmedText
                        : viewModel.username,
                    amountDuffs: confirmationAmountDuffs,
                    // Only the contested request spends a contest fee; the
                    // instant companion is an ordinary registration.
                    showsContestFeeNote: !isNamingInstantUsername,
                    onConfirm: { confirmRequestAccepted() })
            }
        }
        .sheet(isPresented: $showCreateInstantOffer, onDismiss: runSheetFollowUp) {
            DashUIKit.BottomSheet.selfSizing(
                showBackButton: .constant(false),
                showsCloseButton: false,
                fallback: 480
            ) {
                CreateInstantUsernameSheet(
                    onCreate: {
                        sheetFollowUp = .nameInstantUsername
                        showCreateInstantOffer = false
                    },
                    onDecline: {
                        // The contested request alone, as confirmed a step ago
                        // — submitted once this sheet is out of the way.
                        sheetFollowUp = .submit(temporaryUsername: nil)
                        showCreateInstantOffer = false
                    })
            }
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

    /// Label, field and the rules the field is judged by, in one card.
    ///
    /// The card is the design: the three belong together, and putting the rules
    /// on the plain background next to it read as page content rather than as
    /// feedback on what was typed. `MenuViewModifier` is that card — radius 20,
    /// secondary background, shadow at (0, 5) — so its own 6pt of inner padding
    /// plus 14 here is the design's 20pt inset.
    private var usernameCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.AddressFieldView(
                text: $viewModel.username,
                label: NSLocalizedString("Username", comment: "Usernames"),
                placeholder: NSLocalizedString("Enter a username", comment: "Usernames"),
                hasError: hasUsernameError,
                isDisabled: screenLockedAfterAuth,
                // No `onScanQR`: a username has no QR form, and the field draws
                // the button only for a handler that exists.
                isFocused: $isTextInputFocused,
                // A username is short enough to clear by hand, and the rules
                // below already say when it is wrong.
                showsClearButton: false,
                isAccepted: isUsernameAccepted
            )
            .submitLabel(.done)
            .onSubmit { isTextInputFocused = false }

            if !usernameCriteria.isEmpty {
                DashUIKit.Criteria(usernameCriteria)
                    .padding(.top, 20)
            }

            // Inside the card, under the rules: the disclosure is the last
            // thing the rules have to say about the name that was typed — that
            // it is one the network votes on — not a separate remark about the
            // screen.
            if viewModel.showContestedWarning {
                contestedNameWarning
                    .padding(.top, 20)
            }
        }
        .padding(14)
        .modifier(DashUIKit.MenuViewModifier())
    }

    /// The field's error styling follows the rules below it: it turns red only
    /// once something is actually wrong with what was typed, never while a
    /// check is still running or before anything has been entered.
    private var hasUsernameError: Bool {
        let rules: [UsernameValidationRuleResult] = [
            viewModel.uiState.lengthRule,
            viewModel.uiState.allowedCharactersRule,
            viewModel.uiState.usernameBlockedRule,
        ]
        return rules.contains { Self.criterionState($0) == .failed || Self.criterionState($0) == .blocking }
    }

    /// Every rule that has something to say is satisfied, so the field drops
    /// its focus ring. Not `uiState.canContinue`: that also waits on the
    /// availability query, and the ring should go quiet as soon as what the
    /// user typed is accepted rather than when the network agrees.
    private var isUsernameAccepted: Bool {
        let rules: [UsernameValidationRuleResult] = [
            viewModel.uiState.lengthRule,
            viewModel.uiState.allowedCharactersRule,
            viewModel.uiState.costRule,
            viewModel.uiState.usernameBlockedRule,
        ]
        // A rule reported as `.hidden` has nothing to say — it is not a row on
        // screen and not a verdict to wait for. Everything else has to be met.
        let stated = rules.filter { $0 != .hidden }
        return !stated.isEmpty && stated.allSatisfy { Self.criterionState($0) == .met }
    }

    /// The rules, in the order the design lists them — **only the ones still
    /// worth reading**.
    ///
    /// Two kinds of row are left out. A rule the view model reports as
    /// `.hidden` has nothing to say, and `Criteria` has no hidden state because
    /// a silent rule should not take a row's worth of space. A rule that is
    /// **met** is dropped too: a satisfied requirement has stopped being a
    /// requirement, and keeping it on screen buries the one thing that still
    /// needs fixing among ticks. With everything met the block disappears and
    /// Continue lighting up is the confirmation.
    ///
    /// Each row carries a stable `id` so a rule whose text changes (the cost
    /// line's amount, the blocked line's reason) updates in place instead of
    /// being replaced.
    private var usernameCriteria: [DashUIKit.Criterion] {
        var items: [DashUIKit.Criterion] = []

        func add(id: String, text: @autoclosure () -> String, rule: UsernameValidationRuleResult) {
            guard rule != .hidden else { return }
            let state = Self.criterionState(rule)
            guard state != .met else { return }
            items.append(DashUIKit.Criterion(id: id, text: text(), state: state))
        }

        add(
            id: "length",
            text: NSLocalizedString("Between 3 and 23 characters", comment: "Usernames"),
            rule: viewModel.uiState.lengthRule)

        add(
            id: "characters",
            text: NSLocalizedString("Letter, numbers and hyphens only", comment: "Usernames"),
            rule: viewModel.uiState.allowedCharactersRule)

        add(
            id: "cost",
            text: String.localizedStringWithFormat(
                NSLocalizedString("You need to have more %@ Dash to create this username", comment: "Usernames"),
                viewModel.uiState.requiredDash.dashAmount.formattedDashAmountWithoutCurrencySymbol),
            rule: viewModel.uiState.costRule)

        add(
            id: "availability",
            text: getMessageForBlockedRule(),
            rule: viewModel.uiState.usernameBlockedRule)

        return items
    }

    /// The app's validation vocabulary in the library's terms.
    ///
    /// Two pairs collapse: `.empty` and `.hidden` are both "nothing to say yet"
    /// (`.hidden` never reaches here — the caller drops those rows), and
    /// `.invalidCritical` and `.error` both mean the user cannot continue, which
    /// is what `.blocking` is for.
    private static func criterionState(_ result: UsernameValidationRuleResult) -> DashUIKit.CriterionState {
        switch result {
        case .empty, .hidden:
            return .pending
        case .loading:
            return .checking
        case .valid:
            return .met
        case .warning:
            return .warning
        case .invalid:
            return .failed
        case .invalidCritical, .error:
            return .blocking
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

    /// Back leaves the companion pass first, and the screen only once there is
    /// no pass to leave: the requested name is already confirmed by then, so
    /// popping out would drop a decision the user has made rather than the
    /// screen they are on.
    private func goBack() {
        if isNamingInstantUsername {
            isNamingInstantUsername = false
            return
        }

        onBack()
    }

    /// Naming the instant companion, on the same screen Android returns to for
    /// it. Its own view, not a computed property here, because the button has
    /// to track `TemporaryUsernameFieldModel` — a nested `ObservableObject`,
    /// whose changes do not reach this view's `viewModel` subscription. Read
    /// from here, Continue stayed disabled after the name was found available
    /// and only woke up when something unrelated republished.
    private var instantUsernameForm: some View {
        InstantUsernameForm(
            temporaryField: viewModel.temporaryField,
            requestedUsername: viewModel.username,
            onContinue: {
                isTextInputFocused = false
                showConfirmRequest = true
            })
    }

    /// The contested-name disclosure, as a `SystemMessageView`.
    ///
    /// Four shapes, all in the same component so the row never changes its
    /// look mid-typing:
    ///
    /// - Not yet submitted: the designed line — the network will vote, and
    ///   when the result is due. No contest exists yet, so that deadline is a
    ///   projection from the network's own poll duration (see below).
    /// - A vote already running: the real deadline the network reports, and
    ///   whether a request can still join it.
    /// - Past the deadline: the result is being finalized.
    ///
    /// The last two keep warning styling — they qualify what submitting will
    /// do — while the plain case is information, so it takes the info mark.
    /// `See details` opens the voting explainer in every shape.
    private var contestedNameWarning: some View {
        let voteInProgress = viewModel.activeContestContenders != nil
        let title: String
        let body: String?
        var isWarning = false

        if voteInProgress, viewModel.activeContestHasEnded {
            title = NSLocalizedString("Vote ended", comment: "Usernames")
            body = NSLocalizedString(
                "The masternode vote for this name has ended and the result is being finalized. Check back soon.",
                comment: "Usernames")
            isWarning = true
        } else if voteInProgress, let endsAt = viewModel.activeContestEndsAt, viewModel.activeContestJoinClosed {
            title = NSLocalizedString("Vote in progress", comment: "Usernames")
            body = String.localizedStringWithFormat(
                NSLocalizedString(
                    "A masternode vote for this name is in progress — voting ends around %@. New contenders can no longer join this vote.",
                    comment: "Usernames"),
                Self.contestDeadlineText(endsAt))
            isWarning = true
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
        } else if let resultsBy = Self.projectedVotingDeadlineText() {
            // One sentence in the title slot, as designed — there is no
            // heading over it, the statement IS the message.
            title = String.localizedStringWithFormat(
                NSLocalizedString("The Dash network will vote on this username. Results by %@.", comment: "Usernames"),
                resultsBy)
            body = nil
        } else {
            title = NSLocalizedString("The Dash network will vote on this username.", comment: "Usernames")
            body = nil
        }

        return DashUIKit.SystemMessageView(
            title: title,
            subtitle: body,
            icon: isWarning
                ? DashIcon.SystemMessage.warningTriangle.source
                : DashIcon.SystemMessage.infoRectSmall.source,
            backgroundColor: isWarning ? Color.dash.orangeAlpha10 : Color.dash.blueAlpha5,
            buttonName: NSLocalizedString("See details", comment: "Usernames"),
            onAction: { showVotingInfo = true },
            // A link, not a call to action: the message is not asking to be
            // acted on, it points at an explanation.
            buttonStyle: .plainBlue
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    /// When a vote started now would be due, formatted for the disclosure.
    ///
    /// Before submission there is no contest to ask about, so this is the same
    /// conservative projection the submission path persists as its fallback:
    /// the protocol poll duration for the active network — 14 days on mainnet,
    /// 90 minutes on testnet. A testnet projection lands today, where a bare
    /// date says nothing, so that case carries the time as well.
    private static func projectedVotingDeadlineText() -> String? {
        guard let network = WalletEnvironment.network else { return nil }

        let deadline = DWContestedNameStatusService.fallbackVotingEndTime(
            submittedAt: Date(),
            network: network)
        return Calendar.current.isDateInToday(deadline)
            ? contestDeadlineText(deadline)
            : DWDateFormatter.sharedInstance.dateOnly(from: deadline)
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
    /// What `Confirm` does depends on which name it just confirmed.
    ///
    /// - The instant companion: both names go in together.
    /// - The requested name with a companion already named: same.
    /// - The requested name on its own: offer the companion first. Android
    ///   asks at exactly this moment too, which is why the offer is a second
    ///   sheet rather than a section of the first.
    private func confirmRequestAccepted() {
        sheetFollowUp = isNamingInstantUsername
            ? .submit(temporaryUsername: viewModel.temporaryField.trimmedText)
            : .offerInstantUsername
        showConfirmRequest = false
    }

    /// Runs whatever the sheet that just closed asked for. Called from the
    /// sheets' `onDismiss`, which is the first moment UIKit will present
    /// anything else — including the PIN host.
    private func runSheetFollowUp() {
        guard let followUp = sheetFollowUp else { return }
        sheetFollowUp = nil

        switch followUp {
        case .verifyIdentity:
            showVerifyIdentity = true
        case .confirmRequest:
            showConfirmRequest = true
        case .offerInstantUsername:
            showCreateInstantOffer = true
        case .nameInstantUsername:
            viewModel.temporaryField.seedSuggestion(from: viewModel.username)
            isNamingInstantUsername = true
        case .submit(let temporaryUsername):
            confirmContestedSubmission(temporaryUsername: temporaryUsername)
        }
    }

    /// What the confirmation sheet states as the cost.
    ///
    /// Only the contested request spends DASH: the companion is a second DPNS
    /// name on the identity that request funds, so nil — the sheet then says
    /// nothing extra is spent instead of naming a second amount.
    private var confirmationAmountDuffs: UInt64? {
        isNamingInstantUsername ? nil : UInt64(DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME)
    }

    private func confirmContestedSubmission(temporaryUsername: String?) {
        showConfirmRequest = false
        showCreateInstantOffer = false
        isNamingInstantUsername = false
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
        // Every submission except an invitation claim reports its progress on
        // the More row and this screen steps aside straight after the PIN.
        // A contested one used to stay here to the end for its voting
        // explanation; that explanation now lives on the row and behind
        // "Request details", so keeping the screen up only hid the progress
        // the user came to watch. An invitation claim still holds the screen:
        // it carries the inviter contact request afterwards, which has nowhere
        // else to go.
        let handsOffToStatusRow = !viewModel.isInvitationMode
        Task {
            // `inProgress` keeps the Continue spinner up across the PIN gate.
            // Where the screen hands off, that is all it still does; otherwise
            // it also holds the screen alive for the whole registration and the
            // bridge completion resolves the outcome at the terminal phase.
            inProgress = true
            screenLockedAfterAuth = false
            var didHandOff = false
            let outcome = await viewModel.submitUsernameRequest(temporaryUsername: temporaryUsername) {
                isTextInputFocused = false
                if handsOffToStatusRow {
                    // Fires once the registration is actually running — after
                    // the PIN gate, which `startCreateUsername` passes before
                    // any phase change. The work itself lives in the
                    // app-scoped coordinator and outlives this screen.
                    didHandOff = true
                    // The label the registration actually went out under, not
                    // a second normalization of the field: the two must name
                    // the same attempt or the row reports an interruption for
                    // a registration that is running.
                    JoinDashPayViewModel.markRegistrationHandedOff(
                        username: viewModel.submittedRegistrationUsername
                            ?? viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines))
                    handOffToStatusRow()
                } else {
                    screenLockedAfterAuth = true
                }
            }
            inProgress = false

            // The Home row owns the outcome now; alerts from a dismissed screen
            // would either be invisible or land on top of Home.
            guard !didHandOff else { return }

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

    /// Keep `fundingSource` pointing at a viable source. With no choice
    /// carried in from the privacy page, pin to the highest-priority viable
    /// source (Shielded → Platform → Core); with one, only correct it once it
    /// is no longer viable.
    private func syncFundingSourceToViableSource() {
        defer { viewModel.setActiveFundingSource(fundingSource) }

        // An explicit pick is never overridden, not even once it stops being
        // viable. Quietly moving a user who chose Platform onto Core would
        // fund the registration from a balance they did not offer; the cost
        // rule states the shortfall instead and Continue stays disabled.
        guard !didUserPickFundingSource else { return }

        let viable = viableFundingSources
        guard let preferred = viable.first else {
            // Nothing viable — leave the selection alone; the Continue
            // button is disabled by the cost rule anyway.
            return
        }
        fundingSource = preferred
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

// MARK: - TemporaryUsernameField

/// Field + single validation rule row for a temporary-username field, bound to
/// a `TemporaryUsernameFieldModel`. Shared by the contested confirmation sheet
/// above and `UsernameRequestStatusScreen`'s register section so the two
/// surfaces render the same rules.
///
/// The same field and the same rule row as the main form, so the companion pass
/// does not look like a different screen — but no card: this one already sits
/// inside a bottom sheet, and a card inside a sheet is a second surface for no
/// reason.
struct TemporaryUsernameField: View {
    @ObservedObject var model: TemporaryUsernameFieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.AddressFieldView(
                text: $model.text,
                label: NSLocalizedString("Temporary username", comment: "Usernames"),
                placeholder: NSLocalizedString("Enter a username", comment: "Usernames"),
                hasError: ruleResult == .invalid || ruleResult == .invalidCritical || ruleResult == .error)

            if ruleResult != .hidden {
                DashUIKit.Criteria([
                    DashUIKit.Criterion(
                        id: "temporary-username",
                        text: ruleText,
                        state: Self.criterionState(ruleResult)),
                ])
                .padding(.top, 20)
            }
        }
    }

    /// Same mapping as the main form's — see
    /// `CreateUsernameView.criterionState(_:)` for why the pairs collapse.
    private static func criterionState(_ result: UsernameValidationRuleResult) -> DashUIKit.CriterionState {
        switch result {
        case .empty, .hidden: return .pending
        case .loading: return .checking
        case .valid: return .met
        case .warning: return .warning
        case .invalid: return .failed
        case .invalidCritical, .error: return .blocking
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

/// Companion-naming pass of the create-username screen.
///
/// `@ObservedObject` on the field is the point of the type: the availability
/// check publishes on it, and Continue is gated on that check.
private struct InstantUsernameForm: View {
    @ObservedObject var temporaryField: TemporaryUsernameFieldModel
    /// The contested name already confirmed, quoted in the explanation. Fixed
    /// here — this pass names the companion, not the request.
    let requestedUsername: String
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DashUIKit.TopIntroView(
                    title: NSLocalizedString("Create an instant username", comment: "Usernames"),
                    mainDescription: String.localizedStringWithFormat(
                        NSLocalizedString(
                            "While “%@” is out for a vote it does not belong to you yet and other users cannot find you by it. This username works right away and stays yours whatever the vote decides.",
                            comment: "Usernames"),
                        requestedUsername))
                    .padding(.top, 12)

                TemporaryUsernameField(model: temporaryField)
                    .padding(.top, 20)

                DashButton(
                    text: NSLocalizedString("Continue", comment: ""),
                    isEnabled: temporaryField.check == .available,
                    action: onContinue
                )
                .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }
}

