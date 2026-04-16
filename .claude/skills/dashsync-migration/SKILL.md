---
name: dashsync-migration
description: Use when migrating any function from DashSync (legacy ObjC) to SwiftDashSDK (Swift package) in dashwallet-ios. Defines the one-stage cutover approach, when to use a direct swap versus a thin SwiftDashSDK-only shim, the verify-before-assume rule, and the alternative shapes for functions that don't fit a simple replacement. Triggers on phrases like "migrate <X> from DashSync", "swap DashSync for SwiftDashSDK", any work touching DashWallet/Sources/Infrastructure/SwiftDashSDK/, or any reference to DASHSYNC_MIGRATION.md.
---

# DashSync → SwiftDashSDK migration playbook

This skill is the entry point for **all** DashSync removal work in dashwallet-ios, regardless of which function you're migrating. Most sections apply universally; §3 is the default path for functions that fit a straightforward replacement. For everything else, §2 + §3a route you to the right alternative.

## 0. Deployment model: one-shot, single-release migration

**The entire DashSync → SwiftDashSDK migration ships in a single App Store release.** No interim release ever ships with the migration partially done. The cutover work, the key/storage migrators, and DashSync's removal all land on the development branch and ship together.

This is a load-bearing assumption with hard implications for what code you should and shouldn't write:

- **No dual-stack window exists in production.** Users never see a build where DashSync is authoritative for one operation while SwiftDashSDK is authoritative for another. Do not write code for users running partially migrated behavior.
- **Do not write cross-library state-drift handlers.** No wipe-detection branches that scrub SwiftDashSDK state when DashSync state disappears. No PIN-rotation branches that re-encrypt SwiftDashSDK seeds when DashSync's PIN changes. No runtime wallet-ID translation tables. That code is dead in this deployment model.
- **Do not preserve a staged Shadow / Flipped / Solo rollout inside the app just for migration safety.** Verify aggressively in development, then swap. The shadow-then-flip ladder that earlier sessions used is retired — it was ceremony, not insurance, because nothing ever shipped in a shadow state.
- **Hard invariant for storage migrators:** never delete from a DashSync-owned keychain service (`org.dashfoundation.dash`). The DashSync keychain entries from previous app versions persist on user devices forever as belt-and-suspenders rollback. The migrator only ever reads from them. Reference: `DASHSYNC_KEY_MIGRATION.md` and `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKKeyMigrator.swift`.

If you find yourself writing a branch that "handles the case where DashSync did X to its state after the migrator already ran", **stop**. That case can't happen in our deployment model. Delete the branch.

## 1. First step: read the migration map

Always read `DASHSYNC_MIGRATION.md` at the repo root **before** starting any migration work. For the function you're about to touch, find:

- Its row in the main 22-row table
- The **SDK** column (🟢 Ready / 🟡 Partial / 🔴 Blocked / ⚪ N/A)
- The **Status** column
- The **Storage migration?** column
- The **"Where we are"** section at the top — quick scan of in-flight work and notes from previous sessions

If the row doesn't exist or is wrong about the current state, **fix the doc first**. The migration map is the source of truth for status; this skill is the source of truth for procedure.

## 2. First check: does a direct cutover fit?

The one-stage replacement in §3 is the **default**, but it only fits when **all** of these are true:

- **Pure function**: same input → same output, no held state on either side
- **Synchronous**: no callbacks, no events, no completion handlers
- **Directly equivalent APIs**: both libraries expose the same operation with the same shape
- **Few isolated call sites**: a handful, not hundreds

If any are false, **STOP and re-plan**. Go to §3a, find the function's category, use the alternative shape, and ask the user before forging ahead. Do not jam an unfitting function into a direct swap.

**Functions where the direct cutover pattern fits cleanly** (per `DASHSYNC_MIGRATION.md`):

- #2 address validation (✅ done — reference implementation in `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKAddressValidator.swift`)
- #3 mnemonic generation
- #4 mnemonic validation
- #13 backup seed phrase
- #15 provider keys derivation
- #1 receive address (with the index-parameter trick)

## 3. One-stage cutover

For functions that fit §2, do the migration in one review-sized change:

1. Replace the DashSync implementation with the SwiftDashSDK implementation.
2. Remove the DashSync call path in the same change.
3. Delete any migration adapter that only existed to support staged parity, unless a thin SwiftDashSDK-only shim is still useful for Obj-C interop.
4. Update `DASHSYNC_MIGRATION.md` to reflect that the function moved straight to done.

The goal is **not** "run both and compare." The goal is **"verify first, then cut over cleanly"** — and verification happens against the sources in §5, not against DashSync at runtime.

### Shim conventions (when a shim is still useful)

