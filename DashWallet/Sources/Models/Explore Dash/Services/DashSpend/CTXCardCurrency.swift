//
//  CTXCardCurrency.swift
//  DashWallet
//
//  What a CTX purchase needs to know about the merchant's currency before it may go ahead.
//

import Foundation

/// What is known about the currency a CTX merchant sells its cards in.
enum CardCurrencyState: Equatable {
    /// The first load of the merchant has not ended.
    case loading
    case known(String)
    /// The merchant could not be fetched, or its answer names no usable currency.
    case unknown
}

/// What a CTX merchant sells, read from its `GET merchants/{id}` answer.
struct CTXMerchantTerms: Equatable {
    let currency: String
    let isFixed: Bool
    /// The card values of a fixed merchant, in the order CTX lists them.
    let denominations: [Decimal]
    /// The limits of a range merchant.
    let minimum: Decimal?
    let maximum: Decimal?
    /// A `min-max-major` merchant sells whole amounts only: the server refuses an order
    /// for an amount with a fraction.
    let wholeAmountsOnly: Bool

    /// Nil when the answer cannot be used to buy a card: it names no usable currency, one of
    /// its amounts is not a plain number the currency can hold, or the amounts do not make
    /// the terms of its type: at least one card value above zero for `fixed`; a minimum and
    /// a maximum above zero and not below it for `min-max` and `min-max-major`.
    init?(currency: String?, denominationsType: String, denominations: [String]) {
        guard let currency = GiftCardCurrency.normalize(currency) else { return nil }

        var amounts: [Decimal] = []
        for text in denominations {
            guard let amount = GiftCardCurrency.plainDecimal(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  GiftCardCurrency.isRepresentable(amount, in: currency) else {
                return nil
            }
            amounts.append(amount)
        }

        switch denominationsType {
        case "fixed":
            let values = amounts.filter { $0 > 0 }
            guard !values.isEmpty else { return nil }
            isFixed = true
            self.denominations = values
            minimum = nil
            maximum = nil
            wholeAmountsOnly = false
        case "min-max", "min-max-major":
            guard amounts.count == 2, amounts[1] > 0, amounts[0] <= amounts[1] else { return nil }
            isFixed = false
            self.denominations = []
            minimum = amounts[0]
            maximum = amounts[1]
            wholeAmountsOnly = denominationsType == "min-max-major"
        default:
            return nil
        }
        self.currency = currency
    }

    /// Whether CTX sells a card of `price` under these terms.
    func allows(_ price: Decimal) -> Bool {
        guard price > 0 else { return false }
        if isFixed { return denominations.contains(price) }
        guard let minimum, let maximum, price >= minimum, price <= maximum else { return false }
        return !wholeAmountsOnly || GiftCardCurrency.isWhole(price)
    }
}

/// Decides which load of a CTX merchant names the currency of its cards. A load that a later
/// one superseded names nothing.
struct CardCurrencyLoads {
    private(set) var state: CardCurrencyState
    private var latest = 0

    /// - Parameter confirmed: a currency CTX has already confirmed; nil to start loading.
    init(confirmed: String? = nil) {
        state = confirmed.map { .known($0) } ?? .loading
    }

    /// What a finished load found.
    enum Finding: Equatable {
        /// CTX answered with a usable currency.
        case currency(String)
        /// CTX answered, and the answer names no usable currency or cannot be read.
        case unusable
        /// CTX was not reached.
        case noAnswer
    }

    enum Outcome: Equatable {
        /// A later load was started: nothing from this one is applied.
        case superseded
        /// No answer for a merchant whose currency is confirmed: everything stays as it is.
        case kept
        /// The load decided the state. `clearsSelection` when it changed after the first
        /// load: what is selected was chosen for another currency, or while none was known.
        /// The first load clears nothing; no currency was shown while it ran.
        case applied(clearsSelection: Bool)
    }

    /// The currency CTX confirmed; a purchase needs one.
    var confirmed: String? {
        if case .known(let currency) = state { return currency }
        return nil
    }

    /// Starts a load and returns its number. The state stays while it runs.
    mutating func begin() -> Int {
        latest += 1
        return latest
    }

    mutating func finish(_ load: Int, _ finding: Finding) -> Outcome {
        guard load == latest else { return .superseded }

        let before = state
        switch finding {
        case .currency(let currency):
            state = .known(currency)
        case .unusable:
            state = .unknown
        case .noAnswer:
            if confirmed != nil { return .kept }
            state = .unknown
        }
        return .applied(clearsSelection: before != .loading && state != before)
    }
}

/// Why no gift card can be bought, whatever the amount.
enum GiftCardPurchaseBlock: Equatable {
    /// The merchant's currency is not confirmed.
    case currencyUnconfirmed
    /// The wallet has no exchange rate for the card currency, so it cannot estimate the Dash
    /// to pay or check the balance.
    case rateMissing
    /// The wallet has no rates yet: they are still being fetched.
    case ratesFetching

    /// - Parameters:
    ///   - currency: the confirmed card currency; nil when there is none.
    ///   - rate: the wallet's price of one Dash in a currency; nil when it has none.
    ///   - ratesAreFetching: whether the wallet has no rates at all yet.
    static func check(currency: String?, rate: (String) -> Decimal?,
                      ratesAreFetching: Bool = false) -> GiftCardPurchaseBlock? {
        guard let currency else { return .currencyUnconfirmed }
        guard let price = rate(currency), price.isFinite, price > 0 else {
            return ratesAreFetching ? .ratesFetching : .rateMissing
        }
        return nil
    }
}

/// A CTX order: one card, priced in the merchant's currency.
struct CTXGiftCardOrder: Equatable {
    let fiatCurrency: String
    let fiatAmount: String

    enum Refusal: Error, Equatable {
        /// The selection is not exactly one card of the confirmed price.
        case notOneCard
        /// The price is not above zero, or has more decimals than the currency.
        case amountNotInCurrency
    }

    /// - Parameters:
    ///   - price: the total the buyer confirmed.
    ///   - quantities: cards per denomination; empty for an amount the buyer typed.
    init(price: Decimal, quantities: [Decimal: Int], currency: String) throws {
        let selected = quantities.filter { $0.value > 0 }
        if let card = selected.first {
            guard selected.count == 1, card.key == price, card.value == 1 else { throw Refusal.notOneCard }
        }
        guard let amount = GiftCardCurrency.orderAmount(price, currency: currency) else {
            throw Refusal.amountNotInCurrency
        }
        fiatCurrency = currency
        fiatAmount = amount
    }

    /// Whether a confirmation for `price` and `quantities` still shows what is selected on
    /// screen: the amount, and the cards when the screen has a cart. Confirm orders what
    /// the confirmation shows, so one that no longer does is closed.
    static func confirmationShows(price: Decimal, quantities: [Decimal: Int],
                                  amount: Decimal, cart: [Decimal: Int]?) -> Bool {
        guard price == amount else { return false }
        guard let cart else { return true }
        return quantities.filter { $0.value > 0 } == cart.filter { $0.value > 0 }
    }

    /// A change to a selection of fixed cards, held to the one card an order carries: the
    /// card whose count went up replaces the selection.
    static func singleCard(from old: [Decimal: Int], to new: [Decimal: Int]) -> [Decimal: Int] {
        if let raised = new.first(where: { $0.value > (old[$0.key] ?? 0) }) {
            return [raised.key: 1]
        }
        let kept = new.filter { $0.value > 0 }
        return kept.count == 1 ? kept.mapValues { _ in 1 } : [:]
    }
}
