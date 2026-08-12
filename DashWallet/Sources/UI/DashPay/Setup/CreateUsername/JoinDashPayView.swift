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
    case none
    case callToAction
    case voting
    case approved
    case failed
    case blocked
    case contested
    case registered
}

extension JoinDashPayState {
    func hasAction() -> Bool {
        return self == .callToAction || self == .approved || self == .failed || self == .blocked || self == .contested
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
    let state: JoinDashPayState
    let username: String
    let shieldedSnapshot: ShieldedIdentityFundingReadiness.Snapshot?

    var iconName: String {
        switch state {
        case .none, .callToAction, .registered:
            return "dp_user_generic"
        case .voting:
            return "username_requested"
        case .approved:
            return "username_approved"
        default:
            return "username_rejected"
        }
    }

    var title: String {
        switch state {
        case .none:
            return NSLocalizedString("Join DashPay", comment: "")
        case .callToAction:
            return NSLocalizedString("Upgrade to DashPay", comment: "")
        case .voting, .registered:
            return username
        case .approved:
            return NSLocalizedString("Your username has been successfully created", comment: "Usernames")
        case .failed:
            return NSLocalizedString("Username request failed", comment: "Usernames")
        case .blocked:
            return NSLocalizedString("Requested username has been blocked", comment: "Usernames")
        case .contested:
            return NSLocalizedString("Requested username has been given to someone else", comment: "Usernames")
        }
    }
    
    var subtitle: String {
        switch state {
        case .none:
            return NSLocalizedString("Request your username", comment: "")
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
        case .voting:
            if let endTime = DWContestedNameStatusService.shared.pendingVotingEndTime {
                let endDate = DWDateFormatter.sharedInstance.dateAndTime(from: endTime)
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Username %@ has been submitted for voting. Voting ends around %@.",
                        comment: "Usernames"),
                    username,
                    endDate)
            }
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "Username %@ has been submitted for voting. We will notify you when voting ends.",
                    comment: "Usernames"),
                username)
        case .approved:
            return NSLocalizedString("Get started by setting up your profile picture and other information.", comment: "Usernames")
        case .failed:
            return String.localizedStringWithFormat(NSLocalizedString("For some reason, the request for the username '%@' has failed.", comment: "Usernames"), username)
        case .blocked:
            return String.localizedStringWithFormat(NSLocalizedString("The username '%@' was blocked by the Dash Network. Please try again by requesting another username.", comment: "Usernames"), username)
        case .contested:
            return String.localizedStringWithFormat(NSLocalizedString("Due to the voting process, the Dash Network has decided to assign the username '%@' to someone else. Please try again by requesting another username.", comment: "Usernames"), username)
        case .registered:
            return ""
        }
    }
    
    var actionText: String {
        switch state {
        case .callToAction:
            return NSLocalizedString("Upgrade", comment: "")
        case .approved:
            return NSLocalizedString("Edit profile", comment: "")
        default:
            return NSLocalizedString("Retry", comment: "")
        }
    }

    var actionIcon: IconName? {
        switch state {
        case .failed, .blocked, .contested:
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
    var onDismiss: ((JoinDashPayState) -> Void)? = nil
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
            shieldedSnapshot: shieldedReadiness.standardSnapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.MenuItem(
                leadingIcon: .custom(copy.iconName, bundle: .main),
                isEnabled: !isSyncing,
                disabledLeadingIcon: .custom("menu-send-account-disabled", bundle: .dashUIKit),
                title: copy.title,
                helpText: viewModel.state == .registered ? nil : copy.subtitle,
                accessory: .none
            )
            // No action while the chain is catching up: every destination this
            // row leads to (join, retry, edit profile) needs a synced chain, so
            // a tap here could only fail. The note below says why.
            .onTapGesture {
                guard !isSyncing else { return }
                onTap(viewModel.state)
            }
            .overlay(alignment: .topTrailing) {
                if let onDismiss {
                    Button {
                        onDismiss(viewModel.state)
                    } label: {
                        XmarkIcon(size: 10, color: .dash.tertiaryText)
                            // Keep the tap target comfortable without letting
                            // the glyph itself push the row's layout around.
                            .padding(14)
                            .contentShape(Rectangle())
                    }
                    // An overlay rather than `MenuItem`'s `accessory:` — the
                    // accessory sits vertically centred in the row, and this
                    // close belongs in the top trailing corner.
                    .buttonStyle(.plain)
                }
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
        .modifier(MenuViewModifier())
        .onAppear {
            viewModel.checkUsername()
        }
    }
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
                    viewModel: JoinDashPayViewModel(initialState: state),
                    onTap: { _ in })
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
                    .voting,
                    .approved,
                    .failed,
                    .registered
                ],
                id: \.self
            ) { state in
                JoinDashPayMenuItem(
                    viewModel: JoinDashPayViewModel(initialState: state),
                    onTap: { _ in },
                    onDismiss: { _ in })
                    .padding(6)
                    .background(Color.dash.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(20)
    }
}
