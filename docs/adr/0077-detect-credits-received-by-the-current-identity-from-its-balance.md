# 0077 — Detect credits received by the Current identity from its balance

- **Status:** Proposed
- **Date:** 2026-11-27
- **Deciders:** Roman Chornyi (owner), with Claude. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

Someone who sends credits to a wallet holder's identity (Core, Platform or Shielded → Identity ID) leaves no row in
the holder's Home History: Platform has no index of the transitions that credited an identity, and DAPI streams
Core data only (`core.proto` subscriptions), nothing for identity balances. The app reads an identity's balance only
on demand (profile, Create Username, Internal Transfer, after an own spend); no periodic read exists. Android
(dash-wallet#1680) polls the balance every 15 s only while Send is open and shows no Received row either.

## Decision drivers

- One Received row per arrival the wallet did not cause; never a Received row for the wallet's own money.
- No SDK change (option 2, reading the identity's top-up transitions, is a follow-up task).
- Rows per wallet and network, wiped with the wallet (as the credit-send ledger).

## Considered options

1. **Compare each network read with the SDK's local balance.** Own operations write their post-broadcast balance
   into the managed identity, so the difference would be the foreign part. Rejected: every identity re-fetch
   (`take_fetched_identity`: key sync, discovery, profile refresh) also overwrites the local balance, and an
   arrival picked up that way would never get a row.
2. **An app-owned baseline per identity, own operations subtracted by the traces they already leave.** The pattern
   of `PlatformAddressActivityRecorder` (Platform addresses).
3. **Read the identity's credit transitions from Platform.** Exact rows with a sender; needs an SDK query and a
   platform PR. Follow-up task.

## Decision outcome

**Chosen:** option 2.

- **Who:** the Current (main) identity of the selected wallet only (owner, 2026-11-27).
- **When:** the app reads the identity's balance from the network after each Platform-address sync pass and when Home
  appears; one read at a time, dropped if the wallet, network or Current identity changed meanwhile.
- **Baseline:** the first read of a (wallet, network, identity) seeds it silently (registration and history before
  this release give no row). A lower balance moves it silently (own spends have their own rows).
- **Own credits:** each own operation that credited the identity leaves a trace once the credit exists: a consumed
  identity top-up asset lock (`PersistentAssetLock` type 1) for its identity index (every Core route), a credit send to
  it in the app's credit-send ledger (every Platform-address and identity route, including the shielded two-step
  top-up's second leg and the registration's Platform top-up, which this decision adds to the ledger), and a
  confirmed shielded `IdentityTopUp` activity. A trace counts for the read that started after it, if the previous
  read started before it; a send submitted with its result unconfirmed counts for the first rise within 6 hours.
  Each trace counts once (the app keeps which did): the SDK stamps its rows again on every write.
- **Store:** the baseline, the counted traces and the row are written in one transaction; a failed write keeps the old
  baseline, so the next read sees the same rise again. A read that was answered after the wallet's history was
  deleted (wipe, wallet removal) writes nothing.
- **Row:** the growth minus those own credits; if at least 1 duff remains, one Received row with that amount,
  labelled with the identity's username (no sender). Arrivals between two reads merge into one row.

## Consequences

- Good: every route to the identity, including someone else's Core top-up, shows as Received with the amount.
- Bad: three new tables (baseline, rows, counted traces) and a migration; rows are stamped with the read time, so an arrival while the
  app was closed shows at the next read.
- Bad, accepted: an own spend in the same interval (a DashPay fee) lowers the rise, and with it the row.
- Bad, accepted: a submitted credit send whose result stays unconfirmed and that did not execute hides one arrival
  within 6 hours; left out, one that did execute would read as Received.
- Bad, accepted: a trace written before this release and stamped again by the SDK after a read can hide one arrival
  once.
- Bad, accepted: an own Core top-up counts as its lock value, which exceeds the credits Platform granted by the
  processing fee, so a foreign arrival read together with an own top-up is reported up to that fee short.
- Bad, accepted: an arrival on another identity of the wallet gets no row (Current only).
