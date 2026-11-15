# 0050 — Bound an unresolved publish by 48 hours of proved Platform block time

- **Status:** Proposed
- **Date:** 2026-11-13 (bound raised from 24 h to 48 h in the architecture review of 2026-11-14)
- **Deciders:** romchornyi, with Claude during the design pass

## Context

A publish whose document the wallet does not know must stop being unresolved at some point, or a failed publish would keep its response "not removed" and its row marked forever (spec AC-06). Once a publish is resolved, a lookup that finds nothing records the response removed — so resolving too early brings back the defect of #1374. The spec proposed 24 hours by the device clock (spec §8, question 2); the wallet already judges an App Connect request's age by the block time Platform proved, never by the device clock (ADR-0020).

What actually ends a publish on Platform is not a time. A document create is a batch transition signed with the identity's next nonce for the contract. Platform accepts it while that nonce is unused and within its window of recent nonces (`identity_nonce.rs` in platform's rs-dpp), so it stays valid until the identity sends enough other transitions on that contract, and a transition that fails still uses its nonce. A node drops an unconfirmed transition from its mempool after a TTL, which dashmate sets to 24 h for mainnet and testnet (`ttlDuration: '24h'` in its mainnet and testnet config defaults; the base default `'0s'` means no TTL), and an operator can change it.

## Decision drivers

- Spec AC-03: no response is recorded removed while its publish may still land.
- Spec AC-06: a publish older than the bound, or one with no recorded start, is resolved, and an absent response is then recorded removed.
- Precedent ADR-0020: request age and expiry come from proved Platform block time, which the wallet user cannot move.
- The bound must not close before the nodes' mempool TTL does.

## Considered options

1. **48 h of proved Platform block time** — the start is the `platformTime` of the identity snapshot the approval read before publishing; "now" is the `platformTime` of the snapshot the deciding operation read. Without a fresh block time the publish stays unresolved.
2. **24 h of proved Platform block time** — as option 1 with the spec's day. It equals the mempool TTL, while the start is read before the submit and a node counts its TTL by its own clock, so the window can close before the node drops the transition.
3. **24 h by the device clock** — start and now from the injected `now()`.
4. **Resolve by the nonce** — store the publish's nonce and read the identity's proved contract nonce: once it is used, one lookup decides. Not possible with the pinned SDK: its document create picks the nonce inside Rust and does not return it.

## Decision outcome

**Chosen:** option 1. Proved block time cannot be moved by the device, and every operation that decides (approval, disconnect, Connections refresh) already reads an identity snapshot carrying it. Twice the mempool TTL covers the read's age before the submit and a node clock ahead of the block time. Option 4 is the exact answer and is followed up in platform (see Links).

## Consequences

**Positive**
- Turning the device clock forward cannot resolve a publish early.
- Matches how the wallet already judges request age (ADR-0020); no new time source.

**Negative**
- Overrides the spec's "by the device clock" (spec §1, §6, CONTEXT "unresolved publish"); the spec and glossary are patched to match.
- A time bound is not a guarantee: a transition whose nonce is still unused stays valid after every node dropped it, so whoever holds its bytes could broadcast it again later. Only option 4 closes this.
- A publish that times out keeps its response's row marked for up to 48 h when nothing is found.
- An operation whose snapshot has no block time treats every recorded publish as unresolved, so a refresh that cannot read Platform resolves nothing.

**Neutral**
- `AppConnect.isPublishUnresolved(_:platformTime:)` is pure; tests pass block times directly instead of an injected clock.
- A publish that failed for good is not bounded by time at all: its start is cleared (ADR-0049).

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0049](0049-record-the-publish-start-on-the-connection-intent.md); [ADR-0020](0020-judge-request-age-and-expiry-by-proved-platform-block-time.md)
- Issue: #1374; follow-up in platform: dashpay/platform#5927
