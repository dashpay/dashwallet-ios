# 0038 — Let only the voting store write the remembered node choice

- **Status:** Proposed
- **Date:** 2026-11-12
- **Deciders:** romchornyi, with Claude, after a review of #1347

## Context

The masternodes a vote uses are a standing privacy choice the user makes once (AC-12, AC-14) and the app keeps (`VotingStore.selectedNodeIDs`, persisted). The list of this wallet's votable nodes is an observation that can be unavailable (SDK starting, masternode list not synced) or partial (a provider pool unreadable, `mayBeIncomplete`). Two places settled the remembered choice against what they saw and saved the result: `VotingStore.refreshVotableNodes()` and `VotingKeysViewModel.rowsChanged()`. An empty observation was already guarded, but a partial non-empty one still saved a smaller choice for good, so the next vote silently used fewer masternodes. The PR reviewer named the shared cause and suggested one owner for the choice.

## Decision drivers

- Vote safety and the standing choice: a vote never uses masternodes the user did not choose, and a choice is not changed behind the user's back (SAD §1 QG-1; spec AC-12, AC-14).
- The node list can be unavailable or partial at any time; this is outside the app's control (SAD §11, dashpay/platform#5872).
- One owner of shared voting state, with per-screen view models reading it (ADR-0014).

## Considered options

1. **Guard each settling site** — keep both settlers and add a completeness check to each (`!mayBeIncomplete` in the store, a completeness flag passed into the keys view model).
2. **One owner of the remembered choice** — `VotingStore` is the only writer; it exposes the resolution as unavailable / partial / complete; only a complete resolution forgets a remembered node that is no longer votable; the keys screen sends single tick changes, and removing a key forgets that node explicitly. A vote uses the remembered nodes that resolved.

## Decision outcome

**Chosen:** Option 2. Option 1 fixes the partial case but leaves two independent rules that each new observation shape (or a new screen) must patch again — the reviewer saw this class of bug in two rounds. Option 2 separates the user's intent (remembered choice) from the observation (resolved nodes), so no observation can shrink the intent, and a removal is only forgotten when it is proven (complete list) or done by the user.

## Consequences

**Positive**
- A partial or unavailable node list never changes the saved choice; a node that comes back votes again without the user re-ticking it.
- `selectedNodeIDs` is `private(set)`: writes go through `confirmVotingSetup(ticked:)`, `setTick(_:_:)` and `forgetNode(_:)`, which name the user act behind each change.
- The keys screen no longer decides what an absent row means; in manage mode it shows the store's ticks.

**Negative**
- A node revoked while the list stays partial stays remembered until a complete resolution; it is not used for votes meanwhile (`tickedNodeIDs` intersects with the resolved nodes), but it is kept in preferences longer.
- "Add your voting keys" confirmed from a partial list keeps remembered nodes it did not show (`confirmVotingSetup` keeps the unseen ones), so the user cannot drop a node they cannot see.
- The single-row auto-tick in manage mode is saved only from a complete list; on a partial one it is shown but not kept.

**Neutral**
- `VotingKeysSource` gains `nodeResolution` and `setTick(_:_:)` in place of `saveTicks(_:)`; the tests' fake source mirrors the store's intersection.
- Quick voting is unaffected: it reads `tickedNodeIDs` and stays off while the list may be incomplete.

## Links

- Feature summary: [docs/features/username-voting/README.md](../features/username-voting/README.md)
- Related ADR: [0014 — Split voting state into a shared store and per-screen view models](0014-split-voting-state-into-a-shared-store-and-per-screen-view-models.md)
