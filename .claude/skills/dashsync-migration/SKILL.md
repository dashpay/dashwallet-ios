---
name: dashsync-migration
description: Use when migrating any function from DashSync (legacy ObjC) to SwiftDashSDK (Swift package) in dashwallet-ios. Defines the 4-stage migration ladder (Shadow → Flipped → Solo → Done), the @objc adapter pattern under DashWallet/Sources/Infrastructure/SwiftDashSDK/, the verify-before-assume rule, and the alternative shapes for functions that don't fit the basic pattern. Triggers on phrases like "migrate <X> from DashSync", "swap DashSync for SwiftDashSDK", "shadow mode for <X>", any work touching DashWallet/Sources/Infrastructure/SwiftDashSDK/, or any reference to DASHSYNC_MIGRATION.md.
---

# DashSync → SwiftDashSDK migration playbook

This skill is the entry point for **all** DashSync removal work in dashwallet-ios, regardless of which function you're migrating. Most sections apply universally; only §3 (the recipe) is specific to functions that fit the basic shape. For everything else, §2 + §3a route you to the right alternative.

## 0. Deployment model: one-shot, single-release migration

**The entire DashSync → SwiftDashSDK migration ships in a single App Store release.** No interim release ever ships with the migration partially done. The 4-stage adapter ladder in §3 (Shadow → Flipped → Solo → Done), the key/storage migrators, and DashSync's removal all happen on the development branch and land together.

This is a load-bearing assumption with hard implications for what code you should and shouldn't write:

- **No dual-stack window exists in production.** Users never see a build where DashSync's UI is authoritative for one operation while SwiftDashSDK is authoritative for another. Anything you'd write to handle that interleaving is dead code.
- **Do not write cross-library state-drift handlers.** No wipe-detection branches that scrub SwiftDashSDK state when DashSync state disappears. No PIN-rotation branches that re-encrypt SwiftDashSDK seeds when DashSync's PIN changes. No wallet-ID translation tables that map DashSync wallet IDs onto SwiftDashSDK wallet IDs at runtime.
- **Stage 0 ("Shadow") is a development verification harness, not a production safety net.** Its job is to let you sanity-check the SwiftDashSDK call against DashSync ground truth before flipping the adapter on the dev branch — it does not need to survive into a shipped binary as a safety mechanism. Stage 0 → 1 → 2 still happen as separate commits for review hygiene, but they all bake in the same dev branch.
- **Hard invariant for storage migrators:** never delete from a DashSync-owned keychain service (`org.dashfoundation.dash`). The DashSync keychain entries from previous app versions persist on user devices forever as belt-and-suspenders rollback. The migrator only ever reads from them. Reference: `DASHSYNC_KEY_MIGRATION.md` and `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKKeyMigrator.swift`.

If you find yourself writing a branch that "handles the case where DashSync did X to its state after the migrator already ran", **stop**. That case can't happen in our deployment model. Delete the branch.

## 1. First step: read the migration map

Always read `DASHSYNC_MIGRATION.md` at the repo root **before** starting any migration work. For the function you're about to touch, find:

- Its row in the main 22-row table
- The **SDK** column (🟢 Ready / 🟡 Partial / 🔴 Blocked / ⚪ N/A)
- The **Status** column (`—` not started / `🌓` Shadow / `🌗` Flipped / `🌘` Solo / `✅` Done)
- The **Storage migration?** column
- The **"Where we are"** section at the top — quick scan of in-flight work and notes from previous sessions

If the row doesn't exist or is wrong about the current state, **fix the doc first**. The migration map is the source of truth for status; this skill is the source of truth for procedure.

## 2. First check: does the basic pattern fit?

The 4-stage ladder in §3 is the **default** approach but it only fits when **all** of these are true:

- **Pure function**: same input → same output, no held state on either side
- **Synchronous**: no callbacks, no events, no completion handlers
- **Directly equivalent APIs**: both libraries expose the same operation with the same shape
- **Few isolated call sites**: 3-10, not hundreds

