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
//  Kinds whose Core leg is already a history row are not projected twice:
//  ShieldFromAssetLock is always omitted because its Core asset-lock spend
//  renders via `Transaction.isShieldedTransfer`. An internal Withdrawal is
//  temporarily projected as Pending until its Core receipt appears, then
//  matched by destination, amount, and time and replaced by that receipt.
//

import Foundation
import SwiftData
import SwiftDashSDK
import SwiftUI
import DashUIKit

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
    /// Decoded destination, when the entry's counterparty names one:
    /// the Base58Check Core address for a withdrawal, the bech32m
    /// Platform address for an unshield. Nil for other kinds and for
    /// undecodable counterparties.
    let destinationAddress: String?
    /// True when the destination is NOT one of the active wallet's own
    /// addresses — the operation is money leaving the wallet, not an
    /// internal move. Set at fetch time (the ownership lookup needs the
    /// store). Withdrawals and unshields can both be internal or external.
    let isExternalDestination: Bool
    /// True for the temporary Shielded → Transparent row shown after the
    /// shielded spend is recorded but before its matching Core receipt is
    /// persisted. The row is replaced by the real Core transaction once it
    /// arrives, so the history never has a silent post-spend gap.
    let isAwaitingTransparentReceipt: Bool

    var id: String {
        "shielded-" + entryId.map { String(format: "%02x", $0) }.joined() + "-\(accountIndex)"
    }

    init(
        row: PersistentShieldedActivity,
        kindOverride: Kind? = nil,
        amountCreditsOverride: UInt64? = nil,
        destinationAddress: String? = nil,
        isExternalDestination: Bool = false,
        isAwaitingTransparentReceipt: Bool = false
    ) {
        self.destinationAddress = destinationAddress
        self.isExternalDestination = isExternalDestination
        self.isAwaitingTransparentReceipt = isAwaitingTransparentReceipt
        let effectiveKind = kindOverride ?? Kind(rawValue: row.kindTag) ?? .shieldedSpend
        entryId = row.entryId
        accountIndex = row.accountIndex
        kind = effectiveKind
        direction = Direction(rawValue: row.direction) ?? .selfTransfer
        status = isAwaitingTransparentReceipt
            ? .pending
            : Status(rawValue: row.status) ?? .confirmed
        amountDuffs = (amountCreditsOverride ?? row.amount) / 1000
        feeDuffs = row.hasFee ? row.fee / 1000 : nil
        blockHeight = row.hasBlockHeight ? row.blockHeight : nil
        date = Date(timeIntervalSince1970: Double(row.createdAtMs) / 1000.0)
        memoText = Self.decodeTextMemo(row.memo)
        createdIdentityIdHex = effectiveKind == .identityCreate && row.identityId.count == 32
            ? row.identityId.map { String(format: "%02x", $0) }.joined()
            : nil
    }

    // MARK: Display

    var title: String {
        if isAwaitingTransparentReceipt {
            return NSLocalizedString("Internal Transfer", comment: "Transaction within the wallet, transfer of own funds")
        }
        switch kind {
        case .shield, .shieldFromAssetLock:
            return NSLocalizedString("Shielded", comment: "Shielded activity: funds moved into the private shielded balance")
        case .received:
            return NSLocalizedString("Received", comment: "")
        case .sent:
            return NSLocalizedString("Sent", comment: "")
        case .unshield, .withdrawal:
            return isExternalDestination
                ? NSLocalizedString("Sent", comment: "")
                : NSLocalizedString("Unshielded", comment: "Shielded activity: funds moved out of the private shielded balance")
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
        case .unshield, .withdrawal, .sent:
            if isExternalDestination {
                // External destination: show where the money went,
                // shortened to row-pill size (the detail sheet carries
                // the full address).
                if let address = destinationAddress {
                    return String(address.prefix(6)) + "…" + String(address.suffix(6))
                }
                return NSLocalizedString("Shielded", comment: "Shielded activity: funds moved into the private shielded balance")
            }
            switch kind {
            case .unshield:
                return NSLocalizedString("Shielded → Platform", comment: "Transfer of own funds from the private shielded balance to the Platform balance")
            case .withdrawal:
                return NSLocalizedString("Shielded → Transparent", comment: "Transfer of own funds from the private shielded balance back to the transparent wallet")
            default:
                // A Sent row whose recipient couldn't be decoded.
                return NSLocalizedString("Shielded", comment: "Shielded activity: funds moved into the private shielded balance")
            }
        case .received, .identityCreate, .shieldedSpend:
            return NSLocalizedString("Shielded", comment: "Shielded activity: funds moved into the private shielded balance")
        }
    }

    /// Corner-badge SF symbol next to the shield primary icon; nil keeps
    /// the plain shield (the details pill already carries the route).
    var secondarySystemIcon: String? {
        switch kind {
        case .received: return "arrow.down"
        case .sent: return "arrow.up"
        case .unshield:
            return isExternalDestination ? "arrow.up" : "creditcard.fill"
        case .withdrawal:
            return isExternalDestination ? "arrow.up" : "d.circle.fill"
        case .identityCreate: return "person.crop.circle.fill"
        case .shieldedSpend: return "questionmark"
        case .shield, .shieldFromAssetLock: return nil
        }
    }

    /// Internal moves between the user's own balances (Platform ↔
    /// Shielded). The recorded direction reflects the shielded pool's
    /// perspective (a shield is "incoming"), but no funds were gained
    /// or lost — these render signless, like self-transfers. An
    /// unshield or withdrawal to an EXTERNAL address is real money
    /// leaving the wallet, so it is NOT internal despite its kind
    /// being an own-initiated one.
    var isInternalMove: Bool {
        switch kind {
        case .shield, .shieldFromAssetLock:
            return true
        case .unshield, .withdrawal:
            return !isExternalDestination
        case .received, .sent, .identityCreate, .shieldedSpend:
            return false
        }
    }

    /// Whether the amount renders with a +/− direction sign.
    var showsDirectionSign: Bool {
        !isInternalMove && direction != .selfTransfer
    }

    /// From/To wording for the detail sheet. Internal moves name the
    /// user's own balances on both sides (a guarantee — see the fetch
    /// doc); an external unshield/withdrawal names the destination
    /// address (or an honest "External address" when the counterparty
    /// script couldn't be decoded); a Sent entry names its decoded
    /// recipient and stays route-less when the counterparty didn't decode.
    var internalMoveRoute: (source: String, destination: String)? {
        let platform = NSLocalizedString("Your Platform balance", comment: "Shielded activity: source/destination of an internal move")
        let shielded = NSLocalizedString("Your Shielded balance", comment: "Shielded activity: source/destination of an internal move")
        let transparent = NSLocalizedString("Your Transparent balance", comment: "Shielded activity: source/destination of an internal move")
        switch kind {
        case .shield: return (platform, shielded)
        case .shieldFromAssetLock: return (transparent, shielded)
        case .unshield, .withdrawal:
            if isExternalDestination {
                let fallback = NSLocalizedString("External address", comment: "Shielded activity: destination outside this wallet whose exact address is unknown")
                return (shielded, destinationAddress ?? fallback)
            }
            return kind == .unshield ? (shielded, platform) : (shielded, transparent)
        case .sent:
            // Only when the recipient address decoded — a bare Sent row
            // (no counterparty recovered) keeps the sheet route-less
            // rather than claiming a destination we don't know.
            guard let destinationAddress else { return nil }
            return (shielded, destinationAddress)
        case .received, .identityCreate, .shieldedSpend: return nil
        }
    }

    /// Signed duffs for the row amount label. Internal moves and
    /// self-transfers stay positive (and render signless via
    /// `showsDirectionSign`) — own funds moved, not gained or lost.
    var signedDashAmount: Int64 {
        let magnitude = amountDuffs > UInt64(Int64.max) ? Int64.max : Int64(amountDuffs)
        return direction == .outgoing && showsDirectionSign ? -magnitude : magnitude
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
                    .foregroundColor(.dash.blue)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.dash.blue.opacity(0.08)))
                if let badge = item.secondarySystemIcon {
                    Image(systemName: badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.dash.whiteText)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.dash.blue))
                        .offset(x: 4, y: 4)
                }
            }
            .padding(.top, 24)

            Text(item.title)
                .font(.headline)
                .foregroundColor(.dash.primaryText)
                .padding(.top, 12)

            DashAmount(amount: item.signedDashAmount, font: .title2, showDirection: item.showsDirectionSign)
                .padding(.top, 4)
            Text(item.fiatAmount)
                .font(.footnote)
                .foregroundColor(.dash.tertiaryText)
                .padding(.top, 2)

            VStack(spacing: 0) {
                if let details = item.detailsText {
                    infoRow(NSLocalizedString("Type", comment: ""), details)
                }
                // Internal moves are self-originated BY CONSTRUCTION: the
                // shield/unshield kinds are only ever live-recorded for
                // this wallet's own operation (the restore-path scan can't
                // prove origin, so it never labels anything a shield —
                // an old own-shield resurfaces as plain "Received").
                // Saying From/To here is therefore a guarantee, not a guess.
                if let route = item.internalMoveRoute {
                    infoRow(NSLocalizedString("From", comment: ""), route.source)
                    if item.isExternalDestination, let address = item.destinationAddress {
                        copyableRow(NSLocalizedString("To", comment: ""), address)
                    } else {
                        infoRow(NSLocalizedString("To", comment: ""), route.destination)
                    }
                    // Internal unshields still name the exact receiving
                    // address (the counterparty the SDK recorded), not
                    // just "your Platform balance".
                    if !item.isExternalDestination, let address = item.destinationAddress {
                        copyableRow(NSLocalizedString("Address", comment: ""), address)
                    }
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
                            .foregroundColor(.dash.tertiaryText)
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
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 24)

            if item.kind == .shieldedSpend {
                Text(NSLocalizedString("Restored wallets can't always recover the operation type. This entry was reconstructed from on-chain note data.", comment: "Shielded activity"))
                    .font(.caption)
                    .foregroundColor(.dash.tertiaryText)
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
                .foregroundColor(.dash.tertiaryText)
            Spacer()
            Text(value)
                .font(.footnote)
                .foregroundColor(.dash.primaryText)
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
                    .foregroundColor(.dash.tertiaryText)
                Spacer()
                Text(value.prefix(8) + "…" + value.suffix(8))
                    .font(.footnote)
                    .monospaced()
                    .foregroundColor(.dash.primaryText)
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundColor(.dash.blue)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}
