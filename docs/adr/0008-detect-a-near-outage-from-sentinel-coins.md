# 0008 — Detect a NEAR outage from sentinel coins before per-coin checks

- **Status:** Proposed
- **Date:** 2026-11-05 (the rule was set by the owner on 2026-11-02 and is implemented in PR #1297)
- **Deciders:** romchornyi (author)

## Context

NEAR can carry most of the coins in the picker, and on 2026-11-02 its DASH leg was down in both
directions: every NEAR quote answered "no route". Checking NEAR coin by coin during such an outage
would spend one request per NEAR-capable coin to learn one fact. Maya is different: its halts are per
chain, so one Maya coin says nothing about the next.

## Decision drivers

- During an outage ≤ 3 sentinel checks per round, at most one round per 2 min per direction, no per-coin NEAR checks; recovery re-checked on the sentinels after 2 min.
- Light on the network, quick recovery.

## Considered options

1. **Sentinel coins first** — BTC and ETH are asked first, SOL only in place of one that gave no conclusive answer, not in place of a halted one; two conclusive no-routes and none routing → NEAR is down for that direction; one routing → every NEAR-capable coin is checked on its own; a halted sentinel counts toward neither; a round with neither outcome keeps the previous verdict and is retried after 2 min.
2. **Always check NEAR per coin** — no verdict, each coin's NEAR state is its own answer.
3. **Infer the outage from the per-coin checks** — stop checking NEAR once the first K per-coin answers in display order are all no-route.

## Decision outcome

**Chosen:** Option 1. It bounds an outage to at most three checks per round and gives a recovery
signal every two minutes. Option 2 breaks the load limit during exactly the outage it should handle cheaply.
Option 3 depends on which coins happen to be shown first and mixes coin-specific no-routes into a
provider-wide verdict.

## Consequences

**Positive**
- A NEAR outage costs at most three checks per direction per two minutes.
- Recovery shows up while the picker is open; a coin whose own conclusive NEAR answer is newer than the outage keeps that answer.

**Negative**
- The sentinel list is hard-coded (`SwapRouteAvailability.nearSentinels`); if NEAR stops listing these coins, rounds end inconclusive and NEAR stays in the labels from the published lists.
- A NEAR outage limited to some chains is not a "down" verdict; those coins are caught by their own per-coin checks only after a sentinel routes.

**Neutral**
- The verdict is per direction: Sell and Buy can disagree, as they did on 2026-11-02.

## Links

- Feature summary: [docs/features/swap-live-routes/README.md](../features/swap-live-routes/README.md)
- Related ADR: [0006 — Probe live routes with address-free quotes forced to one provider](0006-probe-live-swap-routes-with-address-free-forced-quotes.md)
- Related ADR: [0007 — Keep live route answers in one shared in-memory store with two-step ageing](0007-keep-live-swap-route-answers-in-one-shared-in-memory-store.md)
