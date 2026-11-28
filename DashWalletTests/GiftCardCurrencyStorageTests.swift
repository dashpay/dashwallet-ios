//
//  GiftCardCurrencyStorageTests.swift
//  DashWalletTests
//
//  The currency a saved gift card's price is in. A card saved before the column existed has
//  none and is in USD; a stored currency is never put back to NULL or replaced.
//

import SQLite
import XCTest
@testable import dashpay

final class GiftCardCurrencyStorageTests: XCTestCase {

    private let txId = Data(repeating: 0xC1, count: 32)

    /// The gift cards table as it was before cards had a currency.
    private func makeLegacyConnection() throws -> Connection {
        let connection = try Connection(.inMemory)
        try AddGiftCardsTable().migrateDatabase(connection)
        try AddProviderToGiftCardsTable().migrateDatabase(connection)
        try AddRedeemUrlChallengeToGiftCardsTable().migrateDatabase(connection)
        return connection
    }

    private func makeConnection() throws -> Connection {
        let connection = try makeLegacyConnection()
        try AddCurrencyToGiftCardsTable().migrateDatabase(connection)
        return connection
    }

    private func insertLegacyCard(into connection: Connection) throws {
        try connection.run(GiftCard.table.insert(
            GiftCard.txId <- txId,
            GiftCard.merchantName <- "Test Merchant",
            GiftCard.price <- "25",
            GiftCard.note <- "order-1",
            GiftCard.provider <- "CTX"))
    }

    private func card(price: Decimal = 25, currency: String?) -> GiftCard {
        GiftCard(txId: txId, merchantName: "Test Merchant", merchantUrl: nil, price: price,
                 note: "order-1", provider: "CTX", currency: currency)
    }

    private func storedCurrency(in connection: Connection) throws -> String? {
        try connection.scalar(GiftCard.table.filter(GiftCard.txId == txId).select(GiftCard.currency))
    }

    func testACardSavedBeforeTheMigrationKeepsItsRowAndHasNoCurrency() async throws {
        let connection = try makeLegacyConnection()
        try insertLegacyCard(into: connection)

        try AddCurrencyToGiftCardsTable().migrateDatabase(connection)

        let saved = await GiftCardsDAOImpl(connection: connection).get(byTxId: txId)
        XCTAssertEqual(saved?.merchantName, "Test Merchant")
        XCTAssertEqual(saved?.price, 25)
        XCTAssertNil(saved?.currency)
        XCTAssertEqual(GiftCardCurrency.ofSavedCard(saved?.currency), "USD")
    }

    /// A row read from a table that has no currency column yet still decodes.
    func testARowWithoutTheColumnIsReadWithoutACurrency() throws {
        let connection = try makeLegacyConnection()
        try insertLegacyCard(into: connection)

        let rows = try connection.prepare(GiftCard.table).map { GiftCard(row: $0) }

        XCTAssertEqual(rows.map(\.price), [25])
        XCTAssertEqual(rows.map(\.currency), [nil])
    }

    func testANewCardStoresItsCurrencyAndItsPrice() async throws {
        let connection = try makeConnection()
        let dao = GiftCardsDAOImpl(connection: connection)
        let price = try XCTUnwrap(Decimal(string: "25.5"))

        await dao.create(dto: card(price: price, currency: "GBP"))

        XCTAssertEqual(try storedCurrency(in: connection), "GBP")
        let saved = await dao.get(byTxId: txId)
        XCTAssertEqual(saved?.currency, "GBP")
        XCTAssertEqual(saved?.price, price)
    }

    func testAWriteWithoutACurrencyNeverClearsAStoredOne() async throws {
        let connection = try makeConnection()
        let dao = GiftCardsDAOImpl(connection: connection)
        await dao.create(dto: card(currency: "GBP"))

        await dao.update(dto: card(currency: nil))
        XCTAssertEqual(try storedCurrency(in: connection), "GBP")

        await dao.updateCardDetails(txId: txId, number: "0000", pin: nil)
        await dao.updateBarcode(txId: txId, value: "0000", format: "CODE128")
        await dao.updateRedeemUrl(txId: txId, url: "https://provider.invalid/redeem", challenge: nil)

        XCTAssertEqual(try storedCurrency(in: connection), "GBP")
        let saved = await dao.get(byTxId: txId)
        XCTAssertEqual(saved?.currency, "GBP")
    }

    func testAWriteWithoutACurrencyLeavesALegacyCardWithoutOne() async throws {
        let connection = try makeConnection()
        try insertLegacyCard(into: connection)
        let dao = GiftCardsDAOImpl(connection: connection)

        await dao.update(dto: card(currency: nil))

        XCTAssertNil(try storedCurrency(in: connection))
    }

    func testBackfillGivesALegacyCardItsCurrency() async throws {
        let connection = try makeConnection()
        try insertLegacyCard(into: connection)
        let dao = GiftCardsDAOImpl(connection: connection)

        await dao.backfillCurrency(txId: txId, currency: "USD")

        XCTAssertEqual(try storedCurrency(in: connection), "USD")
        let saved = await dao.get(byTxId: txId)
        XCTAssertEqual(saved?.currency, "USD")
    }

    func testBackfillNeverReplacesAStoredCurrency() async throws {
        let connection = try makeConnection()
        let dao = GiftCardsDAOImpl(connection: connection)
        await dao.create(dto: card(currency: "GBP"))

        await dao.backfillCurrency(txId: txId, currency: "USD")

        XCTAssertEqual(try storedCurrency(in: connection), "GBP")
    }

    func testTheMigrationIsRegisteredAfterEveryOtherOne() {
        let versions = DatabaseConnection.migrations().map(\.version)
        XCTAssertEqual(versions.max(), AddCurrencyToGiftCardsTable().version)
    }
}
