//
//  Created by Claude
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

import SwiftUI
import UIKit
import OSLog

// MARK: - CoinJoinRecoveryDebugScreen
//
// 🧪 CJTEST — TEMPORARY debug console (Tools menu) that lets us exercise the
// CoinJoin → BIP44 recovery sweep WITHOUT real mixed coins. CoinJoin mixing is
// dropped in the migrated build, so we simulate "mixed coins" by sending DASH
// onto the CoinJoin (purpose 4') derivation path directly, then sweeping them
// back.
//
// Flow:
//   1. "Widen gap → 400" generates + watches the CoinJoin (4') receive
//      addresses (mirrors the real recovery widen), so a funded address is
//      seen by the SDK.
//   2. "Fund CoinJoin [idx]" derives a CoinJoin receive address from DashSync
//      (same seed → same path as the SDK watches) and sends DASH to it from the
//      BIP44 spendable balance. On the next sync the SDK credits it to the
//      CoinJoin account and `coinJoinBalanceDuffs` rises.
//   3. "Sweep CoinJoin → BIP44" runs the real `WalletSendService.sweepCoinJoin()`.
//
// index 0  → basic sweep test (watched even at the default gap).
// index 50 → gap-limit test (only watched after the widen).
//
// Every log line is tagged `🧪 CJTEST` (distinct from 🪙 CJRECOV) for filtering.
// REMOVE this screen, its Tools row, and `debugForceWidenCoinJoinGap` before
// release — see the TODO in CoinJoinRecovery.swift.
@MainActor
struct CoinJoinRecoveryDebugScreen: View {
    private let vc: UINavigationController
    @ObservedObject private var walletState = SwiftDashSDKWalletState.shared

