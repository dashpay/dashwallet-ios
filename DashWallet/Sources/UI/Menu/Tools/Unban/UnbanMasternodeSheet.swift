//
//  Created by Claude Code
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftDashSDK
import SwiftUI

/// Confirm-and-submit sheet for unbanning a PoSe-banned masternode: shows
/// what will be re-asserted, collects the evonode P2P port (and, when the
/// node pays an operator reward, the payout address), and walks the guided
/// shielded top-up when the wallet has no spendable DASH for the fee.
struct UnbanMasternodeSheet: View {
    @StateObject private var viewModel: MasternodeUnbanViewModel
    @Environment(\.dismiss) private var dismiss
    /// Called after a successful submit so the presenting detail screen can
    /// refresh its status badge.
    let onSubmitted: () -> Void

    init(record: PlatformMasternode, keySource: UnbanOperatorKeySource, onSubmitted: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: MasternodeUnbanViewModel(record: record, keySource: keySource))
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                if viewModel.isEvonode {
                    p2pPortSection
                }
                if viewModel.payoutAddressRequired {
                    payoutSection
                }
                fundingSection
                reviewToggleSection
                previewSection
                submitSection
            }
            .navigationTitle(NSLocalizedString("Unban masternode", comment: "Masternode unban"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: "")) { dismiss() }
                }
            }
            .onAppear { viewModel.resumePendingIfAny() }
        }
    }

    private var overviewSection: some View {
        Section {
            MasternodeDetailRow(
                label: NSLocalizedString("Masternode", comment: "Masternodes"),
                value: viewModel.record.label ?? viewModel.record.displayTitle)
            if let service = viewModel.record.serviceAddress {
                MasternodeDetailRow(
                    label: NSLocalizedString("Service", comment: "Masternodes"),
                    value: service)
            }
            MasternodeCopyRow(label: "proTxHash", value: viewModel.record.proTxHashHex)
        } footer: {
            Text(NSLocalizedString(
                "Unbanning broadcasts a provider update signed with the operator key, re-asserting the service address shown above. The masternode returns to the valid list within a few blocks.",
                comment: "Masternode unban"))
        }
    }

    private var p2pPortSection: some View {
        Section {
            TextField("26656", text: $viewModel.p2pPortText)
                .keyboardType(.numberPad)
        } header: {
            Text(NSLocalizedString("Platform P2P port", comment: "Masternode unban"))
        } footer: {
            Text(NSLocalizedString(
                "The masternode list doesn't carry an evonode's Platform P2P port, so it must be confirmed here. 26656 is the standard port — change it only if this node uses another.",
                comment: "Masternode unban"))
        }
    }

    private var payoutSection: some View {
        Section {
            TextField(
                NSLocalizedString("Operator payout address", comment: "Masternode unban"),
                text: $viewModel.payoutAddressText)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text(NSLocalizedString("Operator payout address", comment: "Masternode unban"))
        } footer: {
            Text(NSLocalizedString(
                "This masternode pays an operator reward, and the update replaces its payout address on-chain — confirm the address the operator reward should keep paying.",
                comment: "Masternode unban"))
        }
    }

    @ViewBuilder
    private var fundingSection: some View {
        switch viewModel.phase {
        case .needsFunds:
            Section(NSLocalizedString("Network fee", comment: "Masternode unban")) {
                Text(NSLocalizedString(
                    "The wallet has no spendable DASH for the network fee.",
                    comment: "Masternode unban"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
                if viewModel.canTopUp {
                    Button {
                        Task { await viewModel.topUpFromShielded() }
                    } label: {
                        Label(
                            String(
                                format: NSLocalizedString("Move %@ from shielded balance", comment: "Masternode unban"),
                                viewModel.topUpAmountText),
                            systemImage: "shield.lefthalf.filled")
                            .foregroundColor(Color.dash.blue)
                    }
                    Text(NSLocalizedString(
                        "The transfer settles through the network's withdrawal queue — usually a few minutes. You can close this sheet and come back; the unban resumes where it left off.",
                        comment: "Masternode unban"))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                } else {
                    Text(NSLocalizedString(
                        "Receive some DASH to this wallet, or fund its shielded balance, then return here.",
                        comment: "Masternode unban"))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }
        case .toppingUp:
            Section(NSLocalizedString("Network fee", comment: "Masternode unban")) {
                HStack(spacing: 8) {
                    SwiftUI.ProgressView().scaleEffect(0.8)
                    Text(NSLocalizedString("Moving funds from the shielded balance…", comment: "Masternode unban"))
                        .foregroundColor(Color.dash.secondaryText)
                }
            }
        case .waitingForFunds:
            Section(NSLocalizedString("Network fee", comment: "Masternode unban")) {
                HStack(spacing: 8) {
                    SwiftUI.ProgressView().scaleEffect(0.8)
                    Text(NSLocalizedString("Funds are on the way…", comment: "Masternode unban"))
                        .foregroundColor(Color.dash.secondaryText)
                }
                Text(NSLocalizedString(
                    "The withdrawal settles through the network's withdrawal queue — usually a few minutes. You can close this sheet; \"Complete unban\" appears on the masternode until it's done.",
                    comment: "Masternode unban"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            }
        default:
            EmptyView()
        }
    }

    /// Opt-in review (off by default): with it on, Unban builds and signs
    /// the transaction and shows it instead of sending it.
    @ViewBuilder
    private var reviewToggleSection: some View {
        if viewModel.preview == nil {
            Section {
                Toggle(
                    NSLocalizedString("Review transaction first", comment: "Masternode unban"),
                    isOn: $viewModel.reviewBeforeBroadcast)
            } footer: {
                Text(NSLocalizedString(
                    "Build and sign the transaction and show it here, so you can check it before it's broadcast.",
                    comment: "Masternode unban"))
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview = viewModel.preview {
            Section {
                MasternodeDetailRow(
                    label: NSLocalizedString("Network fee", comment: "Masternode unban"),
                    value: preview.feeDuffs.formattedDashAmount)
                MasternodeDetailRow(
                    label: NSLocalizedString("Size", comment: "Masternode unban"),
                    value: String(
                        format: NSLocalizedString("%d bytes", comment: "Masternode unban"),
                        preview.sizeBytes))
                MasternodeDetailRow(
                    label: NSLocalizedString("Inputs", comment: "Masternode unban"),
                    value: "\(preview.inputCount)")
                ForEach(Array(preview.outputs.enumerated()), id: \.offset) { _, output in
                    MasternodeDetailRow(
                        label: NSLocalizedString("Change", comment: "Masternode unban"),
                        value: "\(output.amountDuffs.formattedDashAmount) → \(output.address)")
                }
            } header: {
                Text(NSLocalizedString("Transaction", comment: "Masternode unban"))
            } footer: {
                Text(NSLocalizedString(
                    "This is the signed transaction, exactly as it will be broadcast.",
                    comment: "Masternode unban"))
            }

            Section(NSLocalizedString("Provider update payload", comment: "Masternode unban")) {
                ForEach(preview.payloadFields, id: \.label) { field in
                    MasternodeCopyRow(label: field.label, value: field.value)
                }
            }

            Section {
                DisclosureGroup(NSLocalizedString("Raw transaction", comment: "Masternode unban")) {
                    Text(preview.rawHex)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var submitSection: some View {
        Section {
            switch viewModel.phase {
            case .submitted(let txidHex):
                Label(
                    NSLocalizedString("Unban submitted", comment: "Masternode unban"),
                    systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                MasternodeCopyRow(label: "txid", value: txidHex)
                Text(NSLocalizedString(
                    "The masternode should return to the valid list within a few blocks. Refresh its details in a few minutes.",
                    comment: "Masternode unban"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
                Button(NSLocalizedString("Done", comment: "")) {
                    onSubmitted()
                    dismiss()
                }
            case .submitting:
                HStack(spacing: 8) {
                    SwiftUI.ProgressView().scaleEffect(0.8)
                    Text(NSLocalizedString("Broadcasting…", comment: "Masternode unban"))
                }
                .frame(maxWidth: .infinity)
            case .previewing:
                Button {
                    Task { await viewModel.broadcastReviewed() }
                } label: {
                    Text(NSLocalizedString("Broadcast", comment: "Masternode unban"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                Button(role: .destructive) {
                    viewModel.discardReviewed()
                } label: {
                    Text(NSLocalizedString("Discard", comment: "Masternode unban"))
                        .frame(maxWidth: .infinity)
                }
            default:
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    Text(NSLocalizedString("Unban", comment: "Masternode unban"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.canSubmit)
            }
        } footer: {
            if let error = viewModel.errorText {
                Text(error).foregroundColor(.red)
            }
        }
    }
}
