# 0042 — Report movedToPlatform when a Shielded to Identity top-up fails after the unshield

- **Status:** Superseded by [ADR-0044](0044-top-up-an-identity-from-shielded-in-one-step.md)
- **Date:** 2026-11-10
- **Deciders:** Roman Chornyi (owner), with Claude during the design pass. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

Shielded → Identity runs in two steps: the unshield moves the credits to the wallet's own Platform
address, then the identity top-up spends them. When the top-up fails after the unshield, the three
outcomes of [ADR-0040](0040-report-three-send-outcomes-and-retry-only-when-nothing-left-the-source.md)
fit badly: `notSent` would offer Retry although the money left the Shielded source, and `inFlight`
says "It will finish on its own", but nothing resumes this top-up. The money is not lost: it sits on
the wallet's own Platform balance. This ADR refines ADR-0040.

## Decision drivers

- Funds safety: no double payment, so no Retry once money left the source (AC-19 in the
  [feature summary](../features/external-send/README.md), ADR-0040).
- Honest outcomes: the app must not say a send will finish when no code path finishes it
  (`CLAUDE.md` guardrail 3).
- No resume path for this pair in this release: the SDK has no recovery for an unshield whose
  top-up failed.

## Considered options

1. **A fourth outcome `movedToPlatform`** — no Retry, the sheet closes with a Toast saying where the money is and that the top-up did not complete.
2. **Report it as `inFlight`** — keeps three outcomes, but the "will finish on its own" text is false for this case.
3. **Report it as `notSent`** — offers Retry, which would unshield again from a source the money already left and could leave the holder confused about two Platform movements.
4. **Resume the top-up from the Platform balance** — the honest end state, but needs a recovery record and a resumer this release does not have.

## Decision outcome

**Chosen:** option 1, the executor reports a fourth outcome, `movedToPlatform`, only when Shielded → Identity fails after the unshield; the router shows an info Toast "Top-up not completed" / "The money moved to your Platform balance. The identity top-up did not complete." with no Retry. It keeps ADR-0040's no-Retry rule for any money that left the source and tells the holder the truth; a resume (option 4) can replace it later.

## Consequences

**Positive**
- The holder knows where the money is and that the top-up did not happen; nothing pays twice.
- ADR-0040's rule holds: Retry only on `notSent`.

**Negative**
- One more outcome for the executor, router and tests to handle.
- The holder has to top up the identity again by hand, from Platform.

**Neutral**
- The send result screen handles four outcomes instead of three.
- A later resume path would retire this outcome (or keep it as the resume's failure text).

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Android counterpart: [dashpay/dash-wallet#1680](https://github.com/dashpay/dash-wallet/pull/1680)
- Related ADR: [0040 — Report three send outcomes and retry only when nothing left the source](0040-report-three-send-outcomes-and-retry-only-when-nothing-left-the-source.md) (refined by this ADR)
