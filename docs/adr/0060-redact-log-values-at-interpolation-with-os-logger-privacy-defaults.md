# 0060 — Redact log values at interpolation with os.Logger's privacy defaults

- **Status:** Proposed
- **Date:** 2026-11-18 (decided by the owner on 2026-11-03, amounts re-confirmed on 2026-11-17;
  implemented in PR #1303)
- **Deciders:** romchornyi (author)

## Context

Routing every line into the log export
([ADR-0059](0059-route-every-app-log-line-through-dwlogger-with-an-os-logger-shaped-applogger.md))
means everything a line holds can leave the device in a file a user shares. On the system log,
`os.Logger` redacted non-public values; in a file, nothing does unless the logger decides. By the
time a line reaches `DWLogger` it is one finished string, so an address, an amount or an error text
can no longer be told apart from the rest.

## Decision drivers

- No raw error text, no amount, no address and no full wallet id in the export.
- A free-text value the line does not mark public is written as `<private>`; counts and flags stay
  visible.
- Existing call sites already carry `privacy:` annotations written for `os.Logger` (512 of 529 calls
  on develop), and they should keep their meaning.

## Considered options

1. **Typed interpolation with os.Logger's defaults** — `AppLogMessage` renders each interpolated
   value by its type: integers, floats and `Bool` as is, an `Error` as its summary
   ([ADR-0061](0061-write-every-logged-error-as-a-type-case-and-code-summary.md)), any other value
   as `<private>` unless marked `.public`; `.private` always redacts. An amount, which is a number,
   is marked `.private` on its line.
2. **Scrub the finished line at the DWLogger boundary** — pattern-match addresses, hex ids, paths
   and numbers in the string `DWLogger` receives and replace them.
3. **Default public, opt-in private** — write every value as is unless the line marks it
   `.private`.

## Decision outcome

**Chosen:** option 1, privacy decided per value at interpolation with `os.Logger`'s defaults. It
decides where the value's type is still known, so an unannotated string can never leak, and the
annotations call sites already carry keep the meaning they were written for. Option 2 can only
guess from the text: it misses formats it does not know and would also hide the transaction ids
that support needs to follow a payment. Option 3 inverts the semantics of the existing annotations,
so every unannotated string would start leaking.

Every line that writes a balance or a payment amount marks it `.private`; fees stay visible. Full
wallet and contact ids are cut to their first eight characters; addresses, profile fields and the
invitation scope key are `<private>`.

## Consequences

**Positive**
- A new free-text value is redacted unless someone decides to make it public.
- Marker lines keep the values they showed under #1155 through explicit `.public`, except amounts.
- The rule is local and testable: one unit test per value form.

**Negative**
- An amount is a number, and numbers are public by default, so each amount line depends on its own
  `.private` marker, on review and on its regression test.
- Every `.public` chosen for the on-device system log had to be re-checked for the export.

**Neutral**
- A dedicated amount type that is always redacted would close the gap at the type level, but would
  touch every amount type the app uses; not planned.

## Links

- Feature summary: [docs/features/shareable-app-logs/README.md](../features/shareable-app-logs/README.md)
- The logger: [DashWallet/Sources/Infrastructure/AppLogger.swift](../../DashWallet/Sources/Infrastructure/AppLogger.swift)
- Related ADRs: [0059 — Route every app log line through DWLogger with an os.Logger-shaped AppLogger](0059-route-every-app-log-line-through-dwlogger-with-an-os-logger-shaped-applogger.md), [0061 — Write every logged error as a type, case and code summary](0061-write-every-logged-error-as-a-type-case-and-code-summary.md)
