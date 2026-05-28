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
    @Published var unit: InternalTransferUnit = .dash
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

    var parsedDashAmount: Decimal {
        let sanitized = amountText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: sanitized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    var canContinue: Bool {
        parsedDashAmount > 0
    }

    var fiatString: String {
        CurrencyExchanger.shared.fiatAmountString(for: parsedDashAmount)
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
        amountText = coreBalance.formattedDashAmountWithoutCurrencySymbol
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
