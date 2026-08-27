# Architecture Review — `swift-sdk-integration`

**Date:** 2026-07-03
**Scope:** entire branch vs `master` (merge-base `bce2e51be`) — 204 commits, 209 files, +22,051/−6,303 lines
**Method:** 12-dimension multi-agent review (7 area reviewers + 5 cross-cutting sweepers) → 63 raw findings → manual dedup → every P0/P1 claim re-verified against the working tree and `master` for provenance. Items marked ⚠ rest on reviewer-quoted evidence that was spot-checked rather than fully re-read. Intentional staged-migration seams (shadow → flipped → solo per DASHSYNC_MIGRATION.md) were **not** counted as smells; only badly-built seams were.

---

## TL;DR

The migration's *strategy* is solid — the staged cutover approach, the migration doc, and the seam placement are genuinely good. The *execution* has a systemic habit: **copy-paste instead of extract, stub instead of implement, and confident comments that contradict the code.** Five user-facing correctness holes hide behind those confident comments (worst: the send confirmation sheet is decorative — the transaction is broadcast before the sheet appears, and Cancel does nothing), plus ~25 real structural debts.

Suggested order: **T1 + T2 today** (small diffs, outsized blast radius) → **T6 + T7** as one "shared concurrency/auth primitives" PR → **T9 + T8** as the structural pair → the rest opportunistically.

---

## P0 — Fix before this branch ships (confirmed, user-facing)

