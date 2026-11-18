# 0037 — Cast Quick voting sequentially under one authentication

- **Status:** Proposed
- **Date:** 2026-11-04
- **Deciders:** romchornyi, with Claude during the design pass

## Context

Quick voting approves the request submitted first under every filtered name, from every ticked masternode (AC-18) — for example 100 names × 2 masternodes = 200 votes from one action, each a network call to Platform. Today `MasternodeVoteCaster.cast` authenticates once per contest and then casts from each node in turn, all on the main actor. We had to decide how a run of many votes is sent.

## Decision drivers

- Vote safety: no masternode ever goes over the vote limit, and an existing block or approve is never replaced (SAD §1 QG-1; AC-19).
- Votes from one masternode use its identity nonce (a counter each new state transition must increase); concurrent casts from one masternode can collide and be refused.
- One explicit confirmation for many votes (spec §6.1); the outcome reported once (AC-14b).

## Considered options

1. **Sequential under one authentication** — one `AuthenticationGate` prompt, then name by name and masternode by masternode through the existing caster, re-checking the limit and recording each landed vote before the next.
2. **Parallel per masternode** — one authentication; each ticked masternode runs its own sequential stream, and the streams run at the same time in a task group.

## Decision outcome

**Chosen:** Option 1. It cannot collide on a nonce or race the vote-limit count, and it is a loop over the caster we already have; speed matters less than never sending a wrong or excess vote.

## Consequences

**Positive**
- The vote limit is re-checked against the history after every landed vote, so AC-19 holds even if a run is interrupted and retried.
- No change to the caster's concurrency model (main actor).

**Negative**
- Slow: 200 votes at 1–3 s each take several minutes; progress must be shown.
- If the app goes to the background or the screen is left, the run stops; votes not yet sent are reported as not cast and are covered by "Try again" (AC-06b).
- Stopping is cooperative: the one masternode broadcast in flight when the screen is left still finishes. A voting screen reopened at once has its own store and does not know about it, so its first vote can overlap that broadcast from the same masternode. Accepted (review-2026-11-10j, finding 6): the window is one broadcast long, and no process-wide "vote in flight" flag is added for it.

- Each broadcast runs on the main actor: the pinned SwiftDashSDK's `castContestedResourceVote` calls the FFI synchronously there (dashpay/platform#5875). During a run the screen does not respond while a broadcast is in flight, and the progress, Back and the stop on going to the background take effect only between broadcasts.

**Neutral**
- Switching to parallel streams later needs the caster off the main actor and a synchronised vote-limit count.

## Links

- Feature summary: [docs/features/username-voting/README.md](../features/username-voting/README.md)
- Related ADR: [0035 — Run every vote through a pure vote-attempt state machine](0035-run-every-vote-through-a-pure-vote-attempt-state-machine.md)
