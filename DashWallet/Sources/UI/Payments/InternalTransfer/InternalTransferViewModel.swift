//
//  InternalTransferViewModel.swift
//  DashWallet
//

import Combine
import Foundation
import SwiftDashSDK
import SwiftUI

enum InternalTransferUnit: String {
    case dash
    case fiat
}

/// Source bucket the user is funding the shielded transfer from. Decides
/// which SDK route the `ShieldedTransferCoordinator` runs (asset-lock vs
/// transparent shield) and which balance the screen validates against.
enum InternalTransferSource: String {
    case core
    case platform
}

/// Direction of the transfer, toggled by the swap badge. `.toShielded`
/// funds the shielded balance from Core/Platform (forward); `.fromShielded`
/// withdraws from the shielded balance back to the transparent Dash Wallet
/// (reverse, via `PlatformWalletManager.shieldedWithdraw`).
enum InternalTransferDirection {
    case toShielded
    case fromShielded
}

@MainActor
final class InternalTransferViewModel: ObservableObject {

    @Published var amountText: String = "0"
    @Published var unit: InternalTransferUnit = .dash {
        didSet {
            guard oldValue != unit else { return }
            convertAmountText(from: oldValue, to: unit)
        }
    }

    /// Which "From" bucket the user picked on the source rows. Defaults to
    /// `.core` because most users have BIP44 balance before they have
    /// Platform Payment credits. Only meaningful while `.toShielded`.
    @Published var source: InternalTransferSource = .core

    /// Forward (Core/Platform → Shielded) vs reverse (Shielded → Dash Wallet),
    /// toggled by the swap badge. Reverse has a single fixed destination
    /// (Dash Wallet), so `source` is ignored while `.fromShielded`.
    @Published var direction: InternalTransferDirection = .toShielded

    /// BIP44-only Core balance in duffs — the same number as
    /// `SwiftDashSDKWalletState.balance.total`. Used to validate
    /// `.core` source transfers (which go through `shieldedFundFromAssetLock`,
    /// drawing from BIP44 UTXOs only).
    @Published private(set) var coreBalanceDuffs: UInt64 = 0

    /// DIP-17 Platform Payment credits (1e11 per DASH). Sourced from
    /// `PlatformAddressSyncCoordinator.platformBalance`. Used to validate
    /// `.platform` source transfers (which go through `shieldedShield`,
    /// drawing transparent credits directly).
    @Published private(set) var platformCredits: UInt64 = 0

    /// Real shielded balance in credits, fed by the SDK's shielded sync
    /// pass (`PlatformWalletManager.$lastShieldedSyncEvent → result(for:)`).
    /// Updates whenever the shielded sync loop completes a pass — including
    /// the manual `syncShieldedNow()` kick after a successful transfer.
    @Published private(set) var shieldedBalance: UInt64 = 0

    private var cancellables = Set<AnyCancellable>()

    init() {
        coreBalanceDuffs = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        platformCredits = PlatformAddressSyncCoordinator.shared.platformBalance

        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
            .sink { [weak self] balance in
                self?.coreBalanceDuffs = balance?.total ?? 0
            }
            .store(in: &cancellables)

        PlatformAddressSyncCoordinator.shared.$platformBalance
            .receive(on: RunLoop.main)
            .sink { [weak self] credits in
                self?.platformCredits = credits
            }
            .store(in: &cancellables)

        if let manager = SwiftDashSDKHost.shared.manager,
           let wallet = SwiftDashSDKHost.shared.wallet {
            let walletId = wallet.walletId
            // Seed once from whatever the manager already saw — the
            // publisher only fires on new sync events.
            shieldedBalance = manager.lastShieldedSyncEvent?
                .result(for: walletId)?
                .balance ?? 0

            manager.$lastShieldedSyncEvent
                .receive(on: RunLoop.main)
                .sink { [weak self] event in
                    guard let self else { return }
                    if let walletResult = event?.result(for: walletId),
                       walletResult.success,
                       !walletResult.cooldownSkip {
                        self.shieldedBalance = walletResult.balance
                    }
                }
                .store(in: &cancellables)
        }
    }

