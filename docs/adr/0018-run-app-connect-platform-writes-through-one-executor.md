# 0018 — Run App Connect Platform writes through one executor

- **Status:** Accepted
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

Adding the app's keys, publishing the response, fencing and deleting a response each had their
own logging, re-reads and failure handling. Several of them had exits that said nothing, and a
timeout was treated differently by each.

## Decision drivers

- Every write logs its start and its outcome the same way, without the SDK's error text.
- After an error or a timeout a read of Platform decides; nothing guesses landed or failed. The one
  exception is an approval's key update refused by consensus: it is for good, so it is recorded
  without a read.
  While the publish of a response is unresolved, a read that finds no response decides nothing
  ([ADR-0052](0052-refuse-response-removed-at-its-one-write-point-while-the-publish-is-unresolved.md));
  a submit that ends after its timeout is only logged, and the next read decides.
- Failures can be injected in tests without a network.

## Considered options

1. **One executor.** A write is a value (`PlatformWrite`: update keys, publish, fence, delete a
   response) run by `AppConnectWriteExecutor`, which logs it, applies the timeout and returns what it
   saw: submitted, failed or timed out. It does not read Platform; after an error or a timeout
   `AppConnect.nextStep` routes a key update to `recordRefusal` when Platform refused it by
   consensus (the approval records the refusal on its intent and fails without a read) and to the
   identity read otherwise, a publish or delete to the response read, and a fence to `.stop`. The
   approval does the routed read in the same run. An approval that first fences a superseded
   sign-in (`fenceAndDisable`, ADR-0029) stops before its own key update when that fails, and reads
   the identity again when it succeeds. A disconnect does not follow the route step by
   step: a key update that is not `.done`, a consensus refusal included (it is not recorded on an
   intent), stops its key updates, and the disconnect then tries one identity read in the same
   run. A key that read shows off no longer counts as live; if the read fails, the keys of the
   unconfirmed updates count as still live and the next disconnect reads again. A fence that is not
   `.done` ends only the fence batches: the disconnect still reads the identity and deletes
   responses, and the next disconnect turns off the fences left on. The disconnect reads through an
   injected port and writes through an injected executor factory (`makeWriteExecutor`), so the
   whole disconnect is tested against a fake Platform.
2. **Keep the handling in each call.**

## Decision outcome

**Chosen:** option 1.

## Consequences

**Positive**
- One log, timeout and outcome for every write. The executor does not retry a write.
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
