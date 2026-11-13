//
//  RequestDetailsScreen.swift
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

// MARK: - RequestDetailsScreen

/// One request for a username: what its author published to show the name is
/// theirs, and the control to approve it (or take the approval back). Opened
/// straight from a request row.
struct RequestDetailsScreen: View {
    @ObservedObject var voting: VotingViewModel
    @StateObject private var viewModel: RequestDetailsViewModel
    @State private var voteRequest: VoteFlowRequest?
    @Environment(\.dismiss) private var dismiss

    init(voting: VotingViewModel, normalizedLabel: String, identityId: String) {
        self.voting = voting
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        _viewModel = StateObject(wrappedValue: RequestDetailsViewModel(
            store: voting.store,
            normalizedLabel: normalizedLabel,
            identityId: identityId,
            linkLookup: RequestDetailsViewModel.publishedLink,
            dateFormatter: formatter,
            openLink: { UIApplication.shared.open($0) }))
    }

    var body: some View {
        RequestDetailsContent(
            username: viewModel.username,
            identityId: viewModel.identityId,
            linkState: viewModel.linkState,
            linkText: viewModel.linkText,
            votingPeriodText: viewModel.votingPeriodText,
            approveTitle: viewModel.approveTitle,
            isApproveEnabled: viewModel.canApprove,
            isSending: voting.isSending(normalizedLabel: viewModel.normalizedLabel),
            isBackEnabled: !voting.store.isVoteBusy,
            onBack: { dismiss() },
            onRetry: { Task { await viewModel.loadLink() } },
            onOpenLink: viewModel.open,
            onApprove: { voteRequest = viewModel.voteRequest() })
            .task { await viewModel.loadLink() }
            .task {
                // The list already loaded it in most cases.
                if !voting.hasLoadedVoteHistory(for: viewModel.normalizedLabel) {
                    await voting.loadVotedNodes(for: viewModel.normalizedLabel)
                }
            }
            .voteFlow($voteRequest, viewModel: voting)
            // A vote started here shows its result here; leaving mid-vote
            // would take the result sheet with it. Hiding the system back
            // button also holds the swipe-back.
            .navigationBarBackButtonHidden(voting.store.isVoteBusy)
            // A failed or already held vote is told here; a vote that landed is told by the list.
            .overlay(alignment: .bottom) {
                if let toast = voting.toast, viewModel.showsToast(toast) {
                    toast.view(onClose: voting.list.clearToast)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 92)
                }
            }
            .onReceive(voting.store.$outcome.dropFirst()) { outcome in
                if viewModel.returnsToList(after: outcome) { dismiss() }
            }
    }
}

// MARK: - RequestDetailsContent

/// The screen's layout, from plain values so it previews without a wallet.
struct RequestDetailsContent: View {
    let username: String
    let identityId: String
    let linkState: RequestDetailsViewModel.LinkState
    let linkText: String?
    let votingPeriodText: String
    let approveTitle: String
    let isApproveEnabled: Bool
    let isSending: Bool
    var isBackEnabled = true
    let onBack: () -> Void
    let onRetry: () -> Void
    let onOpenLink: (URL) -> Void
    let onApprove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: {
                    DashUIKit.NavigationBarElement.back.button(action: onBack)
                        .disabled(!isBackEnabled)
                })

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashUIKit.TopIntroView(
                        title: NSLocalizedString("Request details", comment: "Voting"),
                        mainDescription: NSLocalizedString(
                            "Review the posting below to verify the ownership of this username",
                            comment: "Voting"))
                        .padding(.horizontal, 20)

                    VStack(spacing: 10) {
                        RequestDetailField(label: NSLocalizedString("Username", comment: "Voting"), text: username)
                        RequestDetailField(label: NSLocalizedString("Link", comment: "Voting")) { linkValue }
                        RequestDetailField(label: NSLocalizedString("Identity", comment: "Voting"), text: identityId)
                        RequestDetailField(
                            label: NSLocalizedString("Voting period", comment: "Voting"),
                            text: votingPeriodText)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            DashUIKit.DashButton(
                text: approveTitle,
                isEnabled: isApproveEnabled,
                isLoading: isSending,
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: onApprove)
                .padding(20)
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private var linkValue: some View {
        switch linkState {
        case .reading:
            SwiftUI.ProgressView()
                .accessibilityLabel(NSLocalizedString("Checking…", comment: "Voting"))
        case .none:
            Text(linkText ?? "").foregroundStyle(Color.dash.secondaryText)
        case .failed:
            // Not «Not provided»: the check never ran.
            VStack(alignment: .leading, spacing: 8) {
                Text(linkText ?? "").foregroundStyle(Color.dash.secondaryText)
                DashUIKit.DashButton(
                    text: NSLocalizedString("Try again", comment: ""),
                    size: .small,
                    style: .plainBlue,
                    action: onRetry)
            }
        case .published(let url) where RequestDetailsViewModel.isOpenableInBrowser(url):
            // The full address is the text, so the owner sees the real
            // destination before tapping; it opens outside the app.
            Button { onOpenLink(url) } label: {
                Text(url.absoluteString)
                    .foregroundStyle(Color.dash.blue)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isLink)
            .accessibilityRemoveTraits(.isButton)
        case .published(let url):
            // Written by anyone, through any client; a custom-scheme value
            // handed to the system opener is an attacker's choice of action.
            // Show it, do not offer it.
            Text(url.absoluteString).foregroundStyle(Color.dash.secondaryText)
        }
    }
}

