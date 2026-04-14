---
name: dashsync-migration
description: Use when migrating any function from DashSync (legacy ObjC) to SwiftDashSDK (Swift package) in dashwallet-ios. Defines the one-stage cutover approach, when to use a direct swap versus a thin SwiftDashSDK-only shim, the verify-before-assume rule, and the alternative shapes for functions that do not fit a simple replacement. Triggers on requests like "migrate <X> from DashSync", "swap DashSync for SwiftDashSDK", work touching DashWallet/Sources/Infrastructure/SwiftDashSDK/, or references to DASHSYNC_MIGRATION.md.
---

# DashSync to SwiftDashSDK migration playbook

Use this skill for all DashSync removal work in dashwallet-ios, regardless of which function is being migrated. Most sections apply universally; section 3 is the default path for functions that fit a straightforward replacement. For everything else, section 2 and section 3a route to the right alternative.

## 0. Deployment model: one-shot, single-release migration

The entire DashSync to SwiftDashSDK migration ships in a single App Store release. No interim release ever ships with the migration partially done. The cutover work, the key and storage migrators, and DashSync removal all land on the development branch and ship together.

Implications:

- No dual-stack production window exists. Do not write code for users running partially migrated behavior.
- Do not write cross-library state-drift handlers. Wipe detection, PIN-rotation sync, or runtime wallet-ID translation code is dead code in this deployment model.
- Do not preserve a staged Shadow or Flipped rollout inside the app just for migration safety. Verify aggressively in development, then swap.
- Hard invariant for storage migrators: never delete from the DashSync-owned keychain service `org.dashfoundation.dash`. Migrators only read from it. See `DASHSYNC_KEY_MIGRATION.md` and `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKKeyMigrator.swift`.

If you find yourself writing logic for "DashSync changed state after the migrator already ran", stop and delete that branch. That case should not exist here.

## 1. First step: read the migration map

Read `DASHSYNC_MIGRATION.md` at the repo root before touching migration code. For the function you are about to change, find:

- Its row in the main 22-row table
- The `SDK` column
- The `Status` column
- The `Storage migration?` column
- The `Where we are` section near the top

If the row is missing or inaccurate, fix the doc first. `DASHSYNC_MIGRATION.md` is the source of truth for status; this skill is the source of truth for procedure.

## 2. First check: does a direct cutover fit?

The one-stage replacement in section 3 is the default, but it only fits when all of these are true:

- The operation is a pure function
- The operation is synchronous
- DashSync and SwiftDashSDK expose directly equivalent APIs
- There are only a few isolated call sites

If any of those are false, stop and re-plan. Go to section 3a, pick the right alternative shape, and ask the user before forcing the function into a direct swap.

Functions where the direct cutover pattern fits cleanly, per `DASHSYNC_MIGRATION.md`:

- `#2` address validation
- `#3` mnemonic generation
- `#4` mnemonic validation
- `#13` backup seed phrase
- `#15` provider keys derivation
- `#1` receive address, with the index-parameter trick

Reference implementation: `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKAddressValidator.swift`.

## 3. One-stage cutover

For functions that fit section 2, do the migration in one review-sized change:

1. Replace the DashSync implementation with the SwiftDashSDK implementation.
2. Remove the DashSync call path in the same change.
3. Delete any migration adapter that only existed to support staged parity, unless a thin SwiftDashSDK-only shim is still useful for Obj-C interop.
4. Update `DASHSYNC_MIGRATION.md` to reflect that the function moved straight to done.

The goal is not "run both and compare." The goal is "verify first, then cut over cleanly."

### Shim conventions when a shim is still useful

- Prefer direct Swift call-site replacement where practical.
- If Obj-C interop or selector stability makes a shim useful, keep it SwiftDashSDK-only.
- Location: `DashWallet/Sources/Infrastructure/SwiftDashSDK/`
- Naming: `SwiftDashSDK<Concept>.swift`
- Class shape: `final class SwiftDashSDK<Concept>: NSObject` with `@objc(DWSwiftDashSDK<Concept>)`
- Method shape: preserve the original selector only if that materially reduces call-site churn
- Do not call DashSync from the shim.

Example shim shape:

```swift
guard /* validate input */ else { return false }
return SwiftDashSDKModule.theMethod(...)
```

If the shim adds no real value after the cutover, delete it and call SwiftDashSDK directly from the final call sites.

## 3a. When the direct cutover does not fit

If section 2 fails, use the right shape for the category instead of forcing a direct swap.

