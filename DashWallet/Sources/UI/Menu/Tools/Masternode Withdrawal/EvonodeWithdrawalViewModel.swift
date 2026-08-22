//
//  EvonodeWithdrawalViewModel.swift
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

import Foundation
import OSLog
import SwiftDashSDK
import UIKit

// MARK: - EvonodeWithdrawalViewModel

/// Claim (withdraw) an evonode's Platform credits to the Core chain.
///
/// Holds the form state for `EvonodeWithdrawalScreen` and runs the claim:
/// auth gate → `PlatformWalletManager.masternodeWithdraw` (the whole
/// orchestration — identity fetch, key selection, resolver-backed signing,
/// broadcast — lives in Rust behind that one call).
///
/// Which key signs, and whether the destination is editable, comes from the
/// SDK preflight (`MasternodeWithdrawalKeys`) the detail screen fetched:
/// - payout (transfer) key in this wallet ⇒ sign with it, any destination;
/// - otherwise the owner key ⇒ Platform pays the registered payout address
///   and no destination can be chosen.
@MainActor
final class EvonodeWithdrawalViewModel: ObservableObject {
    enum Unit { case dash, fiat }

    enum Phase: Equatable {
        case idle
        case authorizing
        case submitting
        /// The claim was accepted; `remainingCredits` is the identity's new
        /// claimable balance as proven by Platform.
        case success(remainingCredits: UInt64)
        /// The claim was broadcast but its result could not be confirmed
        /// (`PlatformWalletError.masternodeWithdrawalUnconfirmed`). It may
        /// have executed and the identity nonce was consumed — never
        /// re-submit from this state; the detail screen re-reads the balance.
        case submittedUnconfirmed(String)
        /// Definitive failure — nothing executed; safe to try again.
        case failed(String)
    }

    /// Credits per duff (1 DASH = 1e8 duffs = 1e11 credits).
    static let creditsPerDuff: UInt64 = 1000

    /// Headroom kept back from a Max withdrawal so the identity can still pay
    /// the transition fee. Platform's minimum credit-withdrawal fee is
    /// 0.004 DASH (`STATE_TRANSITION_MIN_FEES_VERSION1.credit_withdrawal` =
    /// 400,000,000 credits); the reserve adds a small margin on top.
    static let feeReserveCredits: UInt64 = 500_000_000

    /// The fee figure shown to the user (the Platform minimum above).
    static let estimatedFeeCredits: UInt64 = 400_000_000

    /// Platform's minimum withdrawal: 1000 duffs (`system_limits.min_withdrawal_amount`).
    static let minWithdrawalCredits: UInt64 = 1_000_000

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.evonode-withdrawal")

    let masternode: PlatformMasternode
    let keys: MasternodeWithdrawalKeys
    let claimableCredits: UInt64
    /// Owner-key index from the masternode list's address join; forwarded
    /// to the SDK, which verifies it by derivation before using it.
    let ownerKeyIndexHint: UInt32?

    /// Raw keypad text in `unit` (locale separator allowed; "0" = empty).
    @Published var amountText: String = "0" {
        didSet { maxAmountCredits = nil }
    }
    @Published var unit: Unit = .dash
    /// Destination address. Starts at the registered payout address; only
    /// editable when `canChooseDestination`.
    @Published var destinationText: String
    @Published private(set) var phase: Phase = .idle

    /// Set by `fillMax()` so a Max claim submits the exact credit amount
    /// rather than a re-parsed (display-rounded) figure. Cleared on any edit.
    @Published private(set) var maxAmountCredits: UInt64?

    init(
        masternode: PlatformMasternode,
        keys: MasternodeWithdrawalKeys,
        claimableCredits: UInt64,
        ownerKeyIndexHint: UInt32? = nil
    ) {
        self.masternode = masternode
        self.keys = keys
        self.claimableCredits = claimableCredits
        self.ownerKeyIndexHint = ownerKeyIndexHint
        destinationText = keys.payoutAddress ?? ""
    }

    // MARK: Keys / destination

    /// The payout (transfer) key is in this wallet ⇒ the destination is free.
    var canChooseDestination: Bool { keys.canChooseDestination }

