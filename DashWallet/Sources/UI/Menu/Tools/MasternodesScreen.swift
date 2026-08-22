//
//  MasternodesScreen.swift
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
import UIKit

// MARK: - MasternodesViewModel

/// Tools → Masternodes: the wallet's masternodes/evonodes from the Rust
/// aggregation (`PlatformWalletManager.masternodes(for:)`), the same source
/// the masternode-keys usage resolver reads. Live snapshot — nothing is
/// persisted on the app side.
@MainActor
final class MasternodesViewModel: ObservableObject {
    @Published private(set) var masternodes: [PlatformMasternode] = []
    @Published private(set) var loaded = false

    /// Registrations still on the network — active, PoSe-banned, or (before
    /// the list arrives) indeterminate. These stay expanded at the top: an
    /// inactive node is a problem the user probably wants to see, not
    /// history.
    var currentMasternodes: [PlatformMasternode] {
        masternodes.filter { MasternodeStatus(rawValue: $0.status) != .retired }
    }

    /// Registrations no longer in the masternode list — collateral spent,
    /// revoked, or expired. History: shown in a collapsed section at the
    /// bottom.
    var retiredMasternodes: [PlatformMasternode] {
        masternodes.filter { MasternodeStatus(rawValue: $0.status) == .retired }
    }

    /// In-wallet key index by base58 address for the two address-carrying
    /// families. Operator/platform ownership comes pre-resolved on the
    /// aggregation row; owner/voting is joined here against the derived
    /// address pool (same join as `MasternodeKeyUsage`).
    private var ownerIndexByAddress: [String: UInt32] = [:]
    private var votingIndexByAddress: [String: UInt32] = [:]

    func load() {
        defer { loaded = true }
        guard let manager = SwiftDashSDKHost.shared.manager,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            masternodes = []
            return
        }
        masternodes = manager.masternodes(for: walletId)
            .sorted { $0.orderIndex < $1.orderIndex }
        guard !masternodes.isEmpty else { return }

        ownerIndexByAddress = MasternodeKeyUsage.indexByAddress(
            family: .owner,
            targets: Set(masternodes.compactMap(\.ownerAddress)))
        votingIndexByAddress = MasternodeKeyUsage.indexByAddress(
            family: .voting,
            targets: Set(masternodes.compactMap(\.votingAddress)))
    }

    /// Ownership subtitle for the owner key ("ProviderOwnerKeys #4" /
    /// "not in this wallet"), mirroring the SDK's `keyOwnershipLabel`.
    func ownerOwnership(for masternode: PlatformMasternode) -> String {
        ownershipLabel(index: masternode.ownerAddress.flatMap { ownerIndexByAddress[$0] },
                       accountType: 9)
    }

    func votingOwnership(for masternode: PlatformMasternode) -> String {
        ownershipLabel(index: masternode.votingAddress.flatMap { votingIndexByAddress[$0] },
                       accountType: 8)
    }

    private func ownershipLabel(index: UInt32?, accountType: UInt8) -> String {
        PersistentMasternode.keyOwnershipLabel(
            inWallet: index != nil,
            accountType: accountType,
            index: index ?? 0)
    }
}

// MARK: - PlatformMasternode display helpers

/// Display formatting for the aggregation snapshot, following the SDK's
/// `PersistentMasternode` conventions: txids render in block-explorer
/// (reversed) hex, key hashes in forward order. Internal: the evonode
/// withdrawal screens reuse `displayTitle`.
extension PlatformMasternode {
    var typeName: String {
        isEvonode
            ? NSLocalizedString("Evonode", comment: "")
            : NSLocalizedString("Masternode", comment: "")
    }

    /// "Evonode 2" / "Masternode 5" — evonodes and masternodes number
    /// independently (1-based `typeIndex`).
    var displayTitle: String {
        "\(typeName) \(typeIndex)"
    }

    var masternodeStatus: MasternodeStatus {
        MasternodeStatus(rawValue: status) ?? .unknown
    }

    var statusName: String {
        switch masternodeStatus {
        case .active: return NSLocalizedString("Active", comment: "Masternode status")
        case .inactive: return NSLocalizedString("Inactive", comment: "Masternode status")
        case .retired: return NSLocalizedString("Retired", comment: "Masternode status")
        case .unknown: return NSLocalizedString("Unknown", comment: "Masternode status")
        }
    }

    var statusColor: Color {
        switch masternodeStatus {
        case .active: return .green
        case .inactive: return .orange
        case .retired: return .red
        case .unknown: return .secondary
        }
    }

    var proTxHashHex: String {
        proTxHash.reversed().map { String(format: "%02x", $0) }.joined()
    }

