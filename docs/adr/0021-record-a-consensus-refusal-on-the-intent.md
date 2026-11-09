# 0021 — Record a consensus refusal on the intent and show it as Refused

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

When Platform refuses a sign-in's identity update for good, its keys can never land. Such a
sign-in stayed Confirming until the user disconnected it, which fenced it at the cost of two
identity updates. After a refusal Platform keeps nothing, so the fact cannot be read back later.

## Decision drivers

- Store only what Platform cannot show; a refusal is such a fact.
- A wrong Refused would hide keys that may still land, and Remove runs without a PIN or a fence.
- A refusal must never leave a row the user cannot act on.

## Considered options

1. **Record the refusal on the intent.** When the broadcast returns an error from Platform's
   validation of the transition, the intent records its code and reason; the projection shows
   Refused only while no key of the intent is live. A timeout, a transport error or an unknown
   error leaves it Confirming.
2. **Derive it from the identity revision.** Store the revision the update was signed at, and show
   Refused once Platform shows a later revision without the keys. The SDK signs over a cached
   identity, so that revision is only predicted.

## Decision outcome

**Chosen:** option 1. It stores one observed fact instead of a prediction.

## Consequences

**Positive**
- Refused shows the reason the network gave and needs no fence; Remove hides the row without a PIN
  and writes nothing to Platform.
- A sign-in that may still land is never shown Refused.

**Negative**
- The split between "refused for good" and "unknown" is a list of SDK errors kept in one place; an
  error on the wrong side would show Refused for keys that could still land.
- A refusal seen on another device, or before a reinstall, is not known here: that row stays
  Confirming until Disconnect fences it.

**Neutral**
- The intent gains `refusal` and `removedAt`; an older build ignores them.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADRs: [0015](0015-fence-a-pending-sign-in-on-disconnect.md),
  [0019](0019-let-one-state-table-decide-what-a-connection-shows-and-offers.md)
- PR: #1334
