# 0036 — Measure returned funds as the fallback address increase

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author and author of the change)

## Context

After a charged Shielded registration failure ([ADR-0035](0035-classify-a-charged-shielded-registration-failure-by-the-sdks-proven-outcome.md)) the wallet must state exactly how much came back to the Platform Payment balance. The network does not tell the client: the penalty is a flat 10 000 000 credits plus a verification fee plus the processing fee metered so far, and DAPI drops `gas_used` and the address balance changes from the result it forwards. The app itself names the address that receives the remainder — the lowest-indexed Platform Payment address, passed as `sendToAddressOnCreationFailure` — and Platform address sync reports that address's balance.

## Decision drivers

- The stated amount is the amount that reached the Platform Payment balance; where the network gives no figure, the increase on the address that received it, rounded down to the duff.
- Until the funds are seen, no amount and no advice to try again; the amount, once stated, never changes.
- The SDK proves only that the create's inputs are spent and its identity was not created, not where the money went (ADR-0035).

## Considered options

1. **Increase on the fallback address over a snapshot taken just before sending** — the coordinator reads the address's synced balance before the Type-20 call and keeps it with the failure; the first synced increase in (0, exit denomination] becomes the returned amount.
2. **Exit denomination minus an estimated penalty** — stated at once, without waiting for sync.

## Decision outcome

**Chosen:** the returned amount is the first synced increase of the fallback address over a snapshot taken just before the Type-20 call (option 1). It states what actually arrived, so the balance on Home rises by exactly the stated amount. Option 2 would state a figure that differs from the balance, because the penalty depends on metered fees.

## Consequences

**Positive**
- The stated amount matches the balance the wallet holder sees.
- "Checking where the money went" maps directly onto "not seen yet".

**Negative**
- A payment from elsewhere to the same address between the snapshot and the sync, smaller than the network's penalty (~0.0002 DASH), is included in the figure; a larger one, or a spend from that address, leaves the checking message.
- The explanation waits for Platform address sync; if the increase is never seen, the checking message stays.

**Neutral**
- Zero or an increase above the denomination is not taken as a returned amount.
- If DAPI later forwards the charged fee, the figure can come from the network and the snapshot can go.

## Links

- Feature summary: [docs/features/shielded-registration-failure/README.md](../features/shielded-registration-failure/README.md)
- Related ADR: [0035 — Classify a charged Shielded registration failure by the SDK's proven outcome](0035-classify-a-charged-shielded-registration-failure-by-the-sdks-proven-outcome.md)
- Issue: #1265.
