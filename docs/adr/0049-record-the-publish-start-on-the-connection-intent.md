# 0049 — Record the publish start on the connection intent

- **Status:** Accepted
- **Date:** 2026-11-13
- **Deciders:** romchornyi, with Claude during the design pass. Approved in #1414 by HashEngineering.

## Context

An approval's response publish can land after its publish timeout, and nothing the wallet stores today says that a publish was ever started: `ConnectionIntent` holds the response's document id and `responseRemoved`, nothing in between (`AppConnectProjection.swift:42-91`). After the app restarts, a disconnect therefore cannot tell an intent whose publish may still land from one whose publish never ran (spec US-03, AC-07). Intents are stored in UserDefaults under `.app-connect-intents.v1` with no migration; fields added later must be optional.

## Decision drivers

- Spec AC-07: the unresolved state survives an app restart.
- Spec §1: an intent written before this change carries no start and is treated as before.
- SAD §2: no schema migration for the intent store; a wallet wipe must remove whatever the feature stores.
- Spec §6.1: no new personal data — one optional value on the intent.

## Considered options

1. **An optional field on the intent** — `publishStartBlockTimeMs: UInt64?`, written in the same store update just before the executor submits the publish, and cleared when the publish failed for good: its submit threw a consensus rejection, Platform's own verdict on the transition and the one refusal ADR-0021 counts as permanent. Any other error, known or not, keeps the start: a cancellation or an unconfirmed result says nothing of what Platform did, and an error the wallet does not recognise cannot prove that nothing landed.
2. **A separate pending-publish store** — a new UserDefaults key mapping intent id to start, removed once the publish is resolved.

## Decision outcome

**Chosen:** option 1. Everything the wallet knows about a response stays in one row that is already pinned to its wallet, wiped with it, and decoded tolerantly; an intent written before the change decodes `nil` and keeps today's behaviour with no migration.

## Consequences

**Positive**
- One write records the start; no second store to add to the wipe suffixes or to keep in step with the intents.
- Old intents need nothing: `nil` means "no unresolved publish".
- A publish that failed before Platform accepted it, or that Platform refused, leaves nothing to wait for: the disconnect gives no "may still appear" note and the row no mark (architecture review 2026-11-14).

**Negative**
- One more optional field on an already wide model; every reader must treat `nil` as "no start recorded", never as "started at 0".

**Neutral**
- The value is a Platform block time, not a device date (ADR-0050); its meaning is "the proved block time of the identity read the approval stood on".

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0050](0050-bound-an-unresolved-publish-by-48-hours-of-proved-platform-block-time.md)
- Issue: #1374