    var ownerKeyHashHex: String? {
        ownerKeyHash.map { $0.map { String(format: "%02x", $0) }.joined() }
    }

    var votingKeyHashHex: String? {
        votingKeyHash.map { $0.map { String(format: "%02x", $0) }.joined() }
    }

    var operatorPublicKeyHex: String? {
        operatorPublicKey.map { $0.map { String(format: "%02x", $0) }.joined() }
    }

    var platformNodeIdHex: String? {
        platformNodeId.map { $0.map { String(format: "%02x", $0) }.joined() }
    }

    var collateralDisplay: String? {
        guard let txid = collateralTxid else { return nil }
        let hex = txid.reversed().map { String(format: "%02x", $0) }.joined()
        return "\(hex):\(collateralVout)"
    }
}

// MARK: - MasternodesScreen

struct MasternodesScreen: View {
    @StateObject private var viewModel = MasternodesViewModel()

    /// Retired registrations are history — collapsed until asked for.
    @State private var isRetiredExpanded = false

    var body: some View {
        List {
            if viewModel.loaded && viewModel.masternodes.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40))
                            .foregroundColor(Color.dash.tertiaryText)

                        Text(NSLocalizedString("No masternodes yet", comment: "Masternodes"))
                            .font(.headline)

                        Text(NSLocalizedString("Masternodes and evonodes registered with this wallet's keys will appear here after the wallet syncs.", comment: "Masternodes"))
                            .font(.caption)
                            .foregroundColor(Color.dash.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                if !viewModel.currentMasternodes.isEmpty {
                    Section {
                        ForEach(viewModel.currentMasternodes, id: \.proTxHash) { masternode in
                            row(for: masternode)
                        }
                    }
                }

                if !viewModel.retiredMasternodes.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $isRetiredExpanded) {
                            ForEach(viewModel.retiredMasternodes, id: \.proTxHash) { masternode in
                                row(for: masternode)
                            }
                        } label: {
                            HStack {
                                Text(NSLocalizedString("Retired", comment: "Masternodes"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Spacer()

                                Text("\(viewModel.retiredMasternodes.count)")
                                    .font(.caption)
                                    .foregroundColor(Color.dash.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.load()
        }
    }

    private func row(for masternode: PlatformMasternode) -> some View {
        NavigationLink {
            MasternodeDetailScreen(
                masternode: masternode,
                ownerOwnership: viewModel.ownerOwnership(for: masternode),
                votingOwnership: viewModel.votingOwnership(for: masternode))
        } label: {
            MasternodeListRow(masternode: masternode)
        }
    }
}

// MARK: - MasternodeListRow

private struct MasternodeListRow: View {
    let masternode: PlatformMasternode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(masternode.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let service = masternode.serviceAddress {
                    Text(service)
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }
            }

            Spacer()

            Text(masternode.statusName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(masternode.statusColor)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - MasternodeDetailScreen

/// Detail for one aggregated masternode, mirroring the SwiftExampleApp's
/// `MasternodeDetailView`: overview, registration, keys, key ownership,
/// collateral, revocation, and (evonodes) the claimable Platform-credits
/// balance with a Withdraw entry point when this wallet holds a key that
/// can claim it (owner key → payout address only; payout/transfer key →
/// any destination). The claim itself lives in `EvonodeWithdrawalScreen`.
struct MasternodeDetailScreen: View {
    let masternode: PlatformMasternode
    let ownerOwnership: String
    let votingOwnership: String

    /// Evonode claimable balance = the masternode identity's credit
    /// balance (identity id == display-order proTxHash). `nil` until
    /// fetched / when the identity isn't found.
    @State private var claimableCredits: UInt64?
    @State private var balanceLoading = false
    @State private var balanceError: String?

    /// Which withdrawal signing keys this wallet holds for the evonode
    /// (SDK preflight, local + seedless). `nil` until resolved or when the
    /// preflight failed (`withdrawalKeysError`).
    @State private var withdrawalKeys: MasternodeWithdrawalKeys?
    @State private var withdrawalKeysError: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Label(masternode.typeName, systemImage: "server.rack")
                        .font(.headline)
                    Spacer()
                    Text(masternode.statusName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(masternode.statusColor)
                }
                if let service = masternode.serviceAddress {
                    MasternodeDetailRow(label: NSLocalizedString("Service", comment: "Masternodes"), value: service)
                }
            }

            Section(NSLocalizedString("Registration", comment: "Masternodes")) {
                MasternodeCopyRow(label: "proTxHash", value: masternode.proTxHashHex)
                MasternodeDetailRow(
                    label: NSLocalizedString("Registered at", comment: "Masternodes"),
                    value: masternode.hasRegistration
                        ? String(format: NSLocalizedString("Height %u", comment: "Masternodes"), masternode.registrationHeight)
                        : NSLocalizedString("Not in wallet history", comment: "Masternodes"))
                MasternodeDetailRow(
                    label: NSLocalizedString("Provider transactions", comment: "Masternodes"),
                    value: "\(masternode.txCount)")
            }

            Section(NSLocalizedString("Keys", comment: "Masternodes")) {
                if let owner = masternode.ownerAddress {
                    MasternodeCopyRow(label: NSLocalizedString("Owner address", comment: "Masternodes"), value: owner)
                }
                if let ownerHash = masternode.ownerKeyHashHex {
                    MasternodeCopyRow(label: NSLocalizedString("Owner key hash", comment: "Masternodes"), value: ownerHash)
                }
                if let voting = masternode.votingAddress {
                    MasternodeCopyRow(label: NSLocalizedString("Voting address", comment: "Masternodes"), value: voting)
                }
                if let votingHash = masternode.votingKeyHashHex {
                    MasternodeCopyRow(label: NSLocalizedString("Voting key hash", comment: "Masternodes"), value: votingHash)
                }
                if let operatorKey = masternode.operatorPublicKeyHex {
                    MasternodeCopyRow(label: NSLocalizedString("Operator public key (BLS)", comment: "Masternodes"), value: operatorKey)
                }
                if let nodeId = masternode.platformNodeIdHex {
                    MasternodeCopyRow(label: NSLocalizedString("Platform Node ID", comment: ""), value: nodeId)
                }
                if let payout = masternode.payoutAddress {
                    MasternodeCopyRow(label: NSLocalizedString("Payout address", comment: "Masternodes"), value: payout)
                }
            }

            Section(NSLocalizedString("Key ownership", comment: "Masternodes")) {
                MasternodeDetailRow(label: NSLocalizedString("Owner", comment: "Masternodes"), value: ownerOwnership)
                MasternodeDetailRow(label: NSLocalizedString("Voting", comment: "Masternodes"), value: votingOwnership)
                if masternode.operatorPublicKey != nil {
                    MasternodeDetailRow(
                        label: NSLocalizedString("Operator", comment: "Masternodes"),
                        value: PersistentMasternode.keyOwnershipLabel(
                            inWallet: masternode.operatorInWallet,
                            accountType: masternode.operatorAccountType,
                            index: masternode.operatorKeyIndex))
                }
                if masternode.platformNodeId != nil {
                    // When Rust couldn't check platform ownership (pool not
                    // rehydrated yet), say so instead of claiming "not in
                    // this wallet".
                    MasternodeDetailRow(
                        label: NSLocalizedString("Platform node", comment: "Masternodes"),
                        value: masternode.platformOwnershipChecked
                            ? PersistentMasternode.keyOwnershipLabel(
                                inWallet: masternode.platformInWallet,
                                accountType: masternode.platformAccountType,
                                index: masternode.platformKeyIndex)
                            : NSLocalizedString("Not checked yet", comment: "Masternodes"))
                }
            }

            if let collateral = masternode.collateralDisplay {
                Section(NSLocalizedString("Collateral", comment: "Masternodes")) {
                    MasternodeCopyRow(label: NSLocalizedString("Outpoint", comment: "Masternodes"), value: collateral)
                }
            }

            if masternode.revoked {
                Section(NSLocalizedString("Revocation", comment: "Masternodes")) {
                    MasternodeDetailRow(
                        label: NSLocalizedString("Reason", comment: "Masternodes"),
                        value: "\(masternode.revocationReason)")
                }
            }

            // Platform credits accrue on the masternode's Platform identity
            // (evonodes only). Withdraw is offered when the wallet holds the
            // owner key or the payout (transfer) key — see
            // `EvonodeWithdrawalScreen` for the key rules.
            if masternode.isEvonode {
                Section(NSLocalizedString("Claimable balance", comment: "Masternodes")) {
                    if balanceLoading {
                        HStack(spacing: 8) {
                            // Explicitly SwiftUI's — the app declares its own
                            // `ProgressView` UIKit class that shadows it here.
                            SwiftUI.ProgressView().scaleEffect(0.8)
                            Text(NSLocalizedString("Fetching…", comment: "Masternodes"))
                                .foregroundColor(Color.dash.secondaryText)
                        }
                    } else if let credits = claimableCredits {
                        MasternodeDetailRow(
                            label: NSLocalizedString("Credits", comment: "Masternodes"),
                            value: "\(credits)")
                        MasternodeDetailRow(label: "≈ DASH", value: Self.creditsAsDash(credits))
                    } else if let error = balanceError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Color.dash.secondaryText)
                    }

                    Button {
                        Task { await fetchClaimableBalance() }
                    } label: {
                        Label(NSLocalizedString("Refresh", comment: ""), systemImage: "arrow.clockwise")
                    }
                    .disabled(balanceLoading)

                    withdrawRows
                }
            }
        }
        .navigationTitle(masternode.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if masternode.isEvonode {
                loadWithdrawalKeys()
                await fetchClaimableBalance()
            }
        }
    }

