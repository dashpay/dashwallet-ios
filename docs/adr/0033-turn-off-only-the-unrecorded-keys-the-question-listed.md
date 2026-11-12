# 0033 — Turn off only the unrecorded keys the question listed

- **Status:** Proposed
- **Date:** 2026-11-10
- **Deciders:** romchornyi (owner), with Claude during the design pass

## Context

A disconnect that leaves unrecorded keys of the app asks "Turn them off?" with their count. "Turn them off" calls `disconnect(id:scope:includingUnrecorded: true)`, which builds the plan again from a fresh read after a second PIN. With owner attribution (ADR-0032) the set can grow between the question and the PIN: an owner read that failed before can succeed now. The key that joined would be turned off without the wallet user having been asked about it.

## Decision drivers

- When the wallet user was asked to turn off a number of unrecorded keys, the disconnect turns off no key beyond the ones that question counted (spec AC-08; SAD §1 quality goal 2).
- The keys a disconnect turns off are exactly the keys its result counts (AC-08).
- No hidden state between two calls that a later read cannot rebuild (ADR-0027).

## Considered options

1. **Carry the listed key ids through the question** — the disconnect result carries the ids of the unrecorded keys it offers, the view model passes them back, and the plan after the PIN is the fresh read intersected with them.
2. **Compare counts only** — keep the flag, pass the count; when the count after the PIN differs, turn nothing off and ask the wallet user to try again.
3. **The data source remembers what it offered** — it keeps the offered set in memory per app between the two calls; the interface does not change.

## Decision outcome

**Chosen:** option 1, because consent becomes an exact set the wallet user saw: option 2 cannot tell one key leaving and another joining apart and can loop on errors, and option 3 keeps a stored conclusion between calls with no clear point at which it ends (an alert dismissed, a wallet switch).

- `DashConnectDisconnectResult` carries the offered unrecorded key ids with their count; the "Turn them off?" message keeps them next to the connection it already holds.
- `DashConnectDataSource.disconnect` takes the listed ids in place of `includingUnrecorded: Bool`; the first disconnect passes none.
- After the PIN, the plan turns off the listed keys that are still live and still the app's; a key the fresh read attributes to the app but the list lacks stays on, and the result says access is left instead of reporting none.
- A key id is unique only within an identity, so the offered ids go with the identity they were read on (`DashConnectOfferedKeys`). A disconnect with listed keys runs only while that identity is the active one, checked before the PIN and after it; otherwise it is refused as a wallet or identity change.
- What stays on (offered, left after the question, not checked, not attributable) is told from the read after the update, the read the rows are refreshed from; the count of keys turned off is the plan's.

## Consequences

**Positive**
- The wallet user's "Turn them off" covers exactly the keys they were told about.
- The rule is testable directly on the plan.

**Negative**
- The data source protocol, its mock and the view model change signature.
- A key that joins after the question needs another disconnect to be turned off.

**Neutral**
- A listed key that is gone or no longer the app's by the time of the PIN is simply not turned off.
- For a row whose app has no intent on the identity, the app's keys are those placed on the row's contract: an owner read since the row was shown does not take a listed key away from it (review 2026-11-11 round 2).

## Links

- Related ADR: [0032](0032-pass-owners-read-from-platform-into-the-pure-projection.md); [ADR-0027](0027-derive-app-connect-connections-from-the-identity-and-recorded-intents.md)
- PR: #1364; issue #1346; the #1301 review thread it answers: r4513114671
