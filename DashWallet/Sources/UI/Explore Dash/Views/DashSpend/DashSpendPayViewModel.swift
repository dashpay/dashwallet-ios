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
    private var sourceId: String?
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
    /// Maps each denomination to its specific discount percentage (after service fee)
    private var denominationDiscounts: [Int: Decimal] = [:]
    @Published var selectedDenomination: Int? = nil {
        didSet {
            if let denom = selectedDenomination {
                input = String(denom)
                // Update savingsFraction to use the discount specific to this denomination
                if let specificDiscount = denominationDiscounts[denom] {
                    savingsFraction = specificDiscount
                }
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

        let discountPercent = NSDecimalNumber(decimal: savingsFraction * 100).doubleValue
        let discountText = PercentageFormatter.format(percent: discountPercent, includePercent: false)

        return String(format:
            NSLocalizedString("You are buying a %@ gift card for %@ (%@%% discount)", comment: "DashSpend"),
            originalPrice, formattedDiscountedPrice, discountText)
    }
    var showCost: Bool {
        if error != nil { return false }

        // For fixed denominations, show cost when a valid denomination is selected
        if isFixedDenomination {
            return selectedDenomination != nil && selectedDenomination != 0
        }

        // For flexible amounts, show cost when within limits
        return amount >= minimumAmount && amount <= maximumAmount && hasValidLimits
    }
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
        if let merchantId = merchant.merchant?.merchantId {
            self.merchantId = merchantId
        }

        // Get the sourceId and denomination type for the current provider from giftCardProviders
        var providerIsFixed = false  // Local variable to store denomination type
        var providerSavingsFraction = Decimal(merchant.merchant?.toSavingsFraction() ?? 0.0)

        if let giftCardProviders = merchant.merchant?.giftCardProviders {
            for providerInfo in giftCardProviders {
                if (provider == .ctx && providerInfo.provider == .ctx) ||
                   (provider == .piggyCards && providerInfo.provider == .piggyCards) {
                    // Set sourceId
                    self.sourceId = providerInfo.sourceId
                    // Store provider-specific denomination type
                    providerIsFixed = providerInfo.denominationsType == DenominationType.Fixed.rawValue
                    // Update savings fraction from the provider-specific discount
                    providerSavingsFraction = Decimal(providerInfo.savingsPercentage) / Decimal(10000)
                    break
                }
            }
        } else {
        }

        // Store initial savingsFraction
        savingsFraction = providerSavingsFraction

        // Only use merchant-level denominations as fallback if we don't have provider-specific info
        if merchant.merchant?.denominations != nil {
            self.denominations = merchant.merchant?.denominations.compactMap { Int($0) } ?? []
        }

        super.init()

        // Set the denomination type after super.init()
        self.isFixedDenomination = providerIsFixed

        // Log debug info after super.init()

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

        let transaction: DSTransaction
        let giftCardId: String

        switch provider {
        case .ctx:
            let response = try await purchaseGiftCardAPI()

            // Process the payment using the payment URL
            guard let url = response.paymentUrls?.first?.value else {
                throw DashSpendError.paymentProcessingError("No payment URL received")
            }

            giftCardId = response.paymentId

            // CTX uses BIP70 payment request URLs
            transaction = try await sendCoinsService.payWithDashUrl(url: url)

        case .piggyCards:

            // PiggyCards uses orderGiftCard which returns GiftCardInfo
            guard let piggyCardsRepo = repository[provider] as? PiggyCardsRepository else {
                throw DashSpendError.unauthorized
            }

            let fiatAmountDouble = Double(truncating: amount as NSDecimalNumber)

            let giftCardInfo = try await piggyCardsRepo.orderGiftCard(
                merchantId: merchantId,
                fiatAmount: fiatAmountDouble,
                fiatCurrency: "USD",
                cryptoCurrency: "DASH"
            )


            // PiggyCards returns a simple address and amount, not a BIP70 URL
            // Convert DASH amount to satoshis (1 DASH = 100,000,000 satoshis)
            let dashAmountInSatoshis = UInt64(giftCardInfo.amount * 100_000_000)

            // Use sendCoins directly with address and amount
            // This will properly trigger PIN authorization

            transaction = try await sendCoinsService.sendCoins(
                address: giftCardInfo.paymentAddress,
                amount: dashAmountInSatoshis
            )


            giftCardId = giftCardInfo.orderId
        }

        // Payment successful - save gift card information
        markGiftCardTransaction(txId: transaction.txHashData, provider: provider.displayName)
        customIconProvider.updateIcon(txId: transaction.txHashData, iconUrl: merchantIconUrl)
        saveGiftCardDummy(txHashData: transaction.txHashData, giftCardId: giftCardId)

        return transaction.txHashData
    }

    var contactSupportButtonText: String {
        String(format: NSLocalizedString("Contact %@ Support", comment: "DashSpend"), provider.displayName)
    }

    func contactSupport() {
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
            return
        }


        // Set loading state
        await MainActor.run {
            self.isLoading = true
        }

        do {
            switch provider {
            case .ctx:
                let merchantInfo = try await ctxSpendRepository.getMerchant(merchantId: merchantId)

                // Update merchant details from API (API is source of truth when signed in)
                // Use discount property for backwards compatibility (handles both savingsPercentage and userDiscount)
                savingsFraction = Decimal(merchantInfo.discount) / Decimal(10000)

                // Set denomination type from API response
                if merchantInfo.denominationType == .Range {
                    isFixedDenomination = false
                    minimumAmount = Decimal(merchantInfo.minimumCardPurchase)
                    maximumAmount = Decimal(merchantInfo.maximumCardPurchase)
                    // Clear fixed denomination values
                    denominations = []
                } else {
                    isFixedDenomination = true
                    denominations = merchantInfo.denominations.compactMap { Int($0) }
                    // Clear flexible amount values
                    minimumAmount = 0
                    maximumAmount = 0
                }

            case .piggyCards:
                // For PiggyCards, we need to fetch gift cards for this merchant using the sourceId from the database
                guard let piggyCardsRepo = repository[provider] as? PiggyCardsRepository else {
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }

                guard let sourceId = sourceId else {
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }

                let giftCards = try await piggyCardsRepo.getGiftCards(
                    country: "US",
                    sourceId: sourceId,
                    merchantId: merchantId
                )


                // Aggregate denominations from ALL gift cards (like Android does)
                // Each fixed denomination card is a separate entry in the API response
                var allFixedDenominations: Set<Int> = []
                var denomDiscounts: [Int: Decimal] = [:]  // Track discount per denomination
                var hasRangeCard = false
                var rangeMin: Double = 0
                var rangeMax: Double = 0
                var rangeDiscount: Double = 0
                let serviceFee = Decimal(PiggyCardsConstants.serviceFeePercent)

                for card in giftCards {
                    let normalizedPriceType = card.priceType
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()

                    // Calculate discount after service fee for this card
                    let cardDiscount = max(0, Decimal(card.discountPercentage) - serviceFee) / 100

                    if normalizedPriceType == PiggyCardsPriceType.fixed.rawValue {
                        // Fixed type: collect the denomination and its specific discount
                        if let fixedValue = Int(card.denomination.trimmingCharacters(in: .whitespaces)) {
                            allFixedDenominations.insert(fixedValue)
                            denomDiscounts[fixedValue] = cardDiscount
                        }
                    } else if normalizedPriceType == PiggyCardsPriceType.option.rawValue {
                        // Option type: parse comma-separated values (all share same discount)
                        let denominationValues = card.denomination.split(separator: ",")
                            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                        for value in denominationValues {
                            allFixedDenominations.insert(value)
                            denomDiscounts[value] = cardDiscount
                        }
                    } else if normalizedPriceType == PiggyCardsPriceType.range.rawValue {
                        // Range type: track min/max for flexible amounts
                        hasRangeCard = true
                        if rangeMin == 0 || card.minDenomination < rangeMin {
                            rangeMin = card.minDenomination
                        }
                        if card.maxDenomination > rangeMax {
                            rangeMax = card.maxDenomination
                        }
                        // Track discount for range cards
                        if card.discountPercentage > rangeDiscount {
                            rangeDiscount = card.discountPercentage
                        }
                    }
                }

                // Store denomination-specific discounts
                denominationDiscounts = denomDiscounts

                // Determine UI mode: fixed denominations take precedence if available
                if !allFixedDenominations.isEmpty {
                    // Show fixed denomination buttons
                    isFixedDenomination = true
                    denominations = allFixedDenominations.sorted()
                    // Clear flexible amount values
                    minimumAmount = 0
                    maximumAmount = 0
                    // Set initial savingsFraction to 0 until user selects a denomination
                    savingsFraction = 0
                } else if hasRangeCard {
                    // Only range cards available - show keyboard input
                    isFixedDenomination = false
                    minimumAmount = Decimal(rangeMin > 0 ? rangeMin : 10)
                    maximumAmount = Decimal(rangeMax > 0 ? rangeMax : 500)
                    denominations = []
                    // Apply range card discount
                    savingsFraction = max(0, Decimal(rangeDiscount) - serviceFee) / 100
                } else if let firstCard = giftCards.first {
                    // Fallback: use first card's denomination
                    if let fixedValue = Int(firstCard.denomination.trimmingCharacters(in: .whitespaces)) {
                        isFixedDenomination = true
                        denominations = [fixedValue]
                        minimumAmount = 0
                        maximumAmount = 0
                        let cardDiscount = max(0, Decimal(firstCard.discountPercentage) - serviceFee) / 100
                        denominationDiscounts[fixedValue] = cardDiscount
                        savingsFraction = cardDiscount
                    }
                }
            }


            // Force UI update on main thread
            await MainActor.run {
                self.isLoading = false
                self.objectWillChange.send()
                self.checkAmountForErrors()
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func purchaseGiftCardAPI() async throws -> GiftCardResponse {
        guard !merchantId.isEmpty, repository[provider]?.isUserSignedIn == true else {
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
            note: giftCardId, // Store payment ID in note field temporarily
            provider: provider.displayName  // Store provider (CTX or PiggyCards)
        )

        Task {
            await GiftCardsDAOImpl.shared.create(dto: giftCard)
        }
    }
    
    private func markGiftCardTransaction(txId: Data, provider providerName: String) {
        var txMetadata = TransactionMetadata(txHash: txId)
        txMetadata.taxCategory = TxMetadataTaxCategory.expense

        // Set the service name based on the provider
        switch provider {
        case .ctx:
            txMetadata.service = ServiceName.ctxSpend.rawValue
        #if PIGGYCARDS_ENABLED
        case .piggyCards:
            txMetadata.service = ServiceName.piggyCards.rawValue
        #endif
        }

        txMetadataDao.update(dto: txMetadata)
    }
    
    private func handleNetworkStatusChange(_ status: NetworkStatus) {
        // Re-check errors when network status changes
        checkAmountForErrors()
    }
}
