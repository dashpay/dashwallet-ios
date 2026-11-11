# 0027 — Derive App Connect connections from the identity and recorded intents

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

The earlier App Connect code (#1272) stored its own conclusions about Platform: grant records,
settlement states and predicted identity revisions, reconciled afterwards. Most review findings
on it came from that reconciliation: the unknown outcome of an identity update, which app a key
belongs to, and time. Platform cannot tell the wallet which app a key belongs to, so something has
to be stored, but only that.

## Decision drivers

- Every finding class traced back to a stored conclusion drifting from Platform.
- The user can always keep working and retry, with clear signals.
- Keys carry no app id, and an app key cannot be derived again from what is stored.

## Considered options

1. **Projection over intents.** Before each identity update the wallet writes a
   `ConnectionIntent`: the app, the keys it submits and the response it will publish. Every row,
   status and unrecorded key is computed from one read of the identity plus the intents
   (`AppConnect.project`).
2. **A stored current state per connection**, moved by transitions, as #1272 did.
3. **Keep #1272** and fix its findings one by one.

## Decision outcome

**Chosen:** option 1. It removes the cause, stored conclusions, instead of the findings, and the
projection is pure, so table tests cover it.

## Consequences

**Positive**
- Rows cannot drift from Platform: a read rebuilds them.
- Retry, disconnect and a newer approval all read the same projection.

**Negative**
- An intent lost to a reinstall, another device or a restore cannot be rebuilt: its keys show as
  unrecorded and need their own handling on disconnect.
- A read projects only the active identity; access seen on another identity is kept in the row
  cache (`seenOn`) and can be stale until that identity is read again.

**Neutral**
- The stored rows stay, as a display cache rebuilt on every read.
- The intent is a stored schema: fields added later must decode as empty from older intents.
- The projection is pure and could move to a shared implementation for both wallets later.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0009](0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md)
- PR: #1301
