# 0029 — Allow a new App Connect approval while another one is still confirming

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

An approval whose identity update may still land shows as Confirming. The Android wallet refuses
a new approval of the same app until it settles. A stuck update can stay Confirming for a long
time.

## Decision drivers

- The user can always keep working.
- Two updates must never race for one key id.

## Considered options

1. **Allow, with key ids reserved.** The key ids an open intent may still land on are reserved
   for it, so a new approval takes other ids. The new approval supersedes the pending one, which
   is closed once it can never land.
2. **Block, as Android does,** until the pending update lands or is disconnected.

## Decision outcome

**Chosen:** option 1.

## Consequences

**Positive**
- A stuck Confirming row never blocks the user from signing in again.

**Negative**
- It differs from Android on purpose.
- Making sure a superseded update can never land later may cost one more identity update.

**Neutral**
- The pending intent stays recorded until it is closed.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0027](0027-derive-app-connect-connections-from-the-identity-and-recorded-intents.md)
- PR: #1301
