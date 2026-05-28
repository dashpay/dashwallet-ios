//
//  InternalTransferViewModel.swift
//  DashWallet
//

import Combine
import Foundation
import SwiftUI

enum InternalTransferUnit: String {
    case dash
    case fiat
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
    @Published private(set) var coreBalance: UInt64 = 0
    @Published private(set) var platformBalance: UInt64 = 0

    private var cancellables = Set<AnyCancellable>()

    init() {
        coreBalance = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        platformBalance = PlatformAddressSyncCoordinator.shared.platformBalance

        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
            .sink { [weak self] balance in
                self?.coreBalance = balance?.total ?? 0
            }
            .store(in: &cancellables)

        PlatformAddressSyncCoordinator.shared.$platformBalance
            .receive(on: RunLoop.main)
            .sink { [weak self] credits in
                self?.platformBalance = credits
            }
            .store(in: &cancellables)
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

    var canContinue: Bool {
        parsedDashAmount > 0
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

    var coreBalanceFormatted: String {
        coreBalance.formattedDashAmount
    }

    var platformBalanceFormatted: String {
        let formatted = Self.creditsFormatter.string(from: NSNumber(value: platformBalance)) ?? "\(platformBalance)"
        return "\(formatted) credits"
    }

    func fillMaxFromWallet() {
        switch unit {
        case .dash:
            amountText = coreBalance.formattedDashAmountWithoutCurrencySymbol
        case .fiat:
            let dashDecimal = coreBalance.dashAmount
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
