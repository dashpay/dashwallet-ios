# 0035 — Model Receive options as a Receive-only enum

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** Roman Chornyi (owner), with Claude during the design pass. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

Receive offers its options from `PaymentsLandingViewModel.receiveNetworks`, a list of `ChainNetwork` values (`core`, `platform`, `shielded`), and a Receipt names its option through `ReceiveReceipt.rail: ChainNetwork`. `ChainNetwork` is shared by 21 files: Home's balance rows, the Send toggle, and Internal transfer, which lists its endpoints from `ChainNetwork.allCases`. The feature adds Identity as a fourth Receive option (spec AC-01). The Current identity is not a chain and not one of the wallet's balances in those screens, and spec §3 keeps Identity out of Send and out of any new entry into Receive.

## Decision drivers

- Identity appears on Receive and nowhere else (spec §3 non-goals: no Send to an Identity ID, no new way into Receive).
- Correct identity, always — §1 quality goal 1: a Receipt names the option it was raised on and is never confused with a Platform one.
- Repo guardrail 7 (`CLAUDE.md`): a type's name matches its behaviour — `ChainNetwork` names a chain.
- Size S: the change stays inside `UI/Payments/Landing`.

## Considered options

1. **A Receive-only enum** `ReceiveOption` {core, shielded, platform, identity}: the three chain options map to `ChainNetwork`, identity maps to none; the option row, the selection, the card and `ReceiveReceipt` use it.
2. **Add `identity` to `ChainNetwork`** — fewest new types, but every exhaustive `switch` and every `allCases` in the 21 files has to exclude it by hand, starting with Internal transfer's endpoint list.

## Decision outcome

**Chosen:** option 1, a Receive-only `ReceiveOption` enum that maps its chain cases to `ChainNetwork`. It keeps Identity out of Send, Home and Internal transfer by construction rather than by filters each future call site must remember, and it confines the change to the Receive files.

## Consequences

**Positive**
- `ChainNetwork` and its 21 users do not change; `ChainNetwork.allCases` keeps meaning «chains».
- The compiler lists every Receive place that has to handle `identity` (its exhaustive `switch`es).
- `ReceiveReceipt.rail` says which Receive option a Receipt came from, including Identity.

**Negative**
- Receive code gains a mapping (`ReceiveOption` → `ChainNetwork?`) and the selected-option property changes type; Home and the other callers that open Receive on a given chain pass through that mapping.
- Two enums with three overlapping cases: a reader has to know which one a screen uses.

**Neutral**
- If Send later pays to an Identity ID (spec §8 open question), that is its own decision; this ADR does not make Identity a chain.

## Links

- Feature summary (acceptance criteria and known limits): [identity-receive](../features/identity-receive/README.md)
- Android counterpart: [dashpay/dash-wallet#1677](https://github.com/dashpay/dash-wallet/pull/1677)
- Related ADR: [0034 — Subtract own top-ups via a typed top-up event](0034-subtract-own-top-ups-via-a-typed-top-up-event.md)
