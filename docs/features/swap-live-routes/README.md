# Live route availability in the swap coin picker

**Owner:** romchornyi · Introduced in [#1297](https://github.com/dashpay/dashwallet-ios/pull/1297)

## Why

The Dash DEX coin picker labelled each coin with its provider (NEAR, Maya or Multiple) from the
providers' published coin lists. Those lists say what a provider can carry in principle, not what it
carries now. When NEAR's DASH leg went down and Maya halted BTC and ETH, the picker kept offering
every coin with the old labels. A holder who picked one and typed a valid address was told to
"check your connection", with Continue disabled: the swap aggregator had answered "no route", and
the address screen reported every refusal as a connection problem.

## What changed

- **Live labels.** While the picker is on screen, each coin is checked with a small quote per
  provider and direction, with no address in it. Both providers route → "Multiple", one → that
  provider, none → the existing halted row and toast. Buy follows the same rule; Buy routes through
  NEAR only. See [ADR-0010](../../adr/0010-probe-live-swap-routes-with-address-free-forced-quotes.md).
- **One shared store.** The answers live in one in-memory store that the picker, the address screen
  and the quote paths read: a conclusive answer is re-checked after 10 minutes and forgotten after
  30, an inconclusive one is never stored and is re-asked after 2 minutes. See
  [ADR-0011](../../adr/0011-keep-live-swap-route-answers-in-one-shared-in-memory-store.md).
- **NEAR outages cost a few checks.** NEAR is checked on sentinel coins first: BTC and ETH, and SOL
  whenever those two settle neither outcome. Two "no route" answers and none routing → NEAR is down
  for that direction and no per-coin NEAR checks are sent. Maya is checked per coin, since its halts are per chain. See
  [ADR-0012](../../adr/0012-detect-a-near-outage-from-sentinel-coins.md).
- **The address screen names the real problem.** A refused address gets the address copy; a "no
  route" is re-checked without the address and, when confirmed, says "<coin> can't be swapped at the
  moment"; "check your connection" is shown only when no response came back; an answer the wallet
  cannot read says "The swap service isn't responding. Please try again later." (the one new string).
- **Quotes follow the live state.** The amount and confirmation quotes no longer ask a provider the
  store has just seen halted or without a route.

## What it guarantees

- A coin is shown halted and cannot be picked when the stored answers rule out every provider that
  can carry it and the published token lists name it; a provider with no stored answer counts as usable.
- An inconclusive answer is not stored and never halts a coin by itself; an earlier conclusive answer
  keeps applying until a new one replaces it or it expires (30 minutes).
- At most two checks are in flight; periodic checks start only while the picker is open (one already
  asked may finish after it closes), and the address screen re-checks a "no route" once without the
  address. The route checks and that re-check send no address; the address screen's own quote and
  the amount and confirmation quotes send the entered address.

## Not in scope

- Providers other than NEAR and Maya.
- The Android wallet, which keeps its static labels.
- The answers are not persisted: after a relaunch every coin is checked again.
