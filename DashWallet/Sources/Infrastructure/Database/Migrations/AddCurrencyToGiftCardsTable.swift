//
//  AddCurrencyToGiftCardsTable.swift
//  DashWallet
//
//  Adds the currency a gift card was sold in to the `gift_cards` table.
//

import Foundation
import SQLite
import SQLiteMigrationManager

/// NULL is kept for the cards saved before this column: they read as USD
/// (`GiftCardCurrency.ofSavedCard`), which is what every card was sold in.
struct AddCurrencyToGiftCardsTable: Migration {
    var version: Int64 = 20261127120000

    func migrateDatabase(_ db: Connection) throws {
        try db.run(GiftCard.table.addColumn(GiftCard.currency, defaultValue: nil))
    }
}
