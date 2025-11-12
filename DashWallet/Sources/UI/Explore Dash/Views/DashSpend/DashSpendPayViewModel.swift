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
class DashSpendPayViewModel: NSObject, ObservableObject, NetworkReachabilityHandling {
    private var cancellableBag = Set<AnyCancellable>()
    private let fiatFormatter = NumberFormatter.fiatFormatter(currencyCode: defaultCurrency)
    private let ctxSpendRepository = CTXSpendRepository.shared
    private let provider: GiftCardProvider
    private let customIconProvider = CustomIconMetadataProvider.shared
    private let txMetadataDao = TransactionMetadataDAOImpl.shared
    private let sendCoinsService = SendCoinsService()
    
    private let repository: [GiftCardProvider: any DashSpendRepository] = {
        var dict: [GiftCardProvider: any DashSpendRepository] = [
            .ctx: CTXSpendRepository.shared
        ]
        #if PIGGYCARDS_ENABLED
        dict[.piggyCards] = PiggyCardsRepository.shared
        #endif
        return dict
    }()
    
    // Network monitoring properties
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!

    private var merchantId: String = ""
    private var merchantUrl: String? = nil
    private(set) var amount: Decimal = 0
    private(set) var savingsFraction: Decimal = 0.0
    @Published private(set) var isLoading = false
    @Published private(set) var isProcessingPayment = false
    @Published private(set) var isUserSignedIn = false
    
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
    @Published var isFixedDenomination: Bool = false
    @Published var denominations: [Int] = []
    @Published var selectedDenomination: Int? = nil {
        didSet {
            if let denom = selectedDenomination {
                input = String(denom)
            } else {
                input = "0"
            }
        }
    }
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
    
    init(merchant: ExplorePointOfUse, provider: GiftCardProvider = .ctx) {
        self.provider = provider
        merchantTitle = merchant.name
        merchantIconUrl = merchant.logoLocation ?? ""
        merchantUrl = merchant.website

        // Store initial savings fraction in a local variable
        var initialSavingsFraction = Decimal(merchant.merchant?.toSavingsFraction() ?? 0.0)

        let merchantIdValue = merchant.merchant?.merchantId ?? ""
        if !merchantIdValue.isEmpty {
            merchantId = merchantIdValue
        }

        // DEBUG: Log initialization data
        DSLogger.log("🔍 DashSpendPayViewModel.init - merchant: \(merchant.name), provider: \(provider)")
        DSLogger.log("🔍 DashSpendPayViewModel.init - merchantId: \(merchantIdValue)")
        DSLogger.log("🔍 DashSpendPayViewModel.init - merchant.denominations from DB: \(merchant.merchant?.denominations ?? [])")
        DSLogger.log("🔍 DashSpendPayViewModel.init - merchant.denominationsType from DB: \(merchant.merchant?.denominationsType ?? "nil")")
        DSLogger.log("🔍 DashSpendPayViewModel.init - giftCardProviders count: \(merchant.merchant?.giftCardProviders.count ?? 0)")

        // Use the denomination type from the selected provider, not from the merchant table
        var providerDenominationType: String? = nil
        if let giftCardProviders = merchant.merchant?.giftCardProviders {
            // Find the provider info for the selected provider
            DSLogger.log("🔍 DashSpendPayViewModel.init - Looking for provider: \(provider) in \(giftCardProviders.count) providers")
            for providerInfo in giftCardProviders {
                let providerName = providerInfo.provider?.displayName ?? "nil"
                DSLogger.log("🔍   Provider: \(providerName), denominationsType: \(providerInfo.denominationsType)")
            }

            if let providerInfo = giftCardProviders.first(where: { $0.provider == provider }) {
                providerDenominationType = providerInfo.denominationsType
                // Update savings fraction from the provider-specific discount
                initialSavingsFraction = Decimal(providerInfo.savingsPercentage) / Decimal(10000)
                DSLogger.log("🔍 DashSpendPayViewModel.init - Found CTX provider info: denominationsType=\(providerInfo.denominationsType), savings=\(providerInfo.savingsPercentage)")
            } else {
                DSLogger.log("🔍 DashSpendPayViewModel.init - CTX provider info NOT found")
            }
        }

        // Fall back to merchant's denominationsType if provider info not found
        let denomType = providerDenominationType ?? merchant.merchant?.denominationsType
        DSLogger.log("🔍 DashSpendPayViewModel.init - Final denomType: \(denomType ?? "nil")")

        // Create local variables to store values before super.init()
        var tempIsFixedDenomination = false
        var tempMinimumAmount: Decimal = 0
        var tempMaximumAmount: Decimal = 0
        var tempDenominations: [Int] = []

        if let denomType = denomType {
            tempIsFixedDenomination = denomType == DenominationType.Fixed.rawValue
            DSLogger.log("🔍 DashSpendPayViewModel.init - isFixedDenomination: \(tempIsFixedDenomination)")

            if denomType == DenominationType.Range.rawValue {
                // For Range type (min-max), set minimum and maximum amounts from denominations
                // Note: denominations array is empty from database, will be populated by API
                let denominationValues = merchant.merchant?.denominations ?? []
                DSLogger.log("🔍 DashSpendPayViewModel.init - Range type with denomination values: \(denominationValues)")
                if denominationValues.count >= 1 {
                    tempMinimumAmount = Decimal(denominationValues[0])
                }
                if denominationValues.count >= 2 {
                    tempMaximumAmount = Decimal(denominationValues[1])
                }
                DSLogger.log("🔍 DashSpendPayViewModel.init - Set min: \(tempMinimumAmount), max: \(tempMaximumAmount)")
            } else if denomType == DenominationType.Fixed.rawValue {
                // For Fixed type, store the denominations array
                // Note: denominations array is empty from database, will be populated by API
                tempDenominations = merchant.merchant?.denominations ?? []
                DSLogger.log("🔍 DashSpendPayViewModel.init - Fixed type with denominations: \(tempDenominations)")
            }
            // If denomType is unknown or empty, leave everything at defaults
        }
        
        super.init()

        // Now assign the computed values to instance properties
        savingsFraction = initialSavingsFraction
        isFixedDenomination = tempIsFixedDenomination
        minimumAmount = tempMinimumAmount
        maximumAmount = tempMaximumAmount
        denominations = tempDenominations

        // Set up network status change handler
        networkStatusDidChange = { [weak self] status in
            self?.handleNetworkStatusChange(status)
        }
    }
    
