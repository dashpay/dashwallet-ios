# 0020 — Judge request age and expiry by proved Platform block time

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

A request is answered only while it is fresh (at most 10 minutes old and 2 minutes in the
future), and a connection is Expired once its keys are past their expiry. Both were judged by the
phone clock, so a wrong clock could answer a stale request or show a live connection as Expired.
dashpay/platform#5715 returns a proved block time with the identity's keys; the pinned platform
commit (`1721ca7a8b`) contains it.

## Decision drivers

- Platform stops an expired key by its own block time; any other clock can disagree near the
  boundary.
- The Android wallet reads Platform time for the same decisions.
- An unknown time is modelled as unknown, never guessed.

## Considered options

1. **Proved Platform block time only.** The block time proved with the identity read judges both;
   when it cannot be read, the wallet says it could not check and offers to try again.
2. **Platform block time, with the Core chain tip as a fallback.**
3. **A lower bound from the Core chain tip only** (the tip's time less the header margin), as an
   earlier version of the Expired tab did.

## Decision outcome

**Chosen:** option 1. One clock, the one Platform enforces.

## Consequences

**Positive**
- Expiry and request freshness follow what Platform enforces; the phone clock plays no part.
- Nothing is shown Active or Expired on a guess.

**Negative**
- Every request check and every Connections read waits for a proved read.
- On a quiet network the latest block can be minutes old, so the 2-minute "future" bound may
  refuse a request scanned at once; it is to be measured on a protocol-14 testnet and widened if
  needed.

**Neutral**
- A Core-tip fallback can be added later behind the same snapshot field.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Platform: dashpay/platform#5715
- PR: #1334
