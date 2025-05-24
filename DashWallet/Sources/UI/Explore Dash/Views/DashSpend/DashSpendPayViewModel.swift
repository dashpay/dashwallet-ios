//  
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import Combine

private let defaultCurrency = kDefaultCurrencyCode

@MainActor
class DashSpendPayViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let fiatFormatter = NumberFormatter.fiatFormatter(currencyCode: defaultCurrency)
    private let ctxSpendService = CTXSpendService.shared
    
    private(set) var amount: Decimal = 0
    private(set) var savingsFraction: Decimal = 0.0
    @Published private(set) var isLoading = false
    
    let currencySymbol: String = {
        let locale = Locale.current as NSLocale
        return locale.displayName(forKey: .currencySymbol, value: defaultCurrency) ?? "$"
    }()
    
    @Published var merchantTitle: String = ""
    @Published var merchantIconUrl: String = ""
    @Published var walletBalance: UInt64 = 0
    @Published var coinJoinBalance: UInt64 = 0
    @Published var minimumAmount: Decimal = 0
    @Published var maximumAmount: Decimal = 0
    @Published var error: Error? = nil
    @Published var input: String = "0" {
        didSet {
            // Replace the initial "0" when entering a new digit
            if oldValue == "0" && input.count > 1 && input.first == "0" && input[input.index(after: input.startIndex)] != "." {
                input = String(input.dropFirst())
            }
            
            // Validate input to ensure no more than 2 decimal places
            if let decimalSeparatorIndex = input.firstIndex(of: ".") {
                let decimalPart = input[input.index(after: decimalSeparatorIndex)...]
                if decimalPart.count > 2 {
                    input = oldValue
                }
            }
            
            if input.isEmpty {
                input = "0"
            }
            
            amount = input.decimal() ?? 0
            checkAmountForErrors()
        }
    }
    
    private var merchantId: String = ""
    
    var costMessage: String {
        let originalPrice = fiatFormatter.string(for: amount) ?? "0.00"
        let discountedPrice = amount * (1 - savingsFraction)
        let formattedDiscountedPrice = fiatFormatter.string(for: discountedPrice) ?? "0.00"
        
        let discount = NSDecimalNumber(decimal: savingsFraction * 100).intValue
        return String.localizedStringWithFormat(
            NSLocalizedString("You are buying a %@ gift card for %@ (%d%% discount)", comment: "DashSpend"),
            originalPrice, formattedDiscountedPrice, discount)
    }
    var showCost: Bool { error == nil && amount >= minimumAmount && amount <= maximumAmount }
    var showLimits: Bool { error == nil && !showCost }
    var minimumLimitMessage: String { String.localizedStringWithFormat(NSLocalizedString("Min: %@", comment: "DashSpend"), fiatFormatter.string(for: minimumAmount) ?? "0.0" ) }
    var maximumLimitMessage: String { String.localizedStringWithFormat(NSLocalizedString("Max: %@", comment: "DashSpend"), fiatFormatter.string(for: maximumAmount) ?? "0.0" ) }
    var isMixing: Bool { CoinJoinService.shared.mixingState.isInProgress }
    
    init(merchant: ExplorePointOfUse) {
        merchantTitle = merchant.name
        merchantIconUrl = merchant.logoLocation ?? ""
        savingsFraction = Decimal(merchant.merchant?.savingsBasisPoints ?? 0) / Decimal(10000)
        
        if let merchantId = merchant.merchant?.merchantId {
            self.merchantId = merchantId
        }
    }
    
    func subscribeToUpdates() {
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in self?.refreshBalance() }
            .store(in: &cancellableBag)
        
        if CoinJoinService.shared.mixingState.isInProgress {
            CoinJoinService.shared.$progress
                .removeDuplicates()
                .sink { [weak self] progress in
                    self?.coinJoinBalance = progress.coinJoinBalance
                }
                .store(in: &cancellableBag)
        }
        
        self.refreshBalance()
        
        // Get updated merchant info from CTX API if user is signed in
        Task {
            await updateMerchantInfo()
        }
    }
    
    func unsubscribeFromAll() {
        cancellableBag.removeAll()
    }
    
    private func refreshBalance() {
        walletBalance = DWEnvironment.sharedInstance().currentWallet.balance
    }
    
    private func checkAmountForErrors() {
        guard DWGlobalOptions.sharedInstance().isResyncingWallet == false ||
            DWEnvironment.sharedInstance().currentChainManager.syncPhase == .synced
        else {
            error = SendAmountError.syncingChain
            return
        }

        guard !canShowInsufficientFunds else {
            error = isMixing ? SendAmountError.insufficientMixedFunds : SendAmountError.insufficientFunds
            return
        }

        error = nil
    }
    
    private var canShowInsufficientFunds: Bool {
        let dashAmount = (try? CurrencyExchanger.shared.convertToDash(amount: amount, currency: kDefaultCurrencyCode)) ?? 0

        let account = DWEnvironment.sharedInstance().currentAccount
        let allAvailableFunds = isMixing ? coinJoinBalance : account.maxOutputAmount

        return dashAmount.plainDashAmount > allAvailableFunds
    }
    
    // MARK: - CTX Integration
    
    private func updateMerchantInfo() async {
        guard !merchantId.isEmpty, ctxSpendService.isUserSignedIn else { return }
        
        do {
            let merchantInfo = try await ctxSpendService.getMerchant(merchantId: merchantId)
            
            // Update merchant details
            savingsFraction = Decimal(merchantInfo.savingsPercentage) / 100
            
            if merchantInfo.denominationType == .Range {
                minimumAmount = Decimal(merchantInfo.minimumCardPurchase)
                maximumAmount = Decimal(merchantInfo.maximumCardPurchase)
            }
            
            // Revalidate current amount
            checkAmountForErrors()
        } catch {
            DSLogger.log("Failed to get merchant info: \(error)")
        }
    }
    
    func purchaseGiftCard() async throws -> GiftCardResponse {
        guard !merchantId.isEmpty, ctxSpendService.isUserSignedIn else {
            DSLogger.log("Purchase gift card failed: User not signed in or merchant ID is empty")
            throw CTXSpendError.unauthorized
        }
        
        DSLogger.log("Attempting to purchase gift card for merchant \(merchantId) with amount \(amount)")
        isLoading = true
        defer { isLoading = false }
        
        do {
            let fiatAmountString = String(format: "%.2f", Double(truncating: amount as NSDecimalNumber))
            DSLogger.log("Making API request to purchase gift card: merchantId=\(merchantId), amount=\(fiatAmountString)USD")
            
            let response = try await ctxSpendService.purchaseGiftCard(
                merchantId: merchantId,
                fiatAmount: fiatAmountString,
                fiatCurrency: "USD",
                cryptoCurrency: "DASH"
            )
            
            return response
        } catch {
            DSLogger.log("Gift card purchase failed with error: \(error)")
            throw error
        }
    }
    
    func isUserSignedIn() -> Bool {
        return ctxSpendService.isUserSignedIn
    }
    
    func saveGiftCardDummy(txHashData: Data, giftCardId: String) {
        // TODO: Implement gift card storage in iOS
        // For now, just log the information
        DSLogger.log("Gift card saved - txId: \(txHashData.hexEncodedString()), giftCardId: \(giftCardId)")
        
        // In a full implementation, this would save to Core Data or UserDefaults
        // Similar to how the Android version saves to a Room database
    }
}