- **Prefer direct Swift call-site replacement** where practical.
- If Obj-C interop or selector stability makes a shim useful, keep it **SwiftDashSDK-only** — never route through DashSync.
- **Location**: `DashWallet/Sources/Infrastructure/SwiftDashSDK/` (canonical directory for migration shims)
- **Naming**: `SwiftDashSDK<Concept>.swift` (e.g. `SwiftDashSDKAddressValidator.swift`)
- **Class**: `final class SwiftDashSDK<Concept>: NSObject` with `@objc(DWSwiftDashSDK<Concept>)` so Obj-C call sites can use it without rewriting
- **Method**: preserve the original selector only if it materially reduces call-site churn
- **Do not `import DashSync`** from the shim.

Example shim shape:

```swift
guard /* validate input */ else { return false }
return SwiftDashSDKModule.theMethod(...)
```

Reference implementation: `SwiftDashSDKAddressValidator.swift` (~15 lines). Reference commit for this final shape: `3c87467e5`. If the shim adds no real value after the cutover, delete it and call SwiftDashSDK directly from the final call sites.

## 3a. When the direct cutover doesn't fit — alternative shapes

For functions that fail the §2 check, here's the alternative shape per category. Some are sketched; most will be enriched as we actually ship migrations in each category. When you encounter one of these for the first time, **stop and ask the user** before designing the approach.

| Category | DASHSYNC_MIGRATION rows | Why a direct swap fails | Alternative shape |
|---|---|---|---|
| **Async / network calls** | #16 identity create, #18 contacts, #19 DPNS lookup | Needs callbacks or `async` behavior; Obj-C call sites need rewiring | Single cutover behind a SwiftDashSDK-backed async boundary, with call-site rewiring as needed. |
| **Stateful balance / UTXO** | #5 wallet balance, #9 fee estimation | SwiftDashSDK depends on SPV-populated state | Sequence after #11 SPV sync work. Don't attempt these in isolation. |
| **Persisted data (tx history)** | #6 transaction list, #7 tx detail | Two different storage frameworks (Core Data vs SwiftData); this is a storage migration, not a function wrapper | One-shot data migrator that runs at first launch after upgrade. See the "Storage migration" section in `DASHSYNC_MIGRATION.md`. |
| **Multi-step async write paths** | #8 send Dash, #16 identity create | Build → sign → broadcast carries state across steps | Replace the whole boundary at once; do not mix implementations inside one flow. If Swift and Obj-C callers coexist, introduce one app-level async service plus a thin Obj-C completion bridge, and keep the low-level SDK executor behind that boundary. |
| **Long-running event streams** | #11 SPV sync, #20 CoinJoin, parts of #18 | Event-driven, lifetime-coupled to the app; not a single call you can wrap | Event-router pattern. Much heavier than a shim — needs its own design discussion. |
| **Side-effect-only calls** | #12 network switch, #14 wipe wallet | Both calls just delete or mutate state; nothing meaningful to compare | Direct flip with manual verification. |
| **Not really a migration** | #21 reachability, #22 BIP70 | Replace with iOS framework (`NWPathMonitor`) or drop entirely | Out of scope for this skill — handle as a regular code change. |

**When in doubt, stop and ask the user.** Picking the wrong shape upfront is the most expensive mistake — once call sites are rewired in the wrong shape, undoing them is painful.

## 4. Project structure rules

These apply universally regardless of which shape you're using.

- **Both targets** (`dashwallet` and `dashpay`) need new Swift source files registered in `project.pbxproj`. The pattern: one `PBXFileReference`, two `PBXBuildFile` entries (one per target), both registered in their respective `PBXSourcesBuildPhase`. **Search the pbxproj for `App.swift in Sources`** to see the canonical pattern.
- **Infrastructure PBXGroup IDs** in pbxproj — there are THREE groups named `Infrastructure`. Use `479E7922287C00A000D0F7D7` (top-level `DashWallet/Sources/Infrastructure`). **Do NOT** use `47838B83290665EC0003E8AB` (that's `Models/Coinbase/Infrastructure`) or `47AE8B9728BFACED00490F5E` (that's `DashSpend Model/Infrastructure`). This was a footgun caught in commit `19b475684`.
- **Obj-C call sites** that use a new Swift `@objc` class need `#import "dashwallet-Swift.h"`. Most files in `DashWallet/Sources/UI/Payments/PaymentModels/` already have it; check before adding.
- **Both targets share `dashwallet-Swift.h`** as the auto-generated bridging header (verified via `SWIFT_OBJC_INTERFACE_HEADER_NAME` in pbxproj).
- **Swift migration files** should `import SwiftDashSDK`; they should never `import DashSync`.
- **Remove obsolete DashSync-only files, references, and imports** as part of the cutover when they're no longer needed.
- **UUID family** for migration shim pbxproj entries: extend the existing `A5D5DD0000000000000000…` family. Prefer the `…F1` through `…F4` range used by prior migration files.