// MARK: - Previews

#if DEBUG
private enum DetailsPreview {
    static let identity = "90f95ff7bc2438a748dc8470255b888e1a2b3c4d5e6f708192a3b4c5d6e7f809"

    static func content(
        username: String = "johndoe",
        identity: String = identity,
        link: RequestDetailsViewModel.LinkState,
        linkText: String?,
        period: String = "Not provided – Oct 25, 2026",
        approve: String = "Vote to approve",
        isApproveEnabled: Bool = true,
        isSending: Bool = false,
        isBackEnabled: Bool = true
    ) -> some View {
        RequestDetailsContent(
            username: username, identityId: identity, linkState: link, linkText: linkText,
            votingPeriodText: period, approveTitle: approve, isApproveEnabled: isApproveEnabled, isSending: isSending,
            isBackEnabled: isBackEnabled, onBack: {}, onRetry: {}, onOpenLink: { _ in }, onApprove: {})
    }
}

#Preview("Link published") {
    DetailsPreview.content(
        link: .published(URL(string: "https://x.com/johndoe/status/1")!),
        linkText: "https://x.com/johndoe/status/1")
}
#Preview("Link reading") { DetailsPreview.content(link: .reading, linkText: nil) }
#Preview("Link none") { DetailsPreview.content(link: .none, linkText: "Not provided") }
#Preview("Link failed") { DetailsPreview.content(link: .failed, linkText: "Couldn't check for a link") }
#Preview("My approve") {
    DetailsPreview.content(
        link: .none, linkText: "Not provided", approve: "Cancel approval")
}
#Preview("Long username and identity") {
    DetailsPreview.content(
        username: "averyveryveryverylongusernamethatkeepsgoingandgoingtowrap",
        identity: DetailsPreview.identity + DetailsPreview.identity,
        link: .published(URL(string: "https://example.com/a/very/long/path/that/wraps/over/lines/johndoe")!),
        linkText: "https://example.com/a/very/long/path/that/wraps/over/lines/johndoe")
}
#Preview("Approve disabled") {
    DetailsPreview.content(link: .none, linkText: "Not provided", isApproveEnabled: false)
}
#Preview("Sending") {
    DetailsPreview.content(link: .none, linkText: "Not provided", isSending: true, isBackEnabled: false)
}
#Preview("Sending · other contest") {
    DetailsPreview.content(link: .none, linkText: "Not provided", isApproveEnabled: false, isBackEnabled: false)
}
#Preview("No voting end") {
    DetailsPreview.content(link: .none, linkText: "Not provided", period: "Not provided")
}
#Preview("Dark") {
    DetailsPreview.content(
        link: .published(URL(string: "https://x.com/johndoe")!), linkText: "https://x.com/johndoe")
        .preferredColorScheme(.dark)
}
#endif