If any are false, **STOP and re-plan**. Go to §3a, find the function's category, use the alternative shape, and ask the user before forging ahead. Do not jam an unfitting function into the basic ladder.

**Functions where the basic pattern fits cleanly** (per `DASHSYNC_MIGRATION.md`):
- #2 address validation (✅ done — reference implementation in `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKAddressValidator.swift`)
- #3 mnemonic generation
- #4 mnemonic validation
- #13 backup seed phrase
- #15 provider keys derivation
- #1 receive address (with the index-parameter trick — see §3 notes)

## 3. The 4-stage ladder (basic-pattern recipe)

Each stage is a **separate PR**. Stage transitions are mostly one-line code changes plus a status bump in `DASHSYNC_MIGRATION.md`.

| Stage | Glyph | What the adapter does | Risk |
|---|---|---|---|
| **0 — Shadow** | 🌓 | Calls BOTH libraries on every invocation. Returns DashSync's result. Logs disagreements via `os.log` subsystem `org.dashfoundation.dash`, category `swift-sdk-migration.<name>`. Bug-for-bug identical to baseline. | Zero — DashSync is still authoritative. |
| **1 — Flipped** | 🌗 | One-line change: `return dashSyncResult` → `return sdkResult`. Both libraries still called, mismatches still log, but SwiftDashSDK is now authoritative. | Low — DashSync is still running as a safety check. |
| **2 — Solo** | 🌘 | Drop the DashSync parallel call entirely. Adapter calls only SwiftDashSDK. No mismatch logger. Zero DashSync touch in the adapter file. | Low — only ship after Stage 1 has been baking with no mismatch logs. |
| **3 — Done** | ✅ | Retire the adapter file. Inline `Module.method(...)` directly at the call sites in Swift. | Defer — only do this when DashSync is being fully removed from the project. Adapter is harmless overhead until then. |

### Adapter file conventions

- **Location**: `DashWallet/Sources/Infrastructure/SwiftDashSDK/` (canonical directory for migration adapters)
- **Naming**: `SwiftDashSDK<Concept>.swift` (e.g. `SwiftDashSDKAddressValidator.swift`, `SwiftDashSDKMnemonicValidator.swift`)
- **Class**: `final class SwiftDashSDK<Concept>: NSObject` with `@objc(DWSwiftDashSDK<Concept>)` so Obj-C call sites can use it without rewriting
- **Method**: `@objc(<originalDashSyncSelector>)` so the call-site swap is mechanical — change the receiver, keep the selector
- **Stage 0 body shape:**
  ```swift
  let dashSyncResult = (input as NSString?)?.theDashSyncMethod(...) ?? false
  guard /* SwiftDashSDK supports this case */ else { return dashSyncResult }
  let sdkResult = SwiftDashSDKModule.theMethod(...)
  if sdkResult != dashSyncResult { logger.warning(...) }
  return dashSyncResult  // Stage 1 changes this to sdkResult
  ```
- **Stage 2 collapses to ~15 lines**: just the SwiftDashSDK call with input validation. See `SwiftDashSDKAddressValidator.swift` for the exact shape.
- **Reference commits**: `19b475684` (Stage 0), `3c87467e5` (Stage 2). Do not flip Stage 1 in a separate commit unless the change is trivial — usually rolled into Stage 0 PR's follow-up.

## 3a. When the basic pattern doesn't fit — alternative shapes

For functions that fail the §2 check, here's the alternative shape per category. **None of these are sketched in detail yet** — they will be enriched as we actually ship migrations in each category. When you encounter one of these for the first time, **stop and ask the user** before designing the approach.