    func subscribeToUpdates() {
        // Start network monitoring
        startNetworkMonitoring()
        
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in self?.refreshBalance() }
            .store(in: &cancellableBag)
        
        repository[provider]?.isUserSignedInPublisher
            .sink { [weak self] isSignedIn in
                self?.isUserSignedIn = isSignedIn
            }
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

        do {
            let response = try await purchaseGiftCardAPI()

            // Process the payment using the payment URL
            guard let paymentUrls = response.paymentUrls else {
                throw DashSpendError.paymentProcessingError("No payment URLs received")
            }

            guard let paymentUrlString = paymentUrls.first?.value else {
                throw DashSpendError.paymentProcessingError("No payment URL received")
            }

            DSLogger.log("🔍 purchaseGiftCardAndPay - Processing payment URL: \(paymentUrlString)")

            let transaction: DSTransaction
            do {
                transaction = try await sendCoinsService.payWithDashUrl(url: paymentUrlString)
                DSLogger.log("🔍 purchaseGiftCardAndPay - Payment successful, txId: \(transaction.txHashData.hexEncodedString())")
            } catch {
                DSLogger.log("🔍 purchaseGiftCardAndPay - Payment failed: \(error)")
                throw error
            }

            // Payment successful - save gift card information
            markGiftCardTransaction(txId: transaction.txHashData)
            customIconProvider.updateIcon(txId: transaction.txHashData, iconUrl: merchantIconUrl)
            saveGiftCardDummy(txHashData: transaction.txHashData, giftCardId: response.paymentId)

            return transaction.txHashData
        } catch {
            throw error
        }
    }
    
    func contactCTXSupport() {
        let subject = "\(provider.displayName) Issue: Spending Limit Problem"
        
        var body = "Merchant details\n"
        body += "name: \(merchantTitle)\n"
        body += "id: \(merchantId)\n"
        body += "min: \(minimumAmount)\n"
        body += "max: \(maximumAmount)\n"
        body += "discount: \(savingsFraction)\n"
        body += "fixed denomination: \(isFixedDenomination)\n"
        body += "denominations: \(denominations)\n"
        body += "\n"

        body += "Purchase Details\n"
        body += "amount: \(input)\n"
        body += "\n"
        
        // Add device information
        body += "Platform: iOS\n"
        body += "App version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")\n"
        
        if let emailURL = URL(string: "mailto:\(provider.supportEmail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(emailURL)
        }
    }
    
    func unsubscribeFromAll() {
        cancellableBag.removeAll()
        stopNetworkMonitoring()
    }
    
    private func refreshBalance() {
        walletBalance = DWEnvironment.sharedInstance().currentWallet.balance
    }
    
    private func checkAmountForErrors() {
        // Check network availability first
        guard networkStatus == .online else {
            error = SendAmountError.networkUnavailable
            return
        }
        
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
        guard !merchantId.isEmpty, repository[provider]?.isUserSignedIn == true else {
            DSLogger.log("🔍 updateMerchantInfo - Skipped: merchantId=\(merchantId), isSignedIn=\(repository[provider]?.isUserSignedIn ?? false)")
            return
        }

        DSLogger.log("🔍 updateMerchantInfo - Starting for merchantId: \(merchantId)")

        do {
            let merchantInfo = try await ctxSpendRepository.getMerchant(merchantId: merchantId)

            DSLogger.log("🔍 updateMerchantInfo - API Response received:")
            DSLogger.log("🔍   denominationsType: \(merchantInfo.denominationsType)")
            DSLogger.log("🔍   denominations (raw): \(merchantInfo.denominations)")
            DSLogger.log("🔍   denominationType enum: \(merchantInfo.denominationType)")
            DSLogger.log("🔍   minimumCardPurchase: \(merchantInfo.minimumCardPurchase)")
            DSLogger.log("🔍   maximumCardPurchase: \(merchantInfo.maximumCardPurchase)")
            DSLogger.log("🔍   discount: \(merchantInfo.discount)")

            // Update merchant details
            // Use the discount property which handles both savingsPercentage and userDiscount
            savingsFraction = Decimal(merchantInfo.discount) / Decimal(10000)

            if merchantInfo.denominationType == .Range {
                DSLogger.log("🔍 updateMerchantInfo - Setting Range type values")
                isFixedDenomination = false
                minimumAmount = Decimal(merchantInfo.minimumCardPurchase)
                maximumAmount = Decimal(merchantInfo.maximumCardPurchase)
                DSLogger.log("🔍 updateMerchantInfo - Updated min: \(minimumAmount), max: \(maximumAmount)")
            } else {
                DSLogger.log("🔍 updateMerchantInfo - Setting Fixed type values")
                isFixedDenomination = true
                denominations = merchantInfo.denominations.compactMap { Int($0) }
                DSLogger.log("🔍 updateMerchantInfo - Updated denominations: \(denominations)")
            }

            checkAmountForErrors()
            DSLogger.log("🔍 updateMerchantInfo - Update completed successfully")
        } catch {
            DSLogger.log("🔍 updateMerchantInfo - Failed to get merchant info: \(error)")
        }
    }
    
    private func purchaseGiftCardAPI() async throws -> GiftCardResponse {
        guard !merchantId.isEmpty, repository[provider]?.isUserSignedIn == true else {
            DSLogger.log("Purchase gift card failed: User not signed in or merchant ID is empty")
            throw DashSpendError.unauthorized
        }

        // Use locale-invariant formatter to ensure consistent decimal formatting
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false

        // Round to 2 decimal places without converting to Double
        let roundedAmount = NSDecimalNumber(decimal: amount)
        let fiatAmountString = formatter.string(from: roundedAmount) ?? "0.00"

        DSLogger.log("Attempting to purchase gift card for merchant \(merchantId) with amount \(amount)")

        do {
            let response = try await ctxSpendRepository.purchaseGiftCard(
                merchantId: merchantId,
                fiatAmount: fiatAmountString,
                fiatCurrency: "USD",
                cryptoCurrency: "DASH"
            )
            return response
        } catch {
            throw error
        }
    }
    
    private func saveGiftCardDummy(txHashData: Data, giftCardId: String) {
        DSLogger.log("Gift card saved - txId: \(txHashData.hexEncodedString()), giftCardId: \(giftCardId)")
        
        let giftCard = GiftCard(
            txId: txHashData,
            merchantName: merchantTitle,
            merchantUrl: merchantUrl,
            price: amount,
            note: giftCardId // Store payment ID in note field temporarily
        )
        
        Task {
            await GiftCardsDAOImpl.shared.create(dto: giftCard)
        }
    }
    
    private func markGiftCardTransaction(txId: Data) {
        var txMetadata = TransactionMetadata(txHash: txId)
        txMetadata.taxCategory = TxMetadataTaxCategory.expense
        txMetadata.service = ServiceName.ctxSpend.rawValue
        txMetadataDao.update(dto: txMetadata)
    }
    
    private func handleNetworkStatusChange(_ status: NetworkStatus) {
        // Re-check errors when network status changes
        checkAmountForErrors()
    }
}
