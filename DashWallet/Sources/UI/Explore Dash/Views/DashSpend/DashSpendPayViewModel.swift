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
#if canImport(UIKit)
import UIKit
#endif

private struct GiftCardOrderMetadata: Codable {
    let orderId: String
    let cardAmounts: [String]?
}

/// What the Confirm sheet showed, captured when Pay is tapped. The purchase uses these
/// values, not the view model's current state, which a merchant refresh can change while the
/// sheet is open.
struct GiftCardPurchaseSnapshot: Equatable {
    /// The card value.
    let price: Decimal
    /// The currency `price` is in: the card's.
    let currency: String
    /// The discount fraction.
    let discount: Decimal
    /// Cards per denomination for a multi-card order; empty for a single card.
    let quantities: [Decimal: Int]
    /// The price the buyer pays, in fiat and in Dash at the wallet's rate.
    let approval: GiftCardPaymentGuard.Approval
}

/// The purchase sheet's content.
enum GiftCardPurchaseSheet: Equatable {
    /// The buyer is reading the price.
    case confirm(GiftCardPurchaseSnapshot)
    /// The buyer confirmed; the provider has not answered yet.
    case waitingForProvider(GiftCardPurchaseSnapshot)
    /// The provider asks for more Dash than the buyer confirmed.
    case priceUpdated(GiftCardPaymentGuard.PriceChange)
}

@MainActor
class DashSpendPayViewModel: NSObject, ObservableObject, NetworkReachabilityHandling {
    private var cancellableBag = Set<AnyCancellable>()
    private let provider: GiftCardProvider
    private let dependencies: Dependencies
    private let exchangeRate: (String) -> GiftCardPaymentGuard.ExchangeRate
    private let ratesAreFetching: () -> Bool
    private let now: () -> Date

    /// What a purchase goes through: the provider repositories, the send service and the
    /// stores the purchase is written to.
    struct Dependencies {
        var ctx: any CTXGiftCardOrdering
        #if PIGGYCARDS_ENABLED
        var piggyCards: any PiggyCardsGiftCardOrdering
        #endif
        var payments: any GiftCardPaying
        var purchases: any GiftCardPurchaseRecording

        /// The app's shared repositories, a send service of its own and the app's stores.
        @MainActor
        static func live() -> Dependencies {
            #if PIGGYCARDS_ENABLED
            return Dependencies(ctx: CTXSpendRepository.shared, piggyCards: PiggyCardsRepository.shared,
                                payments: SendCoinsService(), purchases: GiftCardPurchaseStore())
            #else
            return Dependencies(ctx: CTXSpendRepository.shared,
                                payments: SendCoinsService(), purchases: GiftCardPurchaseStore())
            #endif
        }
    }

    /// The sign-in state of the provider this screen buys from.
    private var session: any GiftCardProviderSession {
        switch provider {
        case .ctx:
            return dependencies.ctx
        #if PIGGYCARDS_ENABLED
        case .piggyCards:
            return dependencies.piggyCards
        #endif
        }
    }

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
    /// The purchase sheet to show; nil when there is none.
    @Published private(set) var purchaseSheet: GiftCardPurchaseSheet?
    /// Resumed with the buyer's answer to a price change.
    private var priceDecision: CheckedContinuation<Bool, Never>?
    /// Resumed once the purchase sheet has left the screen.
    private var sheetDismissal: CheckedContinuation<Void, Never>?
    /// The longest the purchase waits for the sheet to report that it left the screen.
    var sheetDismissalWait: TimeInterval = 1
    /// `true` from the screen's `unsubscribeFromAll()` until its next `subscribeToUpdates()`:
    /// no purchase sheet can be shown then, so nobody could answer a price change.
    private var isScreenGone = false
    @Published private(set) var isUserSignedIn = false

    /// Which load of the CTX merchant names the currency of its cards.
    @Published private var currencyLoads: CardCurrencyLoads
    /// Raised when the amount or the cards chosen on screen no longer apply: the screen
    /// drops its own selection.
    @Published private(set) var selectionResets = 0
    /// The currency of the purchase the sheet is about, set when the Confirm sheet opens.
    private(set) var purchaseCurrency = GiftCardCurrency.usd
    private var rateObserver: CurrencyExchangerObserver?

    /// What the CTX merchant sells, from the answer that confirmed its currency.
    private var ctxTerms: CTXMerchantTerms?

    /// The currency of the cards: for CTX the one CTX confirmed, nil until it has and when
    /// it could not. Amounts are shown without a currency meanwhile. PiggyCards sells in USD.
    var cardCurrency: String? {
        provider == .ctx ? currencyLoads.confirmed : GiftCardCurrency.usd
    }

    var currencySymbol: String {
        cardCurrency.map { GiftCardCurrency.symbol(for: $0) } ?? ""
    }

    /// The decimals an amount typed on this screen can have.
    var amountFractionDigits: Int {
        guard ctxTerms?.wholeAmountsOnly != true else { return 0 }
        return cardCurrency.map { GiftCardCurrency.fractionDigits($0) } ?? 0
    }

    /// `true` when the merchant's currency could not be confirmed and loading it again may help.
    var canRetryMerchantLoad: Bool {
        provider == .ctx && currencyLoads.state == .unknown && !isLoading
    }

    func retryMerchantLoad() {
        Task { await updateMerchantInfo() }
    }