### T1. The confirm sheet is fake: broadcast happens before the user confirms; the shown fee is a byte-count; Cancel is a no-op
> **Status: FIXED 2026-07-03.** `buildAndSign` no longer broadcasts (returns the held `CoreTransaction`); `broadcast()` is real and runs on Confirm; the sheet shows the exact FFI `tx.fee` and the all-in amount/total; DASHSYNC_MIGRATION.md #8/#9/#22 corrected.
- `buildAndSign` broadcasts at `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKTransactionSender.swift:99`, then returns `fee = UInt64(txData.count)` (line 121 — comment admits it's "for the preview UI").
- `DWPaymentProcessor.m:584` *then* presents the confirmation sheet (`confirmPaymentOutput:`), whose Confirm button calls the explicit no-op `broadcast()` (`SwiftDashSDKTransactionSender.swift:383-386`).
- The no-op's justification ("the SDK bundles build+sign+broadcast into a single FFI call") is **false in the same file**: `builder.buildSigned` (line 98) and `core.broadcastTransaction` (line 99) are separate calls.
- DASHSYNC_MIGRATION.md #8/#9 describe the *intended* behavior ("exact-fee confirmation… broadcasts on final confirm", "the real fee from the FFI is shown") as if it shipped.

**Action:** move `core.broadcastTransaction` into `broadcast()`; surface the real FFI fee (the selected-input CrowdNode path already gets exact fees); correct DASHSYNC_MIGRATION.md #8/#9.

### T2. Fresh installs default to TestNet in every build configuration, including Release/TestFlight
> **Status: ACCEPTED (descoped 2026-07-03 by owner decision).** Testnet default stays until the migration fully lands — mainnet Platform DAPI is unreachable in the current SDK build anyway. Revisit before any release branch is cut.
- `DashWallet/Sources/Models/DWEnvironment.m:48-54` — master set `ChainType_MainNet`; the branch sets `ChainType_TestNet` as unlabeled migration scaffolding, gated by neither `#if DEBUG` nor the existing `DASH_TESTNET` configuration flag.

**Action:** gate to Debug/TestNet configs now; add a tracking issue so it cannot silently reach a release build.

### T3. "Specify amount" silently discards the amount the user enters
> **Status: FIXED 2026-07-03.** `PaymentsLandingHostingController` now implements the specify-amount and request-amount delegates itself (legacy-parity mirror of `ReceiveViewController`); the stub `ReceiveSpecifyAmountRouter` is no longer referenced from live code (its deletion travels with T17).
- `DashWallet/Sources/UI/Payments/Receive/ReceiveScreen.swift:170-179` — `ReceiveSpecifyAmountRouter.shared` implements `specifyAmountViewController(_:didInput:)` by popping the nav controller; `amount` is unused.
- Wired to the live payments entry at `DashWallet/Sources/UI/Payments/Landing/PaymentsLandingHostingController.swift:91`. The legacy delegate built a `DWReceiveModel(amount:)` payment request from it.

**Action:** implement the request flow or remove the menu item.

### T4. The contested-username success path defers to a method that doesn't exist
> **Status: FIXED 2026-07-03.** `finalizeWon(username:)` is now real (mirror writes + canonical notification, following the `DWProfileUpdateCoordinator` pattern), and `DWIdentityRegistrationCoordinator.checkPendingContestResolution()` reconciles the pending bookmark on Home appear/foreground via `getDpnsNames`/`fetchContestVoteState` — win finalizes, loss/locked/pruned clears (the upstream SDK bug that forced the original removal was fixed in the v11 pin). A contested-status UI screen remains future work.
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/Identity/DWIdentityRegistrationCoordinator.swift:395` and `:481` claim `DWContestedNameStatusService.finalizeWon(...)` "does the mirror writes when the vote resolves in our favor" — `finalizeWon` exists only in those two comments (repo-wide grep).
- `handlePhaseChange` skips the `DWGlobalOptions.dashpayUsername` / `dashpayRegistrationCompleted` writes for contested submissions on that basis; nothing ever clears the pending bookmark; `DWCurrentUserIdentityInfo` filters the pending name out of every username source indefinitely.

**Action:** implement resolution detection, or stop skipping the mirror writes; delete the phantom references.

### T5. The SwiftUI username form asserts "Username is available" without checking
> **Status: FIXED 2026-07-03.** `checkIfBlocked` now runs the real debounced `dpnsCheckAvailability` (0.4 s debounce + task cancellation + trimmed stale-guard, mirroring the legacy rule): available → "Username available", taken → "Username taken" (Continue disabled), RPC failure → "Validating username failed", own pending contested name → "in voting" warning. Legacy localized strings reused.
- `DashWallet/Sources/UI/DashPay/Setup/CreateUsername/CreateUsernameViewModel.swift:270-284` — `checkIfBlocked` unconditionally sets `.valid` (comment admits "by then the user has already committed to submit").
- The real async check exists on the same bridge (`DWIdentityRegistrationBridge.checkAvailability`) and is used by the legacy `DWCheckExistenceUsernameValidationRule` path migrated in this same branch.

**Action:** call `checkAvailability` from `checkIfBlocked`, or change the copy so the UI doesn't claim availability it never verified.

---

## P1 — Architecture debt to burn down before it hardens

### T6. Four-to-six PIN/biometric gates; the newest ones dropped the hang-prevention watchdog
> **Status: FIXED 2026-07-03.** All migration-era auth sites now route through `AuthenticationGate`: `DWIdentityAuthorizer` (covers identity, profile, and shielded-transfer flows) reimplemented over the gate; DWPaymentProcessor's two inline ObjC blocks replaced by a new `DWWalletSendService authenticateSpendWithCompletion:` facade; PlatformSendConfirmScreen switched to the gate and aligned to biometrics-when-enabled (approved). Thin per-context error adapters (BIP70SendAuthorizer, DWIdentityAuthorizer) remain by design.
- `AuthenticationGate` (`DashWallet/Sources/Models/Transactions/WalletSendService.swift:223-252`) exists specifically because a non-presenting PIN prompt hangs an awaiting continuation forever. Its `SendAuthorizer` is `private`, so the branch cloned it:
  - `Infrastructure/SwiftDashSDK/BIP70SendAuthorizer.swift` — header admits "Mirrors the private `SendAuthorizer` in WalletSendService.swift".
  - `Infrastructure/SwiftDashSDK/Identity/DWIdentityAuthorizer.swift:54-69` — raw `withCheckedContinuation`, **no watchdog**; reintroduces the exact hang. Header cites stale line numbers ("129-172"; real code at 254-278).
  - Two near-identical inline ObjC copies in `DWPaymentProcessor.m` (~288-312, ~422-446).
  - A sixth inline call in `PlatformSendConfirmScreen.swift:143-148` hardcoding `usingBiometricAuthentication: false`.

**Action:** hoist one internal `AuthenticationGate`-backed authorizer; delete the copies.

### T7. The main-thread FFI trampoline is hand-rolled in 8 files (twice in one file)
- `if Thread.isMainThread { MainActor.assumeIsolated } else { DispatchQueue.main.sync }` in: `SwiftDashSDKCoinJoinBalanceReader.swift:49`, `SwiftDashSDKReceiveAddressReader.swift:47`, `SwiftDashSDKTransactionSender.swift:104` **and** `:210` (around a network broadcast — on the main thread), `SwiftDashSDKWalletWiper.swift:158` (comment admits "Mirrors HomeViewModel's main-thread trampoline pattern"), `SwiftDashSDKWalletState.swift:303`, `SyncingActivityMonitor.swift:387` (async variant), `HomeViewModel.swift:825`.

**Action:** one shared helper now; durable fix is the already-deferred async SDK-wrapper work (same root cause as the known SPV-restart deadlock).

### T8. `PlatformAddressSyncCoordinator` is an 877-line god object
- One "sync coordinator" singleton owns lifecycle, SwiftData wipes, **21 `@Published` properties** (lines 51-75: sync stats, balances, address lists), money-moving transfers with coin selection, bech32m codec — plus an unrelated second singleton `ShieldedTxLookup` at line 777 of the same file.

**Action:** split into sync engine / published state / transfer execution / lookup, mirroring the Host–State split already done for the core wallet.

### T9. Money-moving business logic inside SwiftUI `View` structs (violates CLAUDE.md's MVVM mandate)
- `DashWallet/Sources/UI/Payments/Pay/PlatformSendConfirmScreen.swift` — auth call at 143 (hardcoded no-biometrics), DSChain→Network mapping with `?? .testnet` fallback at 168-178, all in the View.
- `DashWallet/Sources/UI/Payments/InternalTransfer/InternalTransferConfirmSheet.swift` — **823 lines**, multiple screens in one file, `try? PlatformWalletManager.estimateShieldedFee` FFI calls (208-218) and protocol fee constants (~195) in view code.

**Action:** extract ViewModels; move fee math next to the centralized shielded fee model.

### T10. `Transaction`'s `.sdk` branches fabricate plausible defaults instead of signaling unknowns
- `DashWallet/Sources/Models/Transactions/Model/Transaction.swift:337` — every SDK tx is `.classic` (TODO admits txType unavailable); `:352` state collapses to `processing/ok` (`.confirming`/`.locked`/`.invalid` can never surface); `:200-203` sent SDK txs return `[]` output addresses; `:543` `isCoinbaseTransaction` hardcoded `false`.
- `:125` public mutable `var sdkCoinJoinMixing` populated "by convention" from `HomeViewModel.swift:859`; getters read global singletons (`CoinJoinWithdrawalStore.shared`, `ShieldedTxLookup.shared`).

**Action:** model unknowns as unknowns (optionals / `.unknown` cases); inject classification at init instead of convention-populated mutable state.

### T11. `NSManagedObjectContextDidSaveNotification` used as an app-wide event bus
- `DashWallet/Sources/UI/Payments/Receive/Models/DWReceiveModel.m:61-64` observes it (`object:nil`) routed to a handler named `transactionReceivedNotification`; the handler re-renders the CIFilter QR + PNG-encodes + writes app-group storage on **every SwiftData save batch during sync**. Instance lives for the whole session via `DWHomeModel`.
- ⚠ `HomeViewModel` full unfiltered tx reload on the same trigger, with a `DispatchQueue.main.sync` hop in its "background" source.

**Action:** one debounced "SDK data changed" publisher in Infrastructure; consumers subscribe to that instead of raw Core Data saves.

### T12. Sync-state fan-out: a notification masquerade plus a daisy-chain
- `SyncingActivityMonitor.swift:321-335` re-posts DashSync's `DSChainManagerSync*` wire names from SDK state via re-declared string constants (`:408-410`) — already documented as having poisoned grep audits once.
- ⚠ `HomeViewModel.swift:225` consumes the same transition twice: once via the masqueraded legacy name (bypassing the debounce), once via `$state`; `.syncStateChangedNotification` posted with zero observers (`// TODO: unused?`).
- ⚠ Identity registration state travels a 4-hop chain: coordinator → bridge internal notification → `DWDashPayModel` mirror → canonical notification, with race-coping patches already accreted.

**Action:** one typed state stream per domain; schedule deletion of the legacy-name re-emission together with the M9/M14 consumer migrations.

### T13. KeyMigrator↔WalletRuntime handshake: duplicated private string literals + 100 ms polling ⚠
- `SwiftDashSDKWalletRuntime.swift:29-35` hardcodes copies of the migrator's *private* keys (`"swiftSDKKeyMigration.v1.done"`, two deferred keys) + 30 s timeout + 0.1 s poll; `waitForSeedMigratorIfNeeded` (213-234) spins on UserDefaults. `SwiftDashSDKKeyMigrator.swift:82-90` declares the same literals privately; `:128-131` documents the race it creates.

**Action:** shared constants + async continuation handoff; no polling.

### T14. No owner for the current-wallet → SDK-walletId mapping; recovery-phrase reads are ad-hoc
- `DWPreviewSeedPhraseModel+Mnemonic.swift:42-52` constructs `WalletStorage()` inline, takes `walletIds.first`, silently falls back to `@""` in `DWPreviewSeedPhraseModel.m:87` (blank seed-words UI; comment admits "degraded UX but survivable").
- `SwiftDashSDKHost.swift:147-149` claims to be "the only path that writes new wallet identity", but reads scatter (`DerivationPathKeysModel.swift:160` does its own `try? WalletStorage().retrieveMnemonic`). Testnet and mainnet share one storage; nothing filters by network.

**Action:** one accessor on the Host, keyed by current network.

### T15. `PersistentIdentity` lookup copy-pasted 4×; cold-launch fix applied to 1 ⚠
- `DWCurrentUserIdentityInfo.swift:258-271` documents why the relationship predicate silently misses on cold launch and queries the wallet side instead — the broken predicate remains verbatim in `DWIdentityRegistrationCoordinator.swift:576-580`, `DWProfileUpdateCoordinator.swift:280-285`, `SDKIdentityProfileSheet.swift:255-259`.

**Action:** extract one lookup helper containing the fix.

### T16. CoinJoin sweep triplicated across three ViewModels with independent thresholds
- `WalletSendService.shared.sweepCoinJoin()` + observation/formatting/error blocks in `HomeViewModel.swift:630`, `SettingsMenuViewModel.swift:191`, `ToolsMenuViewModel.swift:171`; Home gates on `CoinJoinRecovery.recoveryDustThresholdDuffs`, Settings defines its own dust threshold (`SettingsMenuViewModel.swift:42`).

**Action:** one sweep-flow object (state machine + single threshold), three thin consumers.

### T17. Dead SwiftUI Receive stack duplicating the landing stack; landing hosting controller is not thin
- Zero references to `ReceiveScreenHostingController` outside its own file (pbxproj build entries only) — superseded by the Payments landing screen, never removed.
- `ReceiveViewModel.swift:10-76` is a near-verbatim copy of `PaymentsLandingViewModel.swift:34-97`, including duplicated `pickNextPlatformAddress`. The dead file hides the one live type (T3's stub router).
- `PaymentsLandingHostingController.swift:10` subclasses the legacy ObjC `DWBasePayViewController` and owns first-run gating via a stringly UserDefaults key — 140 lines, not a thin wrapper.

**Action:** delete the dead Receive stack; relocate the router; slim the hosting controller.

### T18. The new Infrastructure module is `.shared` globals with no protocol seams; seams leak both ways ⚠
- Essentially every new service is a singleton hardwired to `SwiftDashSDKHost.shared`, despite the codebase's protocol-based DI convention.
- UI mutates coordinators directly while `SwiftDashSDKWalletRuntime` claims exclusive lifecycle ownership and compensates by sniffing live coordinator state; stop-time state clearing split across two owners.
- Three error regimes in one module: typed throws (Host) / swallow-into-`os.log` on create/wipe paths / errors flattened to `@Published String?` (runtime/coordinator).

**Action:** decide the DI story now — even minimal protocol facades for the ~5 UI-facing services — and pick one error regime per layer.

### T19. Smaller confirmed duplications (one extraction pass each)
- Byte-identical semaphore `createWalletOnHost` bridge in `SwiftDashSDKKeyMigrator.swift` + `SwiftDashSDKWalletCreator.swift`; identical PIN-fetch/chain-mapping blocks in the two ObjC callers (`DWRecoverWalletCommand.m`, `DWPreviewSeedPhraseModel.m`).
- Dead-but-load-bearing `pin:` parameter in `SwiftDashSDKWalletCreator.swift:59-120` — validated (`guard !pin.isEmpty` can fail the import) then unused; "Retained for Obj-C selector stability".
- DSChain→SDK-network mapping re-implemented 5× (one copy in a SwiftUI View with the `?? .testnet` fallback). ⚠
- Asset-lock SwiftData polling machinery (0.5 s Task loop + FetchDescriptor + status mapping) copy-pasted from `DWIdentityRegistrationCoordinator` into `ShieldedTransferCoordinator`. ⚠
- `Tx.updateRateIfNeeded` duplicated verbatim across the `DSTransaction`/`Transaction` overloads (`Transactions.swift:34`/`:71`).

---

## P2 — Hygiene

### T20. ~1,650 lines of developer diagnostics ship ungated in the production Tools menu
- StorageExplorer (4 files incl. destructive runtime controls), `SwiftDashSDKSPVStatusScreen`, `PlatformSyncStatusScreen`; zero `#if DEBUG` in `ToolsMenuScreen.swift` / `ToolsMenuViewModel.swift`; hardcoded English throughout. The two status screens duplicate each other's scaffold. ⚠ (scaffold dup)

**Action:** gate behind `#if DEBUG` or an internal flag; dedupe the status-screen scaffold.

### T21. Debug-session residue and diary comments in permanent code
- `CJTEST` tags in 14 log lines across 6 files (`HomeViewController`, `HomeViewModel`, `SettingsMenuViewModel`, `ToolsMenuViewModel`, `WalletSendService`, `SwiftDashSDKSPVCoordinator`).
- Migration-diary narration in comments ("Row #17 stage A", M5/M9/M14 references) that will be gibberish in a year; stale cross-references (DWIdentityAuthorizer header cites "lines 129-172", real code at 254-278; TransactionSender fee comment points to `DSTransaction.feeUsed` "once registered with DashSync's chain context" — dead post-M6). ⚠ (narration inventory)

**Action:** sweep the tags; convert diary comments to doc links; delete stale cross-references.

### T22. Wholesale `@objcMembers` ×4 against the repo's own error-severity lint rule
- `DWIdentityRegistrationBridge.swift:50`, `DWProfileUpdateBridge.swift:30`, `DWContestedNameStatusService.swift:46`, `DWCurrentUserIdentityInfo.swift:54` — `.swiftlint.yml` `no_objcMembers` is `severity: error`, and CLAUDE.md prohibits it. Worth checking why lint didn't block these.

**Action:** per-member `@objc`.

### T23. Podfile silently raised the deployment target 14.0 → 18.0
- `platform :ios, '18.0'` ×3 + `IPHONEOS_DEPLOYMENT_TARGET = 18.0` in post_install, while the branch's rewritten CLAUDE.md still documents "iOS 14.0+".

**Action:** if intentional (SwiftData needs 17+), document the decision and update CLAUDE.md; if not, revert — it's a market-share decision that needs an explicit sign-off.

### T24. Repo hygiene: duplicated agent playbooks, root-level work logs, twin test suites
- `dashsync-migration` playbook committed twice (`.claude/skills/` + `.codex/skills/`) as hand-paraphrased forks that have already diverged.
- `BIP70_TESTING.md` is a stale point-in-time work log at the repo root describing the pre-port wallet as current.
- BIP70 assertions maintained in two parallel copies: `DashWalletTests/PaymentProtocolTests.swift` + a 419-line `scripts/bip70_manual_test/main.swift` with a hand-rolled semaphore runner (workaround for the broken tests target; will rot the moment the target is fixed).

**Action:** one canonical skill (symlink the other); move work logs out of the root; pick one test home once the tests target is repaired.

### T25. Sleep-based synchronization
- 500 ms `Task.sleep` sequencing a PIN prompt against a UIKit dismiss animation in `DWProfileUpdateCoordinator.swift:162` — Infrastructure code aware of animation timing (also a layering smell).
- 50 ms polling sleep loop for modal dismissal at `HomeViewController.swift:415`.

**Action:** completion-based presentation hooks.

### T26. Misc confirmed-by-evidence ⚠
- `SwiftDashSDKWalletState` refreshes three unrelated balances at 1 Hz piggybacked on SPV progress ticks — undeduped publish + SwiftData fetch + FFI read + NotificationCenter post every second during sync.
- CrowdNode selected-input path re-implements the FFI fee model app-side; the 0.5 s/30 s UTXO poll gate uses a *different* fee estimate than the spend check.
- `ShieldedTransferCoordinator` fakes a UI phase with back-to-back `@Published` writes and magic 0/4/12-second resync kicks; four transfer routes share copy-pasted boilerplate.
- Hardcoded colors bypassing `Color+DWStyle`, including a pure-white selected-tab pill that breaks in dark mode (`PaymentsLandingScreen.swift`, InternalTransfer views).
- `CoinJoinMixingTxSet` keeps dead pre-branch concurrency scaffolding (unused `amountQueue`, `chain`) and reads `_amount` without the lock its writers use.
- Wallet wipe hangs off a re-declared notification-name string literal with stale cross-references (`SwiftDashSDKWalletWiper.swift`) — a rename silently orphans key material.
- BIP70 ObjC↔Swift seam erases the confirmation box to `id` + stringly KVC and flattens the typed error taxonomy to one code (`DWPaymentInput.m`); `DWPaymentOutput` is a three-mode implicit union carrying skip-PIN state; platform-address validation triplicated with knowingly divergent strictness across the Send stack.
- Funding-source choice smuggled from the SwiftUI form to the coordinator via a mutable singleton property (`DWIdentityRegistrationBridge.preferredFundingSource`) instead of a call parameter.

---

## The pattern behind the patterns

Three habits generate most of this list; they'll keep generating findings until the habit changes:

1. **Copy-then-adapt instead of extract** — usually with an honest comment admitting it ("Mirrors the private SendAuthorizer…", "For now, copy-then-adapt keeps the migration contained"). Each copy then evolves independently: T6's lost watchdog, T15's unpropagated cold-launch fix, T16's forked thresholds.
2. **Comments that describe intent as if it were behavior** — T1's "then show the confirmation UI with the real fee", T4's phantom `finalizeWon`, the false "single FFI call" justification. The most dangerous vibecoding tell on the branch, because it defeats review.
3. **Stub-and-assert** — paths that report success without doing the work: T3's discarded amount, T5's "Username is available", T10's fabricated `.classic`/`.ok` defaults.

## What's genuinely good (for balance)

- The staged shadow→flipped→solo seam strategy, consistently applied and documented per function.
- DASHSYNC_MIGRATION.md itself — the audit corrections (e.g. the honest 2026-07-02 SPV-removal reassessment) show real discipline, even where the code lags the doc.
- Deliberate, documented deviations (phrase-repair engine's sanctioned deviations list, wiper's keep-chain-data rationale) — the *practice* of writing down "we differ from legacy here, on purpose, because…" is exactly right.

---

*Provenance note: findings were produced by 8 completed review agents (63 raw findings; 4 sweepers + the verification wave were cut short by a spend limit) and then manually deduplicated and re-verified. Unmarked items were confirmed by direct code reading on 2026-07-03; ⚠ items were spot-checked against reviewer-quoted code.*