| Category | `DASHSYNC_MIGRATION` rows | Why a direct swap fails | Alternative shape |
|---|---|---|---|
| Async or network calls | `#16`, `#18`, `#19` | Needs callbacks or `async` behavior; Obj-C call sites need rewiring | Single cutover behind a SwiftDashSDK-backed async boundary, with call-site rewiring as needed |
| Stateful balance or UTXO | `#5`, `#9` | SwiftDashSDK depends on SPV-populated state | Sequence after `#11` SPV sync work |
| Persisted data | `#6`, `#7` | This is a storage migration, not a function wrapper | One-shot data migrator on first launch |
| Multi-step async write paths | `#8`, `#16` | Build, sign, and broadcast carry state across steps | Replace the whole boundary at once; do not mix implementations inside one flow |
| Long-running event streams | `#11`, `#20`, parts of `#18` | Not a single call you can wrap | Event-router pattern |
| Side-effect-only calls | `#12`, `#14` | Nothing meaningful to compare | Direct flip with manual verification |
| Not really a migration | `#21`, `#22` | Replace with platform APIs or remove | Handle as a normal code change |

When you hit one of these categories for the first time, stop and confirm the approach with the user before designing it in detail.

## 4. Project structure rules

- New Swift files must be added to both app targets in `DashWallet.xcodeproj/project.pbxproj`.
- For the top-level Infrastructure group in the pbxproj, use `479E7922287C00A000D0F7D7`. Do not attach files to the similarly named Coinbase or DashSpend subgroups.
- Obj-C call sites using a new Swift `@objc` class need `#import "dashwallet-Swift.h"`.
- Both targets use the same generated bridging header name.
- Swift migration files should `import SwiftDashSDK`, never `import DashSync`.
- Remove obsolete DashSync-only files, references, and imports as part of the cutover when they are no longer needed.
- For any remaining SwiftDashSDK shim files added to the pbxproj, extend the existing `A5D5DD0000000000000000...` family and prefer the `...F1` through `...F4` range used by prior migration files.

## 5. Verify-before-assume rule

Before adding defensive fallbacks or special-case branches, read both implementations first.

- DashSync source: `../DashSync/`
- DashSync address logic: `../DashSync/shared/Categories/NSString+Dash.{h,m}`
- DashSync wallet and derivation code: `../DashSync/shared/Models/Wallet/`
- SwiftDashSDK Rust source: `~/.cargo/git/checkouts/rust-dashcore-*/<rev>/`
- SwiftDashSDK revision source of truth: `/Users/bartoszrozwarski/Documents/Developer/platform/Cargo.toml`
- SwiftDashSDK Swift wrappers: `/Users/bartoszrozwarski/Documents/Developer/platform/packages/swift-sdk/Sources/SwiftDashSDK/`

Most of the time the two libraries already behave the same way and the fallback is dead code.

## 6. Verification flow

Run these checks for each cutover:

```bash
plutil -lint DashWallet.xcodeproj/project.pbxproj

xcodebuild build \
  -workspace DashWallet.xcworkspace \
  -scheme dashwallet \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=YES

xcodebuild build \
  -workspace DashWallet.xcworkspace \
  -scheme dashpay \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=YES
```

`EXCLUDED_ARCHS=x86_64` is required because the SwiftDashSDK xcframework only ships `ios-arm64-simulator`.

Also do a focused runtime smoke test of the migrated flow. Since the app no longer preserves staged parity, the runtime gate is the migrated behavior itself, not mismatch logging.

## 7. Update the migration doc on every cutover

Edit `DASHSYNC_MIGRATION.md` in the same change:

- Update the `Where we are` section
- Update the main 22-row table status for the function, usually straight to `✅` for direct cutovers
- If the lesson generalizes to future migrations, update this skill too

## 8. Commit policy

Per `AGENTS.md`, never commit or push without explicit user permission. After making changes, show the diff or summarize the edits and stop for review. Do not treat implementation approval as commit approval.

## 9. Self-improvement clause

At the end of a DashSync migration session, if you learned something that would help migrate other functions later, update this skill before ending the session.

Good additions:

- A reusable Swift and Obj-C bridging gotcha
- A network or enum mapping pitfall
- A commonly mis-targeted pbxproj group
- An FFI signature mismatch pattern
- A verification step that catches a recurring class of bugs
- A category in section 3a that now has a real recipe instead of a placeholder

Do not add one-off lessons that apply only to a single function. Put those in the adapter file or in `DASHSYNC_MIGRATION.md`.