    private func fiat(_ amount: Decimal) -> String {
        cardCurrency.map { GiftCardCurrency.string(amount, currency: $0) } ?? GiftCardCurrency.number(amount)
    }

    /// A card value as a row of fixed cards shows it: a whole amount without decimals.
    func cardValueLabel(_ amount: Decimal) -> String {
        cardCurrency.map { GiftCardCurrency.string(amount, currency: $0, trimsWholeAmounts: true) }
            ?? GiftCardCurrency.number(amount)
    }

    /// `amount` as the amount field shows it, beside the currency symbol.
    func plainAmount(_ amount: Decimal) -> String {
        cardCurrency.map { GiftCardCurrency.plainString(amount, currency: $0) } ?? GiftCardCurrency.number(amount)
    }

    @Published var merchantTitle: String = ""
    @Published var merchantIconUrl: String = ""
    @Published var walletBalance: UInt64 = 0
    @Published var coinJoinBalance: UInt64 = 0
    @Published var minimumAmount: Decimal = 0
    @Published var maximumAmount: Decimal = 0
    @Published var error: Error? = nil
    @Published var isFixedDenomination: Bool = false
    @Published var denominations: [Decimal] = []
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
        closeConfirmationUnlessItShows(cart: quantities)
        basketSavingsFraction = basketDiscountFraction(from: quantities)
        checkAmountForErrors()
    }

    @Published var input: String = "0" {
        didSet {
            let decimalSeparator = Locale.current.decimalSeparator ?? "."

            // Replace the initial "0" when entering a new digit
            if oldValue == "0" && input.count > 1 && input.first == "0" && String(input[input.index(after: input.startIndex)]) != decimalSeparator {
                input = String(input.dropFirst())
            }
            
            // No more decimals than the card currency has; none at all for one like JPY.
            if let decimalSeparatorCharacter = decimalSeparator.first,
               let decimalSeparatorIndex = input.firstIndex(of: decimalSeparatorCharacter) {
                let decimalPart = input[input.index(after: decimalSeparatorIndex)...]
                if amountFractionDigits == 0 || decimalPart.count > amountFractionDigits {
                    input = oldValue
                }
            }
            
            if input.isEmpty {
                input = "0"
            }
            
            amount = PastedAmountParser.parse(input, locale: .current)?.decimalValue ?? input.decimal(locale: .current) ?? 0
            closeConfirmationUnlessItShows(cart: nil)
            checkAmountForErrors()
        }
    }

    /// Closes a confirmation that shows another amount or other cards than the screen now has.
    private func closeConfirmationUnlessItShows(cart: [Decimal: Int]?) {
        guard case .confirm(let shown) = purchaseSheet,
              !CTXGiftCardOrder.confirmationShows(price: shown.price, quantities: shown.quantities,
                                                  amount: amount, cart: cart) else { return }
        purchaseSheet = nil
    }

    func pasteFromClipboard() {
        #if canImport(UIKit)
        guard let raw = UIPasteboard.general.string else { return }
        let locale = Locale.current
        guard let parsed = PastedAmountParser.parse(raw, locale: locale) else { return }
        let pastedValue = PastedAmountParser.editableString(from: parsed.decimalValue, locale: locale) ?? parsed.normalizedString
        input = pastedValue
        #endif
    }
    
    var costMessage: String {
        let originalPrice = fiat(amount)
        let savingsToDisplay = displaySavingsFraction
        let formattedDiscountedPrice = fiat(payableAmount)

        let discountPercent = NSDecimalNumber(decimal: savingsToDisplay * 100).doubleValue
        let discountText = PercentageFormatter.format(percent: discountPercent, includePercent: false)

        return String(localized: "You are buying a \(originalPrice) gift card for \(formattedDiscountedPrice) (\(discountText)% discount)", comment: "DashSpend")
    }
    var showCost: Bool {
        if error != nil || cardCurrency == nil { return false }

        // For fixed denominations, show cost when a valid denomination is selected
        if isFixedDenomination {
            return selectedDenomination != nil && selectedDenomination != 0
        }

        // For flexible amounts, show cost when within limits
        return amount >= minimumAmount && amount <= maximumAmount && hasValidLimits
    }
    var showLimits: Bool { error == nil && !showCost && hasValidLimits }
    var hasValidLimits: Bool { minimumAmount > 0 || maximumAmount > 0 }
    var minimumLimitMessage: String { String(localized: "Min: \(fiat(minimumAmount))", comment: "DashSpend") }
    var maximumLimitMessage: String { String(localized: "Max: \(fiat(maximumAmount))", comment: "DashSpend") }
    /// Always false: legacy DashSync mixing was removed with `CoinJoinService`
    /// (only the SDK sweep survives), so no mix is ever in progress here.
    var isMixing: Bool { false }

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
            let formatted = fiat(PiggyCardsConstants.maxOrderAmount)
            return String(localized: "You can buy up to \(formatted) in gift cards per order", comment: "DashSpend")
        }
        #endif
        return nil
    }


    /// - Parameters:
    ///   - confirmedTerms: what CTX has already confirmed this merchant sells; `nil` when
    ///     its details are still to be loaded.
    ///   - ratesAreFetching: whether the wallet has no rates at all yet.
    ///   - exchangeRate: reads the wallet's rate for a currency and when it was retrieved. It
    ///     is read for the card currency when the Confirm sheet opens; the purchase uses
    ///     that value.
    ///   - now: the clock the rate's age is judged by, when the sheet opens and again on Confirm.
    ///   - dependencies: what a purchase goes through; `nil` for `Dependencies.live()`.
    init(merchant: ExplorePointOfUse, provider: GiftCardProvider = .ctx,
         confirmedTerms: CTXMerchantTerms? = nil,
         exchangeRate: @escaping (String) -> GiftCardPaymentGuard.ExchangeRate = DashSpendPayViewModel.walletExchangeRate,
         ratesAreFetching: @escaping () -> Bool = DashSpendPayViewModel.walletRatesAreFetching,
         now: @escaping () -> Date = { Date() },
         dependencies: Dependencies? = nil) {
        self.provider = provider
        self.dependencies = dependencies ?? .live()
        self.exchangeRate = exchangeRate
        self.ratesAreFetching = ratesAreFetching
        self.now = now
        ctxTerms = confirmedTerms
        currencyLoads = CardCurrencyLoads(confirmed: confirmedTerms?.currency)

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
                self.denominations = localDenominations.map { Decimal($0) }
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
        isScreenGone = false

        // Start network monitoring
        startNetworkMonitoring()
        
        // Source from SwiftDashSDKWalletState. After M6 retired DashSync's
        // SPV, DSWalletBalanceDidChange no longer fires. Function #5 follow-up.
        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshBalance() }
            .store(in: &cancellableBag)

        // Purchase stays disabled while `error` is set, so an amount refused
        // while funds were confirming must be re-checked when they land —
        // otherwise the user waits as told and nothing changes. Only a funds
        // verdict already on screen is re-checked: `checkAmountForErrors` ends
        // in `error = nil`, which would clear an error it does not own
        // (merchant details that failed to load), and with no error up the
        // balance drop that follows a successful purchase would flag the
        // amount just paid. Not during a resync either: the verdict would turn
        // into the syncing notice.
        SwiftDashSDKWalletState.shared.sendVerdictInputsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !Self.isResyncingWallet, self.canRecheck(fundsVerdictOnly: true) else { return }
                self.checkAmountForErrors()
            }
            .store(in: &cancellableBag)

        // The syncing notice (set by an edit, a merchant load or a network
        // change during a resync) is cleared when the sync is done, and a
        // funds verdict skipped meanwhile is judged. A sync that finished while
        // this screen was not subscribed is caught by the check
        // `startNetworkMonitoring` makes on every subscription.
        NotificationCenter.default.publisher(for: .syncStateChangedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, SyncingActivityMonitor.shared.state == .syncDone,
                      self.canRecheck(fundsVerdictOnly: false)
                else { return }
                self.checkAmountForErrors()
            }
            .store(in: &cancellableBag)

        session.isUserSignedInPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSignedIn in
                self?.isUserSignedIn = isSignedIn
            }
            .store(in: &cancellableBag)
        
        stopObservingRates()
        rateObserver = CurrencyExchanger.shared.addObserver { [weak self] _ in
            Task { @MainActor in self?.exchangeRatesDidChange() }
        }

        self.refreshBalance()
        
        // Get updated merchant info from CTX API if user is signed in
        Task {
            await updateMerchantInfo()
        }
    }
    
    /// Judges again what depends on the card currency's rate: the block for a missing rate,
    /// and a funds verdict on screen. An error it does not own stays. With no error up only
    /// the block is raised: a funds verdict then would flag the amount just paid.
    func exchangeRatesDidChange() {
        let ownsError = error == nil || error is GiftCardPurchaseBlock
            || (error as? SendAmountError)?.isFundsVerdict == true
        guard ownsError, !Self.isResyncingWallet else { return }
        if error == nil {
            error = purchaseBlock
        } else {
            checkAmountForErrors()
        }
    }

    /// Opens the Confirm sheet for `price`, with the discount on screen and the Dash amount
    /// the price comes to at the wallet's rate.
    ///
    /// Throws `GiftCardPaymentGuard.rateUnavailableError` when the wallet has no usable rate
    /// for the card currency: the sheet could not show a Dash amount, and a provider's quote
    /// could not be compared. For CTX it also throws when the merchant's currency is not
    /// confirmed, and when the selection is not one card of an amount the currency can hold.
    func beginPurchase(price: Decimal, quantities: [Decimal: Int] = [:]) throws {
        let discount = displaySavingsFraction
        let currency: String
        let approval: GiftCardPaymentGuard.Approval
        do {
            guard let cardCurrency else { throw Self.currencyUnconfirmedError }
            currency = cardCurrency
            if provider == .ctx {
                _ = try ctxOrder(price: price, quantities: quantities, currency: currency)
            }
            approval = try GiftCardPaymentGuard.approve(
                price: price, discount: discount, currency: provider == .ctx ? currency : nil,
                rate: exchangeRate(currency), now: now())
        } catch {
            DWLogger.log("Gift card purchase not opened: \(error)")
            throw error
        }
        // Pay was tapped on the screen, so the screen is there, whatever was last reported.
        isScreenGone = false
        purchaseCurrency = currency
        purchaseSheet = .confirm(GiftCardPurchaseSnapshot(
            price: price, currency: currency, discount: discount, quantities: quantities, approval: approval))
    }

    /// The one-card order CTX is asked for. Throws when the selection is several cards, the
    /// price is not an amount above zero that the currency can hold (it is never rounded to
    /// fit), or the merchant's confirmed terms do not sell a card of that price.
    private func ctxOrder(price: Decimal, quantities: [Decimal: Int], currency: String) throws -> CTXGiftCardOrder {
        let order: CTXGiftCardOrder
        do {
            order = try CTXGiftCardOrder(price: price, quantities: quantities, currency: currency)
        } catch CTXGiftCardOrder.Refusal.notOneCard {
            throw Self.oneCardPerOrderError
        } catch {
            throw DashSpendError.invalidAmount
        }
        guard let ctxTerms, ctxTerms.currency == currency, ctxTerms.allows(price) else {
            throw DashSpendError.invalidAmount
        }
        return order
    }

    static var currencyUnconfirmedError: DashSpendError {
        .customError(GiftCardPurchaseBlock.currencyUnconfirmed.localizedDescription)
    }

    static var oneCardPerOrderError: DashSpendError {
        .customError(String(localized: "This merchant sells one gift card per order. Please choose a single card.",
                            comment: "DashSpend"))
    }

    /// The provider's answer names another currency than the one ordered.
    static var currencyMismatchError: DashSpendError {
        .customError(String(
            localized: "The gift card provider answered in a different currency than the one ordered. Nothing was sent. Please try again or contact support.",
            comment: "DashSpend"))
    }

    static var cardValueMismatchError: DashSpendError {
        .customError(String(
            localized: "The gift card provider answered for a different card value than the one ordered. Nothing was sent. Please try again or contact support.",
            comment: "DashSpend"))
    }

    /// Closes the purchase sheet on the buyer's Cancel or swipe. A price change is declined.
    /// The sheet is not closed while the provider's answer is awaited.
    func dismissPurchaseSheet() {
        switch purchaseSheet {
        case .confirm:
            purchaseSheet = nil
        case .priceUpdated:
            resolvePriceChange(pay: false)
        case .waitingForProvider, nil:
            break
        }
    }

    /// The buyer's answer on the "Price updated" sheet.
    func resolvePriceChange(pay: Bool) {
        guard case .priceUpdated = purchaseSheet else { return }
        if pay {
            DWLogger.log("Gift card price change accepted")
        }
        purchaseSheet = nil
        priceDecision?.resume(returning: pay)
        priceDecision = nil
    }

    /// Called by the screen when the purchase sheet has left the screen.
    func purchaseSheetDidDismiss() {
        sheetDismissal?.resume()
        sheetDismissal = nil
    }

    /// Compares a provider's quote with what the buyer confirmed, before anything is signed.
    ///
    /// A quote at or below the confirmed amount, or above it by a margin too small to ask
    /// about, closes the sheet and returns. A higher quote is shown on the "Price updated"
    /// sheet; this returns when the buyer chooses to pay it and throws
    /// `DashSpendError.purchaseCancelled` when they decline. When it returns, the sheet has
    /// left the screen, so the PIN prompt that follows is not presented over a sheet that is
    /// still closing.
    ///
    /// It also throws `DashSpendError.purchaseCancelled` when the purchase screen has gone
    /// away (a sign-out closes it), whatever the quote: checked when the quote arrives and
    /// again once the sheet has left, so no PIN prompt follows a screen that is gone.
    ///
    /// - Parameter answerWithin: how long the buyer has to accept a higher price, counted
    ///   from the moment the sheet is put up; `nil` for no limit. A higher price accepted
    ///   later than that throws `GiftCardPaymentGuard.quoteExpiredError` once the sheet has
    ///   left the screen. For an order that carries no expiry the payment could be checked
    ///   against.
    func confirmQuote(requested: UInt64, approval: GiftCardPaymentGuard.Approval,
                      answerWithin: TimeInterval? = nil) async throws {
        let assessment = try approval.assess(requested: requested)
        try endPurchaseIfScreenIsGone()

        var answeredLate = false
        switch assessment {
        case .asConfirmed:
            guard purchaseSheet != nil else { return }
            purchaseSheet = nil
        case .higher(let change):
            DWLogger.log("Gift card price changed: the provider asks more than the confirmed amount")
            purchaseSheet = .priceUpdated(change)
            let shownAt = now()
            let pay = await withCheckedContinuation { priceDecision = $0 }
            guard pay else { throw DashSpendError.purchaseCancelled }
            if let answerWithin {
                answeredLate = now().timeIntervalSince(shownAt) > answerWithin
            }
        }

        await waitForSheetDismissal()
        try endPurchaseIfScreenIsGone()

        if answeredLate {
            DWLogger.log("Gift card purchase ended: the higher price was accepted after the time allowed for it. Nothing was sent")
            throw GiftCardPaymentGuard.quoteExpiredError
        }
    }

    private func endPurchaseIfScreenIsGone() throws {
        guard isScreenGone else { return }
        DWLogger.log("Gift card purchase ended: the purchase screen is gone. Nothing was sent")
        throw DashSpendError.purchaseCancelled
    }

    /// Suspends until the screen reports the sheet gone, or `sheetDismissalWait` has passed.
    private func waitForSheetDismissal() async {
        let wait = sheetDismissalWait
        let fallback = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.purchaseSheetDidDismiss()
        }
        await withCheckedContinuation { sheetDismissal = $0 }
        fallback.cancel()
    }

    /// Orders the gift card the buyer confirmed and pays for it.
    ///
    /// Starts only for the snapshot the Confirm sheet is showing, and only once: a call for
    /// any other snapshot, after the sheet was cancelled, or while a purchase is already
    /// running throws `DashSpendError.purchaseCancelled` with nothing ordered. The sheet's
    /// Confirm button can be tapped again before the sheet has redrawn or left the screen.
    ///
    /// - Parameter snapshot: what the Confirm sheet showed. A provider's quote is compared
    ///   with its `approval` through `confirmQuote` before the payment is authorized.
    func purchaseGiftCardAndPay(_ snapshot: GiftCardPurchaseSnapshot) async throws -> Data {
        guard !isProcessingPayment, case .confirm(let shown) = purchaseSheet, shown == snapshot else {
            DWLogger.log("Gift card purchase not started: not the confirmation on screen, or one is already running")
            throw DashSpendError.purchaseCancelled
        }

        let approval = snapshot.approval
        let confirmedPrice = snapshot.price

        // Read again here: the sheet can stay open past the stale-rate limit, and a quote
        // cannot be compared with a Dash amount computed from a rate that old.
        guard approval.isRateFresh(now: now()) else {
            DWLogger.log("Gift card purchase stopped: the confirmed rate went stale while the sheet was open")
            purchaseSheet = nil
            throw GiftCardPaymentGuard.rateUnavailableError
        }

        // The Dash that the provider quotes is paid as it stands, so the order must be in
        // the currency the sheet showed.
        guard cardCurrency == snapshot.currency else {
            DWLogger.log("Gift card purchase stopped: the card currency is no longer the one confirmed")
            purchaseSheet = nil
            throw Self.currencyUnconfirmedError
        }

        isProcessingPayment = true
        purchaseSheet = .waitingForProvider(snapshot)
        defer {
            isProcessingPayment = false
            purchaseSheet = nil
        }

        // Wire-order txid (`Transaction.txHashData` convention) — the gift-card
        // metadata key.
        let txidWire: Data
        let giftCardNote: String

        switch provider {
        case .ctx:
            let order = try ctxOrder(price: confirmedPrice, quantities: snapshot.quantities, currency: snapshot.currency)
            let response = try await purchaseGiftCardAPI(order)

            guard GiftCardCurrency.answerConfirms(ordered: order.fiatCurrency, payment: response.fiatCurrency,
                                                  card: response.cardFiatCurrency) else {
                DWLogger.log("Gift card order stopped: the provider did not answer in the currency ordered. Nothing was sent")
                throw Self.currencyMismatchError
            }
            guard GiftCardCurrency.answerConfirms(cardValue: confirmedPrice, answered: response.cardFiatAmount) else {
                DWLogger.log("Gift card order stopped: the provider did not answer for the card value ordered. Nothing was sent")
                throw Self.cardValueMismatchError
            }

            // Process the payment using the payment URL
            guard let url = response.paymentUrls?.first?.value else {
                throw DashSpendError.paymentProcessingError(String(localized: "No payment URL received", comment: "DashSpend"))
            }

            giftCardNote = response.id

            // CTX uses BIP70 payment request URLs. The acceptance verdict is not awaited: CTX
            // acknowledges the signed transaction and starts fulfilling the order from it, so
            // blocking the buyer for the SDK's 30 s acceptance window only delays the card that
            // is already being issued (the email routinely arrived before the screen moved on).
            do {
                txidWire = try await dependencies.payments.payWithDashUrl(
                    url: url, awaitAcceptance: false,
                    validate: { confirmation in
                        try await self.confirmQuote(
                            requested: confirmation.amount, approval: approval,
                            answerWithin: GiftCardPaymentGuard.priceAnswerLimit(
                                requestExpires: confirmation.request.details.expires))
                    })
            } catch DashSpendError.paymentNotAcknowledged(let unacknowledgedTxIdWire, let reason) {
                // Same loss, one step earlier: the network dropped between posting the payment
                // and reading the acknowledgement. Record the order — CTX may be fulfilling it
                // already — but keep the error, since we genuinely cannot say it was received.
                DWLogger.log("Gift card payment unacknowledged, recording the order anyway: \(reason)")
                recordPurchase(txidWire: unacknowledgedTxIdWire, giftCardNote: giftCardNote, price: confirmedPrice,
                               currency: snapshot.currency)
                throw DashSpendError.paymentNotAcknowledged(
                    txIdWire: unacknowledgedTxIdWire, reason: reason)
            } catch DashSpendError.paymentStatusUnknown(let unconfirmedTxIdWire, let reason) {
                // The payment left the device and CTX holds the signed bytes; only the
                // network's acceptance verdict is missing. Record the purchase against the
                // txid we do have so the order survives — without this the customer pays,
                // CTX fulfils the order, and the app keeps no trace of the card at all.
                DWLogger.log("Gift card payment status unknown, recording the order anyway: \(reason)")
                recordPurchase(txidWire: unconfirmedTxIdWire, giftCardNote: giftCardNote, price: confirmedPrice,
                               currency: snapshot.currency)
                throw DashSpendError.paymentStatusUnknown(txIdWire: unconfirmedTxIdWire, reason: reason)
            }

        #if PIGGYCARDS_ENABLED
        case .piggyCards:

            // PiggyCards uses orderGiftCard which returns GiftCardInfo
            let lineItems = buildPiggyOrderLineItems(
                selectedQuantities: snapshot.quantities, cardValue: confirmedPrice)
            let giftCardInfo = try await dependencies.piggyCards.orderGiftCards(
                merchantId: merchantId,
                lineItems: lineItems,
                fiatCurrency: GiftCardCurrency.usd,
                cryptoCurrency: "DASH"
            )


            // PiggyCards returns a simple address and amount, not a BIP70 URL
            // Convert DASH amount to satoshis (1 DASH = 100,000,000 satoshis)
            guard let dashAmountInSatoshis = GiftCardPaymentGuard.duffs(fromDashAmount: giftCardInfo.amount) else {
                throw GiftCardPaymentGuard.invalidAmountError
            }

            // Compared here, before the payment asks for the PIN: a declined quote shows no
            // prompt. The payment address was validated when the order response was parsed.
            // The order states no expiry, so a higher price has to be accepted in limited time.
            try await confirmQuote(requested: dashAmountInSatoshis, approval: approval,
                                   answerWithin: GiftCardPaymentGuard.priceAnswerLimit)

            giftCardNote = buildPiggyOrderNote(
                orderId: giftCardInfo.orderId, selectedQuantities: snapshot.quantities, cardValue: confirmedPrice)

            // Paid to the order's address; this is where the PIN is asked.
            do {
                txidWire = try await dependencies.payments.payGiftCardOrder(
                    address: giftCardInfo.paymentAddress, amount: dashAmountInSatoshis)
            } catch DashSpendError.paymentStatusUnknown(let unconfirmedTxIdWire, let reason) {
                // The transaction was handed to the network and no acceptance was seen in
                // time; the wallet keeps trying while it is open. Record the order against
                // the txid, as the CTX branch does: without the record a payment that goes
                // through leaves the buyer with no card, and a second try pays twice.
                DWLogger.log("Gift card payment status unknown, recording the order anyway: \(reason)")
                recordPurchase(txidWire: unconfirmedTxIdWire, giftCardNote: giftCardNote, price: confirmedPrice,
                               currency: snapshot.currency)
                throw DashSpendError.paymentStatusUnknown(txIdWire: unconfirmedTxIdWire, reason: reason)
            }
        #endif
        }

        // Payment successful - save gift card information
        recordPurchase(txidWire: txidWire, giftCardNote: giftCardNote, price: confirmedPrice, currency: snapshot.currency)

        return txidWire
    }

    /// The wallet's current rate for `currency` and the time it was retrieved.
    nonisolated static func walletExchangeRate(_ currency: String) -> GiftCardPaymentGuard.ExchangeRate {
        GiftCardPaymentGuard.ExchangeRate(
            price: try? CurrencyExchanger.shared.rate(for: currency),
            retrievedAt: BaseRatesProvider.shared.lastUpdated)
    }

    /// Whether the wallet has no rates yet, as just after launch.
    nonisolated static func walletRatesAreFetching() -> Bool {
        CurrencyExchanger.shared.currencies.isEmpty
    }

    /// Persist everything that ties a paid order to its transaction: the tax/service metadata,
    /// the merchant icon, and the `gift_cards` row whose `note` carries the order id the
    /// details poller needs. Shared by the confirmed and the unconfirmed-broadcast paths.
    ///
    /// - Parameters:
    ///   - price: the card value the buyer confirmed, stored as the card's price.
    ///   - currency: the currency the order was made in, not the one on screen by now.
    private func recordPurchase(txidWire: Data, giftCardNote: String, price: Decimal, currency: String) {
        dependencies.purchases.record(GiftCardPurchaseRecord(
            txidWire: txidWire, provider: provider, merchantName: merchantTitle, merchantUrl: merchantUrl,
            merchantIconUrl: merchantIconUrl, price: price, currency: currency, note: giftCardNote))
    }

    /// What the buyer is told, before the gift card details, when the payment was handed to
    /// the network and its outcome is unknown; `nil` when nothing is shown.
    ///
    /// For PiggyCards this wallet is the only one that can broadcast the payment, and it
    /// keeps trying only while the app is open, so the buyer is told what every other send
    /// with this outcome tells them. CTX holds the signed transaction itself.
    var unknownOutcomeNotice: String? {
        #if PIGGYCARDS_ENABLED
        if provider == .piggyCards { return WalletSendService.unknownBroadcastOutcomeNotice }
        #endif
        return nil
    }

    var contactSupportButtonText: String {
        String(localized: "Contact \(provider.displayName) Support", comment: "DashSpend")
    }

    func contactSupport() {
        let subject = "\(provider.displayName) Issue: Spending Limit Problem"
        
        var body = "Merchant details\n"
        body += "name: \(merchantTitle)\n"
        body += "id: \(merchantId)\n"
        body += "currency: \(cardCurrency ?? "unknown")\n"
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
        stopObservingRates()

        // A price change waiting for the buyer's answer has nobody left to answer it, and a
        // quote that arrives from here on has no screen to go on from: `confirmQuote` ends
        // the purchase for both.
        isScreenGone = true
        resolvePriceChange(pay: false)
    }
    
    private func stopObservingRates() {
        if let rateObserver {
            CurrencyExchanger.shared.removeObserver(rateObserver)
        }
        rateObserver = nil
    }

    private func refreshBalance() {
        walletBalance = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        coinJoinBalance = SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs
    }
    
    var isNetworkAvailable: Bool { networkStatus == .online }

    func checkAmountForErrors() {
        guard isNetworkAvailable else {
            error = SendAmountError.networkUnavailable
            return
        }
        
        guard !Self.isResyncingWallet else {
            error = SendAmountError.syncingChain
            return
        }

        // Before the funds check: without a rate the amount converts to no Dash, which
        // would pass it.
        if let block = purchaseBlock {
            if (error as? GiftCardPurchaseBlock) != block { error = block }
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

        if let refusal = fundsRefusal(requestedDuffs: requestedDashDuffs) {
            // Re-checked on every balance event while it is up: re-setting the
            // same refusal would only re-render both panels.
            if (error as? SendAmountError) != refusal { error = refusal }
            return
        }

        error = nil
    }

    /// Why the wallet cannot send `requestedDuffs` now; nil when it can.
    func fundsRefusal(requestedDuffs: UInt64) -> SendAmountError? {
        let state = SwiftDashSDKWalletState.shared
        let (ceilingDuffs, reserveDuffs) = state.feeAwareMaxSendableAndReserve()
        // The screen shows the whole balance, the gate counts confirmed coins
        // only — so right after a receive the shortfall is often just time,
        // and must not read as "Insufficient funds".
        return SendAmountError(refusing: state.sendVerdict(
            requestedDuffs: requestedDuffs,
            ceilingDuffs: ceilingDuffs,
            reserveDuffs: reserveDuffs))
    }

    /// What blocks every purchase now. Nothing while the first load of a CTX merchant runs:
    /// the screen is loading then, and nothing can be bought before it ends.
    private var purchaseBlock: GiftCardPurchaseBlock? {
        if provider == .ctx, currencyLoads.state == .loading { return nil }
        return GiftCardPurchaseBlock.check(currency: cardCurrency, rate: { exchangeRate($0).price },
                                           ratesAreFetching: ratesAreFetching())
    }

    /// What the buyer pays for the amount on screen: the price a confirmation would hold.
    /// A CTX price is the one CTX charges, after its rounding of the discount.
    private var payableAmount: Decimal {
        guard provider == .ctx, let cardCurrency else { return amount * (1 - displaySavingsFraction) }
        return GiftCardCurrency.discounted(amount, by: displaySavingsFraction, currency: cardCurrency)
    }

    /// Whether a wallet or sync event may re-check the error on screen: a purchase block,
    /// which a rate change during a resync leaves up, the
    /// syncing notice when `fundsVerdictOnly` is false — re-checked like an
    /// edit would — or a funds verdict, unless an amount was entered that does
    /// not convert to DASH: it reads as 0, which would clear the verdict.
    private func canRecheck(fundsVerdictOnly: Bool) -> Bool {
        if error is GiftCardPurchaseBlock { return true }
        guard let shown = error as? SendAmountError else { return false }
        if shown == .syncingChain { return !fundsVerdictOnly }
        return shown.isFundsVerdict && (amount == 0 || requestedDashDuffs > 0)
    }

    private static var isResyncingWallet: Bool {
        WalletSendService.isBlockedByInitialRestoreSync(
            isResyncingWallet: DWGlobalOptions.sharedInstance().isResyncingCurrentNetworkWallet,
            isChainSynced: SyncingActivityMonitor.shared.state == .syncDone)
    }

    private var requestedDashDuffs: UInt64 {
        guard let currency = cardCurrency, let rate = exchangeRate(currency).price, rate > 0 else { return 0 }
        // PiggyCards keeps its check on the card's face value.
        return ((provider == .ctx ? payableAmount : amount) / rate).plainDashAmount
    }
    
    // MARK: - CTX Integration

    func updateMerchantInfo() async {
        guard !merchantId.isEmpty else { return }

        // CTX getMerchant is a public endpoint — fetch limits even when not signed in.
        // PiggyCards requires authentication, so skip if not signed in.
        let requiresAuth: Bool
        #if PIGGYCARDS_ENABLED
        requiresAuth = provider == .piggyCards
        #else
        requiresAuth = false
        #endif
        if requiresAuth && !session.isUserSignedIn { return }


        // Set loading state
        await MainActor.run {
            self.isLoading = true
        }

        do {
            switch provider {
            case .ctx:
                // A load that a later one superseded applies nothing, the loading state included.
                guard try await loadCTXMerchant() else { return }

            #if PIGGYCARDS_ENABLED
            case .piggyCards:
                // For PiggyCards, we need to fetch gift cards for this merchant using the sourceId from the database
                guard let sourceId = sourceId else {
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }

                let giftCards = try await dependencies.piggyCards.getGiftCards(
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
                    DWLogger.log(
                        "DashSpend: PiggyCards mode=\(finalFixed ? "fixed" : "flexible"), " +
                        "range=[\(finalMin), \(finalMax)], fixedCount=\(finalDenominations.count)"
                    )
                    self.denominationDiscounts = finalFixed ? denomDiscounts : [:]
                    self.denominationInventory = finalFixed ? denomInventory : [:]
                    self.isFixedDenomination = finalFixed
                    self.minimumAmount = finalMin
                    self.maximumAmount = finalMax
                    self.denominations = finalDenominations.map { Decimal($0) }
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
            DWLogger.log("DashSpend updateMerchantInfo failed for provider \(provider.displayName): \(error.localizedDescription)")

            await MainActor.run {
                self.isLoading = false
                if let dashError = error as? DashSpendError {
                    self.error = dashError
                } else {
                    self.error = DashSpendError.customError(
                        String(localized: "Unable to load merchant details. Please try again.", comment: "DashSpend")
                    )
                }
            }
        }
    }
    
    /// Loads the CTX merchant and applies what it sells: the currency, the limits or card
    /// values and the discount, all from the same answer or none of them.
    ///
    /// Throws when CTX was not reached for a merchant whose currency is confirmed: everything
    /// stays as it was. A merchant left without a confirmed currency is not an error here; it
    /// blocks the purchase until a load confirms one.
    /// - Returns: `false` for a load that a later one superseded.
    private func loadCTXMerchant() async throws -> Bool {
        let load = currencyLoads.begin()
        var answer: (terms: CTXMerchantTerms, savings: Decimal)?
        var finding = CardCurrencyLoads.Finding.unusable
        var failure: Error = DashSpendError.unknown

        do {
            let merchantInfo = try await dependencies.ctx.getMerchant(merchantId: merchantId)
            if let terms = CTXMerchantTerms(currency: merchantInfo.currency,
                                            denominationsType: merchantInfo.denominationsType,
                                            denominations: merchantInfo.denominations) {
                answer = (terms, Decimal(merchantInfo.discount) / Decimal(10000))
                finding = .currency(terms.currency)
            }
        } catch DashSpendError.parsingError, DashSpendError.invalidMerchant {
            // CTX answered: with something that cannot be read, or that it has no such merchant.
        } catch {
            finding = .noAnswer
            failure = error
        }

        switch currencyLoads.finish(load, finding) {
        case .superseded:
            return false
        case .kept:
            throw failure
        case .applied(let clearsSelection):
            let wasFixed = isFixedDenomination
            let offeredBefore = denominations
            ctxTerms = answer?.terms
            if let (terms, savings) = answer {
                savingsFraction = savings
                isFixedDenomination = terms.isFixed
                minimumAmount = terms.minimum ?? 0
                maximumAmount = terms.maximum ?? 0
                denominations = terms.denominations
                basketSavingsFraction = nil

                if !terms.isFixed {
                    selectedDenomination = nil
                } else if let selected = selectedDenomination, !terms.denominations.contains(Decimal(selected)) {
                    selectedDenomination = nil
                }
            } else {
                DWLogger.log("DashSpend: the CTX merchant's currency could not be confirmed: \(AppLogMessage.errorSummary(failure))")
                minimumAmount = 0
                maximumAmount = 0
                denominations = []
            }

            // The cards chosen on screen were offered by the list they were chosen from.
            if clearsSelection || isFixedDenomination != wasFixed
                || (isFixedDenomination && denominations != offeredBefore) {
                clearSelection()
            } else if case .confirm(let shown) = purchaseSheet, ctxTerms?.allows(shown.price) != true {
                purchaseSheet = nil
            }
        }
        return true
    }

    /// Drops the amount and the cards chosen on screen, and a confirmation that showed them:
    /// they were chosen in another currency or for another kind of merchant.
    private func clearSelection() {
        selectedDenomination = nil
        basketSavingsFraction = nil
        selectionResets += 1
        if case .confirm = purchaseSheet {
            purchaseSheet = nil
        }
    }

    private func purchaseGiftCardAPI(_ order: CTXGiftCardOrder) async throws -> GiftCardResponse {
        guard !merchantId.isEmpty, session.isUserSignedIn else {
            throw DashSpendError.unauthorized
        }

        DWLogger.log("Attempting to purchase gift card for merchant \(merchantId)")

        return try await dependencies.ctx.purchaseGiftCard(
            merchantId: merchantId,
            fiatAmount: order.fiatAmount,
            fiatCurrency: order.fiatCurrency,
            cryptoCurrency: "DASH"
        )
    }
    
    private func handleNetworkStatusChange(_ status: NetworkStatus) {
        // Re-check errors when network status changes
        checkAmountForErrors()
        if status == .online, canRetryMerchantLoad {
            Task { await updateMerchantInfo() }
        }
    }

    private func buildPiggyOrderLineItems(selectedQuantities: [Decimal: Int],
                                          cardValue: Decimal) -> [PiggyCardsRepository.OrderLineItem] {
        let positiveSelections = selectedQuantities
            .filter { $0.value > 0 }
            .map { PiggyCardsRepository.OrderLineItem(denomination: decimalToDouble($0.key), quantity: $0.value) }

        if !positiveSelections.isEmpty {
            return positiveSelections
        }

        return [PiggyCardsRepository.OrderLineItem(denomination: decimalToDouble(cardValue), quantity: 1)]
    }

    private func buildPiggyOrderNote(orderId: String, selectedQuantities: [Decimal: Int],
                                     cardValue: Decimal) -> String {
        var expandedAmounts = selectedQuantities
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .flatMap { entry in Array(repeating: entry.key.description, count: entry.value) }

        if expandedAmounts.isEmpty {
            expandedAmounts = [cardValue.description]
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

extension GiftCardPurchaseBlock: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .currencyUnconfirmed:
            return String(
                localized: "The currency of this merchant's gift cards could not be confirmed, so nothing can be bought right now. Please try again.",
                comment: "DashSpend")
        case .ratesFetching:
            return String(localized: "Fetching rates…", comment: "Balance")
        case .rateMissing:
            return String(
                localized: "There is no exchange rate for this gift card's currency right now, so it cannot be bought. Please try again later.",
                comment: "DashSpend")
        }
    }
}
