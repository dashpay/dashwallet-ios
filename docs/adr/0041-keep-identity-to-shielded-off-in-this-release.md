# 0041 — Keep Identity to Shielded off in this release

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** Roman Chornyi (owner), with Claude during the design pass. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

An earlier design decision switched Identity → someone else's Shielded address on with the SDK pin:
the commit that moves `.platform-ref` to an SDK with the binding of
[ADR-0036](0036-ship-the-ios-screens-and-the-sdk-binding-as-two-surfaces.md) would add the call and
enable the pair. Working out the SDK interface then showed that for this pair the fee is known on
Confirm only as a lower bound (the exact fee is counted when Platform runs the payment), nothing can
be prepared before the Confirm tap, and a rejection after the payment is handed to Platform does not
prove the credits stay. While designing the screens, the owner decided the pair stays unavailable in
this release.

## Decision drivers

- Funds safety: no payment may be left in doubt over its fee or outcome.
- [ADR-0039](0039-estimate-the-fee-on-send-and-recompute-it-on-confirm.md): the fee shown on Confirm
  is the fee the send uses; this pair cannot meet that.
- [ADR-0040](0040-report-three-send-outcomes-and-retry-only-when-nothing-left-the-source.md): doubt
  resolves to `inFlight` with no Retry; for this pair a rejection after handover would land there
  too, an outcome the screens have no design for beyond a Toast.
- AC-06 in the [feature summary](../features/external-send/README.md): an unavailable pair stays
  visible with its reason (Identity → any Shielded address "for as long as the Wallet app cannot
  make that payment yet").
- `CLAUDE.md` guardrail 3: a missing capability disables the control, no stub that pretends to act.

## Considered options

1. **Switch on with the SDK pin** — the pin bump adds the call and flips the policy row; Confirm
   shows the estimate as the fee, which is only a lower bound.
2. **Switch on with the SDK pin, with a lower-bound fee on Confirm** — Confirm shows "at least X"
   for this pair, ADR-0039 gets an exception, and a rejection after handover maps to `inFlight`;
   needs a new Confirm variant that is not in the design.
3. **Keep the pair off in this release** — the policy row stays "not supported yet" even after the
   pin moves and the app has no call site; the SDK binding is still built in this feature
   (ADR-0036), and a later decision switches the pair on.

## Decision outcome

**Chosen:** option 3, Identity → someone else's Shielded address stays unavailable in this release,
with its reason in Select source (AC-06), even after `.platform-ref` points at an SDK with the
binding. Option 1 breaks ADR-0039 by showing a fee that may not be the one paid, and option 2 needs
a Confirm design and an outcome mapping that do not exist yet; both trade funds safety for one pair
out of sixteen. The binding stays in scope per ADR-0036, so switching the pair on later is an app
change only.

## Consequences

**Positive**
- No payment is left in doubt over its fee: every pair that sends meets ADR-0039 without exceptions.
- No Confirm variant and no extra outcome mapping in this release; the policy row and the absence
  of a call site are the same as before the pin bump.
- How to report a rejection after handover no longer blocks this release; it moves to the
  switch-on decision.

**Negative**
- 15 of 16 pairs send at release; the goal that every pair is handled is met for this pair only by
  showing its reason.
- The SDK binding ships in the platform repository with no consumer in the app; its own tests are
  the only proof it works until the pair is switched on, so it can rot unnoticed.
- Switching the pair on needs an app release and a new ADR that settles the Confirm fee display
  and the outcome after handover.

**Neutral**
- The `.platform-ref` bump no longer changes product behaviour for this pair; it still follows the
  `CLAUDE.md` "Platform release pin" rule.

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Android counterpart: [dashpay/dash-wallet#1680](https://github.com/dashpay/dash-wallet/pull/1680)
- Related ADRs: [0036 — Ship the iOS screens and the SDK binding as two surfaces](0036-ship-the-ios-screens-and-the-sdk-binding-as-two-surfaces.md), [0038 — Decide every source and destination pair in one policy](0038-decide-every-source-and-destination-pair-in-one-policy.md), [0039 — Estimate the fee on Send and recompute it on Confirm](0039-estimate-the-fee-on-send-and-recompute-it-on-confirm.md), [0040 — Report three send outcomes and retry only when nothing left the source](0040-report-three-send-outcomes-and-retry-only-when-nothing-left-the-source.md)
