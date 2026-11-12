# 0032 — Pass the owners read from Platform into the pure App Connect projection

- **Status:** Proposed
- **Date:** 2026-11-10
- **Deciders:** romchornyi (owner), with Claude during the design pass

## Context

Since #1301 the wallet links an unrecorded key to an App Connect app only through the contracts the app's connection intents name (`AppConnect.project`, `contractsOfApp`). A key on a sibling binding granted on another device, or before a reinstall or restore, lands on a separate row, and a disconnect of the app leaves it on while reporting no access left (#1346). The base of #1301 read contract and group owners inside the data source during a disconnect (`ownedByOwner`, removed in 3415560d1). The projection is pure and table-tested (ADR-0027); it now needs to know who owns a contract or a contract group.

## Decision drivers

- The rows, the count the "Turn them off?" question shows and the keys a disconnect turns off must agree (spec AC-08; SAD §1 quality goal 2).
- No key is attributed without a known owner match, and an unknown owner never counts as a match or a mismatch (spec §6 NFR "Keys attributed without a known owner match: 0"; CONTEXT invariants; repo guardrail 3).
- Table tests of the projection over known, mismatched and unknown owners, without a network (spec §6 NFR measurement).
- ADR-0027: the data source reads Platform, the projection decides.

## Considered options

1. **Owners as an input of the pure projection** — the data source reads the owners the projection needs and passes them to `project` / `disconnectPlan`; a missing entry is unknown.
2. **The projection reads through a closure** — `project` becomes `async` and takes a `readOwner` closure, as `appConnectOwnership` takes `readContract` / `readGroup`.
3. **Attribution in the data source after the projection** — the projection stays as it is and the data source moves keys from separate rows into an app's row by owner, as `ownedByOwner` did before #1301.

## Decision outcome

**Chosen:** option 1, because one pure owner rule, called by both projection functions, decides rows, question counts and the disconnect plan, so they cannot drift (option 3 splits the rule across two places, the drift class #1272 suffered), and it keeps the projection synchronous and network-free (option 2 makes every projection test async and couples row building to the network).

- A small pure function lists the ids whose owner the projection needs: the app contract of every App Connect app with a connection intent on the active identity, and the bound contract or contract group of every unrecorded key that no intent names by contract and that is not on a system contract (`AppConnect.systemContractIds`, the DashPay contract). A document-type bound is asked about by its contract.
- The data source reads those owners it does not know yet, reusing the owner parsing of `appConnectOwnership` (promoted, not copied, per repo guardrail 1), and passes a map from id to owner; an id it could not read is absent, which means unknown.
- One pure helper applies the owner rule, and both `project` (rows and the counts the question shows) and `disconnectPlan` (the keys a disconnect turns off) call it, so they cannot disagree.
- For a disconnect of app X, an unrecorded key is considered only while it may be X's: unless the owner of its bound and the owner of X's contract are both known and differ (AC-06: such a key is neither turned off nor counted). An owner equal to `AppConnect.systemContractOwnerId` never matches (AC-09). A key it considers has exactly one outcome:
  - **attributed to X** — the owner of its bound is known and equals the known owner of X's contract, and the owner of every other App Connect app with a connection intent on the identity is known and differs. The key joins X's row and its disconnect (AC-01..AC-03).
  - **cannot attribute to X alone** — the owner of its bound is known and equals the known owner of X's contract, and another App Connect app with an intent on the identity has that same known owner, or its bound is a contract group with admins (or whose admins the read does not show), since an admin may add their own contracts to the group. The key stays on its separate row, and the result says so without suggesting a retry (AC-07).
  - **could not be checked** — every other case in which it may be X's: the owner of its bound is unknown (AC-04, AC-05), the owner of X's contract is unknown, or the owner matches X while the owner of another app with an intent is unknown (AC-12). The key stays on its separate row and the result does not report that X has no access left.
- On Connections, an unrecorded key shows in an app's row only when it is attributed to that app; otherwise it stays on its separate row (CONTEXT invariant: never hidden).
- ADR-0031's clause that a live key whose bound the store cannot read stops the whole disconnect no longer describes the code of #1301; it is amended in ADR-0031 itself on #1301, and an unplaced key counts as "could not be checked" here (AC-11).

## Consequences

**Positive**
- The rows, the question's count and the disconnect plan come from one owner rule and one owner map.
- Every attribution rule is covered by synchronous table tests.

**Negative**
- The data source needs one more pure step, listing the ids to read, before it can project.
- A Connections refresh waits for the owner reads it needs, within the spec §6 budget (≤ 1 s p95 for up to 4 distinct contracts and contract groups).
- A key on the own contract of another app of the same owner, approved only on another device (no intent for that app here), is attributed by owner to the one app here with an intent: it shows under that app's row, not its own, and that app's question offers to turn it off. The wallet cannot tell it from the app's own key on a sibling contract (the AC-03 shape); the user's confirm in the question is the safeguard, and AC-07 covers only two apps with an intent here.

**Neutral**
- The projection's result grows two counts (could not be checked, cannot attribute to this app alone) that the result alert and the question word separately.
- Moving the projection to a shared implementation for both wallets later (ADR-0027 Neutral) now also moves the owner rule.

## Links

- Related ADR: [0033](0033-turn-off-only-the-unrecorded-keys-the-question-listed.md); [ADR-0027](0027-derive-app-connect-connections-from-the-identity-and-recorded-intents.md), [ADR-0031](0031-turn-off-unattributed-dashpay-profile-keys-with-any-disconnect.md)
- PR: #1364; issue #1346; the #1301 review thread it answers: r4513114671
