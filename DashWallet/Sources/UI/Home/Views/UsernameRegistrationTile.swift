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

import DashUIKit
import SwiftUI

#if DASHPAY

/// Home's report on a username registration that is no longer holding a screen
/// of its own.
///
/// Sibling of `JoinDashPayMenuItem` and deliberately built from the same parts —
/// `MenuViewModifier` card, `MenuItem`'s row metrics, the same top-trailing
/// `XmarkIcon` — but not a `MenuItem`, because that component has no slot for a
/// progress bar along its bottom edge.
struct UsernameRegistrationTile: View {
    let state: UsernameTileState
    /// Tapping the row, the Retry/Resume button, or the success arrow. Inert
    /// while in progress — the tile *is* the progress UI, there is nothing
    /// better to open.
    var onTap: () -> Void
    /// The X. Absent while in progress: this is the only surface reporting an
    /// operation that is spending the user's money.
    var onDismiss: () -> Void

    private enum Layout {
        /// `MenuItem`'s own metrics, so the tile lines up with the banner it
        /// replaces in the same slot.
        static let rowSpacing: CGFloat = 10
        static let rowPadding: CGFloat = 10
        static let iconSide: CGFloat = 30
        static let textLeading: CGFloat = 6
        static let barHeight: CGFloat = 4
        static let arrowSide: CGFloat = 40
    }

    private var isDismissible: Bool {
        if case .inProgress = state { return false }
        return state != .hidden
    }

    private var isFailure: Bool {
        switch state {
        case .failed, .interrupted: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            progressBar
        }
        .modifier(MenuViewModifier())
        .overlay(alignment: .topTrailing) { dismissButton }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isRowActionable else { return }
            onTap()
        }
        .accessibilityElement(children: .combine)
    }

    /// In-progress is the one state with nowhere to go.
    private var isRowActionable: Bool {
        if case .inProgress = state { return false }
        return state != .hidden
    }

    // MARK: - Row

    private var row: some View {
        HStack(spacing: Layout.rowSpacing) {
            icon

            VStack(alignment: .leading, spacing: 1) {
                Text(state.username ?? "")
                    .dashFont(.subheadMedium)
                    .foregroundColor(Color.dash.primaryText)

                Text(subtitle)
                    .dashFont(.footnote)
                    .foregroundColor(isFailure ? Color.dash.errorText : Color.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, Layout.textLeading)

            Spacer(minLength: Layout.rowSpacing)

            trailing
        }
        .padding(Layout.rowPadding)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .success(let username):
            // The avatar the profile will carry from here on, so the tile ends
            // on the same face the balance header's `HomeUsernameRow` shows.
            // The placeholder's colour is derived from the username's first
            // letter, so an empty seed renders the same circle the header will
            // — there is no profile picture to fetch this early anyway.
            ContactAvatarView(
                title: username,
                avatarURL: nil,
                identitySeed: Data(),
                size: Layout.iconSide)
        case .failed:
            Image("username_rejected")
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSide, height: Layout.iconSide)
        case .hidden, .inProgress, .interrupted:
            Image("username_requested")
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSide, height: Layout.iconSide)
        }
    }

    /// Every in-flight, failed, and completed line comes from
    /// `DWDPRegistrationStatus`; only the kill-recovery case needs copy of its
    /// own, because the legacy model has no state for "we don't know".
    private var subtitle: String {
        if case .interrupted = state {
            return NSLocalizedString(
                "Registration was interrupted",
                comment: "Usernames — the app closed before the registration finished")
        }
        return state.status?.stateDescription() ?? ""
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .failed:
            DashUIKit.DashButton(
                text: NSLocalizedString("Retry", comment: "Usernames"),
                size: .small,
                style: .tintedBlue,
                action: onTap)
        case .interrupted:
            DashUIKit.DashButton(
                text: NSLocalizedString("Resume", comment: "Usernames — continue an interrupted registration"),
                size: .small,
                style: .tintedBlue,
                action: onTap)
        case .success:
            Button(action: onTap) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
                    .frame(width: Layout.arrowSide, height: Layout.arrowSide)
                    .background(Circle().fill(Color.dash.blue))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("Edit profile", comment: "Usernames")))
        case .hidden, .inProgress:
            EmptyView()
        }
    }

    // MARK: - Progress

    /// Determinate throughout, at the milestones `DWDPRegistrationStatus`
    /// defines — the SDK reports discrete phase transitions, not a continuous
    /// percentage, and a bar that invents motion between them would be lying.
    /// Step 3 legitimately rests at 90% for the whole DPNS round-trip.
    ///
    /// Inset rather than flush with the card's edge as on Android: a flush bar
    /// fights the 20pt continuous corner radius `MenuViewModifier` draws.
    @ViewBuilder
    private var progressBar: some View {
        if let progress = state.progress {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.dash.blueAlpha10)

                    Capsule()
                        .fill(Color.dash.blue)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: Layout.barHeight)
            .animation(.easeInOut(duration: 0.35), value: progress)
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 12)
            .accessibilityValue(Text(verbatim: "\(Int(progress * 100))%"))
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        if isDismissible {
            Button(action: onDismiss) {
                XmarkIcon(size: 10, color: .dash.tertiaryText)
                    .padding(14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("Dismiss", comment: "")))
        }
    }
}

#if DEBUG

/// Previewed on Home's own background, in the width the slot gives it — the
/// tile has no background of its own and its card edge is the whole design.
private func tilePreview(_ state: UsernameTileState) -> some View {
    UsernameRegistrationTile(state: state, onTap: {}, onDismiss: {})
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("In progress — all three steps") {
    VStack(spacing: 0) {
        tilePreview(.inProgress(username: "briantest3", step: .processingPayment))
        tilePreview(.inProgress(username: "briantest3", step: .creatingID))
        tilePreview(.inProgress(username: "briantest3", step: .registrationUsername))
    }
}

/// The failure the user is most likely to hit — the payment step — and the
/// last one, where the money is already spent and Retry means something
/// different.
@available(iOS 17, *)
#Preview("Failed") {
    VStack(spacing: 0) {
        tilePreview(.failed(username: "briantest3", step: .processingPayment))
        tilePreview(.failed(username: "briantest3", step: .registrationUsername))
    }
}

@available(iOS 17, *)
#Preview("Interrupted") {
    tilePreview(.interrupted(username: "briantest3"))
}

@available(iOS 17, *)
#Preview("Success") {
    tilePreview(.success(username: "briantest3"))
}

/// A long username must not push the Retry button off the row or wrap the
/// subtitle into the progress bar — the failure this layout is most likely to
/// have.
@available(iOS 17, *)
#Preview("Long username") {
    VStack(spacing: 0) {
        tilePreview(.inProgress(username: "a-rather-long-dashpay-username", step: .creatingID))
        tilePreview(.failed(username: "a-rather-long-dashpay-username", step: .creatingID))
        tilePreview(.success(username: "a-rather-long-dashpay-username"))
    }
}

#endif
#endif
