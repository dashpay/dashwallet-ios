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

// MARK: - TrackedMasternodeDetailViewModel

/// Detail state for one TRACKED (wallet-independent) masternode: the SDK
/// record (refreshable from the list / Platform / its ProRegTx), which key
/// roles have keys in the app's keychain vault, the claimable balance, and
/// the actions those keys enable.
@MainActor
final class TrackedMasternodeDetailViewModel: ObservableObject {
    @Published private(set) var record: PlatformMasternode
    @Published private(set) var attachedRoles: Set<MasternodeKeyRole> = []
    @Published private(set) var refreshing = false
    @Published private(set) var refreshError: String?

    /// Claimable balance of the node's Platform identity (evonodes).
    @Published private(set) var claimableCredits: UInt64?
    @Published private(set) var balanceLoading = false
    @Published private(set) var balanceError: String?

    /// Withdraw state (sheet).
    @Published var withdrawAmountText = ""
    @Published var withdrawDestination = ""
    @Published private(set) var withdrawing = false
    @Published private(set) var withdrawError: String?

    let vault: TrackedMasternodeKeyVaulting

    init(record: PlatformMasternode, vault: TrackedMasternodeKeyVaulting = TrackedMasternodeKeyVault()) {
        self.record = record
        self.vault = vault
        reloadAttachedRoles()
    }

    func reloadAttachedRoles() {
        attachedRoles = vault.attachedRoles(for: record.proTxHash)
    }

    /// What the attached keys enable — the SDK's shared gating policy.
    var capabilities: MasternodeCapabilities {
        MasternodeCapabilities(holding: attachedRoles)
    }

    /// The role whose key signs a withdrawal, preferring the payout key
    /// (it can choose a destination). `nil` when neither key is attached.
    var withdrawalRole: MasternodeKeyRole? {
        if attachedRoles.contains(.ownerPayout) { return .ownerPayout }
        if attachedRoles.contains(.owner) { return .owner }
        return nil
    }

    func load() async {
        await refresh()
        if record.isEvonode {
            await fetchClaimableBalance()
        }
    }

