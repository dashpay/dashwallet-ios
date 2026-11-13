# 0035 — Bound an unresolved publish by 24 hours of proved Platform block time

- **Status:** Proposed
- **Date:** 2026-11-13
- **Deciders:** romchornyi, with Claude during the design pass

## Context

A publish whose document the wallet does not know must stop being unresolved at some point, or a failed publish would keep its response "not removed" and its row marked forever (spec AC-06). Once a publish is resolved, a lookup that finds nothing records the response removed — so resolving too early brings back the defect of #1374. The spec proposed 24 hours by the device clock (spec §8, question 2); the wallet already judges an App Connect request's age by the block time Platform proved, never by the device clock (ADR-0020).

## Decision drivers

- Spec AC-03: no response is recorded removed while its publish may still land.
- Spec AC-06: a publish older than the bound, or one with no recorded start, is resolved, and an absent response is then recorded removed.
- Spec §6 NFR: 24 h from the start.
- Precedent ADR-0020: request age and expiry come from proved Platform block time, which the wallet user cannot move.

## Considered options

1. **24 h of proved Platform block time** — the start is the `platformTime` of the identity snapshot the approval read before publishing; "now" is the `platformTime` of the snapshot the deciding operation read. Without a fresh block time the publish stays unresolved.
2. **24 h by the device clock** — start and now from the injected `now()`.

## Decision outcome

**Chosen:** option 1, by the owner's choice over the spec's default. A device clock moved forward would resolve a publish early and let a lookup miss record its response removed — exactly the defect this feature closes — while proved block time cannot be moved by the device, and every operation that decides (approval, disconnect, Connections refresh) already reads an identity snapshot carrying it.

## Consequences

**Positive**
- Turning the device clock forward cannot resolve a publish early.
- Matches how the wallet already judges request age (ADR-0020); no new time source.

**Negative**
- Overrides the spec's "by the device clock" (spec §1, §6, CONTEXT "unresolved publish"); the spec and glossary are patched to match.
- The start is the block time of the read before the submit, so the window opens up to that read's age earlier than the submit; with a 24 h bound this is seconds to minutes.
- An operation whose snapshot has no block time treats every recorded publish as unresolved, so a refresh that cannot read Platform resolves nothing.

**Neutral**
- `AppConnect.isPublishUnresolved(_:platformTime:)` is pure; tests pass block times directly instead of an injected clock.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0034](0034-record-the-publish-start-on-the-connection-intent.md); [ADR-0020](0020-judge-request-age-and-expiry-by-proved-platform-block-time.md)
- Issue: #1374
