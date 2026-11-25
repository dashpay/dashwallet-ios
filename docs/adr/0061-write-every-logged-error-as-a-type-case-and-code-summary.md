# 0061 — Write every logged error as a type, case and code summary

- **Status:** Proposed
- **Date:** 2026-11-18 (decided by the owner on 2026-11-03, the broadcast exception on 2026-11-17,
  the asset-lock detail exception on 2026-11-25; implemented in PR #1303)
- **Deciders:** romchornyi (author)

## Context

On develop, 133 call sites logged an error as `String(describing: error), privacy: .public` or its
`localizedDescription`. That was harmless while the lines stayed on the device, but with every line
in the log export
([ADR-0059](0059-route-every-app-log-line-through-dwlogger-with-an-os-logger-shaped-applogger.md))
an error's description would leave it, and descriptions quote file paths, stored values,
transaction ids and addresses. Support still needs to tell one failure from another.

## Decision drivers

- No raw error text in the export.
- Support tells failures apart by type, case and code, including the errors a failure wraps.
- At most three wrapped errors per line.
- One form for every place that summarises an error, so support learns one shape
  (`WalletSendService.logSummary` already had its own).

## Considered options

1. **Error summary** — `AppLogMessage.errorSummary`: the error's type, its enum case name, its
   `NSError` domain and code, a consensus rejection's code and kind for `PlatformWalletError`, then
   the same for up to three wrapped errors found in an enum payload or under
   `NSUnderlyingErrorKey`. An interpolated `\(error)` is always written this way;
   `WalletSendService.logSummary` uses the same function.
2. **Keep the description, marked public** — what the 133 call sites did before.
3. **Keep the description, passed through a scrubber** — strip addresses, ids and paths from the
   description text before writing it.

## Decision outcome

**Chosen:** option 1, the error summary. It writes only fields the app controls and support can
search for, and a description never reaches the file. Option 2 is the leak this decision closes.
Option 3 has the scrubber's weakness from
[ADR-0060](0060-redact-log-values-at-interpolation-with-os-logger-privacy-defaults.md): it can only
remove formats it knows about.

**Exception:** a refused broadcast is written with the full transaction id and the rejection reason
as the network returned it, because it is the only source that explains why the network refused a
transaction and it carries no keys or seed material.

**Exception:** an asset-lock retry failure keeps the wallet error's detail on the retry line and in
the diagnostics bundle's `summary.txt`, as #1276 added it. The SDK's catch-all wallet-operation
error has one summary for every cause, so without it two stuck locks look the same. The detail is
curated: a recipient mismatch writes a fixed sentence instead of the SDK's text, which names
addresses; a consensus rejection writes no detail, since its code and kind are in the summary; any
other error writes none. Every word of the detail holding a digit is written as `<n>`, since the
SDK's text can name a lock value or a fee. The bundle already lists each lock's outpoint.

## Consequences

**Positive**
- Error lines are comparable across reports: the same failure gives the same summary.
- A consensus rejection keeps the code and kind that distinguish Platform failures.

**Negative**
- Detail that only the description carried is lost unless the line logs it as its own value; the
  key-migration lines add the keychain `status=` number for this reason.
- The case name is read by reflection (`Mirror`): an enum with a custom description gives no case
  name, and only the first error inside a payload is followed. Type, domain and code are still
  written.

**Neutral**
- App Connect's `AppConnectWriteExecutor.logDescription(of:)` keeps a shorter form of its own (type,
  case, consensus code), and reads the case name through the same `AppLogMessage.caseName(of:)`.
- #1302 applies the same form to the about 70 legacy `DWLogger` lines that still write raw error
  text.

## Links

- Feature summary: [docs/features/shareable-app-logs/README.md](../features/shareable-app-logs/README.md)
- The logger: [DashWallet/Sources/Infrastructure/AppLogger.swift](../../DashWallet/Sources/Infrastructure/AppLogger.swift)
- Related ADR: [0060 — Redact log values at interpolation with os.Logger's privacy defaults](0060-redact-log-values-at-interpolation-with-os-logger-privacy-defaults.md)
