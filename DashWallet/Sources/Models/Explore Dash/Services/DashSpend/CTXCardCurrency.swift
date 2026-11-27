//
//  CTXCardCurrency.swift
//  DashWallet
//
//  What a CTX purchase needs to know about the merchant's currency before it may go ahead.
//

import Foundation

/// What is known about the currency a CTX merchant sells its cards in.
enum CardCurrencyState: Equatable {
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
    /// The limits of a range merchant; nil for one the answer does not state.
    let minimum: Decimal?
    let maximum: Decimal?

    /// Nil when the answer cannot be used: it names no usable currency, or one of its amounts
    /// is not a plain number the currency can hold.
    init?(currency: String?, isRange: Bool, denominations: [String]) {
        guard let currency = GiftCardCurrency.normalize(currency) else { return nil }

        var amounts: [Decimal] = []
        for text in denominations {
            guard let amount = GiftCardCurrency.plainDecimal(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  GiftCardCurrency.isRepresentable(amount, in: currency) else {
                return nil
            }
            amounts.append(amount)
        }

        self.currency = currency
        isFixed = !isRange
        self.denominations = isRange ? [] : amounts.filter { $0 > 0 }
        minimum = isRange ? amounts.first.flatMap { $0 > 0 ? $0 : nil } : nil
        maximum = isRange ? amounts.dropFirst().first.flatMap { $0 > 0 ? $0 : nil } : nil
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
        /// The load decided the state. `clearsSelection` when the amounts on screen are no
        /// longer in the currency they were chosen in.
        case applied(clearsSelection: Bool)
    }

    /// The currency CTX confirmed; a purchase needs one.
    var confirmed: String? {
        if case .known(let currency) = state { return currency }
        return nil
    }

    /// The currency the screen's amounts are in, or nil when it is unknown. Until the first
    /// load ends the amounts are the explore database's, whose merchants are all USD.
    var shown: String? {
        switch state {
        case .loading: return GiftCardCurrency.usd
        case .known(let currency): return currency
        case .unknown: return nil
        }
    }

    /// Starts a load and returns its number. A confirmed currency stays while it runs.
    mutating func begin() -> Int {
        if state == .unknown { state = .loading }
        latest += 1
        return latest
    }

    mutating func finish(_ load: Int, _ finding: Finding) -> Outcome {
        guard load == latest else { return .superseded }

        let shownBefore = shown
        switch finding {
        case .currency(let currency):
            state = .known(currency)
        case .unusable:
            state = .unknown
        case .noAnswer:
            if confirmed != nil { return .kept }
            state = .unknown
        }
        return .applied(clearsSelection: shown != shownBefore)
    }
}

/// Why no gift card can be bought, whatever the amount.
enum GiftCardPurchaseBlock: Equatable {
    /// The merchant's currency is not confirmed.
    case currencyUnconfirmed
    /// The wallet has no exchange rate for the card currency, so it cannot estimate the Dash
    /// to pay or check the balance.
    case rateMissing

    /// - Parameters:
    ///   - currency: the currency the screen's amounts are in; nil when unknown.
    ///   - rate: the wallet's price of one Dash in a currency; nil when it has none.
    static func check(currency: String?, rate: (String) -> Decimal?) -> GiftCardPurchaseBlock? {
        guard let currency else { return .currencyUnconfirmed }
        guard let price = rate(currency), price.isFinite, price > 0 else { return .rateMissing }
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
