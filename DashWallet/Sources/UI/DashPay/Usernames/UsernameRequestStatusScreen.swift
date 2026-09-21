//
//  UsernameRequestStatusScreen.swift
//  DashWallet
//
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
import SwiftDashSDK
import SwiftUI

// MARK: - UsernameRequestStatusViewModel

/// Live status of *this wallet's* pending contested username submission.
///
/// The counterpart to `VotingViewModel`, which is about voting on other
/// people's names. This one answers "how is my own request doing", reading the
/// same contest from Platform and highlighting our own contender.
@MainActor
final class UsernameRequestStatusViewModel: ObservableObject {
    @Published private(set) var voteState: DPNSContestVoteState?
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    /// `false` until the first fetch settles, so "not indexed yet" is not
    /// shown while the first query is still in flight.
    @Published private(set) var hasLoadedOnce = false

    /// The proof-of-identity link published for this request, when there is
    /// one. Read from the `identityVerify` document rather than a local note —
    /// what voters can see is the only thing worth reporting here.
    @Published private(set) var verificationURL: URL?
    @Published private(set) var isPublishingVerification = false
    /// Non-nil drives the failure alert. Cancelling the PIN is not an error.
    @Published var verificationError: String?

    /// The submitted label, as recorded at submission time.
    let label: String
    private let contestsService: ContestedNamesService
    private let identityVerify = IdentityVerifyService.shared

    init(label: String, contestsService: ContestedNamesService? = nil) {
        self.label = label
        self.contestsService = contestsService ?? ContestedNamesService()
    }

    /// Platform's authoritative deadline once the contest is indexed; until
    /// then the conservative submission-time estimate. `nil` when neither is
    /// known — rendered as "Not available yet" rather than a guess.
    var votingEndTime: Date? {
        DWContestedNameStatusService.shared.pendingVotingEndTime
    }

    /// Whether this network can carry a verification link at all
    /// (`identity-verify` is deployed on mainnet and testnet only).
    var canVerifyIdentity: Bool {
        identityVerify.isAvailable
    }

    /// Reads the published link, if any. Silent on failure: the link is extra
    /// information about a request whose status is already on screen, so a
    /// lookup that fails must not present itself as the request failing.
    func refreshVerificationURL() async {
        guard identityVerify.isAvailable else { return }
        verificationURL = try? await identityVerify.publishedURL(forLabel: label)
    }

    /// Publishes `url` as this request's proof of identity (PIN-gated inside
    /// the service). On success the link is what the screen shows from then
    /// on, in place of the invitation to add one.
    func publishVerification(url: URL) async {
        guard !isPublishingVerification else { return }
        isPublishingVerification = true
        defer { isPublishingVerification = false }

        do {
            verificationURL = try await identityVerify.publish(url: url, forLabel: label)
        } catch IdentityVerifyService.ServiceError.authCancelled {
            // The user backed out of the PIN prompt; nothing happened.
        } catch {
            verificationError = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
        }
    }

    /// Our own identity in the base58 form contenders are reported in — and
    /// the form the details screen prints it in.
    var identityIdBase58: String? {
        DWCurrentUserIdentityInfo.shared.identityId.map { ScriptAddressCodec.base58Encode($0) }
    }

    private var myIdentityId: String? { identityIdBase58 }

    func isMe(_ contender: DPNSContender) -> Bool {
        guard let myIdentityId else { return false }
        return contender.identityId == myIdentityId
    }

    /// Our contender row, when Platform has indexed our submission.
    var myContender: DPNSContender? {
        voteState?.contenders.first { isMe($0) }
    }

    var leadingContender: DPNSContender? {
        voteState?.contenders.max { $0.voteTally < $1.voteTally }
    }

    /// `true` when a lock vote currently outranks every contender — the name
    /// would go to nobody rather than to the leader.
    var lockIsLeading: Bool {
        guard let voteState else { return false }
        return voteState.lockVotes > (leadingContender?.voteTally ?? 0)
    }

    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            let normalized = try contestsService.requireNormalizedLabel(for: label)
            voteState = try await contestsService.voteState(normalizedLabel: normalized)
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    #if DASHPAY
    // MARK: Temporary username (DASHPAY only — the field model and the
    // marketplace registration live in dashpay-target-only files)

