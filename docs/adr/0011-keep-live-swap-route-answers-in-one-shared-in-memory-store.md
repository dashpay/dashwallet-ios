# 0011 — Keep live route answers in one shared in-memory store with two-step ageing

- **Status:** Proposed
- **Date:** 2026-11-05 (implemented in PR #1297)
- **Deciders:** romchornyi (author)

## Context

Route checks (ADR-0010) produce one answer per direction, provider and coin. Three places read those
answers: the coin picker (labels and halted rows), the address screen (it also writes what its own
quote learned) and the quote paths (which providers a Sell quote asks). Every swap flow builds its own
`SwapKitSwapProvider` (`SwapBackend.makeProvider()`), so answers kept on the provider would die with
each picker. The repo's guardrail #4 (`CLAUDE.md`) asks every new singleton to state its reason.

## Decision drivers

- A conclusive answer is re-checked after 10 min and still shown until 30 min; an inconclusive one is re-asked after 2 min, not sooner.
- A coin with a conclusive answer from the last ten minutes is not checked again when the picker is reopened.
- An unknown answer never halts a coin or removes a label.
- Providers are created per flow, so state on a provider dies with each picker; prefer no new storage when memory meets the load limits, since persisting needs a SQLite migration.

## Considered options

1. **One app-wide in-memory store** (`SwapRouteAvailability.shared`), `@MainActor`, keyed by direction × provider × coin, with two-step ageing (due after 10 min, forgotten after 30 min) and inconclusive answers not stored (only their time, for the 2-minute back-off). Tests build their own instance.
2. **A cache on the provider instance** — answers live as long as one swap flow.
3. **A persisted cache** (UserDefaults or the app's SQLite) that survives a relaunch.

## Decision outcome

**Chosen:** Option 1. It is the only option that skips re-checking fresh answers across picker openings without adding
storage: option 2 re-checks every coin on every opening (coins × providers requests), and option 3
adds serialization and a migration for answers that are forgotten after 30 minutes anyway. Keeping
unknown answers out of the store is what makes "unknown never halts" hold by construction.

## Consequences

**Positive**
- The picker, the address screen and the quote paths read one truth; a no-route the address screen confirms shows as halted when the Wallet holder goes back, when the published token lists name the coin.
- One place enforces the in-flight cap and the NEAR verdict for both directions.
- Testable with an injected clock and an injected probe.

**Negative**
- A new `static let shared`: its reason is written in the type doc, as guardrail #4 asks, but it is global state for the app's lifetime.
- After a relaunch every coin is checked again from scratch.

**Neutral**
- The two-step ageing means a label can lag a provider's recovery by up to ten minutes (two for a NEAR outage); a quote reads only answers that are not yet due (`freshOnly`), so a stale "ruled out" never narrows a real quote.

## Links

- Feature summary: [docs/features/swap-live-routes/README.md](../features/swap-live-routes/README.md)
- Related ADR: [0010 — Probe live routes with address-free quotes forced to one provider](0010-probe-live-swap-routes-with-address-free-forced-quotes.md)
- Related ADR: [0012 — Detect a NEAR outage from sentinel coins before per-coin checks](0012-detect-a-near-outage-from-sentinel-coins.md)
