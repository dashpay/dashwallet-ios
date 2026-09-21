//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

enum JoinDashPayState {
    case loading
    case retryLoading
    case none
    case callToAction
    /// A username registration the create screen handed off is running.
    /// `JoinDashPayViewModel.registrationStep` says which of its three stages.
    case creating
    /// That registration stopped at `registrationStep` and will not advance.
    case creationFailed
    /// A registration was recorded and the app died before it finished. The
    /// coordinator is idle after a relaunch, so there is no stage to claim.
    case interrupted
    /// An identity exists with credits but no username yet — the
    /// registration can be finished from where it stopped.
    case usernameRequired
    case voting
    case approved
    case failed
    case blocked
    case contested
    case registered
}

extension JoinDashPayState {
    func hasAction() -> Bool {
        return self == .usernameRequired || self == .callToAction || self == .approved || self == .failed || self == .blocked || self == .contested
            || self == .creationFailed || self == .interrupted
    }

    /// The row is reporting on a registration this wallet started, rather than
    /// inviting the user to start one. Home shows these regardless of whether
    /// the call to action was dismissed: they are that registration's only
    /// surface once the create screen has stepped aside.
    var isRegistrationReport: Bool {
        switch self {
        case .creating, .creationFailed, .interrupted, .approved:
            return true
        case .none, .loading, .retryLoading, .callToAction, .usernameRequired, .voting, .failed, .blocked, .contested, .registered:
            return false
        }
    }
}

/// State → banner copy for the Join DashPay surfaces. Holds the inputs the
/// copy depends on and nothing else, so both call sites of
/// `JoinDashPayMenuItem` (Home and More) render identical text from one place.
///
/// `@MainActor` because the voting subtitle reads
/// `DWContestedNameStatusService.shared`, which is main-actor isolated.
@MainActor
struct JoinDashPayCopy {
    /// Which surface is asking. The two say different things about a
    /// registration in flight: Home is where the user watches it happen, so it
    /// counts the stages (1/3 → 3/3, as Android's home does); More is a menu
    /// entry they pass by, so it states what is happening in one sentence.
    enum Surface {
        case home
        case more
    }

    let state: JoinDashPayState
    let username: String
    var surface: Surface = .home
    let shieldedSnapshot: ShieldedIdentityFundingReadiness.Snapshot?
    /// Which stage `.creating` and `.creationFailed` describe. Ignored by
    /// every other state.
    var registrationStep: DWDPRegistrationState = .processingPayment

    /// The legacy status object that owns the "(1/3) Processing Payment" copy
    /// and its failure variants in all 43 locales. Built rather than
    /// reimplemented; only the interrupted line has no equivalent there.
    private var registrationStatus: DWDPRegistrationStatus {
        DWDPRegistrationStatus(state: registrationStep, failed: state == .creationFailed, username: username)
    }

    /// Contested names get the redesigned reporting — one plain sentence about
    /// the submission, then the vote — because their registration is not three
    /// payment stages to the user, it is a request that has to be voted on.
    /// An uncontested one keeps the staged "(1/3) Processing Payment" copy,
    /// which is accurate for it and already translated into 43 locales.
    ///
    /// `dash_sdk_dpns_is_contested_username` on the label: a local predicate,
    /// no network, the same one the create form validates with.
    private var isContested: Bool {
        DWContestedNameStatusService.isContestedLabel(username)
    }

    var iconName: String {
        switch state {
        case .loading, .retryLoading, .none, .callToAction, .usernameRequired, .registered:
            return "dp_user_generic"
        case .voting, .creating, .interrupted:
            return "username_requested"
        case .approved:
            return "username_approved"
        default:
            return "username_rejected"
        }
    }

    var title: String {
        switch state {
        case .retryLoading:
            return NSLocalizedString("Retry loading identity", comment: "Identity recovery")
        case .loading:
            return NSLocalizedString("Loading identity…", comment: "DashPay registration recovery")
        case .none:
            return NSLocalizedString("Join DashPay", comment: "")
        case .callToAction:
            return NSLocalizedString("Upgrade to DashPay", comment: "")
        case .creating:
            return isContested
                ? String.localizedStringWithFormat(
                    NSLocalizedString("Requesting – %@", comment: "Usernames — Home row title while a contested username is being submitted"),
                    username)
                : String.localizedStringWithFormat(
                    NSLocalizedString("Creating – %@", comment: "Usernames — Home row title while a username is being registered"),
                    username)
        case .voting:
            return String.localizedStringWithFormat(
                NSLocalizedString("Voting – %@", comment: "Usernames — Home row title while the network votes on a username"),
                username)
        case .usernameRequired:
            return NSLocalizedString("Finish username registration", comment: "DashPay registration recovery")
        case .registered, .creationFailed, .interrupted:
            return username
        case .approved:
            return NSLocalizedString("Your username has been successfully created", comment: "Usernames")
        // A request that never completed and a name given to someone else
        // are both "rejected"; a locked name is its own ending, and saying
        // so is the difference between "pick another name" and "this name
        // now exists for nobody".
        case .failed, .contested:
            return String.localizedStringWithFormat(
                NSLocalizedString("Rejected – %@", comment: "Usernames — Home row title after a username request was refused"),
                username)
        case .blocked:
            return String.localizedStringWithFormat(
                NSLocalizedString("Blocked – %@", comment: "Usernames — Home row title after the network locked a requested username"),
                username)
        }
    }
    
