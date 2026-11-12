# 0034 — Subtract own top-ups via a typed top-up event

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** Roman Chornyi (owner), with Claude during the design pass. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

The Identity option raises a Receipt when the Current identity's credits rise above the Starting balance (spec AC-05), because Platform gives the wallet only the identity's balance, not a list of incoming transfers (spec §6.1). The wallet can raise the same balance itself: an identity top-up from Internal transfer or from the identity profile, both run by `IdentityTopUpViewModel.topUp`, and the top-ups `DWIdentityRegistrationCoordinator` makes for an existing identity before registering another username or buying a name. Spec AC-06 says such a top-up raises no Receipt and moves the Starting balance up with it; AC-08 says credits from a Payer that land while Internal transfer or Share covers the card still raise a Receipt at the first successful check after the gap. The top-up path and the Receive watcher are in different modules (`UI/Payments/InternalTransfer`, `UI/DashPay/Profile` and `UI/Payments/Landing`) and share no signal today; the only post after a balance refresh is the DashPay-named `DWDashPayRegistrationStatusUpdatedNotification`, which carries no amount. Simply taking a fresh Starting balance once Internal transfer closes is ruled out by AC-08: it would absorb a Payer's credits that landed meanwhile.

## Decision drivers

- No fake or early Receipt — spec §6.1 abuse case, §1 quality goal 1.
- No lost Receipt for a Payer's credits that land during a gap — spec AC-08.
- Repo guardrail 5 (`CLAUDE.md`): new state gets a new typed publisher or notification, never a re-post of another system's notification name.
- Repo guardrail 4: no new `static let shared` without a reason.

## Considered options

1. **A typed top-up event** — after a successful top-up, the top-up path posts a new `IdentityTopUpDidComplete` notification carrying the wallet, the network, the identity and the credits the top-up added; the Identity watcher raises its Starting balance by that amount, whether or not the card is covered at that moment.
2. **An in-memory ledger of own top-ups** — the top-up path records each top-up in a shared registry that the watcher reads on every check. Same information as option 1, pulled instead of pushed, at the cost of a new shared object.
3. **The typed event plus a registry of top-ups in flight** — option 1, and the top-up path also registers each top-up in a shared `IdentityTopUpsInFlight` from before the SDK call until after the event is posted or the call throws. While a top-up of the watched identity is in flight, the watcher raises no Receipt and takes no Starting balance. Platform raises the balance before the top-up call returns, so option 1 alone shows a check in that window as «Received» (PR #1344 review, review-2026-11-10-r3 Q1).

## Decision outcome

**Chosen:** option 3, a typed `IdentityTopUpDidComplete` event that the watcher subtracts from future increases by raising its Starting balance, plus a registry of top-ups in flight that holds the Receipt decision until that event arrives. The event carries the balance the top-up's transition returned and the credits it was handed, and the watcher sets its Starting balance to the lower of that balance and its Starting balance plus those credits: a delta over the whole top-up would be cut by a spend from elsewhere while it ran, which the watcher has already subtracted, and the top-up would come back as a Receipt (review-2026-11-11-r1 S1). The event alone (option 1) left the window between Platform raising the balance and the top-up call returning, in which a check took the own top-up for a payment and ended the watch. The registry is shared because a top-up can start before the Receive screen that watches its identity exists (the username flow closes while its top-up still runs); that is the reason guardrail 4 asks for, and the watcher takes it injected. The event stays a new, typed name rather than a re-post of the DashPay registration notification.

## Consequences

**Positive**
- A top-up from this wallet raises no Receipt, wherever it was started and whether a check sees its rise before or after it is announced: Internal transfer and the profile sheet run `IdentityTopUpViewModel.topUp`, and the registration coordinator's shortfall and name-purchase top-ups and the asset-lock recovery's top-up retry run through `IdentityTopUpDidComplete.announcing`; each is in flight while it runs and posts the event (the retry only when its lock row is stored, as the lock's value bounds the credits).
- A Payer's credits seen while an own top-up runs are not lost: the Receipt waits, and the event raises the Starting balance only by the top-up's credits.
- A Payer's credits that land while Internal transfer covers the card still raise a Receipt after it closes.
- Other future listeners (for example, a History entry for an own top-up) can use the same event.

**Negative**
- Every top-up path gets a new outgoing contract: a top-up of an existing identity that neither runs `IdentityTopUpViewModel.topUp` nor goes through `IdentityTopUpDidComplete.announcing` raises a false Receipt.
- A new process-wide object, `IdentityTopUpsInFlight.shared`. A top-up that is in flight when the Identity option is opened delays the Starting balance until it ends, so the card says it is watching a little later.
- The event carries the transition's own balance, so a Payer's credits that land between the watcher's last check and the end of the top-up are in it. The Starting balance moves by at most the credits the top-up was handed, so at most the top-up's fee worth of them raises no Receipt (sad.md §11).
- A top-up that throws after Platform carried it out posts nothing; once it leaves the registry, its rise shows as «Received» (accepted limit, spec §6.1).

**Neutral**
- A top-up of the same identity from another device holding the same recovery phrase still shows as «Received» — an accepted limit in spec §6.1 that this event cannot see.

## Links

- Feature summary (acceptance criteria and known limits): [identity-receive](../features/identity-receive/README.md)
- Android counterpart: [dashpay/dash-wallet#1677](https://github.com/dashpay/dash-wallet/pull/1677)
- Related ADR: [0035 — Model Receive options as a Receive-only enum](0035-model-receive-options-as-a-receive-only-enum.md)