    /// Input + validation for the non-contested temporary username the
    /// screen offers while the vote is unresolved. Same shared model the
    /// signup flow's contested confirmation sheet uses.
    let temporaryField = TemporaryUsernameFieldModel()

    @Published private(set) var isRegisteringTemporary = false
    /// Non-nil drives the registration-failure alert.
    @Published var temporaryRegistrationError: String?
    /// Set on success — flips the offer section to its confirmation and
    /// keeps it flipped for this screen visit (the identity-info
    /// snapshot also stops reporting an empty username list).
    @Published private(set) var justRegisteredTemporaryUsername: String?

    /// Stateless facade, instantiated per view model by design (see its
    /// type doc). `register(label:)` refuses contested labels, so the
    /// field's non-contested gate has a second line of defense.
    private let marketplaceService = UsernameMarketplaceService()

    /// Offer the temporary-username section only while it can still
    /// help: the vote is unresolved (or not yet indexed — the bookmark
    /// this screen was opened from proves a submission exists) and the
    /// identity owns no other username to be reached at.
    var canOfferTemporaryUsername: Bool {
        guard justRegisteredTemporaryUsername == nil else { return false }
        guard DWCurrentUserIdentityInfo.shared.usernames.isEmpty else { return false }
        guard let voteState else { return true }
        if case .ongoing = voteState.outcome { return true }
        return false
    }

    /// Register the validated temporary username to the existing
    /// identity via the marketplace service (own PIN prompt; refreshes
    /// the identity snapshot on success). PIN cancel is a silent no-op.
    func registerTemporaryUsername() async {
        let label = temporaryField.trimmedText
        guard temporaryField.check == .available, !isRegisteringTemporary else { return }
        isRegisteringTemporary = true
        defer { isRegisteringTemporary = false }
        do {
            try await marketplaceService.register(label: label)
            justRegisteredTemporaryUsername = label
        } catch UsernameMarketplaceService.ServiceError.authCancelled {
            // User backed out of the PIN — keep the section as-is.
        } catch {
            temporaryRegistrationError = UsernameMarketplaceService.userFacingMessage(for: error)
        }
    }
    #endif
}

// MARK: - UsernameRequestStatusScreen

/// "Your username request" — reached from the More menu's DashPay row while a
/// contested submission is still being voted on.
struct UsernameRequestStatusScreen: View {
    @StateObject var viewModel: UsernameRequestStatusViewModel
    /// Pops this screen. Both hosts push it into a stack that hides the UIKit
    /// bar (`BaseNavigationController` leaves it hidden for a plain
    /// `UIHostingController`), so the way back is this screen's own bar —
    /// the same `DashUIKit.NavigationBar` the create-username form uses.
    var onBack: () -> Void = {}
    /// "What is username voting?" — the explainer, one level behind this
    /// screen, exactly as Android places it (`ivInfo` on the request-details
    /// screen, not on the row that leads here).
    @State private var showVotingInfo = false
    /// The proof-of-identity screen: copy the post text, paste the link back.
    @State private var showVerifyIdentity = false

