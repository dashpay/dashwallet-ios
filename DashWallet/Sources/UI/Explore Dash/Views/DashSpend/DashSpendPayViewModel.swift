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

private struct GiftCardOrderMetadata: Codable {
    let orderId: String
    let cardAmounts: [String]?
}

@MainActor
class DashSpendPayViewModel: NSObject, ObservableObject, NetworkReachabilityHandling {
    private var cancellableBag = Set<AnyCancellable>()
    private let fiatFormatter = NumberFormatter.fiatFormatter(currencyCode: defaultCurrency)
    private let ctxSpendRepository = CTXSpendRepository.shared
    private let provider: GiftCardProvider
    private lazy var customIconProvider = CustomIconMetadataProvider.shared
    private lazy var txMetadataDao = TransactionMetadataDAOImpl.shared
    private lazy var sendCoinsService = SendCoinsService()
    
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
    private let providerConfiguredIsFixed: Bool?
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
    /// Maps each denomination to its available inventory count
    @Published var denominationInventory: [Int: Int] = [:]
    /// Maps each denomination to its specific discount percentage (after service fee)
    private var denominationDiscounts: [Int: Decimal] = [:]
    @Published private var basketSavingsFraction: Decimal? = nil
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
    var displaySavingsFraction: Decimal {
        basketSavingsFraction ?? savingsFraction
    }