    @State private var indexText: String = "0"
    @State private var amountText: String = "0.05"
    @State private var derivedAddress: String?
    @State private var logLines: [LogLine] = []
    @State private var isBusy = false

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "coinjoin-recovery-debug")

    init(vc: UINavigationController) {
        self.vc = vc
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back button
            HStack {
                Button(action: { vc.popViewController(animated: true) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)

            HStack {
                Text("CoinJoin Recovery 🧪")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    balancesCard
                    inputsCard
                    actionsCard
                    logCard
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 20)
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: Cards

    private var balancesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Balances").font(.headline).foregroundColor(.primaryText)
            infoRow("CoinJoin (4')", "\(duffsToDash(walletState.coinJoinBalanceDuffs)) DASH")
            infoRow("BIP44 spendable", "\(duffsToDash(walletState.balance?.spendable ?? 0)) DASH")
            Button(action: {
                walletState.refreshCoinJoinBalance()
                appendLog("🔄 refreshed balances — CoinJoin \(duffsToDash(walletState.coinJoinBalanceDuffs)) DASH")
            }) {
                Text("Refresh").font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var inputsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parameters").font(.headline).foregroundColor(.primaryText)
            HStack {
                Text("CoinJoin index").foregroundColor(.secondary)
                Spacer()
                TextField("0", text: $indexText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Amount (DASH)").foregroundColor(.secondary)
                Spacer()
                TextField("0.05", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Imported real wallet: just tap 'Widen + FULL rescan', wait for SPV 100%, then Refresh + Dump — no funding needed (a full rescan finds historical mixed coins). Fund / idx are only for synthetic tests. Rescan re-downloads the whole chain (minutes).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var actionsCard: some View {
        VStack(spacing: 10) {
            actionButton("Widen + FULL rescan (wipe SPV)", systemImage: "arrow.clockwise.circle", action: fullRescan)
            actionButton("Derive + copy CoinJoin address", systemImage: "doc.on.doc", action: derive)
            actionButton("Fund CoinJoin (send from BIP44)", systemImage: "arrow.down.circle", action: fund)
            actionButton("Sweep CoinJoin → BIP44", systemImage: "arrow.up.circle", action: sweep)
            actionButton("Dump all SDK balances", systemImage: "list.bullet.rectangle", action: dumpBalances)

            if let addr = derivedAddress {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target address (idx \(indexText))")
                        .font(.caption).foregroundColor(.secondary)
                    Text(addr)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primaryText)
                    if let url = explorerAddressURL(addr) {
                        Link("View address on explorer ↗", destination: url).font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log (🧪 CJTEST)").font(.headline).foregroundColor(.primaryText)
            if logLines.isEmpty {
                Text("No actions yet.").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(logLines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = line.url {
                            Link("↗ explorer", destination: url).font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    // MARK: Subviews

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).foregroundColor(.primaryText)
        }
        .font(.subheadline)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
                Spacer()
                if isBusy { SwiftUI.ProgressView() }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primaryBackground)
            .cornerRadius(8)
        }
        .disabled(isBusy)
        .foregroundColor(.primaryText)
    }

    // MARK: Actions

    private func fullRescan() {
        appendLog("♻️ widen 400 + clear SPV + FULL rescan — main balance dips then rebuilds; wait for SPV 100%, then Refresh + Dump")
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            await SwiftDashSDKSPVCoordinator.shared.debugFullRescanWithWidenedCoinJoinGap(gapLimit: 400)
            appendLog("✅ rescan kicked off — watch SwiftDashSDK SPV Status until 100%, then Refresh + Dump")
        }
    }

    private func dumpBalances() {
        let lines = SwiftDashSDKCoinJoinBalanceReader.debugDumpAllBalances()
        appendLog("📊 SDK accounts (\(lines.count)):")
        for line in lines { appendLog("   \(line)") }
    }

    private func derive() {
        guard let index = parseIndex() else { appendLog("⚠️ invalid index"); return }
        guard let address = coinJoinAddress(index: index) else {
            appendLog("⚠️ could not derive CoinJoin address (path not loaded?)")
            return
        }
        derivedAddress = address
        UIPasteboard.general.string = address
        appendLog("📋 CoinJoin idx \(index): \(address) (copied)", url: explorerAddressURL(address))
    }

    private func fund() {
        guard let index = parseIndex() else { appendLog("⚠️ invalid index"); return }
        guard let amountDuffs = parseAmountDuffs() else { appendLog("⚠️ invalid amount"); return }

        // Make sure the CoinJoin address is watched before we fund it.
        _ = SwiftDashSDKSPVCoordinator.shared.debugForceWidenCoinJoinGap(gapLimit: 400)

        guard let address = coinJoinAddress(index: index) else {
            appendLog("⚠️ could not derive CoinJoin address (path not loaded?)")
            return
        }
        derivedAddress = address

        let spendable = walletState.balance?.spendable ?? 0
        guard spendable > amountDuffs + 10_000 else {
            appendLog("⚠️ insufficient BIP44 spendable (\(duffsToDash(spendable)) DASH) for \(duffsToDash(amountDuffs)) DASH + fee")
            return
        }

        appendLog("➡️ funding CoinJoin idx \(index) with \(duffsToDash(amountDuffs)) DASH → \(address)", url: explorerAddressURL(address))
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                let tx = try await WalletSendService.shared.send(address: address, amount: amountDuffs)
                let txid = tx.txHashHexString
                appendLog("✅ funded — tx \(txid)", url: explorerTxURL(txid))
                walletState.refreshCoinJoinBalance()
            } catch {
                appendLog("❌ fund failed: \(error.localizedDescription)")
            }
        }
    }

    private func sweep() {
        let watchAddress = derivedAddress ?? parseIndex().flatMap { coinJoinAddress(index: $0) }
        appendLog("➡️ sweeping CoinJoin (\(duffsToDash(walletState.coinJoinBalanceDuffs)) DASH) → BIP44")
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                let swept = try await WalletSendService.shared.sweepCoinJoin()
                appendLog("✅ swept \(duffsToDash(swept)) DASH → BIP44", url: watchAddress.flatMap(explorerAddressURL))
                walletState.refreshCoinJoinBalance()
            } catch {
                appendLog("❌ sweep failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Helpers

    /// Derive a CoinJoin (purpose 4') receive address from DashSync at the
    /// given external index. DashSync shares the wallet seed, so this is the
    /// same address the SDK watches at that CoinJoin index. Derivation is
    /// deterministic from the xpub and works with a zero balance.
    private func coinJoinAddress(index: UInt32) -> String? {
        guard let path = DWEnvironment.sharedInstance().currentAccount.coinJoinDerivationPath else {
            return nil
        }
        return path.address(at: index, internal: false)
    }

    private func parseIndex() -> UInt32? {
        UInt32(indexText.trimmingCharacters(in: .whitespaces))
    }

    private func parseAmountDuffs() -> UInt64? {
        guard let dash = Double(amountText.trimmingCharacters(in: .whitespaces)),
              dash > 0, dash.isFinite else { return nil }
        return UInt64((dash * 100_000_000.0).rounded())
    }

    private func duffsToDash(_ duffs: UInt64) -> String {
        String(format: "%.8f", Double(duffs) / 100_000_000.0)
    }

    private func explorerTxURL(_ txid: String) -> URL? {
        if DWEnvironment.sharedInstance().currentChain.isTestnet() {
            return URL(string: "https://insight.testnet.networks.dash.org:3002/insight/tx/\(txid)")
        }
        return URL(string: "https://insight.dash.org/insight/tx/\(txid)")
    }

    private func explorerAddressURL(_ address: String) -> URL? {
        if DWEnvironment.sharedInstance().currentChain.isTestnet() {
            return URL(string: "https://insight.testnet.networks.dash.org:3002/insight/address/\(address)")
        }
        return URL(string: "https://insight.dash.org/insight/address/\(address)")
    }

    private func appendLog(_ text: String, url: URL? = nil) {
        Self.logger.info("🧪 CJTEST :: \(text, privacy: .public)")
        logLines.insert(LogLine(text: text, url: url), at: 0)
        if logLines.count > 40 {
            logLines.removeLast(logLines.count - 40)
        }
    }

    private struct LogLine: Identifiable {
        let id = UUID()
        let text: String
        let url: URL?
    }
}