    var body: some View {
        VStack(spacing: 0) {
            // Two controls only, as on Android's toolbar: the way back and the
            // explainer. The screen's own title lives in the intro below it,
            // where it can carry a sentence with it.
            DashUIKit.NavigationBar(
                leading: { DashUIKit.NavigationBarElement.back.button(action: onBack) },
                trailing: {
                    Button {
                        showVotingInfo = true
                    } label: {
                        DashUIKit.InfoRoundIcon(size: 20, color: .dash.blue)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(NSLocalizedString("What is username voting?", comment: "Usernames"))
                })

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashUIKit.TopIntroView(
                        title: NSLocalizedString("Request details", comment: "Usernames"),
                        mainDescription: votingPeriodStatus)
                        .padding(.horizontal, 20)

                    detailsCard

                    if let loadError = viewModel.loadError {
                        VotingBanner(text: loadError, tone: .error)
                            .padding(.horizontal, 20)
                    }

                    // Four rows and nothing else, as on Android's request
                    // details. The contenders list, the masternode tallies and
                    // the companion-name offer used to sit here; the offer is
                    // part of the submission flow (the instant-username sheet)
                    // and the tallies answer a question this screen does not
                    // ask.
                    if !viewModel.hasLoadedOnce, viewModel.loadError == nil {
                        caption(NSLocalizedString("Checking the contest…", comment: "Usernames"))
                    }
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable {
                await viewModel.refresh()
                await viewModel.refreshVerificationURL()
            }
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
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
        .task {
            await viewModel.refresh()
            await viewModel.refreshVerificationURL()
        }
        .sheet(isPresented: $showVerifyIdentity) {
            // The library's sheet, not a `NavigationView` with a Cancel item:
            // its close control is the way out, and the screen carries its own
            // heading — a navigation title on top of it was the same words
            // twice.
            DashUIKit.BottomSheet.selfSizing(
                showBackButton: .constant(false),
                fallback: 600
            ) {
                VerifyIdentityScreen(
                    username: viewModel.label,
                    onConfirmed: { url in
                        showVerifyIdentity = false
                        guard let url else { return }
                        Task { await viewModel.publishVerification(url: url) }
                    })
            }
        }
        .alert(
            NSLocalizedString("Could not publish the link", comment: "Usernames"),
            isPresented: Binding(
                get: { viewModel.verificationError != nil },
                set: { if !$0 { viewModel.verificationError = nil } })
        ) {
            Button(NSLocalizedString("OK", comment: "")) { viewModel.verificationError = nil }
        } message: {
            Text(viewModel.verificationError ?? "")
        }
        #if DASHPAY
        .alert(
            NSLocalizedString("Registration failed", comment: "Usernames"),
            isPresented: Binding(
                get: { viewModel.temporaryRegistrationError != nil },
                set: { if !$0 { viewModel.temporaryRegistrationError = nil } }
            )
        ) {
            Button(NSLocalizedString("OK", comment: "")) {
                viewModel.temporaryRegistrationError = nil
            }
        } message: {
            Text(viewModel.temporaryRegistrationError ?? "")
        }
        #endif
    }

    /// Describes only what Platform actually reported. A contest that is not
    /// indexed yet says so instead of implying voting is under way.
    /// Row metrics copied from `OrderPreviewView`, so a detail row here reads
    /// as the same component the swap flow shows.
    private enum Layout {
        static let cardSpacing: CGFloat = 2
        static let rowHPadding: CGFloat = 14
        static let rowVPadding: CGFloat = 12
        static let labelSpacing: CGFloat = 20
        static let rowMinHeight: CGFloat = 46
    }

    /// The four rows Android's request-details screen carries: the name, the
    /// proof link, the identity it was requested by, and when the result is
    /// due.
    private var detailsCard: some View {
        card {
            detailRow(NSLocalizedString("Username", comment: "Usernames")) {
                Text(viewModel.label)
            }

            detailRow(NSLocalizedString("Link", comment: "Usernames")) {
                linkValue
            }

            detailRow(NSLocalizedString("Identity", comment: "Usernames")) {
                Text(identityText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            detailRow(NSLocalizedString("Results", comment: "Usernames")) {
                Text(resultsText)
            }
        }
    }

    /// Published link, the invitation to add one, or nothing to show — the
    /// three states Android puts in this slot (`linkLayout` / `verifyNowLayout`
    /// / `none`).
    @ViewBuilder
    private var linkValue: some View {
        if let url = viewModel.verificationURL {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Text(url.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.up.right.square")
                }
                .foregroundStyle(Color.dash.blue)
            }
        } else if viewModel.canVerifyIdentity {
            Button {
                showVerifyIdentity = true
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isPublishingVerification {
                        // `SwiftUI.ProgressView` spelled out: the app has a
                        // UIKit `ProgressView` of its own, and the bare name
                        // resolves to it.
                        SwiftUI.ProgressView()
                    }
                    Text(NSLocalizedString("Verify Now", comment: "Usernames"))
                }
                .foregroundStyle(Color.dash.blue)
            }
            .disabled(viewModel.isPublishingVerification)
        } else {
            Text(NSLocalizedString("None", comment: "Usernames"))
                .foregroundStyle(Color.dash.tertiaryText)
        }
    }

    /// The identity that owns the request, in the base58 form Platform reports
    /// contenders in. Truncated in the middle by the row, never shortened here
    /// — a partial id that looks complete is worse than an elided one.
    private var identityText: String {
        viewModel.identityIdBase58 ?? NSLocalizedString("Not available yet", comment: "Usernames")
    }

    /// When the result is due, or what it was once the vote is over. Android
    /// assumes a finished vote means the name went to someone else; we have the
    /// outcome from Platform, so the real one is reported instead.
    private var resultsText: String {
        if let voteState = viewModel.voteState, case .ongoing = voteState.outcome {
            return votingEndText
        }
        if viewModel.voteState != nil {
            return statusText
        }
        return votingEndText
    }

    private var votingEndText: String {
        guard let endTime = viewModel.votingEndTime else {
            return NSLocalizedString("Not available yet", comment: "Usernames")
        }
        return DWDateFormatter.sharedInstance.dateAndTime(from: endTime)
    }

    /// The sentence under the title, as Android words it — and its
    /// past-tense twin once voting is over.
    private var votingPeriodStatus: String {
        if let voteState = viewModel.voteState, case .ongoing = voteState.outcome {
            return NSLocalizedString("After the voting ends we will notify you about its results", comment: "Usernames")
        }
        if viewModel.voteState != nil {
            return NSLocalizedString("Voting has ended", comment: "Usernames")
        }
        return NSLocalizedString("After the voting ends we will notify you about its results", comment: "Usernames")
    }

    /// One labelled row, with the metrics of `OrderPreviewTableRow`. A
    /// `ViewBuilder` trailing rather than a string: two of the four rows are a
    /// link and a button.
    @ViewBuilder
    private func detailRow<Value: View>(
        _ label: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .top, spacing: Layout.labelSpacing) {
            Text(label)
                .dashFont(.subheadMedium)
                .foregroundColor(Color.dash.tertiaryText)
                .fixedSize()

            value()
                .dashFont(.subhead)
                .foregroundColor(Color.dash.primaryText)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Layout.rowHPadding)
        .padding(.vertical, Layout.rowVPadding)
        .frame(minHeight: Layout.rowMinHeight)
    }

    /// A card of rows, optionally captioned — the grouping `OrderPreviewView`
    /// uses for its table.
    @ViewBuilder
    private func card<Content: View>(
        _ caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let caption {
                Text(caption)
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
                    .padding(.horizontal, 20)
            }

            VStack(spacing: Layout.cardSpacing) {
                content()
            }
            .modifier(MenuViewModifier(shadowRadius: 20))
            .padding(.horizontal, 20)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .dashFont(.footnote)
            .foregroundStyle(Color.dash.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
    }

    private var statusText: String {
        guard let voteState = viewModel.voteState else {
            return viewModel.hasLoadedOnce
                ? NSLocalizedString("Waiting for Dash Platform", comment: "Usernames")
                : NSLocalizedString("Checking…", comment: "Usernames")
        }
        switch voteState.outcome {
        case .ongoing:
            if viewModel.lockIsLeading {
                return NSLocalizedString("Voting in progress — lock votes are ahead", comment: "Usernames")
            }
            if let mine = viewModel.myContender, mine.id == viewModel.leadingContender?.id {
                return NSLocalizedString("Voting in progress — you are ahead", comment: "Usernames")
            }
            return NSLocalizedString("Voting in progress", comment: "Usernames")
        case .wonBy(let identityId):
            return identityId == viewModel.myContender?.identityId
                ? NSLocalizedString("You won this username", comment: "Usernames")
                : NSLocalizedString("This username went to someone else", comment: "Usernames")
        case .locked:
            return NSLocalizedString("Locked — nobody receives this username", comment: "Usernames")
        case .noWinner:
            return NSLocalizedString("Voting ended with no winner", comment: "Usernames")
        }
    }

    private var statusColor: Color {
        guard let voteState = viewModel.voteState else { return Color.dash.secondaryText }
        switch voteState.outcome {
        case .ongoing: return Color.dash.secondaryText
        case .wonBy(let identityId):
            return identityId == viewModel.myContender?.identityId ? .green : .red
        case .locked, .noWinner: return .orange
        }
    }
}