    /// Withdraw entry point + the one-line reason it is / isn't available.
    /// Shown only once the balance is known and positive.
    @ViewBuilder
    private var withdrawRows: some View {
        if let credits = claimableCredits, credits > 0 {
            if let keys = withdrawalKeys, keys.canWithdraw {
                NavigationLink {
                    EvonodeWithdrawalScreen(
                        masternode: masternode,
                        keys: keys,
                        claimableCredits: credits,
                        onWithdrawn: { remaining in claimableCredits = remaining })
                } label: {
                    Label(NSLocalizedString("Withdraw", comment: "Evonode withdrawal"), systemImage: "arrow.down.circle")
                        .foregroundColor(Color.dash.blue)
                }

                Text(keys.canChooseDestination
                    ? NSLocalizedString(
                        "This wallet holds the payout address key, so you can withdraw to any address.",
                        comment: "Evonode withdrawal")
                    : NSLocalizedString(
                        "This wallet holds the owner key, so withdrawals go to the registered payout address.",
                        comment: "Evonode withdrawal"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            } else if withdrawalKeys != nil {
                Text(NSLocalizedString(
                    "This wallet holds neither the owner key nor the payout address key of this evonode, so its balance can't be withdrawn from here.",
                    comment: "Evonode withdrawal"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            } else if let error = withdrawalKeysError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            }
        }
    }

    /// Resolve which withdrawal keys this wallet holds — local and seedless
    /// (account-xpub derive-and-compare + address-pool lookup in Rust).
    private func loadWithdrawalKeys() {
        guard let manager = SwiftDashSDKHost.shared.manager,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            withdrawalKeysError = NSLocalizedString("Wallet is not ready. Try again in a moment.", comment: "Evonode withdrawal")
            return
        }
        do {
            withdrawalKeys = try manager.masternodeWithdrawalKeys(
                walletId: walletId,
                proTxHash: masternode.proTxHash)
            withdrawalKeysError = nil
        } catch {
            withdrawalKeys = nil
            withdrawalKeysError = NSLocalizedString(
                "Couldn't check which keys of this evonode are in the wallet.",
                comment: "Evonode withdrawal")
        }
    }

    /// Fetch the masternode identity's credit balance. The identity id IS
    /// the proTxHash in display (reversed) byte order; the stored bytes are
    /// raw wire order, so reverse before keying the fetch. The FFI call is
    /// blocking — run it off the main actor.
    @MainActor
    private func fetchClaimableBalance() async {
        guard let sdk = SwiftDashSDKHost.shared.sdk else {
            balanceError = NSLocalizedString("Platform SDK not ready", comment: "Masternodes")
            return
        }
        let identityId = Data(masternode.proTxHash.reversed())
        balanceLoading = true
        balanceError = nil
        do {
            let credits = try await Task.detached(priority: .userInitiated) {
                try sdk.identities.getBalance(id: identityId)
            }.value
            claimableCredits = credits
        } catch {
            claimableCredits = nil
            // Distinguish "no identity registered" from a transport failure
            // so the copy isn't misleading on a transient network error.
            let message = error.localizedDescription.lowercased()
            if message.contains("not found") || message.contains("no identity")
                || message.contains("does not exist") {
                balanceError = NSLocalizedString("This masternode has no Platform identity yet.", comment: "Masternodes")
            } else {
                balanceError = NSLocalizedString("Couldn't fetch the balance (network error). Try Refresh.", comment: "Masternodes")
            }
        }
        balanceLoading = false
    }

    /// 1 DASH = 100,000,000,000 credits.
    private static func creditsAsDash(_ credits: UInt64) -> String {
        String(format: "%.8f DASH", Double(credits) / 100_000_000_000.0)
    }
}

// MARK: - Rows

/// Label + trailing value row.
private struct MasternodeDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Color.dash.secondaryText)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Caption + monospaced, tap-to-copy value block for hashes / addresses.
private struct MasternodeCopyRow: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { copied = false }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                    Spacer()
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(copied ? .green : .dash.blue)
                }
                Text(value)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(Color.dash.primaryText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }
}
