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

// MARK: - AddMasternodeScreen

/// Tools → Masternodes → Add masternode.
///
/// One field finds the node — IP, proTxHash, or any of its private keys —
/// then the user tracks it (with an optional label) and can attach keys,
/// with the key that found the node already filled into its field.
struct AddMasternodeScreen: View {
    @StateObject private var viewModel = AddMasternodeViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false
    /// Fires after the node is tracked and this screen closes, so the list
    /// refreshes immediately.
    let onTracked: () -> Void

    var body: some View {
        List {
            if viewModel.trackedRecord == nil {
                findSection
                resultsSection
            } else {
                keysSection
            }
        }
        .navigationTitle(NSLocalizedString("Add masternode", comment: "Add masternode"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScanner) {
            QRScannerRepresentable(
                onScanned: { value in
                    viewModel.query = value
                    showScanner = false
                    Task { await viewModel.search() }
                },
                onCancel: { showScanner = false })
                .ignoresSafeArea()
        }
    }

    // MARK: Find

    private var findSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(
                    NSLocalizedString("IP address, proTxHash or private key", comment: "Add masternode"),
                    text: $viewModel.query,
                    axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await viewModel.search() } }

                Button {
                    if let pasted = UIPasteboard.general.string {
                        viewModel.query = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await viewModel.search() }
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)

                Button {
                    showScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .buttonStyle(.borderless)
            }

