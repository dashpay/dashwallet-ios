//
//  ShieldedActivityHistory.swift
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
//  Shielded operations in the home transaction history. The SDK's
//  shielded persister writes one `PersistentShieldedActivity` row per
//  operation (live-recorded on execution, or scan-derived on restore);
//  this file projects those rows into immutable list items that the
//  home history interleaves with the Core transaction rows, plus the
//  detail sheet a tapped row opens.
//
//  Kinds whose Core leg is already a history row are NOT projected —
//  ShieldFromAssetLock (the Core asset-lock spend renders via
//  `Transaction.isShieldedTransfer`) and Withdrawal (the Core receipt
//  renders via `Transaction.isShieldedWithdrawalReceipt`). Projecting
//  them too would show one user action as two rows. There is no txid
//  on the activity entry to dedupe by, so the exclusion is by kind —
//  guaranteed-correct for live-recorded entries because those two
//  kinds have a Core transaction by construction.
//

import Foundation
import SwiftData
import SwiftDashSDK
import SwiftUI

// MARK: - List item

/// Immutable projection of one `PersistentShieldedActivity` row,
/// captured at reload time so the list never holds live `@Model`
/// references (same contract as the `Transaction` snapshot wrapper).
struct ShieldedActivityItem: Identifiable {

    enum Kind: Int {
        case shield = 0              // platform transparent → shielded
        case shieldFromAssetLock = 1 // Core L1 → shielded (Core leg shown instead)
        case received = 2
        case sent = 3
        case unshield = 4            // shielded → platform transparent
        case withdrawal = 5          // shielded → Core L1 (Core leg shown instead)
        case identityCreate = 6
        case shieldedSpend = 7       // restore-path residual
    }

    enum Direction: Int {
        case incoming = 0
        case outgoing = 1
        case selfTransfer = 2
    }

    enum Status: Int {
        case pending = 0
        case confirmed = 1
        case failed = 2
    }

    let entryId: Data
    let accountIndex: UInt32
    let kind: Kind
    let direction: Direction
    let status: Status
    /// Principal in duffs (the store keeps credits; 1000 credits = 1 duff).
    let amountDuffs: UInt64
    /// Exact fee in duffs, when the entry recorded one.
    let feeDuffs: UInt64?
    let blockHeight: UInt64?
    let date: Date
    /// Decoded UTF-8 text memo, when the 36-byte Dash memo is kind-1 text.
    let memoText: String?
    /// Created identity id (hex) for `identityCreate` entries.
    let createdIdentityIdHex: String?

    var id: String {
        "shielded-" + entryId.map { String(format: "%02x", $0) }.joined() + "-\(accountIndex)"
    }

    init(row: PersistentShieldedActivity) {
        entryId = row.entryId
        accountIndex = row.accountIndex
        kind = Kind(rawValue: row.kindTag) ?? .shieldedSpend
        direction = Direction(rawValue: row.direction) ?? .selfTransfer
        status = Status(rawValue: row.status) ?? .confirmed
        amountDuffs = row.amount / 1000
        feeDuffs = row.hasFee ? row.fee / 1000 : nil
        blockHeight = row.hasBlockHeight ? row.blockHeight : nil
        date = Date(timeIntervalSince1970: Double(row.createdAtMs) / 1000.0)
        memoText = Self.decodeTextMemo(row.memo)
        createdIdentityIdHex = row.kindTag == Kind.identityCreate.rawValue && row.identityId.count == 32
            ? row.identityId.map { String(format: "%02x", $0) }.joined()
            : nil
    }

    // MARK: Display

    var title: String {
        switch kind {
        case .shield, .shieldFromAssetLock:
            return NSLocalizedString("Shielded", comment: "Shielded activity: funds moved into the private shielded balance")
        case .received:
            return NSLocalizedString("Received", comment: "")
        case .sent:
            return NSLocalizedString("Sent", comment: "")
        case .unshield, .withdrawal:
            return NSLocalizedString("Unshielded", comment: "Shielded activity: funds moved out of the private shielded balance")
        case .identityCreate:
            return NSLocalizedString("Identity registration", comment: "Asset lock funding a DashPay identity registration")
        case .shieldedSpend:
            return NSLocalizedString("Shielded Spend", comment: "Shielded activity: a spend restored from on-chain data whose exact type is unknown")
        }
    }

    /// Route/context pill under the time — mirrors the Core internal-
    /// transfer rows' "Transparent → Shielded" wording. The memo wins
    /// when present (it's the sender's message, strictly more useful).
    var detailsText: String? {
        if let memoText { return memoText }
        switch kind {
        case .shield, .shieldFromAssetLock:
            return NSLocalizedString("Platform → Shielded", comment: "Transfer of own funds from the Platform balance into the private shielded balance")
        case .unshield, .withdrawal:
            return NSLocalizedString("Shielded → Platform", comment: "Transfer of own funds from the private shielded balance to the Platform balance")
        case .received, .sent, .identityCreate, .shieldedSpend:
            return NSLocalizedString("Shielded", comment: "Shielded activity: funds moved into the private shielded balance")
        }
    }

