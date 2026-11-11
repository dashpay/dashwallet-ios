# 0028 — Answer App Connect v2 only and remove the two-scan login

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author)

## Context

The two-scan `dash-key` login (App Connect v1) and its `dash-st` key registration were in the
code but never reached a store release, only internal TestFlight builds. Keeping them meant
protecting their keys from every App Connect cleanup, which produced its own class of review
findings: how the two-scan keys are derived, lockout, and coexistence with v2. The Android wallet
answers v2 only.

## Decision drivers

- New connections are v2 only, as on Android.
- Nothing to migrate: no store user has a two-scan connection.

## Considered options

1. **Remove v1.** A v1 QR is refused when scanned, `dash-st` is taken only as a token purchase,
   and the protection of two-scan keys, the approved status and the scan-to-complete banner go.
2. **Refuse v1 from protocol 14 only**, keep the v1 flow below it and protect its keys from
   cleanup.

## Decision outcome

**Chosen:** option 1. It never shipped, and keeping it cost more than any user it served.

## Consequences

**Positive**
- The two-scan protection is gone, and a disconnect no longer derives two-scan keys.

**Negative**
- Keys from old two-scan logins on testnet stay on the identity, and the wallet no longer lists
  them. The two-scan login ran only below protocol 14, where a key cannot carry limits, so its
  key has no expiry and is not an App Connect key (`AppConnect.isAppConnectAuthKey`). A stored
  two-scan row goes on the first refresh, and Connections cannot turn its key off. This is no
  worse than before, when a two-scan disconnect was local only, and it reaches only internal
  testnet installs.
- The Debug mock scan still feeds a v1 QR, which is refused.

**Neutral**
- The login choice by protocol version (ADR-0006) still decides whether App Connect is offered.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADRs: [0006](0006-choose-the-app-connect-login-by-the-protocol-version-read-at-runtime.md),
  [0009](0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md)
- PR: #1301
