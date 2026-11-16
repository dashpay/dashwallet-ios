# 0054 — Decide a failed Platform payment by the wallet's payment class

- **Status:** Proposed
- **Date:** 2026-11-16
- **Deciders:** Roman Chornyi (owner), with Claude. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

[ADR-0040](0040-report-three-send-outcomes-and-retry-only-when-nothing-left-the-source.md) says a
send offers Retry only when nothing left the source, and treats any doubt as in progress. For a
`PlatformWalletError`, `SendOutcome` decided that from a list of error types kept in the app: a few
types meant "not sent", everything else "in progress". The list drifted from the wallet. A new
error code, or a type the wallet classes differently from what its name suggests, read as in
progress although nothing had left (an identity lookup that failed before any spend), or could
read as not sent although the payment may have gone out
([dashwallet-ios#1427](https://github.com/dashpay/dashwallet-ios/issues/1427) is one such case).

[dashpay/platform#5928](https://github.com/dashpay/platform/pull/5928) moves that decision into
the Rust wallet: every `PlatformWalletError` carries a payment class (`delivery`: not sent, maybe
sent, or lock held, with whether a retry is allowed). The wallet is the layer that knows how far a
payment got.

## Decision

`SendOutcome` decides a `PlatformWalletError` by its `delivery`:

- `.notSent` → not sent. The error's type only picks the words of the reason (rejected, signing key
  unavailable, identity not found, otherwise failed).
- `.maybeSent` or `.lockHeld` → in progress. A held lock with its funding type keeps coming from the
  coordinator, which reports it as `lockHeld` itself.
- unclassified (`nil`) → in progress: not proven safe to send again.

`LiveCoreTwoStepSend.lockMayExist` reads the same class: only a not-sent failure proves the Core →
Identity top-up built no lock. Errors that are not `PlatformWalletError` (the app's own refusals,
`WalletSendService`, BIP70) keep their existing mapping.

## Consequences

- A new wallet error code needs no app change to be reported correctly; the app's type list is gone.
- The app depends on dashpay/platform#5928; this change cannot merge before it, and its pin moves to
  a platform line that carries it.
- `SendOutcome` follows the wallet even where the wallet is conservative: a nonce mismatch, classed
  maybe sent, stays in progress.