| Category | DASHSYNC_MIGRATION rows | Why basic ladder fails | Alternative shape |
|---|---|---|---|
| **Async / network calls** | #16 identity create, #18 contacts, #19 DPNS lookup | Adapter would have to be `async` or take a completion handler; Obj-C call sites need rewriting | **Async-adapter variant**: same ladder, but adapter exposes both a callback-style (for Obj-C) and `async` Swift API. Mismatch comparison happens after both have completed. Higher per-call latency in Stage 0 because we wait for both. |
| **Stateful balance / UTXO** | #5 wallet balance, #9 fee estimation | SwiftDashSDK can't compute balance until SPV runs and populates its own UTXO store; nothing meaningful to shadow against | **Sequenced after #11**: ship SPV chain sync first (which itself uses an event-router pattern below). Don't attempt these in isolation. |
| **Persisted data (tx history)** | #6 transaction list, #7 tx detail | Two different storage frameworks (Core Data vs SwiftData); there's no "function" to shadow — it's a data migration | **One-shot data migrator** that runs at first launch after upgrade. Completely different shape — not an adapter at all. See the "Storage migration" section in `DASHSYNC_MIGRATION.md`. |
| **Multi-step async write paths** | #8 send Dash, #16 identity create | Build → sign → broadcast is 3+ steps with state in between; shadow-running both would actually broadcast two real transactions | **Step-level shadow is impossible.** Either flip atomically (risky — requires extensive offline test vectors first) or restructure the call sites to use a thin DashSync-or-SwiftDashSDK selector behind a feature flag. |
| **Long-running event streams** | #11 SPV sync, #20 CoinJoin, parts of #18 | Event-driven, lifetime-coupled to the app; not a single call we can wrap | **Event-router pattern**: a parallel event bus that fans out events from both SDKs to the same UI listeners. Much heavier than an adapter — needs its own design discussion. |
| **Side-effect-only calls** | #12 network switch, #14 wipe wallet | Both calls just delete or mutate state; nothing to compare in shadow | **Direct flip** with manual verification. Skip Stage 0 — start at Stage 1 (or just ship the swap atomically). |
| **Not really a migration** | #21 reachability, #22 BIP70 | Replace with iOS framework (`NWPathMonitor`) or drop entirely | Out of scope for this skill — handle as a regular code change. |

**When in doubt, stop and ask the user.** Picking the wrong shape upfront is the most expensive mistake — once call sites are rewired in the wrong shape, undoing them is painful.

## 4. Project structure rules

These apply universally regardless of which shape you're using.

- **Both targets** (`dashwallet` and `dashpay`) need new Swift source files registered in `project.pbxproj`. The pattern: one `PBXFileReference`, two `PBXBuildFile` entries (one per target), both registered in their respective `PBXSourcesBuildPhase`. **Search the pbxproj for `App.swift in Sources`** to see the pattern in action — that's the canonical example.
- **Infrastructure PBXGroup IDs** in pbxproj — there are THREE groups named `Infrastructure`. Use `479E7922287C00A000D0F7D7` (top-level `DashWallet/Sources/Infrastructure`). **Do NOT** use `47838B83290665EC0003E8AB` (that's `Models/Coinbase/Infrastructure`) or `47AE8B9728BFACED00490F5E` (that's `DashSpend Model/Infrastructure`). This was a footgun caught in commit `19b475684`.
- **Obj-C call sites** that use a new Swift `@objc` class need `#import "dashwallet-Swift.h"`. Most files in `DashWallet/Sources/UI/Payments/PaymentModels/` already have it; check before adding.
- **Both targets share `dashwallet-Swift.h`** as the auto-generated bridging header (verified via `SWIFT_OBJC_INTERFACE_HEADER_NAME` in pbxproj).
- **Swift adapter files** should `import SwiftDashSDK`; they should never `import DashSync`. If you need a DashSync call (Stage 0), reach it through `(string as NSString?)?.method(...)` because DashSync's category methods on `NSString` are pulled in via the bridging header.
- **UUID family** for migration adapter pbxproj entries: extend the existing `A5D5DD0000000000000000…` family. Use `…F1, F2, F3, F4` series for new files (the `…E…` series was used by the parity-test work).

## 5. Verify-before-assume rule

**The devnet-fallback episode is the load-bearing lesson here.** When tempted to add a defensive fallback or skip-case ("just in case the two libraries differ on edge case X"), spend 5 minutes reading both implementations FIRST.

