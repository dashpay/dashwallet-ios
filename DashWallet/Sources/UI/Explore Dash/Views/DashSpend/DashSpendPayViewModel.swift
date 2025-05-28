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
class DashSpendPayViewModel: NSObject, ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let fiatFormatter = NumberFormatter.fiatFormatter(currencyCode: defaultCurrency)
    private let ctxSpendService = CTXSpendService.shared
    private let sendCoinsService = SendCoinsService()

    private var merchantId: String = ""
    private(set) var amount: Decimal = 0
    private(set) var savingsFraction: Decimal = 0.0
    @Published private(set) var isLoading = false
    @Published private(set) var isProcessingPayment = false
    
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
    
    var costMessage: String {
        let originalPrice = fiatFormatter.string(for: amount) ?? "0.00"
        let discountedPrice = amount * (1 - savingsFraction)
        let formattedDiscountedPrice = fiatFormatter.string(for: discountedPrice) ?? "0.00"
        
        let discount = NSDecimalNumber(decimal: savingsFraction * 100).intValue
        return String.localizedStringWithFormat(
            NSLocalizedString("You are buying a %@ gift card for %@ (%d%% discount)", comment: "DashSpend"),
            originalPrice, formattedDiscountedPrice, discount)
    }
    var showCost: Bool { error == nil && amount >= minimumAmount && amount <= maximumAmount && hasValidLimits }
    var showLimits: Bool { error == nil && !showCost && hasValidLimits }
    var hasValidLimits: Bool { minimumAmount > 0 || maximumAmount > 0 }
    var minimumLimitMessage: String { String.localizedStringWithFormat(NSLocalizedString("Min: %@", comment: "DashSpend"), fiatFormatter.string(for: minimumAmount) ?? "0.0" ) }
    var maximumLimitMessage: String { String.localizedStringWithFormat(NSLocalizedString("Max: %@", comment: "DashSpend"), fiatFormatter.string(for: maximumAmount) ?? "0.0" ) }
    var isMixing: Bool { CoinJoinService.shared.mixingState.isInProgress }
    
    init(merchant: ExplorePointOfUse) {
        merchantTitle = merchant.name
        merchantIconUrl = merchant.logoLocation ?? ""
        savingsFraction = Decimal(merchant.merchant?.toSavingsFraction() ?? 0.0)
        
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
    
    func purchaseGiftCardAndPay() async throws -> Data {
        isProcessingPayment = true
        defer { isProcessingPayment = false }
        
        let response = try await purchaseGiftCardAPI()
        
        // Process the payment using the payment URL
        guard let paymentUrlString = response.paymentUrls.first?.value else {
            throw CTXSpendError.paymentProcessingError("No payment URL received")
        }
        
        let transaction = try await sendCoinsService.processGiftCardPayment(with: paymentUrlString)
        
        // Payment successful - save gift card information
        DSLogger.log("Payment transaction completed: \(transaction.txHashHexString)")
        saveGiftCardDummy(txHashData: transaction.txHashData, giftCardId: response.paymentId)
        
        return transaction.txHashData
    }
    
    func isUserSignedIn() -> Bool {
        return ctxSpendService.isUserSignedIn
    }
    
    func contactCTXSupport() {
        let subject = "CTX Issue: Spending Limit Problem"
        
        var body = "Merchant details\n"
        body += "name: \(merchantTitle)\n"
        body += "id: \(merchantId)\n"
        body += "min: \(minimumAmount)\n"
        body += "max: \(maximumAmount)\n"
        body += "discount: \(savingsFraction)\n"
//        body += "denominations type: \(denominationsType)\n" TODO: fixed denoms
//        body += "denominations: \(denominations)\n"
        body += "\n"

        body += "Purchase Details\n"
        body += "amount: \(input)\n"
        body += "\n"
        
        // Add device information
        body += "Platform: iOS\n"
        body += "App version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")\n"
        
        if let emailURL = URL(string: "mailto:\(CTXConstants.supportEmail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(emailURL)
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
            savingsFraction = Decimal(merchantInfo.savingsPercentage) / Decimal(10000)
            
            if merchantInfo.denominationType == .Range {
                minimumAmount = Decimal(merchantInfo.minimumCardPurchase)
                maximumAmount = Decimal(merchantInfo.maximumCardPurchase)
            }
            
            checkAmountForErrors()
        } catch {
            DSLogger.log("Failed to get merchant info: \(error)")
        }
    }
    
    private func purchaseGiftCardAPI() async throws -> GiftCardResponse {
        guard !merchantId.isEmpty, ctxSpendService.isUserSignedIn else {
            DSLogger.log("Purchase gift card failed: User not signed in or merchant ID is empty")
            throw CTXSpendError.unauthorized
        }
        
        DSLogger.log("Attempting to purchase gift card for merchant \(merchantId) with amount \(amount)")
        
        let fiatAmountString = String(format: "%.2f", Double(truncating: amount as NSDecimalNumber))
        DSLogger.log("Making API request to purchase gift card: merchantId=\(merchantId), amount=\(fiatAmountString)USD")
        
        return try await ctxSpendService.purchaseGiftCard(
            merchantId: merchantId,
            fiatAmount: fiatAmountString,
            fiatCurrency: "USD",
            cryptoCurrency: "DASH"
        )
    }
    
    private func saveGiftCardDummy(txHashData: Data, giftCardId: String) {
        DSLogger.log("Gift card saved - txId: \(txHashData.hexEncodedString()), giftCardId: \(giftCardId)")
        
        let giftCard = GiftCard(
            txId: txHashData,
            merchantName: merchantTitle,
            merchantUrl: nil, // TODO: get merchant URL from API
            price: amount,
            note: giftCardId // Store payment ID in note field temporarily
        )
        
        Task {
            await GiftCardsDAOImpl.shared.create(dto: giftCard)
        }
    }
}
