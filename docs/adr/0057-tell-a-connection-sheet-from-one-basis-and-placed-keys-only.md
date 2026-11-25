# 0057 — Tell a connection sheet from one basis, and claim access only from placed keys

- **Status:** Accepted
- **Date:** 2026-11-13 (shipped in #1399; recorded 2026-11-17)
- **Deciders:** romchornyi (ADR author)

## Context

The connection sheet shows what an app was given (access, messages) and what is left to spend
(funding lines from the keys' remaining budgets). They came from separate reads: a refresh could
show the access of one read of the identity beside the funding of another, and a key whose bound
contract the store had not read yet could be counted as the app's. Review found both twice (#1399,
round 6).

## Decision drivers

- What the sheet says about one app must come from one read of Platform.
- A claim that a key belongs to the app needs proof, not a guess.

## Considered options

1. **Narrow fixes**: re-read funding after every refresh and skip keys with an unknown bound in the
   places review named.
2. **One basis, one proof**: a `ConnectionBasis` (one identity snapshot, the intents that hold the
   app on it, the keys it gives the app that no intent names) is what a sheet is told from; access
   and funding are both derived from it, and funding read for another basis is dropped
   (`ConnectionDetails.attaching(_:for:)`). `AppConnect.placedKey(withId:in:)`, a key whose bound
   the store holds, is the only proof for access, messages and funding.

## Decision outcome

**Chosen:** one basis, one proof (Roman chose the full redesign over the narrow fixes). The two
failure classes go away by construction instead of per call site.

## Consequences

**Positive**
- Access and funding on one sheet always tell of the same read.
- A key on another contract of the same owner never shows as this app's.

**Negative**
- A key whose bound is not read yet backs no claim until a later read places it, so a sheet may
  show less than the app has for one refresh.

**Neutral**
- The projection stays pure (ADR-0055); the basis is built where the snapshot is read.

## Links

- Code: `ConnectionBasis` (DashConnectModels.swift), `AppConnect.placedKey`
  (AppConnectProjection.swift), `ConnectionDetails.attaching(_:for:)`
- Related ADR: [ADR-0027](0027-derive-app-connect-connections-from-the-identity-and-recorded-intents.md)
- Promoted from the DashConnect feature ADR 0019 on 2026-11-17, after the decision shipped.
