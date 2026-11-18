# 0022 — Derive disconnected apps from the intents a disconnect marked

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

The Connections page lists disconnected apps for as long as the wallet exists, and the approve
sheet cautions on a first connection only when the wallet has never connected to the app. Platform
keeps no such history, so the wallet keeps it on the device. An app's disconnected entry gives way
to its newer connection.

## Decision drivers

- Store only what Platform cannot show, and nothing that has to be kept in step with it by hand.
- A disconnected entry must never show while a key of the app is still live.

## Considered options

1. **Derive from the intents.** A disconnect marks the intents it closes, or leaves open for an
   unknown outcome, with `disconnectedAt`. The projection shows the app Disconnected once every
   key is off; the entry's details and dates come from the intents its last disconnect marked.
2. **A separate history store.** A disconnect writes an entry (name, website, identity, username,
   limits, dates) to a store of its own, and a new approval removes it.

## Decision outcome

**Chosen:** option 1. One store, and the "gives way to a newer connection" rule falls out of the
projection.

## Consequences

**Positive**
- A Disconnected entry shows only when the projection sees every key off, so it cannot contradict
  Platform after a partial disconnect.
- The history store of the redesign (#1289), and its write and remove paths, go away.

**Negative**
- An app whose keys came only from another device or from before a restore has no intent here, so
  it gets no Disconnected entry; its keys are still turned off (ADR-0016).
- The intents do not record the username, so a disconnected app's sheet does not show it.
- The intent store grows until the wallet is wiped.

**Neutral**
- A restored wallet has no intents, so it shows the first-connection caution again.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADRs: [0016](0016-turn-off-unrecorded-keys-on-disconnect-without-asking.md),
  [0021](0021-record-a-consensus-refusal-on-the-intent.md)
- PR: #1334
