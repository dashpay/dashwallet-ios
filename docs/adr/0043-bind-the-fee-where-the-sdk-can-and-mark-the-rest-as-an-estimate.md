# 0043 — Bind the fee where the SDK can and mark the rest as an estimate

- **Status:** Proposed
- **Date:** 2026-11-11
- **Deciders:** Roman Chornyi (owner), with Claude, on the review of PR #1358. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

ADR-0039 promised that the fee on Confirm is the fee the send pays, for every route. The review of PR #1358 showed that only Core → Core and BIP70 keep that promise:
they are built and signed at Continue and only broadcast at Confirm. The routed sends re-run the
estimator and the live adapters ignore the figure. Shielded spends are priced at two actions while
the SDK's `select_notes_with_fee` charges per selected note (fee = 40M + 37.07M·n credits at the
current protocol), so five notes cost about twice what Confirm shows (≈ +0.0011 DASH). Platform-address
and Identity spends carry no maximum fee in their state transition: drive meters the fee while it
executes them, so no SDK can bind it without a protocol change; only `estimate_min_fee` (rs-dpp) is
known in advance. Android (dash-wallet#1680) shows an exact fee for Core, "~" for Shielded and the
asset-lock routes, and "—" with Max off for the Platform and Identity sources.

## Decision drivers

- Quality goal 1, funds safety: the holder never pays more than Confirm says without being told it
  is an estimate (AC-01, AC-08 in the [feature summary](../features/external-send/README.md)).
- The binding has to come from the layer that selects inputs and builds the transition
  (dashpay/platform `packages/swift-sdk/CLAUDE.md`: wrappers marshal, Rust decides), not from a second estimator in
  the app.
- Parity with Android where the protocol gives no better answer.
- Fee and total on Confirm within 3 s for every source; AC-01b: a failed estimate blocks
  Confirm with a retry.

## Considered options

1. **Bind Core and Shielded, mark the rest "~"** — Core → Core and BIP70 stay prepared at Continue;
   Shielded spends get an SDK call (platform PR) that selects the notes, returns the exact fee and
   runs that plan or refuses when it no longer holds; asset-lock, Platform-address and Identity fees
   show as "~" estimates and Max stays, sized with the estimate.
2. **Exactly like Android** — no platform change: Shielded "~" from the two-action estimate,
   Platform and Identity sources show "—" and lose Max.
3. **"~" everywhere but Core, client-side note count** — the app reproduces the SDK's note selection
   to price Shielded closer, still unbound; Max kept.
4. **Keep ADR-0039 and bind every credit route** — needs a maximum-fee field in the address and
   identity transitions, a consensus change outside this feature.

## Decision outcome

**Chosen:** option 1. It keeps ADR-0039's promise where the protocol allows it — Core and, through the
SDK, Shielded, where the overrun was largest — and tells the truth everywhere else, as Android does,
without taking Max away from the Platform and Identity sources. ADR-0039's flow stays: estimate on
Send, authenticate and prepare at Continue, Confirm shows the prepared figure and its tap only sends;
a prepared figure that no longer fits sends the holder back to Send.

## Consequences

**Positive**
- Confirm never presents an estimate as the amount charged.
- Shielded spends, the largest overrun, become exact and refuse instead of overcharging when the
  notes changed between Continue and Confirm.
- The note selection lives once, in rs-platform-wallet.

**Negative**
- A platform PR (rs-platform-wallet + FFI + Swift) and a `.platform-ref` bump before the app can
  use it; the feature now ships with the platform release that carries it.
- Platform-address and Identity spends can still cost more than the "~" figure; Max on those routes
  keeps a margin, so a little stays behind.
- Confirm gets a second fee style ("~") and its wording.

**Neutral**
- A protocol issue for a maximum fee on address and identity transitions can be filed separately;
  if it lands, this ADR is superseded for those routes.
- Asset-lock routes stay "~": the L1 fee is chosen by coin selection at Confirm, and the pool-sized
  estimate is designed to stay above it.

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Review: [dashpay/dashwallet-ios#1358](https://github.com/dashpay/dashwallet-ios/pull/1358)
- Related ADR: supersedes [ADR-0039](0039-estimate-the-fee-on-send-and-recompute-it-on-confirm.md); extends the platform surface of [ADR-0036](0036-ship-the-ios-screens-and-the-sdk-binding-as-two-surfaces.md)
