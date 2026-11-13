# 0018 — Run App Connect Platform writes through one executor

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

Adding the app's keys, publishing the response, fencing and deleting a response each had their
own logging, re-reads and failure handling. Several of them had exits that said nothing, and a
timeout was treated differently by each.

## Decision drivers

- Every write logs its start and its outcome the same way, without the SDK's error text.
- After an error or a timeout the next read of Platform decides; nothing guesses landed or failed.
- Failures can be injected in tests without a network.

## Considered options

1. **One executor.** A write is a value (`PlatformWrite`: update keys, publish, fence, delete a
   response) run by `AppConnectWriteExecutor`, which logs it and re-reads Platform after an error
   or a timeout. The disconnect path runs its writes and reads through an injected port, so the
   whole disconnect is tested against a fake Platform.
2. **Keep the handling in each call.**

## Decision outcome

**Chosen:** option 1.

## Consequences

**Positive**
- One retry and re-read policy for every write.
- A disconnect that stops part-way reports what is still live and keeps the row, and its outcome
  is settled from the read after its writes; this is covered by seam tests.

**Negative**
- One more layer between the data source and the SDK.

**Neutral**
- A read that is behind what this wallet already saw is refused and read again, so a lagging node
  cannot make a landed write look lost.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0015](0015-fence-a-pending-sign-in-on-disconnect.md)
- PR: #1334