- **DashSync source**: sibling repo at `../DashSync/`. Address-related logic in `DashSync/shared/Categories/NSString+Dash.{h,m}`. Wallet/derivation in `DashSync/shared/Models/Wallet/`.
- **SwiftDashSDK Rust source**: cached at `~/.cargo/git/checkouts/rust-dashcore-*/<rev>/`. Find the rev via `grep "rust-dashcore" /Users/bartoszrozwarski/Documents/Developer/platform/Cargo.toml`. Address logic at `dash/src/address.rs`. FFI wrappers at `key-wallet-ffi/src/`.
- **SwiftDashSDK Swift wrappers**: `/Users/bartoszrozwarski/Documents/Developer/platform/packages/swift-sdk/Sources/SwiftDashSDK/`.

Most of the time the two libraries make identical decisions and any defensive fallback is dead code. The devnet check (commit `3c87467e5`) is the canonical example: assumed `.devnet` might differ from evonet, added a fallback, then found they use byte-identical logic and the fallback was deletable in the very next PR. Do the read first.

## 6. Verification flow

Run for each stage. None of these require the app to launch (the host-app crash on iPhone 17 + iOS 26.3 in `[DSChain retrieveWallets]` is a known pre-existing blocker for runtime testing on this machine; build verification is what proves correctness).

```bash
# 1. pbxproj sanity
plutil -lint DashWallet.xcodeproj/project.pbxproj

# 2. dashwallet target builds
xcodebuild build \
  -workspace DashWallet.xcworkspace \
  -scheme dashwallet \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=YES

# 3. dashpay target builds (same flags, different scheme)
xcodebuild build \
  -workspace DashWallet.xcworkspace \
  -scheme dashpay \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=YES
```

`EXCLUDED_ARCHS=x86_64` is required because the SwiftDashSDK xcframework only ships `ios-arm64-simulator` (not x86_64). On Apple Silicon this works fine; CI on Intel would need a rebuilt xcframework.

**Stage 0 only — manual smoke test (when possible):** open Console.app on the host machine, filter by `subsystem:org.dashfoundation.dash category:swift-sdk-migration.<name>`, exercise the function in the app, confirm zero mismatch warnings before shipping the Stage 1 flip.

## 7. Update the migration doc on every stage transition

Edit `DASHSYNC_MIGRATION.md` as part of the same PR:

- The **"Where we are"** table at the top: update or add the row for this function with the new state and a brief note about what landed (cite the commit SHA)
- The main 22-row table: update the **Status** column for this row (`—` → `🌓` → `🌗` → `🌘` → `✅`)
- If the lesson learned is broadly applicable, also update this SKILL.md per §9

## 8. Commit policy

**Per `CLAUDE.md`: never commit without explicit user permission.** Make changes, run verification, show the diff, wait for the explicit phrase ("commit", "push", "commit and push"). Plan-mode approval is NOT commit approval. After completing a task like "address review comments" or "fix this", do NOT automatically commit — the user typically wants to test first.

## 9. Self-improvement clause

**At the end of any DashSync migration session, if you learned something during it that would be useful for migrating OTHER functions in the future, update this SKILL.md before ending the session.**

Examples of things worth capturing here:
- A new Swift-from-ObjC bridging gotcha
- A network/enum mapping pitfall
- A new pbxproj group that's commonly mis-targeted (like the Infrastructure footgun in §4)
- An FFI signature mismatch class
- A verification step that catches a class of bugs
- A category of functions whose "alternative shape" in §3a now has a sketched approach (as we ship migrations in each category, §3a should grow from "stop and ask" into "here's the recipe")

**Do NOT update SKILL.md** for one-off lessons specific to a single function. Those go in the function's adapter file as a comment, or in `DASHSYNC_MIGRATION.md` as a row note. The bar for editing SKILL.md is "useful for migrating OTHER functions, not just this one".

**Format for additions:** keep them in the relevant section above (e.g., "Project structure rules"), one sentence per item, link to the commit SHA where the lesson was learned. If a section grows past ~10 items, propose a refactor in the next session.

**The skill grows over time.** Its long-term value comes from being kept current with what we've learned. A stale skill is worse than no skill — it gives confident wrong advice. If you notice anything in here that contradicts current reality, propose a fix.