    func updateTotalAmount(_ total: Decimal, quantities: [Decimal: Int]? = nil) {
        amount = total
        basketSavingsFraction = basketDiscountFraction(from: quantities)
        checkAmountForErrors()
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
        let savingsToDisplay = displaySavingsFraction
        let discountedPrice = amount * (1 - savingsToDisplay)
        let formattedDiscountedPrice = fiatFormatter.string(for: discountedPrice) ?? "0.00"

        let discountPercent = NSDecimalNumber(decimal: savingsToDisplay * 100).doubleValue
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

    var supportsMultipleMode: Bool {
        #if PIGGYCARDS_ENABLED
        return provider == .piggyCards
        #else
        return false
        #endif
    }

    var maxOrderLimitMessage: String? {
        #if PIGGYCARDS_ENABLED
        if provider == .piggyCards {
            let formatted = fiatFormatter.string(for: PiggyCardsConstants.maxOrderAmount) ?? "$2,500"
            return String(format: NSLocalizedString("You can buy up to %@ in gift cards per order", comment: "DashSpend"), formatted)
        }
        #endif
        return nil
    }
    
    init(merchant: ExplorePointOfUse, provider: GiftCardProvider = .ctx) {
        self.provider = provider

        merchantTitle = merchant.name
        merchantIconUrl = merchant.logoLocation ?? ""
        merchantUrl = merchant.website
        if let merchantId = merchant.merchant?.merchantId {
            self.merchantId = merchantId
        }

        // Get the sourceId and denomination type for the current provider from giftCardProviders
        var providerIsFixed: Bool? = nil  // Local variable to store denomination type
        var providerSavingsFraction = Decimal(merchant.merchant?.toSavingsFraction() ?? 0.0)

        if let giftCardProviders = merchant.merchant?.giftCardProviders {
            for providerInfo in giftCardProviders {
                var isMatchingProvider = false
                if provider == .ctx && providerInfo.provider == .ctx {
                    isMatchingProvider = true
                }
                #if PIGGYCARDS_ENABLED
                if provider == .piggyCards && providerInfo.provider == .piggyCards {
                    isMatchingProvider = true
                }
                #endif

                if isMatchingProvider {
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
        // Seed initial UI state from local merchant data while remote details are loading.
        if let merchantData = merchant.merchant {
            let localDenominations = merchantData.denominations
            let localDenominationType = merchantData.denominationsType

            if providerIsFixed == true {
                self.denominations = localDenominations
            } else if localDenominationType == DenominationType.Range.rawValue, localDenominations.count >= 2 {
                self.minimumAmount = Decimal(localDenominations[0])
                self.maximumAmount = Decimal(localDenominations[1])
            }
        }
        self.providerConfiguredIsFixed = providerIsFixed

        super.init()

        // Set the denomination type after super.init()
        self.isFixedDenomination = providerIsFixed ?? false

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
            .receive(on: DispatchQueue.main)
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
    
    func purchaseGiftCardAndPay(selectedQuantities: [Decimal: Int] = [:]) async throws -> Data {
        isProcessingPayment = true
        defer { isProcessingPayment = false }

        let transaction: DSTransaction
        let giftCardNote: String

        switch provider {
        case .ctx:
            let response = try await purchaseGiftCardAPI()

            // Process the payment using the payment URL
            guard let url = response.paymentUrls?.first?.value else {
                throw DashSpendError.paymentProcessingError("No payment URL received")
            }

            giftCardNote = response.paymentId

            // CTX uses BIP70 payment request URLs
            transaction = try await sendCoinsService.payWithDashUrl(url: url)

        #if PIGGYCARDS_ENABLED
        case .piggyCards:

            // PiggyCards uses orderGiftCard which returns GiftCardInfo
            guard let piggyCardsRepo = repository[provider] as? PiggyCardsRepository else {
                throw DashSpendError.unauthorized
            }

            let lineItems = buildPiggyOrderLineItems(selectedQuantities: selectedQuantities)
            let giftCardInfo = try await piggyCardsRepo.orderGiftCards(
                merchantId: merchantId,
                lineItems: lineItems,
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


            giftCardNote = buildPiggyOrderNote(orderId: giftCardInfo.orderId, selectedQuantities: selectedQuantities)
        #endif
        }

        // Payment successful - save gift card information
        markGiftCardTransaction(txId: transaction.txHashData, provider: provider.displayName)
        customIconProvider.updateIcon(txId: transaction.txHashData, iconUrl: merchantIconUrl)
        saveGiftCardDummy(txHashData: transaction.txHashData, giftCardNote: giftCardNote)

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
    
    var isNetworkAvailable: Bool { networkStatus == .online }

    func checkAmountForErrors() {
        guard isNetworkAvailable else {
            error = SendAmountError.networkUnavailable
            return
        }
        
        guard DWGlobalOptions.sharedInstance().isResyncingWallet == false ||
            DWEnvironment.sharedInstance().currentChainManager.syncPhase == .synced
        else {
            error = SendAmountError.syncingChain
            return
        }

        #if PIGGYCARDS_ENABLED
        if provider == .piggyCards && amount > 0 {
            guard amount <= PiggyCardsConstants.maxOrderAmount else {
                error = DashSpendError.purchaseLimitExceeded
                return
            }
        }
        #endif

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
        guard !merchantId.isEmpty else { return }

        // CTX getMerchant is a public endpoint — fetch limits even when not signed in.
        // PiggyCards requires authentication, so skip if not signed in.
        let requiresAuth: Bool
        #if PIGGYCARDS_ENABLED
        requiresAuth = provider == .piggyCards
        #else
        requiresAuth = false
        #endif
        if requiresAuth && repository[provider]?.isUserSignedIn != true { return }


        // Set loading state
        await MainActor.run {
            self.isLoading = true
        }

        do {
            switch provider {
            case .ctx:
                let merchantInfo = try await ctxSpendRepository.getMerchant(merchantId: merchantId)

                let newSavings = Decimal(merchantInfo.discount) / Decimal(10000)
                let isRange = merchantInfo.denominationType == .Range
                let apiMin = Decimal(merchantInfo.minimumCardPurchase)
                let apiMax = Decimal(merchantInfo.maximumCardPurchase)
                let newMin = isRange ? (apiMin > 0 ? apiMin : minimumAmount) : Decimal(0)
                let newMax = isRange ? (apiMax > 0 ? apiMax : maximumAmount) : Decimal(0)
                let newDenominations = isRange ? [] : merchantInfo.denominations.compactMap { parseWholeDollarDenomination($0) }

                await MainActor.run {
                    self.savingsFraction = newSavings
                    self.isFixedDenomination = !isRange
                    self.minimumAmount = newMin
                    self.maximumAmount = newMax
                    self.denominations = newDenominations
                    self.basketSavingsFraction = nil

                    if isRange {
                        self.selectedDenomination = nil
                    } else if let selected = self.selectedDenomination, !newDenominations.contains(selected) {
                        self.selectedDenomination = nil
                    }
                }

            #if PIGGYCARDS_ENABLED
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
                var denomInventory: [Int: Int] = [:]      // Track inventory per denomination
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
                        if let fixedValue = parseWholeDollarDenomination(card.denomination) {
                            allFixedDenominations.insert(fixedValue)
                            denomDiscounts[fixedValue] = cardDiscount
                            denomInventory[fixedValue] = card.quantity
                        }
                    } else if normalizedPriceType == PiggyCardsPriceType.option.rawValue {
                        // Option type: parse comma-separated values (all share same discount)
                        let denominationValues = card.denomination.split(separator: ",")
                            .compactMap { parseWholeDollarDenomination(String($0)) }
                        for value in denominationValues {
                            allFixedDenominations.insert(value)
                            denomDiscounts[value] = cardDiscount
                            denomInventory[value] = card.quantity
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

                // Compute final state on background, then publish on MainActor.
                // Signed-in API response is the source of truth for PiggyCards denomination mode.
                var finalFixed = false
                var finalMin = Decimal(0)
                var finalMax = Decimal(0)
                var finalDenominations: [Int] = []
                var finalSavings = Decimal(0)

                let hasFixedCards = !allFixedDenominations.isEmpty
                let preferredFixedInMixedSet = providerConfiguredIsFixed

                if hasRangeCard && hasFixedCards {
                    // Some sources (e.g. test data) can return mixed types for the same sourceId.
                    // In that case, honor merchant/provider configuration from the local database.
                    if preferredFixedInMixedSet == true {
                        finalFixed = true
                        finalDenominations = allFixedDenominations.sorted()
                        finalSavings = denomDiscounts.values.max() ?? 0
                    } else {
                        finalFixed = false
                        finalMin = Decimal(rangeMin > 0 ? rangeMin : 10)
                        finalMax = Decimal(rangeMax > 0 ? rangeMax : 500)
                        finalSavings = max(0, Decimal(rangeDiscount) - serviceFee) / 100
                    }
                } else if hasRangeCard {
                    finalFixed = false
                    finalMin = Decimal(rangeMin > 0 ? rangeMin : 10)
                    finalMax = Decimal(rangeMax > 0 ? rangeMax : 500)
                    finalSavings = max(0, Decimal(rangeDiscount) - serviceFee) / 100
                } else if hasFixedCards {
                    finalFixed = true
                    finalDenominations = allFixedDenominations.sorted()
                    finalSavings = denomDiscounts.values.max() ?? 0
                } else if let firstCard = giftCards.first,
                          let fixedValue = parseWholeDollarDenomination(firstCard.denomination) {
                    finalFixed = true
                    finalDenominations = [fixedValue]
                    finalSavings = max(0, Decimal(firstCard.discountPercentage) - serviceFee) / 100
                }

                await MainActor.run {
                    DSLogger.log(
                        "DashSpend: PiggyCards mode=\(finalFixed ? "fixed" : "flexible"), " +
                        "range=[\(finalMin), \(finalMax)], fixedCount=\(finalDenominations.count)"
                    )
                    self.denominationDiscounts = finalFixed ? denomDiscounts : [:]
                    self.denominationInventory = finalFixed ? denomInventory : [:]
                    self.isFixedDenomination = finalFixed
                    self.minimumAmount = finalMin
                    self.maximumAmount = finalMax
                    self.denominations = finalDenominations
                    self.savingsFraction = finalSavings
                    self.basketSavingsFraction = nil
                    if finalFixed {
                        if let selected = self.selectedDenomination, !finalDenominations.contains(selected) {
                            self.selectedDenomination = nil
                        }
                    } else {
                        self.selectedDenomination = nil
                    }
                }
            #endif
            }


            // Force UI update on main thread
            await MainActor.run {
                self.isLoading = false
                self.objectWillChange.send()
                self.checkAmountForErrors()
            }
        } catch {
            DSLogger.log("DashSpend updateMerchantInfo failed for provider \(provider.displayName): \(error.localizedDescription)")

            await MainActor.run {
                self.isLoading = false
                if let dashError = error as? DashSpendError {
                    self.error = dashError
                } else {
                    self.error = DashSpendError.customError(
                        NSLocalizedString("Unable to load merchant details. Please try again.", comment: "DashSpend")
                    )
                }
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
    
    private func saveGiftCardDummy(txHashData: Data, giftCardNote: String) {
        DSLogger.log("Gift card saved - txId: \(txHashData.hexEncodedString())")

        let giftCard = GiftCard(
            txId: txHashData,
            merchantName: merchantTitle,
            merchantUrl: merchantUrl,
            price: amount,
            note: giftCardNote, // Store payment/order metadata in note field temporarily
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

    private func buildPiggyOrderLineItems(selectedQuantities: [Decimal: Int]) -> [PiggyCardsRepository.OrderLineItem] {
        let positiveSelections = selectedQuantities
            .filter { $0.value > 0 }
            .map { PiggyCardsRepository.OrderLineItem(denomination: decimalToDouble($0.key), quantity: $0.value) }

        if !positiveSelections.isEmpty {
            return positiveSelections
        }

        return [PiggyCardsRepository.OrderLineItem(denomination: decimalToDouble(amount), quantity: 1)]
    }

    private func buildPiggyOrderNote(orderId: String, selectedQuantities: [Decimal: Int]) -> String {
        var expandedAmounts = selectedQuantities
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .flatMap { entry in Array(repeating: entry.key.description, count: entry.value) }

        if expandedAmounts.isEmpty {
            expandedAmounts = [amount.description]
        }

        let metadata = GiftCardOrderMetadata(
            orderId: orderId,
            cardAmounts: expandedAmounts
        )

        guard
            let encoded = try? JSONEncoder().encode(metadata),
            let serialized = String(data: encoded, encoding: .utf8)
        else {
            return orderId
        }

        return serialized
    }

    private func decimalToDouble(_ value: Decimal) -> Double {
        Double(truncating: value as NSDecimalNumber)
    }

    private func basketDiscountFraction(from quantities: [Decimal: Int]?) -> Decimal? {
        #if PIGGYCARDS_ENABLED
        guard
            provider == .piggyCards,
            isFixedDenomination,
            let quantities,
            !quantities.isEmpty
        else { return nil }

        var originalTotal = Decimal(0)
        var discountedTotal = Decimal(0)

        for (denomination, quantity) in quantities where quantity > 0 {
            let discount = discountForDenomination(denomination)
            let lineOriginal = denomination * Decimal(quantity)
            let lineDiscounted = lineOriginal * (1 - discount)
            originalTotal += lineOriginal
            discountedTotal += lineDiscounted
        }

        guard originalTotal > 0 else { return nil }
        return 1 - (discountedTotal / originalTotal)
        #else
        return nil
        #endif
    }

    private func discountForDenomination(_ denomination: Decimal) -> Decimal {
        guard let key = wholeDollarDenominationKey(from: denomination),
              let mappedDiscount = denominationDiscounts[key] else {
            return savingsFraction
        }

        return mappedDiscount
    }

    private func wholeDollarDenominationKey(from denomination: Decimal) -> Int? {
        let asDouble = NSDecimalNumber(decimal: denomination).doubleValue
        let rounded = Int(asDouble.rounded())
        guard abs(asDouble - Double(rounded)) < 0.0001 else { return nil }
        return rounded
    }

    private func parseWholeDollarDenomination(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Accept values like "5", "5.0", "5.00".
        if let intValue = Int(trimmed) {
            return intValue
        }

        if let decimalValue = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) {
            let asDouble = NSDecimalNumber(decimal: decimalValue).doubleValue
            let rounded = Int(asDouble.rounded())
            if abs(asDouble - Double(rounded)) < 0.0001 {
                return rounded
            }
        }

        return nil
    }
}
