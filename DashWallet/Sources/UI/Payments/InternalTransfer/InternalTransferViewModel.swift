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
    /// Platform Payment credits.
    @Published var source: InternalTransferSource = .core

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
        let dash = parsedDashAmount
        guard dash > 0 else { return false }
        switch source {
        case .core:
            return dashDuffsUnsigned <= coreBalanceDuffs
        case .platform:
            return creditsPreview <= platformCredits
        }
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

    var creditsPreview: UInt64 {
        let credits = parsedDashAmount * Decimal(PlatformCreditsFormatter.creditsPerDash)
        return NSDecimalNumber(decimal: credits.rounded(.down)).uint64Value
    }

    var creditsPreviewFormatted: String {
        Self.creditsFormatter.string(from: NSNumber(value: creditsPreview)) ?? "\(creditsPreview)"
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

    /// Formatted live shielded balance for the To card.
    var shieldedBalanceFormatted: String {
        let formatted = Self.creditsFormatter.string(from: NSNumber(value: shieldedBalance)) ?? "\(shieldedBalance)"
        return "\(formatted) credits"
    }

    /// Source-aware Max fill. Keeps the same unit semantics — DASH or fiat —
    /// but draws the upper bound from whichever bucket the user picked.
    func fillMaxFromWallet() {
        let sourceDuffs: UInt64
        switch source {
        case .core:
            sourceDuffs = coreBalanceDuffs
        case .platform:
            // Credits → duffs: integer divide by 1000.
            sourceDuffs = platformCredits / 1000
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

    private static let creditsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f
    }()
}
