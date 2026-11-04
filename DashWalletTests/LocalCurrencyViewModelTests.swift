//
//  LocalCurrencyViewModelTests.swift
//  DashWalletTests
//
//  The currency list serves two kinds of caller. Settings and the Home
//  shortcut change the app-wide fiat currency; the amount screens and the
//  Coinbase transfer pick a currency for the amount being entered only and
//  must leave the app-wide one alone. Also the search the list inherited from
//  the Objective-C picker: every word, any order, ignoring case and accents.
//

import XCTest
@testable import dashpay

@MainActor
final class LocalCurrencyViewModelTests: XCTestCase {

    private var savedAppCurrency: String!

    private let items = [
        CurrencyItem(code: "USD", name: "US Dollar", flagName: nil, priceString: nil),
        CurrencyItem(code: "EUR", name: "Euro", flagName: nil, priceString: nil),
        CurrencyItem(code: "BRL", name: "Brazilian Réal", flagName: nil, priceString: nil),
        CurrencyItem(code: "AED", name: "United Arab Emirates Dirham", flagName: nil, priceString: nil),
        CurrencyItem(code: "INR", name: "Indian Rupee", flagName: nil, priceString: nil),
    ]

    override func setUp() {
        super.setUp()
        savedAppCurrency = App.shared.fiatCurrency
        App.shared.fiatCurrency = "USD"
    }

    override func tearDown() {
        App.shared.fiatCurrency = savedAppCurrency
        super.tearDown()
    }

    // MARK: - App-wide vs. this amount only

    func testAppWidePickChangesTheAppCurrency() {
        let viewModel = LocalCurrencyViewModel(allItems: items, selectedCurrencyCode: "USD", changesAppCurrency: true)

        viewModel.select(currencyCode: "EUR")

        XCTAssertEqual(viewModel.selectedCurrencyCode, "EUR")
        XCTAssertEqual(App.shared.fiatCurrency, "EUR")
    }

    func testAmountOnlyPickLeavesTheAppCurrencyAlone() {
        let viewModel = LocalCurrencyViewModel(allItems: items, selectedCurrencyCode: "USD", changesAppCurrency: false)

        viewModel.select(currencyCode: "EUR")

        XCTAssertEqual(viewModel.selectedCurrencyCode, "EUR")
        XCTAssertEqual(App.shared.fiatCurrency, "USD")
    }

    func testAppWideIsTheDefault() {
        let viewModel = LocalCurrencyViewModel(allItems: items, selectedCurrencyCode: "USD")

        viewModel.select(currencyCode: "BRL")

        XCTAssertEqual(App.shared.fiatCurrency, "BRL")
    }

    // MARK: - Search

    func testEveryWordMustMatchInAnyOrder() {
        let viewModel = LocalCurrencyViewModel(allItems: items, selectedCurrencyCode: "USD")

        viewModel.applyFilter("emirates united")

        XCTAssertEqual(viewModel.filteredItems.map(\.code), ["AED"])
    }

    func testSearchIgnoresCaseAndAccents() {
        let viewModel = LocalCurrencyViewModel(allItems: items, selectedCurrencyCode: "USD")

        viewModel.applyFilter("BRAZILIAN REAL")

        XCTAssertEqual(viewModel.filteredItems.map(\.code), ["BRL"])
    }

    func testSearchMatchesTheCode() {
        let viewModel = LocalCurrencyViewModel(allItems: items, selectedCurrencyCode: "USD")

        viewModel.applyFilter("eur")

        XCTAssertEqual(viewModel.filteredItems.map(\.code), ["EUR"])
    }

    func testCodeMatchIsLocaleIndependent() {
        // "inr" must find INR whatever the device locale (Turkish folds "I"
        // to a dotless "ı"); the search uses a fixed locale.
        let viewModel = LocalCurrencyViewModel(allItems: items, selectedCurrencyCode: "USD")

        viewModel.applyFilter("inr")

        XCTAssertEqual(viewModel.filteredItems.map(\.code), ["INR"])
    }

    // MARK: - Highlight

    private func highlighted(_ query: String, in text: String) -> [String] {
        LocalCurrencyViewModel.matchRanges(of: query, in: text).map { String(text[$0]) }
    }

    func testEveryMatchingWordIsHighlighted() {
        XCTAssertEqual(highlighted("emirates united", in: "United Arab Emirates Dirham"), ["United", "Emirates"])
    }

    func testHighlightIgnoresCaseAndAccents() {
        XCTAssertEqual(highlighted("real", in: "Brazilian Réal"), ["Réal"])
    }

    func testOverlappingMatchesMerge() {
        XCTAssertEqual(highlighted("dol dollar", in: "US Dollar"), ["Dollar"])
    }

    func testNoQueryHighlightsNothing() {
        XCTAssertTrue(highlighted("  ", in: "Euro").isEmpty)
    }

    func testBlankQueryShowsEverything() {
        let viewModel = LocalCurrencyViewModel(allItems: items, selectedCurrencyCode: "USD")
        viewModel.applyFilter("eur")

        viewModel.applyFilter("   ")

        XCTAssertEqual(viewModel.filteredItems.count, items.count)
    }
}