    var subtitle: String {
        switch state {
        case .none:
            return NSLocalizedString("Request your username", comment: "")
        case .usernameRequired:
            return NSLocalizedString("Your identity is ready. Use its existing credits to register a username.", comment: "DashPay registration recovery")
        case .callToAction:
            switch shieldedSnapshot?.state {
            case .maturing(let readyAt):
                let time = DateFormatter.localizedString(from: readyAt, dateStyle: .none, timeStyle: .short)
                return String.localizedStringWithFormat(
                    NSLocalizedString("Your Shielded balance is resting — you can register privately around %@", comment: "Usernames"),
                    time)
            case .ready:
                return NSLocalizedString("Your Shielded balance is ready — register your username privately now", comment: "Usernames")
            case .needsFunding, .poolTooSmall, nil:
                return NSLocalizedString("Add to your Shielded balance now and register your username privately a few hours later", comment: "Usernames")
            }
        case .creating where surface == .more:
            return NSLocalizedString("Submitting username to the Dash network. It might take a few minutes.", comment: "Usernames")
        case .creating, .creationFailed:
            return registrationStatus.stateDescription()
        case .interrupted:
            return NSLocalizedString(
                "Registration was interrupted",
                comment: "Usernames — the app closed before the registration finished")
        case .voting:
            let deciding = NSLocalizedString(
                "Masternode owners are deciding whether you get this username.",
                comment: "Usernames")
            if let endTime = DWContestedNameStatusService.shared.pendingVotingEndTime {
                return deciding + "\n" + String.localizedStringWithFormat(
                    NSLocalizedString("Results on %@", comment: "Usernames — when a username vote closes"),
                    DWDateFormatter.sharedInstance.dateOnly(from: endTime))
            }
            return deciding + " " + NSLocalizedString(
                "We will notify you when voting ends.",
                comment: "Usernames")
        case .approved:
            return NSLocalizedString("Get started by setting up your profile picture and other information.", comment: "Usernames")
        // One title, three reasons: the request never completed, the network
        // refused the name, or the vote went to someone else. Only the last
        // two are verdicts on the name itself.
        case .failed:
            return NSLocalizedString("Your username request did not go through. Try again.", comment: "Usernames")
        case .blocked:
            return NSLocalizedString("The Dash network blocked this username. Nobody can register it — please try a different one.", comment: "Usernames")
        case .contested:
            return NSLocalizedString("The voting gave this username to someone else. Please try again with a different username.", comment: "Usernames")
        case .loading, .retryLoading, .registered:
            return ""
        }
    }
    
    var actionText: String {
        switch state {
        case .usernameRequired:
            return NSLocalizedString("Continue", comment: "DashPay registration recovery")
        case .callToAction:
            return NSLocalizedString("Upgrade", comment: "")
        case .approved:
            return NSLocalizedString("Edit profile", comment: "")
        case .failed, .blocked, .contested:
            return NSLocalizedString("Try again", comment: "Usernames")
        default:
            return NSLocalizedString("Retry", comment: "")
        }
    }

    /// The row explains a contested registration in flight — submitted, or
    /// out for a vote — and the info button opens what that means.
    var showsVotingInfo: Bool {
        switch state {
        case .voting:
            return true
        case .creating:
            return isContested
        default:
            return false
        }
    }

    /// A refused request: the row carries its own "Try again" alongside the
    /// tap, because the retry is the only thing left to do with it.
    var showsRetryButton: Bool {
        switch state {
        case .failed, .blocked, .contested:
            return true
        default:
            return false
        }
    }

    var actionIcon: IconName? {
        switch state {
        case .failed, .blocked, .contested, .creationFailed, .interrupted:
            return .system("arrow.counterclockwise")
        default:
            return nil
        }
    }
}

