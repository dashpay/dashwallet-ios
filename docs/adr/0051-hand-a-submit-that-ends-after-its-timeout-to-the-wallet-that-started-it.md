# 0051 — Hand a submit that ends after its timeout to the wallet that started it

- **Status:** Proposed
- **Date:** 2026-11-13
- **Deciders:** romchornyi, with Claude during the design pass

## Context

`AppConnectWriteExecutor` races the submit against a timer; when the timer wins it returns `timedOut`, cancels the submit without awaiting it, and drops its late result (`AppConnectWriteExecutor.swift:36-40`, `Race.finish`). The SDK submit ignores cancellation, so the publish may still create its document; the id is written to a `SharedValue` nobody reads after `publishAndRecord` returns. The spec requires that a publish returning its document while the app runs is recorded at once on the intent of the wallet that started it, whichever wallet is active then, and dropped if that wallet was wiped (AC-09, AC-10). Intent writes rely on running inside the wallet's operation gate (`PlatformDashConnectDataSource.swift:1045-1047`).

## Decision drivers

- Spec AC-09, AC-10: record a late document at once, only on the starting wallet.
- ADR-0018: every App Connect write is logged and judged in one place.
- `AGENTS.md` guardrail 1: no copy-then-adapt of the race logic.
- Seam tests: the late outcome must be drivable with the injected sleep, without a network.

## Considered options

1. **A late-outcome handler on the executor** — `run` takes an optional handler; a submit that finishes after the timeout is logged and its outcome passed to it; the document id comes from the publish closure's `created` value, which the late submit filled. The data source binds the handler, when the publish starts, to the starting wallet's id, and records the document through `operationGate.run(for:)` of that wallet into its pinned intent store; no intent there (wallet wiped) → dropped.
2. **The data source awaits its own submit task** — the executor stays as is; the publish closure's task is kept by the data source and awaited after `timedOut`.

## Decision outcome

**Chosen:** option 1. The late result stays inside the executor that already owns the race and the write log, and reaches only the starting wallet's store through that wallet's own gate, so it cannot interleave with another operation's read-modify-write.

## Consequences

**Positive**
- One place logs a write's start, outcome and late outcome (ADR-0018 kept).
- The wallet binding is fixed at publish start, so a wallet switch cannot redirect the result.

**Negative**
- The executor now has work that outlives `run`; a late handler queued behind a long operation of the same wallet records later than "at once" by that operation's length.
- ADR-0018 (Proposed) is amended: "after a timeout the next read decides" becomes "a read that finds no response while the publish is unresolved decides nothing, and a submit that ends after its timeout is reported, not dropped".

**Neutral**
- If the app is killed before the submit returns, nothing is recorded in-process; the Connections refresh lookup covers that case (spec AC-05, AC-07).

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [ADR-0018](0018-run-app-connect-platform-writes-through-one-executor.md) (amended for this decision); [0052](0052-refuse-response-removed-at-its-one-write-point-while-the-publish-is-unresolved.md)
- Issue: #1374
