# 0017 — Answer an App Connect request at most once

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

Retrying an approval used to publish again a response sealed in an earlier attempt. Review rounds
on #1301 kept finding new ways the state it was sealed for could have changed in between: limits
raised, an encryption key rotated or turned off, an auth key turned off, a node behind, an
observation lost between attempts. Each fix opened another case.

## Decision drivers

- The wallet cannot prove that a sealed response still holds.
- The Android wallet does not replay a sealed response.

## Considered options

1. **At most once.** Once an approval's intent is recorded, any failure of its update, of the
   checks before publishing, or of the publish spends the request. A request already answered,
   seen in this wallet's record or on Platform (its response, or its auth key on, off or expired),
   is refused before any PIN; the app asks again with a new code.
2. **Replay with checks.** Keep the retry and check limits, current keys and key state again
   before publishing, carrying observations across attempts.
3. **Retry from the row.** Show a stuck connection with a Retry button that publishes again.

## Decision outcome

**Chosen:** option 1. It removes the retry class instead of guarding it.

## Consequences

**Positive**
- The replay class of findings is gone.
- The checks before publishing run inside one attempt, on the keys it just chose.
- Another device's answer to the same request is seen as well, so a request is not answered twice
  by two devices of one identity.

**Negative**
- If the link drops between the identity update and the publish, the user scans a new code
  instead of tapping Approve again.
- Scanning a request that was already answered reports it as spent, although the app has its
  answer.
- When the answered check cannot read Platform, the sheet says so and offers to try again.

**Neutral**
- A spent request that never landed stays Confirming until Disconnect fences it (ADR-0015) or a
  newer sign-in supersedes it.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- PR: #1334