/// The Join DashPay banner, rendered as a standard menu row. Used on both
/// Home and More.
///
/// There are no Hide/Upgrade buttons: the whole row is the primary action —
/// tapping it means "act on this state" (upgrade / edit profile / retry).
///
/// `onDismiss` is optional and decides whether the trailing close control
/// exists. Home passes it (the banner is an interruption there, so it must
/// be dismissible); More does not, because the banner is a permanent menu
/// entry that the user scrolls past rather than something to get rid of.
struct JoinDashPayMenuItem: View {
    @StateObject var viewModel: JoinDashPayViewModel
    @ObservedObject private var shieldedReadiness = ShieldedIdentityFundingReadiness.shared
    var onTap: (JoinDashPayState) -> Void
    var onDismiss: ((JoinDashPayState) -> Void)?
    /// Opens the username-voting explainer. Rendered as the round info button
    /// on the trailing edge while a contested request is in flight; without a
    /// handler the button is not drawn at all rather than drawn and dead.
    var onShowVotingInfo: (() -> Void)?
    /// Which surface this row is on — it decides how a running registration is
    /// described (see `JoinDashPayCopy.Surface`).
    var surface: JoinDashPayCopy.Surface = .home
    /// Chain still catching up. The row stays visible but presents itself as
    /// unavailable — greyed icon and text, a note saying why, and no action —
    /// because registration cannot start before the chain is synced. Showing
    /// it and refusing the tap is what tells the user the feature exists and
    /// is coming; hiding the row entirely (the previous behaviour) just made
    /// it look like the menu was missing an entry.
    var isSyncing: Bool = false

