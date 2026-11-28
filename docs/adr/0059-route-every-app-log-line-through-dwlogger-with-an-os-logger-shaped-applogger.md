# 0059 — Route every app log line through DWLogger with an os.Logger-shaped AppLogger

- **Status:** Proposed
- **Date:** 2026-11-18 (decided by the owner on 2026-11-03; implemented in PR #1303)
- **Deciders:** romchornyi (author)

## Context

"Share application logs" exports `DWLogger`'s rolling files and the SDK session logs. A scan of
develop on 2026-11-03 found 529 log calls in 56 Swift files that went through `os.Logger`, whose
lines stay in the device's system log and never reach the export; 219 of them were errors. A
report from a user therefore arrived without the lines that described the failure. #1155 fixed this
for one coordinator with a local `CoordinatorLog` that wrote each line to both places, which showed
that the gap was app-wide.

## Decision drivers

- Every line the app logs reaches the log export.
- An error line survives a crash that follows it: it has to be in a file before the process dies,
  not only in the system log.
- Marker lines that support searches by (identity registration, sends, chain sync, key migration)
  keep their tags and wording, so call sites should change as little as possible.
- `DWLogger` over CocoaLumberjack already writes the exported files and a console copy; no new
  dependency.

## Considered options

1. **AppLogger over DWLogger** — a value type with the same call shape as `os.Logger`
   (`logger.info("… \(x, privacy: .public)")`) that writes each finished line through `DWLogger`
   into the file log and, through `DWLogger`'s OSLog sink, to the console. One declaration line
   changes per file.
2. **Read the system log at export time** — keep `os.Logger` and have the exporter add the app's
   own entries read through `OSLogStore`. On iOS an app can read only its current process's
   entries, so lines from earlier launches, including the launch that crashed, are not available.
3. **Write each line twice** — keep `os.Logger` and add a `DWLogger` line next to every call, the
   `CoordinatorLog` pattern of #1155, applied app-wide.

## Decision outcome

**Chosen:** option 1, `AppLogger` writing through `DWLogger`. It is the only option that puts lines
from a crashed launch into the export, and it keeps the call shape, so the 56 files change one
declaration line each instead of every call. Option 3 doubles every call and lets the two copies
drift; `CoordinatorLog` is removed in favour of `AppLogger`.

Error and fault lines are written synchronously (`DDLogError`); debug lines are written in DEBUG
builds only, like `os.Logger` debug lines, which the system does not persist. A SwiftLint rule,
`no_os_logger`, run on every pull request by `unit-tests.yml`, rejects new `os.Logger`, `os_log`
and `NSLog` calls.

## Consequences

**Positive**
- Every app log line is in the export, still mirrored to the console.
- Call sites keep the `os.Logger` shape and their existing `privacy:` annotations
  ([ADR-0060](0060-redact-log-values-at-interpolation-with-os-logger-privacy-defaults.md)).
- A line written right before a crash is in the file.

**Negative**
- The system log loses the app's subsystem and per-file categories; developers who filtered
  Console.app by them now search the category name inside the line.
- The message string is built on every call, also for a debug line that a release build drops;
  `os.Logger` defers that work.
- About 529 more call sites write into the same rolling files, so an export reaches back over a
  shorter time span.

**Neutral**
- `print()` calls and the legacy `DWLogger` lines are outside this route; #1302 moves them onto
  `AppLogger`.
- Moving back to `os.Logger` would again be one declaration line per file, but would bring back the
  export gap.

## Links

- Feature summary: [docs/features/shareable-app-logs/README.md](../features/shareable-app-logs/README.md)
- The logger: [DashWallet/Sources/Infrastructure/AppLogger.swift](../../DashWallet/Sources/Infrastructure/AppLogger.swift)
- Related ADRs: [0060 — Redact log values at interpolation with os.Logger's privacy defaults](0060-redact-log-values-at-interpolation-with-os-logger-privacy-defaults.md), [0061 — Write every logged error as a type, case and code summary](0061-write-every-logged-error-as-a-type-case-and-code-summary.md)
