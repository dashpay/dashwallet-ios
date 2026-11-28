# 0077 — Store a gift card's currency in a nullable column where NULL means USD

- **Status:** Proposed
- **Date:** 2026-11-27
- **Deciders:** AshFrancis (ADR author)

## Context

Every DashSpend gift card was sold in US dollars, so the `gift_cards` table stores a card's value in
`price` and no currency. CTX now lists merchants whose cards are priced in other currencies
(`GET merchants/{id}` returns `currency`), and the purchase flow orders a card in the merchant's
currency. A saved card must keep that currency, or the details screen would show a £25 card as $25.

The rows already on devices have no currency. All of them were bought while every card was USD.

## Decision drivers

- A card bought before this change must keep showing its value in dollars, with no data rewrite.
- A stored currency must never be lost: several writers save a whole row (`create` with
  `INSERT OR REPLACE`, used by `update`) and most of them do not know the currency.
- The meaning of `price` (the card value the buyer confirmed) must not change, because rows written
  by older versions stay in the table.
- The migration must be safe to ship on its own, before any merchant in another currency is listed.

## Considered options

1. **A nullable `currency` column; NULL is read as USD** — one `ADD COLUMN`, no backfill, old rows
   are correct as they are.
2. **A `NOT NULL` column with default `'USD'`** — also one statement, but a row then cannot tell
   "bought in USD" from "written by a writer that did not know", so a wrong USD could never be
   told from a right one.
3. **Encode the currency in `price` or `note`** — no migration, but it changes the meaning of a
   column older versions and the details poller read.

## Decision outcome

**Chosen:** option 1. `AddCurrencyToGiftCardsTable` (version `20261127120000`) adds
`currency TEXT NULL` to `gift_cards` through SQLite.swift, registered in
`DatabaseConnection.migrations()` like the table's earlier columns.

- **Read:** `GiftCard.currency` is optional and read with `try?`, like the other added columns.
  `GiftCardCurrency.ofSavedCard` turns NULL into USD and keeps a stored three-letter code as it is,
  also one the running system's currency list does not have. A stored value that is not such a code
  has no currency: the price is shown as a number, never as dollars. Nothing else interprets the
  column.
- **Write:** a purchase stores the currency the order was made in. A whole-row write stores
  `COALESCE(new, stored)`, so a writer without a currency keeps the stored one and never puts NULL
  over it.
- **Backfill:** `backfillCurrency` writes only where the column is NULL. The details poller calls it
  with the card currency CTX returns for the order, so a row saved without a currency gets one
  while it is still being polled. Rows that are no longer polled stay NULL, which reads as USD.
- **`price`:** unchanged — the card value the buyer confirmed, as a decimal string.

PiggyCards sells in USD and stores `USD`.

## Consequences

- No row is rewritten by the migration, and a version without the column ignores it: SQLite.swift
  reads columns by name.
- A NULL currency is ambiguous in principle ("USD" or "unknown"). It is safe only because no card in
  another currency could be bought before the column existed. A later writer that saves a non-USD
  card without a currency would show it in dollars; the purchase path always passes one.
- The column holds what the wallet ordered, not what the provider reported. The purchase stops
  before payment when the provider's answer names another currency, so the two cannot differ for a
  paid card.
- A downgrade keeps the column and its values; the older version shows such a card in dollars.

## Links

- [ADR-0001](0001-record-architecture-decisions-as-adrs.md) — rule 1: a storage schema or migration.
- `DashWallet/Sources/Infrastructure/Database/Migrations/AddCurrencyToGiftCardsTable.swift`
- `DashWallet/Sources/Models/Explore Dash/Model/DAO/GiftCardsDAO.swift`
- `DashWalletTests/GiftCardCurrencyStorageTests.swift`
