# 0052 — Refuse "response removed" at its one write point while the publish is unresolved

- **Status:** Proposed
- **Date:** 2026-11-13
- **Deciders:** romchornyi, with Claude during the design pass

## Context

Several paths record a response removed: a disconnect whose lookup found nothing (`deleteResponses`), a failed delete followed by a lookup miss (`markRemovedIfGone`), and now the Connections refresh (spec AC-06). Each one deciding on its own is how a lookup miss after a publish timeout became "removed for good" (#1374). All of them already end in `markResponseRemoved` (`PlatformDashConnectDataSource.swift:2308`).

## Decision drivers

- Spec AC-03: no operation records a response removed while its publish is unresolved.
- Spec AC-02: the disconnect must know that it kept a response not removed, to tell the wallet user.
- Spec §6 NFR: 0 responses recorded removed while unresolved, enforced by a seam test.

## Considered options

1. **One guarded write point** — `markResponseRemoved` asks the pure `AppConnect.isPublishUnresolved(_:platformTime:)` (ADR-0050) and refuses while it holds, returning that it kept the response; callers report the refusal instead of re-checking.
2. **A check in every caller** — each path asks the predicate before calling `markResponseRemoved`.

## Decision outcome

**Chosen:** option 1. The invariant holds by construction for every present and future caller, and one seam test on the write point covers it; the refusal it returns is what the disconnect turns into its note.

## Consequences

**Positive**
- A new path cannot forget the check; the bug class cannot return through a new caller.
- The disconnect's "response may still appear" comes from the write point's answer, not a second evaluation that could disagree.

**Negative**
- The write point needs the deciding operation's Platform block time, threaded through every caller.

**Neutral**
- Every path that finds a response records its `responseDocumentId` before deleting it, which ends the unresolved state, so a found response is deleted and recorded removed as before (spec AC-11).
- Only refusals on the disconnected app's own intents set the disconnect's note; refusals on another app's intent reached through `responsesLeft` are logged and shown on that app's row (spec AC-02).

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0050](0050-bound-an-unresolved-publish-by-24-hours-of-proved-platform-block-time.md)
- Issue: #1374
