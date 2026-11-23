# Shareable app logs: every app log line in the log export

**Owner:** romchornyi · Introduced in [#1303](https://github.com/dashpay/dashwallet-ios/pull/1303)

## Why

When a wallet flow fails in the field, support reads the logs a user shares through "Export Logs",
"Copy Logs", the wallet failure card or "Contact Support". Most of the app's Swift code logged to
the device's system log instead: a scan of develop on 2026-11-03 found 529 log calls in 56 files,
219 of them errors, that never reached the export. A report therefore arrived without the lines that
described the failure. Where those lines did carry an error, 133 call sites wrote its full
description, which can quote paths, stored values and addresses. #1155 fixed this for identity
registration with a local helper; this change fixes it for the whole app.

## What changed

- **One app logger.** `AppLogger` has the call shape of `os.Logger` and writes every line through
  `DWLogger` into the exported files, with a console copy
  ([ADR-0059](../../adr/0059-route-every-app-log-line-through-dwlogger-with-an-os-logger-shaped-applogger.md)).
  Each line carries its category, and warnings, errors and faults carry a `WARNING`, `ERROR` or
  `FAULT` tag. Error and fault lines are written before the call returns, so they survive a crash
  right after; debug lines exist only in developer builds.
- **Privacy at interpolation.** Numbers and flags are written as is; any other value is `<private>`
  unless the line marks it public
  ([ADR-0060](../../adr/0060-redact-log-values-at-interpolation-with-os-logger-privacy-defaults.md)).
  Every balance and payment amount is marked private; fees stay visible. Wallet and contact ids are
  cut to their first eight characters; addresses, profile fields and the invitation scope key are
  `<private>`.
- **Errors as summaries.** An error is written as its type, case, domain and code, a consensus
  rejection's code and kind, and the same for up to three wrapped errors — never its description
  ([ADR-0061](../../adr/0061-write-every-logged-error-as-a-type-case-and-code-summary.md)). A
  failed key migration also writes the keychain `status=` number. Asset-lock retry failures are
  written, and stored for the diagnostics bundle, as their case and error summary.
- **Stated exceptions.** Transaction ids stay in full, and a refused broadcast keeps the network's
  rejection reason as returned, so support can follow a payment and see why it was refused.
- **Marker lines kept.** The lines support searches by tag (`IDENT-COORD`, `TXSEND`, `KEYMIG`,
  chain sync) keep their tags and wording; `CoordinatorLog` from #1155 is replaced by `AppLogger`. Lines written
  before the PIN prompt of a username registration or purchase, and lines about a name that may not have been
  submitted yet (the username form's checks, the marketplace name check, contest bookmarks made before the write),
  do not write the name, so a name that is never registered stays out of the export.
- **A check for new lines.** The SwiftLint rule `no_os_logger` rejects new `os.Logger`, `os_log`
  and `NSLog` calls, and `unit-tests.yml` runs it on every pull request with a pinned SwiftLint
  (0.63.2, checked by sha256).

## How to use it

- Declare `AppLogger(category:)` where `Logger(subsystem:category:)` was, and log as before:
  `log.error("TXSEND: broadcast failed \(error)")`.
- Mark a value `privacy: .public` only when it is safe in a file a user shares; mark any amount
  `privacy: .private`, because the logger cannot tell an amount from a count.
- To read a report, search the export by Marker tag and by `ERROR` / `WARNING`.

## Operational notes

- No migration. An asset-lock failure record gains an optional `summary`; records stored before it
  are written as their case only.
- Console.app lines from the app no longer carry the app's subsystem and per-file categories; the
  category is part of the line text instead.

## Not in scope

- Log files written before this change: the rules apply when a line is written, so an export from an
  updated install can still hold older entries as they were. Existing files are not rewritten or filtered;
  they age out with the rolling log files.
- About 50 `print()` calls and about 70 legacy `DWLogger` lines that still write raw error text:
  #1302.
