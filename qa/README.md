# Wallet restore and sync QA

Run this scenario on demand to check that the iOS wallet restores known Core and
shielded funds, recovers the supported history, and retains them after relaunch.
This is a text playbook for a human-assisted agent, not an installed agent,
executable test runner, or CI job. Scenario ID: `wallet-restore-sync`; version: `1`.

The [reference wallet](reference-wallet.md) is **partially prepared and blocked**:
the tested SDK's shielding transition was rejected by testnet protocol 14.
Its preparation
and first successful restore must happen before this scenario can produce a
passing result. Do not invent addresses, transaction IDs, balances, or a baseline.

## Starting a run

Ask your agent: “Read qa/README.md and run wallet-restore-sync v1 against the
selected app and platform revisions. Follow the reference wallet and report
template. Pause for me to enter the recovery phrase. Save results locally.”

Follow repository instructions. Do not change application code, dependency pins,
or expected results to make a run pass. Do not commit, push, or upload reports.
Use [report-template.md](report-template.md) for every attempt, including blocked
ones. Save it as `qa-results/<UTC timestamp>-<unique suffix>/report.md`; keep all
run artifacts underneath that directory. Record each retry as a new run.

## Fixed simulator PIN

PIN policy version: `1`. Use **`1111`** when setting and confirming the app PIN
on each new dedicated QA simulator, including preparation and restore. Reuse
`1111` for subsequent authentication prompts. Do not ask the operator to choose
or supply a PIN. This is a public test fixture value for disposable testnet
installations only; never change an existing personal wallet's PIN.

Enter the fixed PIN automatically when the runner permits credential setup.
The current Codex computer-use tool requires a human handoff for creation of a
new authentication credential, including the app PIN. With that tool, give the
operator the fixed value and ask only for manual entry, confirmation and
submission; do not claim unattended setup or bypass the restriction. Record that
intervention separately from sync time. An unattended run with this limitation
is `blocked` at PIN setup until a permitted setup mechanism is available.
This limitation does not require asking the operator for the PIN again when
authenticating with the already configured test PIN.

## Preflight and build provenance

1. Read the fixture version and readiness status. Confirm that the operator has
   its Keychain item; never retrieve or print the phrase through agent tools.
2. Record full app and platform commit SHAs, repository URLs, and local changes.
   Record the app's `.platform-ref` separately from the actual platform checkout.
   Resolve the local Swift package path; a worktree does not automatically have
   the required sibling repositories. Record the actual paths used.
3. Resolve rust-dashcore dependencies from the platform `Cargo.lock`, checking
   manifests and Cargo configuration for patches or local path overrides. Record
   each distinct effective source/revision and affected crates. For a local
   checkout, include its SHA and changes. Do not assume all crates share a pin.
4. Establish which source produced the simulator FFI binary. Build from the
   selected sources using the repository build instructions, or use an existing
   artifact with recorded provenance. Capture build command, profile, toolchain,
   source revisions, and SHA-256 of the actual simulator library inside
   `DashSDKFFI.xcframework` (record its relative path). A checksum identifies a
   binary; it does not alone prove its source revision. Unknown provenance blocks
   the run. Do not reuse an unexplained cached framework.
5. Build the `dashpay` app from the recorded workspace and framework, arm64 for
   Simulator. Record the command, configuration, app bundle identifier, and build
   evidence. Resolve missing setup without overwriting another developer's work;
   do not create placeholder secrets without authorization. Record local patches
   without capturing secret files. Only clean source revisions may establish the
   first committed reference; later runs may test documented local changes.
6. Confirm simulator control, log access, and a way to inspect the required data.
   Stop as `blocked` if these are unavailable. Record tool/agent/model versions,
   Mac hardware, macOS, Xcode, and simulator runtime. Before starting sync, record
   a 60-minute sync observation budget; expiry alone is not a performance failure.

## Restore and observe

1. Create a dedicated disposable simulator and record its UDID. Never erase an
   operator's existing simulator. Install the recorded app. Uninstalling alone
   does not establish a fresh wallet because simulator Keychain data can survive.
   Apply the fixed simulator PIN policy whenever onboarding requests PIN setup.
