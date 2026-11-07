# 0010 — Probe live routes with address-free quotes forced to one provider

- **Status:** Proposed
- **Date:** 2026-11-05 (the approach was approved by the owner on 2026-11-02 and is implemented in PR #1297)
- **Deciders:** romchornyi (author)

## Context

The swap coin picker labelled each coin from SwapKit's published coin lists (`/tokens?provider=`),
which say what NEAR or Maya can carry in principle, not now. On 2026-11-02 NEAR's DASH leg was down,
Maya had BTC and ETH halted, and SwapKit answered "no route" for DASH → USDT on Arbitrum through Maya
even though Maya itself quoted that pair. The picker still offered every coin. The wallet needs a
per-coin, per-direction, per-provider signal of what can be swapped right now.

## Decision drivers

- A Wallet holder never picks a coin that no provider can swap right now — the signal must reflect the whole path the swap will take, SwapKit's own leg included.
- A check carries no address at all.
- Check size about US$50 of the sold coin; ≤ 2 checks in flight.
- Prefer the integration the wallet already has (SwapKit through `SwapKitAPIService`) when it meets the goals: a new one adds a client, a dependency and its own failure modes.
- Only a conclusive answer may halt a coin.

## Considered options

1. **Route checks through SwapKit** — one quote per coin, direction and provider, forced to that provider's SwapKit names (both Maya flavours in one check), sized at about US$50, with no source or destination address; the answer is classified as available / halted / no route / unknown.
2. **Read the providers' own status directly** — Maya's node (`inbound_addresses` halt flags per chain) and a NEAR status source, bypassing SwapKit.
3. **No checks in the picker** — learn availability only from the address screen's own quote once the Wallet holder has picked a coin.

## Decision outcome

**Chosen:** Option 1. It asks the same service, through the same leg, that the real swap will use,
so it catches failures that live in SwapKit rather than in the provider (the ARB.USDT case above,
which option 2 would have shown as available), and it needs no new integration. Option 3 leaves the
defect in place: the Wallet holder still picks a dead coin and types an address first.

## Consequences

**Positive**
- One classifier (`LiveRouteState.classify`) serves Sell and Buy, the picker and the address screen.
- The answer matches what a real quote would get, SwapKit's leg included.
- No address leaves the device in a check.

**Negative**
- Every check spends SwapKit API quota; the volume is bounded only by the load limits (two in flight, ten-minute reuse, two-minute back-off).
- The classification depends on SwapKit's error-code strings (`noRoutesFound`, `swapHalted`, the below-minimum family); a renamed code turns a conclusive answer into `unknown`, which keeps coins pickable rather than halting them.
- A bare top-level "no route" is read as conclusive only because of the check size; a Sell check without a DASH price falls back to 1 DASH, and a Buy check without a price is not sent at all.

**Neutral**
- Moving to provider status endpoints later is possible behind the same `Probe` function type; the store and the picker would not change.

## Links

- Feature summary: [docs/features/swap-live-routes/README.md](../features/swap-live-routes/README.md)
- Related ADR: [0011 — Keep live route answers in one shared in-memory store with two-step ageing](0011-keep-live-swap-route-answers-in-one-shared-in-memory-store.md)
- Related ADR: [0012 — Detect a NEAR outage from sentinel coins before per-coin checks](0012-detect-a-near-outage-from-sentinel-coins.md)