            Toggle(isOn: $viewModel.searchPlatform) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Search Platform too", comment: "Add masternode"))
                        .font(.subheadline)
                    Text(NSLocalizedString(
                        "Finds owner and payout keys, which aren't in the masternode list. Sends the key's public fingerprint to a Platform node.",
                        comment: "Add masternode"))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }

            Button {
                Task { await viewModel.search() }
            } label: {
                if viewModel.searching {
                    HStack(spacing: 8) {
                        SwiftUI.ProgressView().scaleEffect(0.8)
                        Text(NSLocalizedString("Searching…", comment: "Add masternode"))
                    }
                } else {
                    Label(NSLocalizedString("Find", comment: "Add masternode"), systemImage: "magnifyingglass")
                }
            }
            .disabled(viewModel.searching
                || viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } footer: {
            if let error = viewModel.searchError {
                Text(error).foregroundColor(.red)
            } else {
                Text(NSLocalizedString(
                    "Track any masternode or evonode on the network — it doesn't have to belong to this wallet.",
                    comment: "Add masternode"))
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if let matches = viewModel.matches {
            Section(NSLocalizedString("Matches", comment: "Add masternode")) {
                if matches.isEmpty {
                    Text(NSLocalizedString("No masternode on the list matches that.", comment: "Add masternode"))
                        .font(.subheadline)
                        .foregroundColor(Color.dash.secondaryText)
                }
                ForEach(matches, id: \.proTxHash) { match in
                    matchRow(match)
                }
                if let note = viewModel.platformLookupNote {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }
            if let error = viewModel.trackError {
                Section { Text(error).font(.caption).foregroundColor(.red) }
            }
        }
    }

    private func matchRow(_ match: MasternodeLocateMatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    match.isEvonode
                        ? NSLocalizedString("Evonode", comment: "")
                        : NSLocalizedString("Masternode", comment: "Masternodes"),
                    systemImage: "server.rack")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(match.isValid
                    ? NSLocalizedString("Active", comment: "Masternode status")
                    : NSLocalizedString("PoSe banned", comment: "Masternode status"))
                    .font(.caption)
                    .foregroundColor(match.isValid ? .green : .orange)
            }
            if let service = match.serviceAddress {
                Text(service)
                    .font(.system(.footnote, design: .monospaced))
            }
            Text(match.proTxHashHex)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Color.dash.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            if !match.matchedKeys.isEmpty {
                Text(matchedKeyCaption(match.matchedKeys))
                    .font(.caption)
                    .foregroundColor(Color.dash.blue)
            }

            if match.inWalletId != nil {
                Text(NSLocalizedString(
                    "Already one of this wallet's masternodes — it's in the list above.",
                    comment: "Add masternode"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            } else if match.alreadyTracked {
                Text(NSLocalizedString("Already tracked.", comment: "Add masternode"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            } else {
                Button {
                    Task { await viewModel.track(match) }
                } label: {
                    if viewModel.tracking {
                        SwiftUI.ProgressView().scaleEffect(0.8)
                    } else {
                        Text(NSLocalizedString("Track this masternode", comment: "Add masternode"))
                            .fontWeight(.medium)
                    }
                }
                .disabled(viewModel.tracking)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    private func matchedKeyCaption(_ roles: [MasternodeKeyRole]) -> String {
        let names = roles.map { $0.displayName }.joined(separator: ", ")
        return String(
            format: NSLocalizedString("Matches this node's %@ key", comment: "Add masternode"),
            names)
    }

    // MARK: Keys

    private var keysSection: some View {
        Group {
            Section {
                if let record = viewModel.trackedRecord {
                    HStack {
                        Label(record.typeName, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        Spacer()
                        Text(record.serviceAddress ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Color.dash.secondaryText)
                    }
                }
                TextField(NSLocalizedString("Label (optional)", comment: "Add masternode"), text: $viewModel.label)
                    .onSubmit { viewModel.saveLabelIfChanged() }
            } footer: {
                Text(NSLocalizedString(
                    "Tracked. Add this node's keys below to enable actions like withdrawing and voting, or finish now and add them later.",
                    comment: "Add masternode"))
            }

            TrackedKeyFieldsSection(viewModel: viewModel)

            Section {
                Button {
                    viewModel.saveLabelIfChanged()
                    if viewModel.saveKeys() {
                        onTracked()
                        dismiss()
                    }
                } label: {
                    Text(NSLocalizedString("Done", comment: ""))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.canSaveKeys)
            } footer: {
                if !viewModel.canSaveKeys {
                    Text(NSLocalizedString(
                        "A key doesn't match this masternode — fix or clear it to continue.",
                        comment: "Add masternode"))
                        .foregroundColor(.red)
                } else if let error = viewModel.trackError {
                    Text(error).foregroundColor(.red)
                }
            }
        }
    }

}

// MARK: - TrackedKeyFieldsSection

/// The four key fields (owner / voting / operator / payout) with live
/// verification badges. Shared by the add flow and the detail screen's key
/// management.
struct TrackedKeyFieldsSection: View {
    @ObservedObject var viewModel: AddMasternodeViewModel

    var body: some View {
        Section(NSLocalizedString("Keys", comment: "Masternodes")) {
            if viewModel.refreshing {
                HStack(spacing: 8) {
                    SwiftUI.ProgressView().scaleEffect(0.8)
                    Text(NSLocalizedString("Loading registration details…", comment: "Add masternode"))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
            } else if let note = viewModel.refreshNote {
                Text(note)
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            }
            ForEach(AddMasternodeViewModel.formRoles, id: \.rawValue) { role in
                keyField(role)
            }
        }
    }

    private func keyField(_ role: MasternodeKeyRole) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(role.displayName)
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
                Spacer()
                stateBadge(viewModel.keyStates[role] ?? .empty)
            }
            // A plain field, deliberately not `SecureField`: iOS treats
            // secure fields as password entries and pushes the strong-
            // password / AutoFill sheet over them, which is nonsense for a
            // masternode key (and blocks pasting). Keys are entered by
            // paste and verified inline, so visible monospaced text is the
            // useful presentation.
            TextField(role.inputPlaceholder, text: binding(for: role), axis: .vertical)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                .onSubmit { viewModel.revalidateKeys() }
        }
        .padding(.vertical, 2)
    }

    private func binding(for role: MasternodeKeyRole) -> Binding<String> {
        Binding(
            get: { viewModel.keyInputs[role] ?? "" },
            set: { newValue in
                viewModel.keyInputs[role] = newValue
                viewModel.revalidateKeys()
            })
    }

    @ViewBuilder
    private func stateBadge(_ state: AddMasternodeViewModel.KeyFieldState) -> some View {
        switch state {
        case .empty:
            EmptyView()
        case .matches:
            Label(NSLocalizedString("Matches", comment: "Add masternode"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .doesNotMatch:
            Label(NSLocalizedString("Doesn't match", comment: "Add masternode"), systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        case .unverifiable:
            Label(NSLocalizedString("Can't verify yet", comment: "Add masternode"), systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundColor(.orange)
        case .invalid(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}

// MARK: - Role display names

extension MasternodeKeyRole {
    /// Short human name for a key role.
    var displayName: String {
        switch self {
        case .owner: return NSLocalizedString("Owner", comment: "Masternodes")
        case .voting: return NSLocalizedString("Voting", comment: "Masternodes")
        case .operator: return NSLocalizedString("Operator", comment: "Masternodes")
        case .platformNode: return NSLocalizedString("Platform node", comment: "Masternodes")
        case .ownerPayout: return NSLocalizedString("Payout", comment: "Masternodes")
        case .operatorPayout: return NSLocalizedString("Operator payout", comment: "Masternodes")
        }
    }

    /// Placeholder describing the accepted key format.
    var inputPlaceholder: String {
        switch self {
        case .operator:
            return NSLocalizedString("BLS private key (hex)", comment: "Add masternode")
        case .platformNode:
            return NSLocalizedString("Node key (base64 or hex)", comment: "Add masternode")
        default:
            return NSLocalizedString("Private key (WIF or hex)", comment: "Add masternode")
        }
    }
}
