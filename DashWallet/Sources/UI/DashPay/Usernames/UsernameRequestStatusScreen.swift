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

    /// The submitted label, as recorded at submission time.
    let label: String
    private let contestsService: ContestedNamesService

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

    /// Our own identity in the base58 form contenders are reported in.
    private var myIdentityId: String? {
        DWCurrentUserIdentityInfo.shared.identityId.map { ScriptAddressCodec.base58Encode($0) }
    }

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

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    // `label` here is the submission as the user typed it,
                    // straight from our own bookmark — already the display
                    // form, so no decode is involved.
                    Text(viewModel.label)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(statusColor)
                }
                .padding(.vertical, 4)

                HStack {
                    Text(NSLocalizedString("Voting ends", comment: "Usernames"))
                        .foregroundColor(Color.dash.secondaryText)
                    Spacer()
                    if let endTime = viewModel.votingEndTime {
                        Text(DWDateFormatter.sharedInstance.dateAndTime(from: endTime))
                    } else {
                        Text(NSLocalizedString("Not available yet", comment: "Usernames"))
                            .foregroundColor(Color.dash.tertiaryText)
                    }
                }
                .font(.subheadline)
            }

            if let loadError = viewModel.loadError {
                Section {
                    VotingBanner(text: loadError, tone: .error).listRowInsets(EdgeInsets())
                }
            }

            #if DASHPAY
            // The gap this closes: a user whose FIRST username went to a
            // vote has no username at all until it resolves. Offer the
            // same non-contested temporary username the signup flow now
            // prompts for — here, registered to the already-existing
            // identity.
            if viewModel.canOfferTemporaryUsername {
                TemporaryUsernameRegistrationSection(
                    viewModel: viewModel,
                    temporaryField: viewModel.temporaryField)
            } else if let registered = viewModel.justRegisteredTemporaryUsername {
                Section {
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString(
                            "“%1$@” is now your username. If the vote awards you “%2$@”, you will be reachable at both usernames.",
                            comment: "Usernames"),
                        registered,
                        viewModel.label))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }
            #endif

            if let voteState = viewModel.voteState {
                Section(NSLocalizedString("Who is requesting this name", comment: "Usernames")) {
                    ForEach(voteState.contenders) { contender in
                        ContestantStatusRow(
                            contender: contender,
                            isMe: viewModel.isMe(contender),
                            isLeading: contender.id == viewModel.leadingContender?.id
                                && !viewModel.lockIsLeading)
                    }
                }

                Section(NSLocalizedString("Masternode votes", comment: "Usernames")) {
                    LabeledContent(
                        NSLocalizedString("Lock the name", comment: "Usernames"),
                        value: "\(voteState.lockVotes)")
                    LabeledContent(
                        NSLocalizedString("Abstain", comment: "Usernames"),
                        value: "\(voteState.abstainVotes)")
                }
            } else if viewModel.hasLoadedOnce && viewModel.loadError == nil {
                Section {
                    Text(NSLocalizedString(
                        "Dash Platform has not indexed this contest yet. Vote counts appear here once it does.",
                        comment: "Usernames"))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }

            Section {
                Text(NSLocalizedString(
                    "Masternodes vote on names more than one person requested. You will be notified when voting ends.",
                    comment: "Usernames"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            }
        }
        .navigationTitle(NSLocalizedString("Request details", comment: "Usernames"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
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

#if DASHPAY
// MARK: - TemporaryUsernameRegistrationSection

/// "Add a temporary username" list section: explainer, the shared
/// validated field, and the register action. A separate struct (rather
/// than inline in the screen body) so it observes the field model
/// directly — the register button's enabled state must re-render on
/// every validation change, and nested `ObservableObject`s don't
/// propagate through the parent's `@StateObject`.
private struct TemporaryUsernameRegistrationSection: View {
    @ObservedObject var viewModel: UsernameRequestStatusViewModel
    @ObservedObject var temporaryField: TemporaryUsernameFieldModel

    var body: some View {
        Section(NSLocalizedString("Add a temporary username", comment: "Usernames")) {
            Text(String.localizedStringWithFormat(
                NSLocalizedString(
                    "You do not have a username while the vote is in progress. Register a non-contested username now — it is yours to keep, and if the vote awards you “%@”, you will be reachable at both usernames.",
                    comment: "Usernames"),
                viewModel.label))
                .font(.caption)
                .foregroundColor(Color.dash.secondaryText)

            TemporaryUsernameField(model: temporaryField)
                .padding(.vertical, 4)

            DashButton(
                text: NSLocalizedString("Register username", comment: "Usernames"),
                size: .medium,
                isEnabled: temporaryField.check == .available && !viewModel.isRegisteringTemporary,
                isLoading: viewModel.isRegisteringTemporary
            ) {
                Task { await viewModel.registerTemporaryUsername() }
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            temporaryField.seedSuggestion(from: viewModel.label)
        }
    }
}
#endif

// MARK: - ContestantStatusRow

private struct ContestantStatusRow: View {
    let contender: DPNSContender
    let isMe: Bool
    let isLeading: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe
                     ? NSLocalizedString("You", comment: "Usernames")
                     : contender.displayNameOrIdentity)
                    .font(.subheadline)
                    .fontWeight(isMe ? .semibold : .regular)
                    .monospaced(!isMe && contender.displayLabel == nil)
                Text(String(format: NSLocalizedString("%u votes", comment: "Voting"),
                            contender.voteTally))
                    .font(.caption)
                    .foregroundColor(isLeading ? .green : Color.dash.secondaryText)
            }

            Spacer()

            if isLeading {
                Text(NSLocalizedString("Leading", comment: "Usernames"))
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 2)
    }
}
