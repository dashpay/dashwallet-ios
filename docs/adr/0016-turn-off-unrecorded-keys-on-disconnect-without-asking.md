# 0016 — Turn off unrecorded keys on disconnect without asking

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author), the product owner (disconnect is all or nothing)

## Context

An identity can hold keys of an app that this wallet has no record of giving: keys added from
another device, keys from before a restore, and DashPay profile keys no connection accounts for.
#1301 turned them off only after a second question ("Turn them off?") once the disconnect had
run. The product owner decided that a disconnect turns off everything that may give the app
access, in one step.

## Decision drivers

- The product owner's decision: disconnect is all or nothing.
- A second question after a disconnect is a decision the user should not have to make, and a
  "Leave them" answer leaves access behind.

## Considered options

1. **Automatic.** Every disconnect plan includes the live keys bound to the app's contracts that
   no record names and every DashPay profile key no connection accounts for. The question, its
   texts and `unrecordedKeysLeft` go.
2. **Keep the question**, as #1301 had it.

## Decision outcome

**Chosen:** option 1.

## Consequences

**Positive**
- One step and no question; nothing is left on by a "Leave them" tap.

**Negative**
- It differs from the Android wallet, which only reports such keys.
- A key of a contract the app shares with another app, or a profile key another wallet relies on,
  is turned off without a question.

**Neutral**
- A key whose bound the wallet cannot tell yet is still not turned off; the disconnect reports it
  as not checked and keeps the connection listed.
- Profile keys no connection accounts for get no row while some connection on the identity can be
  disconnected. On an identity with none, they stand as a "DashPay" row of their own, so they can
  always be turned off.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0015](0015-fence-a-pending-sign-in-on-disconnect.md)
- PR: #1334; issue #1305
