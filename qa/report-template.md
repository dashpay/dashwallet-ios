# Wallet restore and sync report

Template version: `1`. Copy into the run's ignored output directory.
Replace `NOT RECORDED`; use `unavailable` with a reason when needed. Unfilled rows
never mean success. Evidence links must resolve inside this run directory.

## Run and outcome

| Field | Value |
| --- | --- |
| Run ID and UTC start/end | NOT RECORDED |
| Scenario ID/version; fixture ID/data version | NOT RECORDED |
| Overall status: passed / failed / inconclusive / blocked | NOT RECORDED |
| Reason and first failing or blocked stage | NOT RECORDED |
| Agent/model, instruction revision, tool versions; operator | NOT RECORDED |
| Comparison run ID, if any | NOT RECORDED |
| Observation budget and actual elapsed time | NOT RECORDED |

## Source and artifact provenance

| Component | Repository URL and full SHA or effective source | Local changes / overrides | Evidence |
| --- | --- | --- | --- |
| iOS app | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Platform / SwiftDashSDK | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| rust-dashcore crate group (one row per distinct source) | NOT RECORDED | NOT RECORDED | NOT RECORDED |

| Field | Value |
| --- | --- |
| App platform pin; actual platform and package paths | NOT RECORDED |
| Cargo.lock SHA-256; affected crates per effective source | NOT RECORDED |
| Framework build command, profile, source/build record | NOT RECORDED |
| Actual simulator library path within XCFramework and SHA-256 | NOT RECORDED |
| App build command, configuration, bundle ID, build log | NOT RECORDED |
| Local patch evidence or explicit clean status | NOT RECORDED |
| Mac hardware, macOS, Xcode, Rust and CocoaPods versions | NOT RECORDED |
| Simulator model, iOS version, UDID, fresh-state evidence | NOT RECORDED |
| Testnet selection, account scope and scan start | NOT RECORDED |
| Operator import completed (never include phrase or PIN) | NOT RECORDED |
| Fixed PIN policy version; setup/authentication method and any required handoff | NOT RECORDED |

## Required checks

For each row record `passed`, `failed`, `inconclusive`, `blocked`, or `not_run`.
Explain every non-passing row. Expand history rows to the fixture's individual
assertions. Repeat relevant values after relaunch; do not just write “same”.

| Check | Expected | Observed before relaunch | Observed after relaunch | Status and evidence |
| --- | --- | --- | --- | --- |
| Core/Platform anchors remain valid; no fixture drift | Fixture anchors/activity | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Core completion and persisted coverage | syncDone; coverage through fixture anchor | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Shielded completion and persisted coverage | Bound wallet; successful pass excluding skips/cooldown no-ops; fixture boundary covered | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Core balance categories, integer duffs | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Shielded balance categories, integer credits | NOT RECORDED | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Ordinary receive history | Fixture assertion | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Ordinary send history | Fixture assertion | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Recoverable shielding history | Fixture assertion | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Recoverable withdrawal history | Fixture assertion | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Relaunch without clearing storage | Same wallet and retained data; no crash | NOT RECORDED | NOT RECORDED | NOT RECORDED |

## Observations and evidence

Record Core network/scanned/persisted heights, Platform anchor, shielded scan
watermarks and pass result, last errors, and timestamped progress samples. Include
the source of each measurement. Record sync durations with start/end definitions;
build and operator-entry time are separate. Memory and history counts are optional
observations with measurement method and scope, never invented or pass criteria.

| UTC time / stage | Observation or intervention | Local evidence link |
| --- | --- | --- |
| NOT RECORDED | NOT RECORDED | NOT RECORDED |

## Limitations and follow-up

- Checks not run and reasons: NOT RECORDED.
- Differences from fixture or comparison run, and comparability limits: NOT RECORDED.
- Evidence reviewed for secrets; redactions or omitted artifacts: NOT RECORDED.
- Disposable simulator retained/deleted and its UDID: NOT RECORDED.
- Suggested next investigation, without changing expectations: NOT RECORDED.

New spending, InstantSend, ChainLocks, storage upgrades, and performance guarantees
are outside this scenario. A passing restore result does not claim those passed.