    /// Which wallet key signs. The transfer key when available (it allows any
    /// destination), else the owner key. `nil` when neither is held — the
    /// detail screen doesn't offer Withdraw in that case.
    var signingKey: MasternodeWithdrawalSigningKey? { keys.preferredSigningKey }

    var payoutAddress: String? { keys.payoutAddress }

    var destinationIsPayoutAddress: Bool {
        guard let payout = keys.payoutAddress else { return false }
        return destinationText.trimmingCharacters(in: .whitespacesAndNewlines) == payout
    }

    var destinationIsValid: Bool {
        destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
            .isValidDashAddressForCurrentNetwork
    }

    /// Shown under the address field once the user typed something invalid.
    var destinationErrorMessage: String? {
        let trimmed = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !destinationIsValid else { return nil }
        return NSLocalizedString("Not a valid Dash address for this network", comment: "Evonode withdrawal")
    }

    func resetDestinationToPayoutAddress() {
        destinationText = keys.payoutAddress ?? ""
    }

    /// Apply a scanned / pasted value. Accepts a bare address or a
    /// `dash:` payment URI (the address part is used).
    func setDestination(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("dash:") {
            value = String(value.dropFirst("dash:".count))
            if let query = value.firstIndex(of: "?") {
                value = String(value[..<query])
            }
        }
        destinationText = value
    }

    func pasteDestination() {
        guard let text = UIPasteboard.general.string else { return }
        setDestination(text)
    }

    // MARK: Amount

    /// Maximum claimable after the fee reserve (whole duffs).
    var maxWithdrawableCredits: UInt64 {
        guard claimableCredits > Self.feeReserveCredits else { return 0 }
        let net = claimableCredits - Self.feeReserveCredits
        return net - net % Self.creditsPerDuff
    }

    var claimableDashFormatted: String {
        (claimableCredits / Self.creditsPerDuff).formattedDashAmountWithoutCurrencySymbol
    }

    var maxWithdrawableDashFormatted: String {
        (maxWithdrawableCredits / Self.creditsPerDuff).formattedDashAmountWithoutCurrencySymbol
    }

    var estimatedFeeDashFormatted: String {
        (Self.estimatedFeeCredits / Self.creditsPerDuff).formattedDashAmountWithoutCurrencySymbol
    }