## 5. Verify-before-assume rule

**The devnet-fallback episode is the load-bearing lesson here.** When tempted to add a defensive fallback or special-case branch ("just in case the two libraries differ on edge case X"), spend 5 minutes reading both implementations FIRST.

`dashwallet-ios` depends on the sibling `../platform` repo for SwiftDashSDK. Treat that repo as the source of truth for the Swift SDK surface this app is actually consuming. Do not infer SwiftDashSDK behavior from dashwallet wrappers alone.

Default inspection order:

1. Read the dashwallet call sites you're changing.
2. Read the SwiftDashSDK wrappers in `../platform/packages/swift-sdk/Sources/SwiftDashSDK/` to confirm the real Swift API shape, naming, lifecycle, and availability.
3. If wrapper behavior, type mapping, FFI boundaries, or runtime semantics are still unclear, inspect the underlying Rust / core implementation and FFI layer before designing the migration.

Concrete locations:

- **DashSync source**: sibling repo at `../DashSync/`
- **DashSync address logic**: `../DashSync/shared/Categories/NSString+Dash.{h,m}`
- **DashSync wallet / derivation**: `../DashSync/shared/Models/Wallet/`
- **SwiftDashSDK Rust source**: `~/.cargo/git/checkouts/rust-dashcore-*/<rev>/`. Find the rev via `grep "rust-dashcore" /Users/bartoszrozwarski/Documents/Developer/platform/Cargo.toml`. Address logic at `dash/src/address.rs`. FFI wrappers at `key-wallet-ffi/src/`.
- **SwiftDashSDK revision source of truth**: `/Users/bartoszrozwarski/Documents/Developer/platform/Cargo.toml`
- **SwiftDashSDK Swift wrappers**: `/Users/bartoszrozwarski/Documents/Developer/platform/packages/swift-sdk/Sources/SwiftDashSDK/`

Most of the time the two libraries already behave the same way and the fallback is dead code. The devnet check (commit `3c87467e5`) is the canonical example: assumed `.devnet` might differ from evonet, added a fallback, then found they use byte-identical logic and the fallback was deletable in the very next PR. Do the read first.

## 6. Verification flow

Run these checks for each cutover. Build verification proves static correctness; a focused runtime smoke test of the migrated flow is the second gate. Since the app no longer preserves staged parity, the runtime gate is the migrated behavior itself — not mismatch logging.

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

The iPhone 17 simulator runs dashwallet again as of 2026-04 — earlier sessions had to skip simulator runs because of a `[DSChain retrieveWallets]` crash on iOS 26.3, but that no longer reproduces. Exercise the migrated flow end-to-end before calling it done.

## 7. Update the migration doc on every cutover

Edit `DASHSYNC_MIGRATION.md` as part of the same change:

- The **"Where we are"** section: update or add the row for this function with the new state and a brief note about what landed (cite the commit SHA once it exists).
- The main 22-row table: update the **Status** column for this row — usually straight to `✅` for direct cutovers.
- If the lesson generalizes to future migrations, update this skill too (see §9).

## 8. Commit policy

**Per `CLAUDE.md`: never commit or push without explicit user permission.** Make changes, run verification, show the diff, wait for the explicit phrase ("commit", "push", "commit and push"). Plan-mode approval is NOT commit approval. After completing a task like "address review comments" or "fix this", do NOT automatically commit — the user typically wants to test first.

## 9. Self-improvement clause

**At the end of any DashSync migration session, if you learned something during it that would be useful for migrating OTHER functions in the future, update this SKILL.md before ending the session.**

Examples of things worth capturing here:

- A new Swift-from-ObjC bridging gotcha
- A network / enum mapping pitfall
- A new pbxproj group that's commonly mis-targeted (like the Infrastructure footgun in §4)
- An FFI signature mismatch class
- A verification step that catches a class of bugs
- A category in §3a that now has a real recipe instead of "stop and ask"

**Do NOT update SKILL.md** for one-off lessons specific to a single function. Those go in the adapter file as a comment, or in `DASHSYNC_MIGRATION.md` as a row note. The bar for editing SKILL.md is "useful for migrating OTHER functions, not just this one".

**Format for additions:** keep them in the relevant section above, one sentence per item, link to the commit SHA where the lesson was learned. If a section grows past ~10 items, propose a refactor in the next session.

**The skill grows over time.** Its long-term value comes from being kept current with what we've learned. A stale skill is worse than no skill — it gives confident wrong advice. If you notice anything in here that contradicts current reality, propose a fix.
