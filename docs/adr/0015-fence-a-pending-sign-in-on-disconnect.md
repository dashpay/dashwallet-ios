# 0015 — Fence a pending sign-in on disconnect and recover forward only

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

An App Connect sign-in is an identity update that adds the app's keys. When its outcome is not
known (a timeout, a lost connection), it may still land after the user has disconnected the app.
A key that Platform has disabled cannot be enabled again, and undoing a write is itself a write
whose outcome may be unknown.

## Decision drivers

- Platform refuses an update that adds a key id the identity already holds.
- Recovery goes forward: no undo or compensation step that can itself fail half-way.
- A disconnect must leave no access the user cannot see.

## Considered options

1. **Fence on disconnect.** At each key id a pending sign-in would take, the wallet adds a key of
   its own (HASH160, HIGH, budget 1, no expiry), then turns it off. The pending update can then
   never land.
2. **Wait.** Leave the pending sign-in alone and let it land or not.
3. **Compensate.** Turn the app's keys off again if the update lands later.

## Decision outcome

**Chosen:** option 1. It closes the window for good with writes the wallet controls.

## Consequences

**Positive**
- A sign-in that lands late can never bring back access the user turned off.
- A fence left on cannot let the sign-in land either; it is reported, and turned off by the next
  disconnect.

**Negative**
- Disconnecting a pending sign-in costs two identity updates (add the fence, then turn it off).
- The fence's shape has unit and seam tests; it is still to be run against a testnet that runs
  protocol 14.

**Neutral**
- A disconnect whose update outcome is unknown marks the sign-ins it carried, so a late landing
  still ends Disconnected (ADR-0022).

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADRs: [0016](0016-turn-off-unrecorded-keys-on-disconnect-without-asking.md),
  [0018](0018-run-app-connect-platform-writes-through-one-executor.md)
- PR: #1334