2. Explicitly select testnet before importing; fresh installs default to mainnet.
   Confirm the fixture account scope and scan start precede its first activity.
   Do not import into an SPV store anchored after that activity.
3. Pause screenshots, recordings, and UI/accessibility dumps while the operator
   enters the phrase from Keychain. Resume only after leaving recovery screens.
   Never ask for the phrase in chat. Do not save clipboard or Keychain dumps.
4. Observe Core and shielded sync separately. Record progress and errors at least
   once per minute while waiting, with timestamps and evidence references. Do not
   silently reset, clear storage, change peers, or retry: preserve the attempt and
   report interventions. Stop at the declared observation limit.
5. For Core, observe `SyncingActivityMonitor.syncDone`, the scanned height and
   wallet's durable persisted watermark. The transient SPV `synced` state or a
   100% label is insufficient. Require persisted coverage through the fixture's
   Core anchor, and record the current network/scanned tip and any persistence
   lag. `syncDone` itself does not guarantee persister catch-up.
6. For shielded funds, require a successful pass for the active wallet that was
   neither skipped nor a cooldown no-op,
   a bound shielded wallet, and persisted scan coverage of the fixture's
   note commitment boundary. Record the current pass result and watermark;
   `isSyncing == false`, a cached timestamp, or Core sync completion is insufficient.
7. Verify the fixture anchors still belong to the relevant chains and inspect
   whether the fixture has gained activity. Compare exact Core and shielded
   balances using their declared integer units and balance categories. Compare
   each required historical operation using the fixture's restore assertions.
   Unexpected activity or a replaced anchor makes the fixture comparison
   `inconclusive`; do not rewrite its expected values during the test.
8. Terminate and relaunch the same installed app without clearing any state.
   Recheck both sync domains, balances, required history, and persisted coverage.
   Do not require a transient UI state to remain visible continuously.
9. Complete the report, identifying all unexecuted checks. Collect only sanitized
   logs, selected data extracts, and screenshots outside secret-entry screens.
   Inspect artifacts before retaining them; avoid full databases or app-container
   archives that can include sensitive data. Record whether the disposable
   simulator was retained or deleted; keep it for operator inspection by default.

## Evidence and verdict

Use UI to navigate and check presentation; corroborate correctness with logs and
persisted wallet data. Start with these implementation references, then inspect
the tested revision rather than assuming database tables or log text are stable:

- [Core sync monitor](../DashWallet/Sources/Application/Syncyng%20Activity%20Monitor/SyncingActivityMonitor.swift)
- [Shielded sync monitor](../DashWallet/Sources/Infrastructure/SwiftDashSDK/ShieldedSyncMonitor.swift)
- [Shielded restored history](../DashWallet/Sources/UI/Home/Views/ShieldedActivityHistory.swift)

Shielded restoration can recover different labels, grouping, or dates from the
original live activity. Assert documented recoverable facts, not identical UI row
counts or descriptions. Missing evidence is not proof that a check passed.

- `passed`: every required check has supporting evidence and matches the fixture.
- `failed`: evidence establishes an application failure, such as a crash, missing
  known funds/history after verified sync, or data lost on relaunch.
- `inconclusive`: execution started but network conditions, fixture drift, or
  insufficient evidence prevent a correctness verdict. A timeout alone belongs here.
- `blocked`: a prerequisite is missing, such as fixture data, operator import,
  tooling, build, or artifact provenance. Describe the stage and cause.

For a mixed outcome, retain every per-check result. A demonstrated failure takes
precedence; otherwise any unresolved required check prevents `passed`. Report
build/setup errors explicitly even though the restore scenario itself is blocked.

Do not send, shield, unshield, or otherwise mutate the fixture's on-chain state
during a restore run. This scenario does not validate new spending, InstantSend,
ChainLocks, an in-place app/storage upgrade, or performance thresholds. Timings
are descriptive. Compare old/new versions on the same machine with the same
fixture and scenario; use repeated trials before making performance claims.