    private var rawTypedDecimal: Decimal {
        let sanitized = amountText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: sanitized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// The amount in DASH the user means, whichever unit is being typed.
    var parsedDashAmount: Decimal {
        if let maxAmountCredits {
            return (maxAmountCredits / Self.creditsPerDuff).dashAmount
        }
        let raw = rawTypedDecimal
        switch unit {
        case .dash:
            return raw
        case .fiat:
            guard raw > 0 else { return 0 }
            return (try? CurrencyExchanger.shared.convertToDash(amount: raw, currency: App.fiatCurrency)) ?? 0
        }
    }

    var amountDuffs: UInt64 { parsedDashAmount.plainDashAmount }

    /// What gets submitted: whole duffs × 1000 — always a multiple of 1000
    /// credits, as Platform requires for a withdrawal.
    var amountCredits: UInt64 {
        if let maxAmountCredits { return maxAmountCredits }
        return amountDuffs * Self.creditsPerDuff
    }

    var fiatCurrencyCode: String { App.fiatCurrency }

    var fiatAmountString: String {
        CurrencyExchanger.shared.fiatAmountString(for: parsedDashAmount)
    }

    var amountValidationMessage: String? {
        let credits = amountCredits
        guard credits > 0 else { return nil }
        if maxWithdrawableCredits == 0 {
            return NSLocalizedString(
                "The claimable balance is too small to cover the Platform withdrawal fee.",
                comment: "Evonode withdrawal")
        }
        if credits > maxWithdrawableCredits {
            return String(
                format: NSLocalizedString(
                    "You can withdraw up to %@ DASH — the rest stays to cover the Platform fee. Tap Max to use it.",
                    comment: "Evonode withdrawal"),
                maxWithdrawableDashFormatted)
        }
        if credits < Self.minWithdrawalCredits {
            return String(
                format: NSLocalizedString("The minimum withdrawal is %@ DASH.", comment: "Evonode withdrawal"),
                (Self.minWithdrawalCredits / Self.creditsPerDuff).formattedDashAmountWithoutCurrencySymbol)
        }
        return nil
    }

    var amountIsValid: Bool {
        let credits = amountCredits
        return credits >= Self.minWithdrawalCredits && credits <= maxWithdrawableCredits
    }

    var canContinue: Bool {
        signingKey != nil && amountIsValid && destinationIsValid && phase == .idle
    }

    func fillMax() {
        let credits = maxWithdrawableCredits
        guard credits > 0 else { return }
        let duffs = credits / Self.creditsPerDuff
        switch unit {
        case .dash:
            amountText = duffs.formattedDashAmountWithoutCurrencySymbol
        case .fiat:
            let fiat = (try? CurrencyExchanger.shared.convertDash(amount: duffs.dashAmount, to: App.fiatCurrency)) ?? 0
            amountText = Self.formatTyped(fiat, fractionDigits: 2)
        }
        // `amountText.didSet` cleared it — pin the exact figure afterwards.
        maxAmountCredits = credits
    }

    static func formatTyped(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.decimalSeparator = "."
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    // MARK: Signing key label

    /// "Owner key (ProviderOwnerKeys #4)" / "Payout address key" for the
    /// confirmation summary.
    var signingKeyLabel: String {
        switch signingKey {
        case .transfer:
            return NSLocalizedString("Payout address key", comment: "Evonode withdrawal signing key")
        case .owner:
            let ownership = PersistentMasternode.keyOwnershipLabel(
                inWallet: keys.ownerKeyInWallet,
                accountType: 9,
                index: keys.ownerKeyIndex ?? 0)
            return String(
                format: NSLocalizedString("Owner key (%@)", comment: "Evonode withdrawal signing key"),
                ownership)
        case nil:
            return NSLocalizedString("Not available", comment: "")
        }
    }

    // MARK: Submit

    /// Auth gate, then the claim. Never broadcasts without the user passing
    /// the PIN / biometric prompt. On success `phase` carries the remaining
    /// claimable balance Platform proved after the withdrawal. An ambiguous
    /// outcome (broadcast accepted, result unconfirmed) lands in
    /// `.submittedUnconfirmed` — a terminal state here: the nonce was
    /// consumed, so a retry could withdraw twice.
    func submit() async {
        guard canContinue, let signingKey else { return }
        guard let manager = SwiftDashSDKHost.shared.manager,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            phase = .failed(NSLocalizedString("Wallet is not ready. Try again in a moment.", comment: "Evonode withdrawal"))
            return
        }

        let credits = amountCredits
        let destination = signingKey == .transfer
            ? destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        phase = .authorizing
        let outcome = await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
            spendAmount: amountDuffs)
        switch outcome {
        case .ok:
            break
        case .cancelled:
            phase = .idle
            return
        case .failed, .timedOut:
            phase = .failed(NSLocalizedString("Authentication failed", comment: ""))
            return
        }

        phase = .submitting
        Self.logger.info("🏛️ EVONODE :: withdrawing \(credits) credits with \(String(describing: signingKey)) key to \(destination ?? "payout address", privacy: .private)")
        do {
            let remaining = try await manager.masternodeWithdraw(
                walletId: walletId,
                proTxHash: masternode.proTxHash,
                amountCredits: credits,
                signingKey: signingKey,
                destinationAddress: destination,
                ownerKeyIndexHint: ownerKeyIndexHint)
            Self.logger.info("🏛️ EVONODE :: withdrawal accepted, remaining \(remaining) credits")
            phase = .success(remainingCredits: remaining)
        } catch PlatformWalletError.masternodeWithdrawalUnconfirmed(let detail) {
            Self.logger.error("🏛️ EVONODE :: withdrawal outcome unconfirmed: \(detail, privacy: .public)")
            phase = .submittedUnconfirmed(detail)
        } catch {
            Self.logger.error("🏛️ EVONODE :: withdrawal failed: \(String(describing: error), privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Back to the editable state after a DEFINITIVE failure (the form keeps
    /// its values). `.submittedUnconfirmed` is deliberately not resettable —
    /// the user must leave and re-read the balance first.
    func resetAfterFailure() {
        if case .failed = phase {
            phase = .idle
        }
    }
}
