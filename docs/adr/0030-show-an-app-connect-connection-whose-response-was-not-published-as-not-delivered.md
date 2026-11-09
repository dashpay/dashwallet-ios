# 0030 — Show an App Connect connection whose response was not published as Not delivered

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

An approval registers the app's keys first and publishes the response that hands them to the app
second. When the publish fails, the keys are live on the identity but the app never got them.
Showing that as Active claims a working connection. An approval makes one attempt and does not
retry the publish; the app needs a new code.

## Decision drivers

- A row says what Platform and the intents show, not what the wallet hopes.
- The only useful actions are Disconnect and a new code.

## Considered options

1. **A Not delivered row.** An app whose live access comes only from intents with no recorded
   response shows "Not delivered", with Disconnect. A response that landed without its
   acknowledgement is looked up on Platform when Connections refreshes, within a day of the
   request.
2. **Active**, as an ordinary connection.
3. **A three-state delivery** (delivered, not delivered, unknown) on every intent.

## Decision outcome

**Chosen:** option 1.

## Consequences

**Positive**
- The row tells the user the app holds keys it cannot use, and offers to turn them off.

**Negative**
- A response that was published but neither acknowledged nor found by the lookup within a day
  stays shown as Not delivered.

**Neutral**
- Disconnect turns the keys off whichever way the delivery went.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0027](0027-derive-app-connect-connections-from-the-identity-and-recorded-intents.md)
- PR: #1301