    /// Re-fetch the record: current list entry + Platform identities +
    /// (once) the registration transaction.
    func refresh() async {
        guard let manager = SwiftDashSDKHost.shared.manager, !refreshing else { return }
        refreshing = true
        refreshError = nil
        defer { refreshing = false }
        do {
            record = try await manager.refreshTrackedMasternode(proTxHash: record.proTxHash)
        } catch {
            refreshError = (error as? PlatformWalletError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Same identity-balance fetch as the wallet masternode detail: the
    /// identity id IS the proTxHash in display (reversed) order.
    func fetchClaimableBalance() async {
        guard let sdk = SwiftDashSDKHost.shared.sdk else {
            balanceError = NSLocalizedString("Platform SDK not ready", comment: "Masternodes")
            return
        }
        let identityId = Data(record.proTxHash.reversed())
        balanceLoading = true
        balanceError = nil
        do {
            let credits = try await Task.detached(priority: .userInitiated) {
                try sdk.identities.getBalance(id: identityId)
            }.value
            claimableCredits = credits
        } catch {
            claimableCredits = nil
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

    func setLabel(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let manager = SwiftDashSDKHost.shared.manager else { return }
        try? manager.setTrackedMasternodeLabel(
            proTxHash: record.proTxHash,
            label: trimmed.isEmpty ? nil : trimmed)
        // Re-read the record (local registry call) so the navigation title
        // reflects the new label immediately, matching the list behind.
        if let updated = manager.trackedMasternodes()
            .first(where: { $0.proTxHash == record.proTxHash }) {
            record = updated
        }
    }

    /// Untrack: registry row + every vault key. The keys belong to the app,
    /// so they go when the tracking goes.
    func stopTracking() -> Bool {
        guard let manager = SwiftDashSDKHost.shared.manager else { return false }
        do {
            _ = try manager.untrackMasternode(proTxHash: record.proTxHash)
            vault.removeAllKeys(for: record.proTxHash)
            return true
        } catch {
            refreshError = (error as? PlatformWalletError)?.errorDescription
                ?? error.localizedDescription
            return false
        }
    }

    func removeKey(_ role: MasternodeKeyRole) {
        vault.removeKey(for: record.proTxHash, role: role)
        reloadAttachedRoles()
    }

    // MARK: Withdraw

    /// 1 DASH = 1e8 duffs × `EvonodeWithdrawalViewModel.creditsPerDuff`
    /// credits = 1e11 credits — the Platform protocol constant, kept out
    /// of the Views per the repo guardrails.
    private static let creditsPerDash =
        Decimal(100_000_000) * Decimal(EvonodeWithdrawalViewModel.creditsPerDuff)

    static func creditsAsDash(_ credits: UInt64) -> String {
        let dash = NSDecimalNumber(decimal: Decimal(credits) / creditsPerDash)
        return String(format: "%.8f DASH", dash.doubleValue)
    }

    /// Formatted balance / withdrawable amounts for the Views.
    var claimableBalanceText: String? {
        claimableCredits.map(Self.creditsAsDash)
    }

    var maxWithdrawText: String {
        Self.creditsAsDash(maxWithdrawCredits)
    }

    /// Highest withdrawable amount: the balance minus the fee reserve the
    /// identity keeps back for the transition fee.
    var maxWithdrawCredits: UInt64 {
        guard let credits = claimableCredits else { return 0 }
        return credits > EvonodeWithdrawalViewModel.feeReserveCredits
            ? credits - EvonodeWithdrawalViewModel.feeReserveCredits
            : 0
    }

    var withdrawAmountCredits: UInt64? {
        guard let dash = Decimal(string: withdrawAmountText.replacingOccurrences(of: ",", with: ".")),
              dash > 0 else { return nil }
        let credits = dash * Self.creditsPerDash
        // `NSDecimalNumber.uint64Value` is undefined past UInt64.max — an
        // absurd typed amount could WRAP to a small value that then passes
        // the max-withdrawal check. Reject out-of-range input instead.
        guard credits <= Decimal(UInt64.max) else { return nil }
        return NSDecimalNumber(decimal: credits).uint64Value
    }

    var canSubmitWithdrawal: Bool {
        guard let amount = withdrawAmountCredits else { return false }
        let destinationOK = withdrawalRole == .owner
            || withdrawDestination.isEmpty
            || withdrawDestination.isValidDashAddressForCurrentNetwork
        return amount >= EvonodeWithdrawalViewModel.minWithdrawalCredits
            && amount <= maxWithdrawCredits
            && destinationOK
    }

    /// Authenticate, read the signing key from the vault, and submit. The
    /// key text goes straight to the SDK for this one call.
    func submitWithdrawal() async -> Bool {
        guard let manager = SwiftDashSDKHost.shared.manager,
              let role = withdrawalRole,
              let amount = withdrawAmountCredits else { return false }
        withdrawError = nil

        let outcome = await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled)
        guard outcome == .ok else { return false }

        guard let keyText = vault.key(for: record.proTxHash, role: role) else {
            withdrawError = NSLocalizedString(
                "The signing key is missing from the keychain — re-add it and try again.",
                comment: "Tracked masternodes")
            return false
        }

        withdrawing = true
        defer { withdrawing = false }
        do {
            let destination = withdrawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
            let remaining = try await manager.trackedMasternodeWithdraw(
                proTxHash: record.proTxHash,
                amountCredits: amount,
                role: role,
                key: keyText,
                destinationAddress: (role == .ownerPayout && !destination.isEmpty) ? destination : nil)
            claimableCredits = remaining
            return true
        } catch let error as PlatformWalletError {
            if case .masternodeWithdrawalUnconfirmed = error {
                // Ambiguous outcome: the nonce may be consumed. Drop the
                // stale figure and re-read before any retry is possible.
                claimableCredits = nil
                Task { await fetchClaimableBalance() }
                withdrawError = NSLocalizedString(
                    "The withdrawal was sent but its result couldn't be confirmed. The balance is being re-checked — don't retry until it settles.",
                    comment: "Tracked masternodes")
            } else {
                withdrawError = error.errorDescription
            }
            return false
        } catch {
            withdrawError = error.localizedDescription
            return false
        }
    }
}

// MARK: - TrackedMasternodeDetailScreen

/// Detail for one tracked masternode: status and everything the SDK has
/// learned about it, the keys attached on this device (with add / remove),
/// and the actions those keys enable.
struct TrackedMasternodeDetailScreen: View {
    @StateObject private var viewModel: TrackedMasternodeDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var labelDraft: String
    @State private var showStopConfirm = false
    @State private var showWithdrawSheet = false
    @State private var showKeysSheet = false
    @State private var showUnbanSheet = false
    /// Set after a successful ProUpServTx broadcast: the DML entry stays
    /// PoSe-banned for a few more blocks, so the row must not invite a
    /// duplicate submission in that window.
    @State private var unbanSubmitted = false
    let onChanged: () -> Void

    init(record: PlatformMasternode, onChanged: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: TrackedMasternodeDetailViewModel(record: record))
        _labelDraft = State(initialValue: record.label ?? "")
        self.onChanged = onChanged
    }

    var body: some View {
        List {
            overviewSection
            registrationSection
            keysSection
            balanceSection
            manageSection
        }
        .navigationTitle(viewModel.record.label ?? viewModel.record.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(isPresented: $showWithdrawSheet) {
            TrackedWithdrawalSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showKeysSheet, onDismiss: { viewModel.reloadAttachedRoles() }) {
            TrackedKeyManagementSheet(record: viewModel.record, vault: viewModel.vault)
        }
        .sheet(isPresented: $showUnbanSheet) {
            UnbanMasternodeSheet(
                record: viewModel.record,
                keySource: .tracked(vault: viewModel.vault),
                onSubmitted: {
                    unbanSubmitted = true
                    Task {
                        await viewModel.refresh()
                        onChanged()
                    }
                })
        }
        .confirmationDialog(
            NSLocalizedString("Stop tracking this masternode?", comment: "Tracked masternodes"),
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Stop tracking", comment: "Tracked masternodes"), role: .destructive) {
                if viewModel.stopTracking() {
                    onChanged()
                    dismiss()
                }
            }
        } message: {
            Text(NSLocalizedString(
                "Any keys you added for it are deleted from this device's keychain too.",
                comment: "Tracked masternodes"))
        }
    }

    private var overviewSection: some View {
        Section {
            HStack {
                Label(viewModel.record.typeName, systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                Text(NSLocalizedString("Tracked", comment: "Tracked masternodes"))
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.dash.blue.opacity(0.15))
                    .foregroundColor(Color.dash.blue)
                    .clipShape(Capsule())
                Text(viewModel.record.statusName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(viewModel.record.statusColor)
            }
            if let service = viewModel.record.serviceAddress {
                MasternodeDetailRow(label: NSLocalizedString("Service", comment: "Masternodes"), value: service)
            }
            TextField(NSLocalizedString("Label (optional)", comment: "Add masternode"), text: $labelDraft)
                .onSubmit {
                    viewModel.setLabel(labelDraft)
                    onChanged()
                }
        } footer: {
            if let error = viewModel.refreshError {
                Text(error)
            }
        }
    }

    private var registrationSection: some View {
        Section(NSLocalizedString("Registration", comment: "Masternodes")) {
            MasternodeCopyRow(label: "proTxHash", value: viewModel.record.proTxHashHex)
            if viewModel.record.hasRegistration {
                MasternodeDetailRow(
                    label: NSLocalizedString("Registered at", comment: "Masternodes"),
                    value: String(
                        format: NSLocalizedString("Height %u", comment: "Masternodes"),
                        viewModel.record.registrationHeight))
            }
            if let collateral = viewModel.record.collateralDisplay {
                MasternodeCopyRow(label: NSLocalizedString("Outpoint", comment: "Masternodes"), value: collateral)
            }
            if let owner = viewModel.record.ownerAddress {
                MasternodeCopyRow(label: NSLocalizedString("Owner address", comment: "Masternodes"), value: owner)
            }
            if let voting = viewModel.record.votingAddress {
                MasternodeCopyRow(label: NSLocalizedString("Voting address", comment: "Masternodes"), value: voting)
            }
            if let operatorKey = viewModel.record.operatorPublicKeyHex {
                MasternodeCopyRow(label: NSLocalizedString("Operator public key (BLS)", comment: "Masternodes"), value: operatorKey)
            }
            if let nodeId = viewModel.record.platformNodeIdHex {
                MasternodeCopyRow(label: NSLocalizedString("Platform Node ID", comment: ""), value: nodeId)
            }
            if let payout = viewModel.record.payoutAddress {
                MasternodeCopyRow(label: NSLocalizedString("Payout address", comment: "Masternodes"), value: payout)
            }
        }
    }

    private var keysSection: some View {
        Section {
            ForEach(TrackedMasternodeKeyVault.managedRoles, id: \.rawValue) { role in
                HStack {
                    Text(role.displayName)
                        .font(.subheadline)
                    Spacer()
                    if viewModel.attachedRoles.contains(role) {
                        Label(NSLocalizedString("On this device", comment: "Tracked masternodes"), systemImage: "key.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Button(role: .destructive) {
                            viewModel.removeKey(role)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Text(NSLocalizedString("Not added", comment: "Tracked masternodes"))
                            .font(.caption)
                            .foregroundColor(Color.dash.tertiaryText)
                    }
                }
            }
            Button {
                showKeysSheet = true
            } label: {
                Label(NSLocalizedString("Add keys", comment: "Tracked masternodes"), systemImage: "plus")
            }
        } header: {
            Text(NSLocalizedString("Keys on this device", comment: "Tracked masternodes"))
        } footer: {
            Text(NSLocalizedString(
                "Keys are stored in this device's keychain and never leave it except to sign the action you request.",
                comment: "Tracked masternodes"))
        }
    }

    @ViewBuilder
    private var balanceSection: some View {
        if viewModel.record.isEvonode {
            Section(NSLocalizedString("Claimable balance", comment: "Masternodes")) {
                if viewModel.balanceLoading {
                    HStack(spacing: 8) {
                        SwiftUI.ProgressView().scaleEffect(0.8)
                        Text(NSLocalizedString("Fetching…", comment: "Masternodes"))
                            .foregroundColor(Color.dash.secondaryText)
                    }
                } else if let balance = viewModel.claimableBalanceText {
                    MasternodeDetailRow(
                        label: NSLocalizedString("Balance", comment: "Masternodes"),
                        value: balance)
                } else if let error = viewModel.balanceError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                }

                Button {
                    Task { await viewModel.fetchClaimableBalance() }
                } label: {
                    Label(NSLocalizedString("Refresh", comment: ""), systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.balanceLoading)

                if let credits = viewModel.claimableCredits, credits > 0 {
                    if viewModel.withdrawalRole != nil {
                        Button {
                            showWithdrawSheet = true
                        } label: {
                            Label(NSLocalizedString("Withdraw", comment: "Evonode withdrawal"), systemImage: "arrow.down.circle")
                                .foregroundColor(Color.dash.blue)
                        }
                    } else {
                        Text(NSLocalizedString(
                            "Add this node's owner key or payout address key to withdraw from here.",
                            comment: "Tracked masternodes"))
                            .font(.caption)
                            .foregroundColor(Color.dash.secondaryText)
                    }
                }
            }
        }
    }

    private var manageSection: some View {
        Section {
            unbanRows

            requestStatusRow

            Button {
                Task {
                    await viewModel.refresh()
                    onChanged()
                }
            } label: {
                if viewModel.refreshing {
                    HStack(spacing: 8) {
                        SwiftUI.ProgressView().scaleEffect(0.8)
                        Text(NSLocalizedString("Refreshing…", comment: "Tracked masternodes"))
                    }
                } else {
                    Label(NSLocalizedString("Refresh details", comment: "Tracked masternodes"), systemImage: "arrow.clockwise")
                }
            }
            .disabled(viewModel.refreshing)

            Button(role: .destructive) {
                showStopConfirm = true
            } label: {
                Label(NSLocalizedString("Stop tracking", comment: "Tracked masternodes"), systemImage: "eye.slash")
                    .foregroundColor(.red)
            }
        }
    }

    /// Unban entry point: shown while the node is PoSe-banned (or an unban
    /// funded from the shielded balance is still pending), enabled when the
    /// operator key — the one that signs a ProUpServTx — is on this device.
    @ViewBuilder
    private var unbanRows: some View {
        let pending = PendingMasternodeUnbanStore.shared.pending(
            forProTxHash: viewModel.record.proTxHash) != nil
        if unbanSubmitted {
            Text(NSLocalizedString(
                "Unban submitted — the masternode list updates within a few blocks.",
                comment: "Masternode unban"))
                .font(.caption)
                .foregroundColor(Color.dash.secondaryText)
        } else if viewModel.record.masternodeStatus == .inactive || pending {
            if viewModel.capabilities.canUpdateService {
                Button {
                    showUnbanSheet = true
                } label: {
                    Label(
                        pending
                            ? NSLocalizedString("Complete unban", comment: "Masternode unban")
                            : NSLocalizedString("Unban masternode", comment: "Masternode unban"),
                        systemImage: "arrow.up.heart")
                        .foregroundColor(Color.dash.blue)
                }
            } else if viewModel.record.masternodeStatus == .inactive {
                Text(NSLocalizedString(
                    "Add this masternode's operator key to unban it from here.",
                    comment: "Masternode unban"))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
            }
        }
    }

    /// Ask the node itself for its DAPI status — the same
    /// `EvonodeStatusScreen` the wallet-owned detail pushes, keyed off the
    /// record's DAPI address (evonodes with a routable service address).
    @ViewBuilder
    private var requestStatusRow: some View {
        if viewModel.record.platformDAPIAddress != nil {
            NavigationLink {
                EvonodeStatusScreen(masternode: viewModel.record)
            } label: {
                Label(NSLocalizedString("Request status", comment: "Evonode status"), systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundColor(Color.dash.blue)
            }
        }
    }
}

// MARK: - TrackedWithdrawalSheet

/// Compact withdrawal form for a tracked evonode: amount, destination (when
/// signing with the payout key), authenticate, submit. The wallet-scoped
/// flow keeps its richer screen; this one signs with a vault key via
/// `trackedMasternodeWithdraw`.
private struct TrackedWithdrawalSheet: View {
    @ObservedObject var viewModel: TrackedMasternodeDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MasternodeDetailRow(
                        label: NSLocalizedString("Available", comment: "Evonode withdrawal"),
                        value: viewModel.maxWithdrawText)
                    TextField(
                        NSLocalizedString("Amount (DASH)", comment: "Evonode withdrawal"),
                        text: $viewModel.withdrawAmountText)
                        .keyboardType(.decimalPad)
                    if viewModel.withdrawalRole == .ownerPayout {
                        TextField(
                            NSLocalizedString("Destination address (optional)", comment: "Tracked masternodes"),
                            text: $viewModel.withdrawDestination)
                            .font(.system(.footnote, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } footer: {
                    Text(viewModel.withdrawalRole == .owner
                        ? NSLocalizedString(
                            "Signing with the owner key — the withdrawal goes to the registered payout address.",
                            comment: "Tracked masternodes")
                        : NSLocalizedString(
                            "Signing with the payout address key. Leave the destination empty to withdraw to the payout address.",
                            comment: "Tracked masternodes"))
                }

                Section {
                    Button {
                        Task {
                            if await viewModel.submitWithdrawal() {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.withdrawing {
                            HStack(spacing: 8) {
                                SwiftUI.ProgressView().scaleEffect(0.8)
                                Text(NSLocalizedString("Withdrawing…", comment: "Tracked masternodes"))
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(NSLocalizedString("Withdraw", comment: "Evonode withdrawal"))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!viewModel.canSubmitWithdrawal || viewModel.withdrawing)
                } footer: {
                    if let error = viewModel.withdrawError {
                        Text(error).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Withdraw", comment: "Evonode withdrawal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - TrackedKeyManagementSheet

/// Add / replace keys for an already-tracked node — the same verified key
/// fields as the add flow, seeded from the tracked record.
private struct TrackedKeyManagementSheet: View {
    @StateObject private var viewModel: AddMasternodeViewModel
    @Environment(\.dismiss) private var dismiss

    init(record: PlatformMasternode, vault: TrackedMasternodeKeyVaulting) {
        let model = AddMasternodeViewModel(vault: vault)
        model.adoptTrackedRecord(record)
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            List {
                TrackedKeyFieldsSection(viewModel: viewModel)
                Section {
                    Button {
                        if viewModel.saveKeys() {
                            dismiss()
                        }
                    } label: {
                        Text(NSLocalizedString("Save keys", comment: "Tracked masternodes"))
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
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Add keys", comment: "Tracked masternodes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
            }
        }
    }
}
