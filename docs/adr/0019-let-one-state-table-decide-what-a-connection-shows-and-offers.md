# 0019 — Let one state table decide what a connection shows and offers

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

A connection can be Active, Confirming, Not delivered, Refused, Expired or Disconnected, and the
Connections page has Active, Disconnected and Expired tabs. Which tab a connection is on, the
badge and text it shows, and which actions it allows (Disconnect, Remove, Reconnect) were decided
in several view models and views. Earlier findings of the form "a row showed Active after the
publish failed" came from screens deciding on their own.

## Decision drivers

- A connection is never shown Active without a live key and a published response.
- The status is worked out once, from Platform and the wallet's record; the UI decides nothing of
  its own on top of it.
- No screen can offer an action its status does not allow.

## Considered options

1. **One pure table.** `AppConnect.StateActions.row(for:)` maps each status to its tab, badge
   colour, text and allowed actions. The row, the connection sheet and the page's tabs only read
   it. Its switch has no `default`, so a new status does not compile until it has a row.
2. **Rules in each view model**, as before.

## Decision outcome

**Chosen:** option 1.

## Consequences

**Positive**
- One table test per status covers every screen.
- Adding a status (Refused, ADR-0021) is one new row.
- The redesigned Connections page (#1277, #1289, #1293) reads the same table: Remove on a Refused
  row, Reconnect on a Disconnected or Expired one, Disconnect where keys may be live.

**Negative**
- A screen that wants a different action order than the table's still needs a rule of its own
  (an expired row offers Reconnect first, as in the design).

**Neutral**
- The table is pure, so it can move with the projection to a shared implementation later.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADRs: [0021](0021-record-a-consensus-refusal-on-the-intent.md),
  [0022](0022-derive-disconnected-apps-from-the-intents-a-disconnect-marked.md)
- PR: #1334