    /// The raw numeric value the user has typed, with locale comma normalised
    /// to a dot. Interpretation depends on `unit` — this is *not yet* the DASH
    /// amount when in `.fiat` mode.
    private var rawTypedDecimal: Decimal {
        let sanitized = amountText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: sanitized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    var parsedDashAmount: Decimal {
        let raw = rawTypedDecimal
        switch unit {
        case .dash:
            return raw
        case .fiat:
            guard raw > 0 else { return 0 }
            return (try? CurrencyExchanger.shared.convertToDash(amount: raw, currency: App.fiatCurrency)) ?? 0
        }
    }

    /// Continue is enabled when the typed amount is > 0 AND fits in the
    /// currently-selected source bucket. Each route has its own balance
    /// envelope — asset-lock spends BIP44 duffs, transparent shield spends
    /// DIP-17 credits.
    var canContinue: Bool {
        // Gate on duffs, not raw DASH: a sub-duff amount (e.g. 1e-9 DASH)
        // renders as 0 in the confirm sheet, so it must not enable Continue —
        // otherwise the credit routes would submit a nonzero amount while the
        // UI shows 0.
        guard dashDuffsUnsigned > 0 else { return false }
        switch direction {
        case .toShielded:
            switch source {
            case .core:
                // Asset-lock route: the Platform pool fee is carved from the
                // locked value (not charged on top of the Core balance) and the
                // Rust side rejects an undersized lock, so no source-balance fee
                // headroom is reserved here.
                return dashDuffsUnsigned <= coreBalanceDuffs
            case .platform:
                // Shield (Type 15): the SDK's input selection requires
                // balance ≥ amount + reserve. Fail closed if the reserve is
                // unavailable. Subtraction keeps the UInt64 add overflow-safe.
                guard let reserve = feeReserveCredits else { return false }
                return platformCredits >= reserve
                    && creditsPreview <= platformCredits - reserve
            }
        case .fromShielded:
            // Unshield/withdraw: the SDK debits amount + fee from the shielded
            // pool (recipient receives the full amount), so the balance must
            // cover amount + fee. Fail closed if the reserve is unavailable.
            guard let reserve = feeReserveCredits else { return false }
            return shieldedBalance >= reserve
                && creditsPreview <= shieldedBalance - reserve
        }
    }

    /// Fixed input-selection reserve the Shield route requires ON TOP of the
    /// amount — mirrors Rust `FEE_RESERVE_CREDITS = 1_000_000_000`
    /// (rs-platform-wallet `platform_wallet.rs`; `select_shield_inputs` rejects
    /// `balance < amount + reserve`). It is a conservative selection headroom,
    /// NOT the on-chain fee (which is ~6× smaller); the unclaimed remainder
    /// stays on the source address rather than being spent.
    private static let shieldSelectionReserveCredits: UInt64 = 1_000_000_000

    /// Fee/selection headroom (credits) the SDK requires ON TOP of the amount
    /// for the active route, used by `canContinue` and Max. `nil` means the
    /// requirement is currently unavailable for a fee-reserved route → callers
    /// fail closed (block). A literal `0` (the asset-lock route) is NOT `nil` —
    /// that route reserves nothing from the source balance.
    private var feeReserveCredits: UInt64? {
        switch (direction, source) {
        case (.toShielded, .core):
            return 0
        case (.toShielded, .platform):
            // Shield: fixed 1e9-credit selection reserve, not the (smaller) fee.
            return Self.shieldSelectionReserveCredits
        case (.fromShielded, .core):
            // The withdraw/unshield fee scales with the number of spent notes;
            // the SDK recomputes it from real note selection (up to the
            // 16-action `max_shielded_transition_actions` cap) at send time.
            // Reserve that worst case so a fragmented wallet can't pass the
            // affordability check and then fail SDK note selection.
            return try? PlatformWalletManager.estimateShieldedFee(kind: .withdrawal, numActions: 16)
        case (.fromShielded, .platform):
            return try? PlatformWalletManager.estimateShieldedFee(kind: .unshield, numActions: 16)
        }
    }

    /// A credit balance minus the route's fee reserve, floored at 0 — so a Max
    /// fill leaves room for the fee/headroom the SDK requires on top of the
    /// amount. Fails closed (returns 0) when the reserve is unavailable.
    private func creditsMinusFeeReserve(_ balanceCredits: UInt64) -> UInt64 {
        guard let fee = feeReserveCredits else { return 0 }
        return balanceCredits > fee ? balanceCredits - fee : 0
    }

    /// `parsedDashAmount` expressed as Int64 duffs, for `DashAmount` views.
    var dashDuffs: Int64 {
        Int64(parsedDashAmount.plainDashAmount)
    }

    /// Same as `dashDuffs` but unsigned, for SDK calls and balance compares
    /// (avoids re-rounding via Int64).
    var dashDuffsUnsigned: UInt64 {
        parsedDashAmount.plainDashAmount
    }

    /// Fiat-formatted DASH amount — always returns the fiat representation
    /// regardless of `unit`. Used by the confirm sheet which always shows
    /// fiat alongside the credits.
    var fiatAmountString: String {
        CurrencyExchanger.shared.fiatAmountString(for: parsedDashAmount)
    }

    /// Currency symbol for the active fiat (e.g. `$`). Used by the view to
    /// prefix the big-number text in FIAT mode.
    var primaryCurrencySymbol: String {
        NumberFormatter.fiatFormatter.currencySymbol ?? ""
    }

    /// The small grey line under the big number. Shows whichever unit is *not*
    /// currently the input unit.
    var secondaryDisplayString: String {
        switch unit {
        case .dash:
            return CurrencyExchanger.shared.fiatAmountString(for: parsedDashAmount)
        case .fiat:
            return parsedDashAmount.formattedDashAmount
        }
    }

    /// Credit amount handed to the SDK, aligned to the displayed duff precision
    /// (1 duff = 1000 credits) so the confirm sheet's DASH amount exactly equals
    /// what gets submitted — no sub-duff dust that shows as 0 but transfers a
    /// nonzero credit amount. Decimal keeps the conversion overflow-safe for
    /// absurd inputs (saturates rather than trapping).
    var creditsPreview: UInt64 {
        NSDecimalNumber(decimal: Decimal(dashDuffsUnsigned) * 1000).uint64Value
    }

    /// The transfer amount as DASH (no currency symbol), for the
    /// "You will transfer" preview line. Credits are never shown to the user;
    /// `creditsPreview` (the raw integer) is kept only for SDK args + the
    /// reverse balance check.
    var dashAmountFormatted: String {
        parsedDashAmount.formattedDashAmountWithoutCurrencySymbol
    }

    /// Formatted BIP44 balance as DASH (no currency symbol). Used by the
    /// Dash Wallet source row.
    var coreBalanceFormatted: String {
        coreBalanceDuffs.formattedDashAmountWithoutCurrencySymbol
    }

    /// Formatted Platform Payment balance as DASH (no currency symbol). The
    /// credits-to-duffs conversion is `/ 1000` (1e8 duffs per DASH vs 1e11
    /// credits per DASH).
    var platformCreditsFormatted: String {
        (platformCredits / 1000).formattedDashAmountWithoutCurrencySymbol
    }

    /// Formatted live shielded balance as DASH (no currency symbol).
    /// Credits → duffs is `/ 1000` (1e8 duffs per DASH vs 1e11 credits).
    var shieldedBalanceFormatted: String {
        (shieldedBalance / 1000).formattedDashAmountWithoutCurrencySymbol
    }

    /// Source-aware Max fill. Keeps the same unit semantics — DASH or fiat —
    /// but draws the upper bound from whichever bucket the user picked.
    func fillMaxFromWallet() {
        let sourceDuffs: UInt64
        switch direction {
        case .toShielded:
            switch source {
            case .core:
                sourceDuffs = coreBalanceDuffs
            case .platform:
                // Reserve the fee the SDK charges on top of the amount so Max
                // stays sendable (credits → duffs: integer divide by 1000).
                sourceDuffs = creditsMinusFeeReserve(platformCredits) / 1000
            }
        case .fromShielded:
            // Reverse: upper bound is the shielded balance minus the fee reserve
            // (debited on top of the amount), so Max stays sendable.
            sourceDuffs = creditsMinusFeeReserve(shieldedBalance) / 1000
        }

        switch unit {
        case .dash:
            amountText = sourceDuffs.formattedDashAmountWithoutCurrencySymbol
        case .fiat:
            let dashDecimal = sourceDuffs.dashAmount
            guard dashDecimal > 0 else {
                amountText = "0"
                return
            }
            if let fiat = try? CurrencyExchanger.shared.convertDash(amount: dashDecimal, to: App.fiatCurrency) {
                amountText = Self.formatTyped(fiat, fractionDigits: 2)
            } else {
                amountText = "0"
            }
        }
    }

    // MARK: - Conversion on unit toggle

    private func convertAmountText(from old: InternalTransferUnit, to new: InternalTransferUnit) {
        let raw = rawTypedDecimal
        guard raw > 0 else { return }
        let currency = App.fiatCurrency
        do {
            switch (old, new) {
            case (.dash, .fiat):
                let fiat = try CurrencyExchanger.shared.convertDash(amount: raw, to: currency)
                amountText = Self.formatTyped(fiat, fractionDigits: 2)
            case (.fiat, .dash):
                let dash = try CurrencyExchanger.shared.convertToDash(amount: raw, currency: currency)
                amountText = Self.formatTyped(dash, fractionDigits: 8)
            default:
                break
            }
        } catch {
            // Rate fetch failed — leave `amountText` as-is so the user can re-type.
        }
    }

    /// Formats a Decimal as a user-typed-style string: no grouping separator,
    /// dot as the decimal mark, trailing zeros trimmed. Capped at
    /// `fractionDigits` decimals.
    private static func formatTyped(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.decimalSeparator = "."
        let rounded = NSDecimalNumber(decimal: value)
        return formatter.string(from: rounded) ?? "\(value)"
    }
}
