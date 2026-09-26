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

public struct JoinDashPayInfoDialog: View {
    @Environment(\.presentationMode) private var presentationMode
    var action: () -> Void
    /// Non-nil surfaces the "Have an invitation?" redeem entry on the
    /// embedded join screen; the dialog dismisses before forwarding.
    var onClaimInvitation: (() -> Void)? = nil
    /// Non-nil lets the privacy page offer "Shield your funds first"; the
    /// dialog dismisses before forwarding, same as the invitation entry.
    /// Routed from both presenters — Home and the More menu.
    var onShieldFunds: (() -> Void)? = nil
    #if DEBUG
    /// Preview-only: a posed view model handed to the embedded screen so the
    /// canvas never builds `CreateUsernameViewModel.shared`. nil in the app.
    var previewViewModel: CreateUsernameViewModel? = nil
    #endif

    /// The pages this sheet walks through, in order. Paging is state here
    /// rather than a `NavigationLink` inside each screen — the sheet owns its
    /// own chrome, so the back leg is `BottomSheet`'s back button and no
    /// navigation stack is needed.
    private enum Page {
        case join
        case fundingPrivacy
        case votingInfo

        /// Where the back button goes, and by the same token whether there is
        /// one at all.
        ///
        /// Every case returns nil: each step's answers are all ways forward,
        /// and the voting explanation is the last word before the form — a back
        /// arrow there offers to un-answer a funding choice the flow has
        /// already acted on. The back plumbing below is kept, and kept
        /// exercised by this one property, so that naming a predecessor here is
        /// all it takes to bring the leg back.
        var back: Page? {
            switch self {
            case .join, .fundingPrivacy, .votingInfo: return nil
            }
        }
    }

    @State private var page: Page = .join

    /// Which way the pending page change travels. The pages slide the way a
    /// push and a pop do — forward enters from the trailing edge, back from
    /// the leading one — and that reads from the direction, not from the page.
    @State private var isMovingBack = false


    public var body: some View {
        // `selfSizing` rather than a pinned detent: each page is a different
        // height, and the join screen's own height moves with the balance line
        // and with however many lines each feature description wraps to. A
        // fixed height truncated them. `fallback` is only what the sheet shows
        // before the first measurement lands.
        DashUIKit.BottomSheet.selfSizing(
            showBackButton: Binding(
                get: { page.back != nil },
                set: { _ in }),
            onBackButtonPressed: { goBack() },
            showsCloseButton: false,
            fallback: 600
        ) {
            // A ZStack, not a plain `switch`: both pages have to be on screen
            // at once for one to slide out while the other slides in. It is
            // top-aligned so the pages line up under the sheet's header while
            // they cross, rather than drifting from a shared centre.
            ZStack(alignment: .top) {
                switch page {
                case .join:
                    joinScreen
                        .modifier(PageLayout(transition: pageTransition))
                case .fundingPrivacy:
                    privacyScreen
                        .modifier(PageLayout(transition: pageTransition))
                case .votingInfo:
                    VotingInfoScreen(action: finishFlow)
                        .modifier(PageLayout(transition: pageTransition))
                }
            }
            // The container clips, or the leaving page keeps drawing past the
            // sheet's edges, over the dimmed background behind it.
            .clipped()
        }
    }

    // MARK: - Paging

    private func go(to next: Page) {
        isMovingBack = false
        withAnimation(Self.pageChange) { page = next }
    }

    private func goBack() {
        guard let back = page.back else { return }

        isMovingBack = true
        withAnimation(Self.pageChange) { page = back }
    }

    /// Matches a navigation push closely enough to read as one, while staying
    /// short — the sheet also resizes to the new page's height underneath it,
    /// and a slower slide makes the two look like separate movements.
    private static let pageChange: Animation = .easeInOut(duration: 0.22)

    /// A push slides, it does not fade: combining the two made the pages read
    /// as dissolving past each other rather than as one replacing the other.
    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isMovingBack ? .leading : .trailing),
            removal: .move(edge: isMovingBack ? .trailing : .leading))
    }

    /// Every page is laid out to the sheet's full width, so a page slides its
    /// own width rather than the width of its widest line — and so its text
    /// wraps against the sheet instead of being offered an ideal width by the
    /// ZStack and truncating.
    private struct PageLayout: ViewModifier {
        let transition: AnyTransition

        func body(content: Content) -> some View {
            content
                // The sheet self-sizes by measuring what it renders, and the
                // ZStack this page sits in would otherwise report whatever
                // height it was handed — which is the fallback detent, fed
                // back to itself forever, with every line inside squeezed to
                // fit it. Asking for the page's own ideal height breaks that
                // loop; `BottomSheet` does the same for single-page sheets.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .top)
                .transition(transition)
        }
    }

    private var privacyScreen: some View {
        UsernameFundingPrivacyScreen(
            // The pick itself is recorded on the shared
            // `CreateUsernameViewModel` by the page that asks: this dialog
            // hands off to a presenter that routes through the Home shortcut
            // dispatcher, which carries no payload, so passing the value up
            // through the callback would only strand it here.
            onContinue: { _ in
                go(to: .votingInfo)
            },
            onShieldFunds: onShieldFunds.map { shield in
                {
                    presentationMode.wrappedValue.dismiss()
                    shield()
                }
            })
    }

    /// Closes the sheet and hands over to the presenter, which starts the
    /// create-username flow from its `onDismiss` (`HomeView`,
    /// `MainMenuViewController`) — the dialog itself never navigates.
    private func finishFlow() {
        presentationMode.wrappedValue.dismiss()
        action()
    }

    @ViewBuilder
    private var joinScreen: some View {
        let onContinue = { go(to: .fundingPrivacy) }
        let onClaim = onClaimInvitation.map { claim in
            {
                presentationMode.wrappedValue.dismiss()
                claim()
            }
        }

        #if DEBUG
        if let previewViewModel {
            JoinDashPayScreen(
                previewViewModel: previewViewModel,
                action: onContinue,
                onClaimInvitation: onClaim
            )
        } else {
            JoinDashPayScreen(action: onContinue, onClaimInvitation: onClaim)
        }
        #else
        JoinDashPayScreen(action: onContinue, onClaimInvitation: onClaim)
        #endif
    }
}

// MARK: - Previews

#if DEBUG

/// The sheet exactly as `HomeView` and the More menu present it, at the
/// `.height(600)` detent both call sites pin — with a balance that already
/// covers a contested name.
#Preview("Sheet — enough for a contested name") {
    Color.dash.secondaryBackground
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            JoinDashPayInfoDialog(
                action: {},
                onClaimInvitation: {},
                previewViewModel: .makeForPreview(
                    balance: "0.30000000",
                    hasMinimumRequiredBalance: true,
                    hasRecommendedBalance: true)
            )
        }
}

/// Same sheet for a wallet that cannot cover a contested name — the state the
/// redesign gives its own button treatment.
#Preview("Sheet — not enough for a contested name") {
    Color.dash.secondaryBackground
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            JoinDashPayInfoDialog(
                action: {},
                onClaimInvitation: {},
                previewViewModel: .makeForPreview(
                    balance: "0.00999774",
                    shieldedReadiness: ShieldedIdentityFundingReadiness.Snapshot(
                        state: .needsFunding(shortfallCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits),
                        requiredCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits,
                        matureCredits: 0,
                        unspentCredits: 0,
                        poolNoteCount: nil))
            )
        }
}

#endif