    private var copy: JoinDashPayCopy {
        JoinDashPayCopy(
            state: viewModel.state,
            username: viewModel.username,
            surface: surface,
            shieldedSnapshot: shieldedReadiness.standardSnapshot,
            registrationStep: viewModel.registrationStep)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row

            if copy.showsRetryButton {
                DashUIKit.DashButton(
                    text: copy.actionText,
                    size: .small,
                    style: .filledBlue,
                    action: { onTap(viewModel.state) }
                )
                .padding(.leading, Self.textInset)
                .padding(.trailing, 10)
                .padding(.bottom, 12)
            }

            if isSyncing {
                HStack(spacing: 0) {
                    Spacer()

                    Text(NSLocalizedString("Available after sync finishes", comment: "DashPay"))
                        .dashFont(.footnote)
                        .foregroundStyle(Color.dash.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.dash.blueAlpha5)
                        .clipShape(.rect(cornerRadius: 14))

                    Spacer()
                }
                .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let onDismiss {
                Button {
                    onDismiss(viewModel.state)
                } label: {
                    XmarkIcon(size: 10, color: .dash.tertiaryText)
                        // Keep the tap target comfortable without letting the
                        // glyph itself push the row's layout around.
                        .padding(14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .modifier(MenuViewModifier())
        .onAppear {
            viewModel.checkUsername()
        }
        .task(id: viewModel.state == .loading) {
            for _ in 0..<20 {
                guard viewModel.state == .loading else { return }
                do { try await Task.sleep(nanoseconds: 250_000_000) }
                catch { return }
                viewModel.checkUsername()
            }
            viewModel.finishLoadingAttempt()
        }
    }

    /// The row, built here rather than with `DashUIKit.MenuItem`.
    ///
    /// The reporting states need slots a menu row does not have — a round info
    /// button beside the text, and a "Try again" button under it — and
    /// `MenuItem`'s accessory is a single vertically centred element with a
    /// fixed inset. The styling is deliberately the same as `MenuItem`'s for
    /// now (30pt icon box, `.subheadMedium` title, `.footnote` help text, the
    /// same colours and the same 10 + 6 insets), so only the layout is ours.
    private var row: some View {
        HStack(alignment: .center, spacing: 10) {
            // Icon + text carry the row's own tap; the trailing button sits
            // OUTSIDE this group on purpose. A tap gesture on the whole row
            // swallows a `Button` inside it — which is why the info control
            // did nothing at all.
            HStack(alignment: .center, spacing: 10) {
                icon

                VStack(alignment: .leading, spacing: 1) {
                    Text(copy.title)
                        .dashFont(.subheadMedium)
                        .foregroundColor(isSyncing ? Color.dash.secondaryText : Color.dash.primaryText)

                    // `.registered` is the resting state of a wallet that has a
                    // username: the row shows the name and nothing else.
                    if viewModel.state != .registered {
                        Text(copy.subtitle)
                            .dashFont(.footnote)
                            .foregroundColor(isSyncing ? Color.dash.tertiaryText : Color.dash.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 30)
            }
            // Tappable except while the chain is catching up: every
            // destination the row leads to (join, retry, edit profile) needs a
            // synced chain, so the note under it says why instead.
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isSyncing else { return }
                onTap(viewModel.state)
            }

            // Not on Home: the close control already occupies that corner, and
            // two round buttons at the same edge read as a mistake. Tapping the
            // row leads to the same place.
            if let onShowVotingInfo, surface == .more, copy.showsVotingInfo, !isSyncing {
                Button(action: onShowVotingInfo) {
                    // 20pt mark in a 30pt target: the glyph stays small beside
                    // the text while the tap area remains comfortable.
                    DashUIKit.InfoRoundIcon(size: 20, color: .dash.blueAlpha50)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }

    private var icon: some View {
        Image(dash: isSyncing
            ? .custom("menu-send-account-disabled", bundle: .dashUIKit)
            : .custom(copy.iconName, bundle: .main))
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
    }

    /// Where the row's text starts: this view's own padding, the icon box and
    /// the gaps around it. Anything that has to line up with the title (the
    /// retry button) uses it rather than repeating the arithmetic.
    private static let textInset: CGFloat = 10 + 30 + 10 + 6
}

// MARK: - Previews

/// The syncing presentation: greyed icon and text via `MenuItem`'s own
/// disabled styling, the "available after sync" note, and no action. Compare
/// against the enabled previews below — the row must stay in place and only
/// change its appearance, never disappear.
#Preview("Menu row — syncing") {
    VStack(spacing: 12) {
        JoinDashPayMenuItem(
            viewModel: JoinDashPayViewModel(initialState: .callToAction),
            onTap: { _ in },
            isSyncing: true)

        JoinDashPayMenuItem(
            viewModel: JoinDashPayViewModel(initialState: .callToAction),
            onTap: { _ in },
            isSyncing: false)
    }
    .padding(20)
}

/// The More presentation: no close control — the row is a permanent menu
/// entry there. Rendered inside the same card the menu groups use.
#Preview("Menu row — More (no close)") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(
                [
                    JoinDashPayState.callToAction,
                    .voting,
                    .approved,
                    .failed,
                    .blocked,
                    .contested,
                    .registered
                ],
                id: \.self
            ) { state in
                JoinDashPayMenuItem(
                    viewModel: JoinDashPayViewModel(initialState: state, username: "jordan"),
                    onTap: { _ in },
                    // Both hosts pass this, so the preview does too — without
                    // it the info button is absent here and present in the app.
                    onShowVotingInfo: { })
                    .padding(6)
                    .background(Color.dash.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(20)
    }
}

/// The Home presentation: identical row plus the trailing close control.
/// Worth comparing against the More preview — the close sits in the top
/// trailing corner and must not shift the title or subtitle.
#Preview("Menu row — Home (with close)") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(
                [
                    JoinDashPayState.callToAction,
                    .creating,
                    .creationFailed,
                    .interrupted,
                    .voting,
                    .approved,
                    .failed,
                    .registered
                ],
                id: \.self
            ) { state in
                JoinDashPayMenuItem(
                    viewModel: JoinDashPayViewModel(initialState: state, username: "jordan12345"),
                    onTap: { _ in },
                    onDismiss: { _ in },
                    onShowVotingInfo: { })
                    .padding(6)
                    .background(Color.dash.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(20)
    }
}

/// The contested reporting, which is what the row's redesigned states are for.
///
/// The username drives them: `isContestedLabel` is a local SDK predicate, so
/// "jordan" (letters only, short, no hyphen) takes the contested copy and the
/// info button, while "jordan2" is auto-approved and keeps the staged
/// "(1/3) Processing Payment" reporting. Both are rendered here so the pair is
/// compared rather than described.
#Preview("Menu row — contested reporting") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contested — “jordan”")
                .dashFont(.footnote)
                .foregroundStyle(Color.dash.secondaryText)

            ForEach(
                [
                    JoinDashPayState.creating,
                    .voting,
                    .contested,
                    .blocked,
                    .failed
                ],
                id: \.self
            ) { state in
                JoinDashPayMenuItem(
                    viewModel: JoinDashPayViewModel(initialState: state, username: "jordan"),
                    onTap: { _ in },
                    // Non-nil, so the info button is drawn on the two states
                    // that report a vote in flight.
                    onShowVotingInfo: { })
                    .padding(6)
                    .background(Color.dash.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            Text("Auto-approved — “jordan2”")
                .dashFont(.footnote)
                .foregroundStyle(Color.dash.secondaryText)
                .padding(.top, 8)

            JoinDashPayMenuItem(
                viewModel: JoinDashPayViewModel(initialState: .creating, username: "jordan2"),
                onTap: { _ in },
                onShowVotingInfo: { })
                .padding(6)
                .background(Color.dash.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(20)
    }
}

