# 0065 — Recognize Platform refusals by consensus code in one table

- **Status:** Proposed
- **Date:** 2026-11-23
- **Deciders:** llbartekll (ADR author)

## Context

The app told Platform's refusals apart by fragments of the error message. The messages are Rust
renderings that change between SDK revisions, so a match stops working without a build error: one
branch waited for a text Platform no longer produces, and another matched unrelated failures.
Both FFI layers now carry the rs-dpp consensus code beside the message, as
`PlatformConsensusError` on `SDKError` and `PlatformWalletError`. Three features already read it,
each with its own copy of the numbers.

## Decision drivers

- A consensus code is a contract with platform; a message is not.
- An error the app cannot classify must stay unclassified, not be read as a known case.
- One number must not be written in two files.

## Considered options

1. **One table and one mapping.** `PlatformConsensusCode` names every code the app branches on,
   and `PlatformRefusal` maps a code to an app case. A code outside the table is `.other(code:)`;
   an error with no consensus code has no `PlatformRefusal`. Text is matched only where no code
   reaches Swift, and each such match carries `TODO(platform-error-codes)` naming the gap.
2. **Per-feature constants.** Each feature keeps the codes it needs, as today. The numbers repeat,
   and nothing shows which refusals are still matched by text.
3. **Wait for platform to type every refusal.** A dedicated result code per refusal needs a
   platform change for each one and leaves the text matches in place meanwhile.

## Decision outcome

**Chosen:** option 1. It moves every refusal that already has a code off the message text now,
and makes the remaining text matches a visible, bounded list.

## Consequences

**Positive**
- A reworded Platform message no longer changes what the app does for a refusal with a code.
- The text matches left are listed by one label, each with the reason no code is available.

**Negative**
- The table has to follow rs-dpp's numbering by hand; a renumbered code would be read as
  `.other(code:)` until the table is updated.
- Several refusals still arrive as text, because the wallet layer renders the SDK error into a
  message before the FFI can read its code: a DPNS registration, an identity registration or
  top-up funded from Platform addresses, and an identity update. They stay text matches until
  platform keeps the SDK error on those paths.

**Neutral**
- `PlatformRefusal.consensusError(in:)` is the list of SDK errors ADR-0021 refers to, moved
  unchanged out of the App Connect data source; what counts as a permanent refusal there is the
  same.
- A missing contest and a missing masternode identity are not refusals and carry no code. They are
  read from the query's own empty answer instead.

## Links

- Related ADRs: [0021](0021-record-a-consensus-refusal-on-the-intent.md),
  [0013](0013-treat-dashuikit-and-swiftdashsdk-as-library-surfaces.md)
- Upstream: dashpay/platform#4838
- PR: #1476
