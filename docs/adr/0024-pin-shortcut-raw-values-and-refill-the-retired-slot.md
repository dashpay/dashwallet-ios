# 0024 — Pin shortcut raw values and refill the retired slot

- **Status:** Proposed
- **Date:** 2026-11-05 (decision taken 2026-10-30, recorded retroactively)
- **Deciders:** romchornyi (author)

## Context

The Home shortcut bar is saved in `DWGlobalOptions.shortcuts` as an array of `ShortcutActionType` raw `Int` values. The removed `.crowdNode` case was 18. If it is deleted from an implicitly numbered enum, every later case (Coinbase, Uphold, Explore and the rest) shifts down by one, and saved bars show the wrong buttons. A saved 18 also has to become something, or `compactMap` drops it and the bar shrinks or resets.

## Decision drivers

- Same bar: other buttons stay in place, the retired slot gets an action the bar doesn't show yet, the bar keeps its size.
- Same actions: buttons after CrowdNode in the list keep their action.
- No duplicates: the update adds no button already on the bar when another one is free.

## Considered options

1. **Pin and refill** — give every case after the removed one an explicit raw value (`coinbase = 19` …), retire 18 for good, and let `ShortcutActionType.restoredBar` fill a saved 18 with the first action the bar doesn't show yet (Spend, the faucet on testnet, then Explore, Receive…).
2. **Reset to defaults** — on a saved 18, discard the saved bar and show the default shortcuts.
3. **Drop the slot** — pin raw values but skip a saved 18, so the bar has one button less.

## Decision outcome

**Chosen:** Option 1. It is the only option that keeps both the same bar (same size) and the same actions. Option 2 throws away the Wallet holder's customisation, and Option 3 changes the bar's size. Android does the same with its id 10: the id is reserved and its refill logic fills the slot (dash-wallet #1664).

## Consequences

**Positive**
- Saved bars survive the upgrade unchanged apart from the retired slot.
- Restoring a bar is one pure function, `restoredBar`, which `ShortcutActionTypeTests` covers.

**Negative**
- Raw value 18 is a permanent gap; reusing it would silently turn old CrowdNode slots into the new action.
- The explicit numbering has to be kept when cases are added later.

**Neutral**
- Duplicates that the existing availability fallbacks can produce on their own are a separate ticket.

## Links

- Pull request: [dashpay/dashwallet-ios#1268](https://github.com/dashpay/dashwallet-ios/pull/1268)
- Android counterpart: [dashpay/dash-wallet#1664](https://github.com/dashpay/dash-wallet/pull/1664)
- Related ADR: [0023 — Remove CrowdNode entirely, as Android does](0023-remove-crowdnode-entirely-as-android-does.md)