    /// Corner-badge SF symbol next to the shield primary icon; nil keeps
    /// the plain shield (the details pill already carries the route).
    var secondarySystemIcon: String? {
        switch kind {
        case .received: return "arrow.down"
        case .sent: return "arrow.up"
        case .identityCreate: return "person.crop.circle.fill"
        case .shieldedSpend: return "questionmark"
        case .shield, .shieldFromAssetLock, .unshield, .withdrawal: return nil
        }
    }

    /// Signed duffs for the row amount label. Self-transfers stay
    /// positive and render with no sign (own funds moved, not gained
    /// or lost).
    var signedDashAmount: Int64 {
        let magnitude = amountDuffs > UInt64(Int64.max) ? Int64.max : Int64(amountDuffs)
        return direction == .outgoing ? -magnitude : magnitude
    }

    var fiatAmount: String {
        CurrencyExchanger.shared.fiatAmountString(for: amountDuffs.dashAmount)
    }

    var trailingStatusText: String? {
        switch status {
        case .pending: return NSLocalizedString("Pending", comment: "")
        case .failed: return NSLocalizedString("Failed", comment: "")
        case .confirmed: return nil
        }
    }

    var shortTimeString: String {
        DWDateFormatter.sharedInstance.timeOnly(from: date)
    }

    /// Decode the 36-byte Dash memo when it is kind-1 UTF-8 text:
    /// 4-byte LE kind tag == 1, then up to 32 bytes of UTF-8 with
    /// trailing zeros trimmed. Nil for empty / non-text memos.
    private static func decodeTextMemo(_ memo: Data) -> String? {
        guard memo.count >= 4 else { return nil }
        let bytes = [UInt8](memo)
        let kind = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
        guard kind == 1 else { return nil }
        let payload = bytes[4...].prefix(while: { $0 != 0 })
        guard !payload.isEmpty else { return nil }
        return String(bytes: payload, encoding: .utf8)
    }
}

// MARK: - Detail sheet

/// Read-only detail for one shielded activity entry, presented from the
/// history list inside the standard `BottomSheet`. Deliberately simpler
/// than `TXDetailVC`: a shielded entry has no inputs/outputs/addresses
/// to enumerate — its whole point is that those stay private.
struct ShieldedActivityDetailsView: View {
    let item: ShieldedActivityItem

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.dashBlue)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.dashBlue.opacity(0.08)))
                if let badge = item.secondarySystemIcon {
                    Image(systemName: badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.dashBlue))
                        .offset(x: 4, y: 4)
                }
            }
            .padding(.top, 24)

            Text(item.title)
                .font(.headline)
                .foregroundColor(.primaryText)
                .padding(.top, 12)

            DashAmount(amount: item.signedDashAmount, font: .title2, showDirection: item.direction != .selfTransfer)
                .padding(.top, 4)
            Text(item.fiatAmount)
                .font(.footnote)
                .foregroundColor(.tertiaryText)
                .padding(.top, 2)

            VStack(spacing: 0) {
                if let details = item.detailsText {
                    infoRow(NSLocalizedString("Type", comment: ""), details)
                }
                infoRow(
                    NSLocalizedString("Status", comment: ""),
                    item.trailingStatusText ?? NSLocalizedString("Confirmed", comment: ""))
                if let height = item.blockHeight {
                    infoRow(NSLocalizedString("Block", comment: "Block height of a confirmed shielded operation"), "\(height)")
                }
                if let fee = item.feeDuffs, fee > 0 {
                    HStack {
                        Text(NSLocalizedString("Network fee", comment: ""))
                            .font(.footnote)
                            .foregroundColor(.tertiaryText)
                        Spacer()
                        DashAmount(amount: Int64(fee), font: .footnote, showDirection: false)
                    }
                    .padding(.vertical, 10)
                }
                if let identityId = item.createdIdentityIdHex {
                    copyableRow(NSLocalizedString("Identity ID", comment: "Identities"), identityId)
                }
                infoRow(
                    NSLocalizedString("Date", comment: ""),
                    DWDateFormatter.sharedInstance.longString(from: item.date))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 24)

            if item.kind == .shieldedSpend {
                Text(NSLocalizedString("Restored wallets can't always recover the operation type. This entry was reconstructed from on-chain note data.", comment: "Shielded activity"))
                    .font(.caption)
                    .foregroundColor(.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
            }

            Spacer(minLength: 24)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.footnote)
                .foregroundColor(.tertiaryText)
            Spacer()
            Text(value)
                .font(.footnote)
                .foregroundColor(.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func copyableRow(_ label: String, _ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.footnote)
                    .foregroundColor(.tertiaryText)
                Spacer()
                Text(value.prefix(8) + "…" + value.suffix(8))
                    .font(.footnote)
                    .monospaced()
                    .foregroundColor(.primaryText)
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundColor(.dashBlue)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}
