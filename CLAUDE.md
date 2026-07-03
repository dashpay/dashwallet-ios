# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dash Wallet is an iOS cryptocurrency wallet for the Dash network — a fork of breadwallet implementing SPV (Simplified Payment Verification) for fast mobile performance. Advanced features include DashPay (user-to-user transactions), CoinJoin (privacy), and integrations with external services such as Uphold and Coinbase.

## Build & Setup

```bash
pod install                   # Install dependencies (run after Podfile changes; avoid `pod update` unless needed)
open DashWallet.xcworkspace   # Always open the workspace, not the .xcodeproj
```

- **Schemes**: `dashpay` (DashPay-enabled — **the working scheme during the SwiftDashSDK migration**), `dashwallet` (main app; not kept green on this branch)
- **Configurations**: Debug, TestNet, Release, TestFlight
- **Canonical build** — the SwiftDashSDK FFI xcframework ships an arm64-only simulator slice, so always force `ARCHS=arm64`:
  ```bash
  xcodebuild -workspace DashWallet.xcworkspace -scheme dashpay -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' ARCHS=arm64 build
  ```
- **Tests**: the unit-test target is **currently broken** (pre-existing breakage; new tests such as `PhraseRepairEngineTests` / `PaymentProtocolTests` are written compile-ready but unrunnable). Verification standard while it's broken: clean `dashpay` build + a testnet smoke of the touched flow. `fastlane test` (iPhone 17 simulator) once the target is repaired.

### Required tools
- Xcode 16+
- CocoaPods (`gem install cocoapods`)
- iOS deployment target: **18.0** (raised from 14.0 during the migration — Podfile `platform :ios, '18.0'` + post_install)
- Rust toolchain (builds the SwiftDashSDK FFI; also legacy DashSync)

### Optional tools
- `swiftformat`, `swiftlint`, `clang-format` (Objective-C), `bartycrouch` (localization)

### External repo dependencies (expected as sibling directories)
```
../platform/        # dashpay/platform monorepo — SwiftDashSDK lives at packages/swift-sdk (local SPM dependency)
../DashSync/        # Legacy ObjC protocol library — being migrated OFF (see DASHSYNC_MIGRATION.md)
../dapi-grpc/       # gRPC API definitions
../dashwallet-ios/  # This repository
```

The SwiftDashSDK `DashSDKFFI.xcframework` is **gitignored** — after pulling `../platform`, rebuild it:
```bash
cd ../platform/packages/swift-sdk && ./build_ios.sh --target ios --target sim
```
If the app fails with missing SDK symbols (e.g. "no member …"), `../platform` is on the wrong branch — check the branch/commit pins recorded in `DASHSYNC_MIGRATION.md`.

## MCP / Figma Setup

This project uses the Figma Dev Mode MCP server, configured in `.mcp.json` (`http://127.0.0.1:3845/mcp`). To use it:

1. Run Figma Desktop, enable Dev Mode (`Shift+D`), and click "Enable desktop MCP server" in the inspect panel.
2. Restart Claude Code — MCP servers connect only at startup.
3. Verify the server responds: `curl -s http://127.0.0.1:3845/mcp`

## Architecture

### Languages
- **Objective-C**: legacy wallet functionality, core models, some view controllers
- **Swift**: modern UI, SwiftUI, new features. Many view controllers bridge ObjC ↔ Swift.

### Key directories
- `DashWallet/Sources/Application/` — app lifecycle, constants, configuration
- `DashWallet/Sources/UI/` — UI components, organized by feature
- `DashWallet/Sources/Models/` — business logic, data models, services
- `DashWallet/Sources/Infrastructure/` — core services (networking, database, currency)
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/` — the SwiftDashSDK adapter layer (host, wallet runtime/state, SPV coordinator, transaction sender, identity coordinators) — the app-side boundary to the Rust SDK

### Targets
Main app, `TodayExtension` (widget), and `WatchApp`, with shared code in `Shared/`. Each target has its own deployment target and capabilities.

### Patterns
- **MVVM** — ViewModels for SwiftUI views and modern controllers
- **Protocol-based dependency injection**
- **Service layer** — dedicated services for major functionality (e.g. `SendCoinsService`, `CurrencyExchanger`)
- **Repository / DAO** — data access objects over SQLite
- **Coordinator** — `DWAppRootViewController` manages navigation flow

### Notable services & files
- `WalletSendService.swift` — the send boundary: auth → build+sign (`SwiftDashSDKTransactionSender`) → user confirm → broadcast. `SendCoinsService.swift` is a thin programmatic wrapper over it.
- `SwiftDashSDKHost.swift` / `SwiftDashSDKWalletRuntime.swift` / `SwiftDashSDKWalletState.swift` / `SwiftDashSDKSPVCoordinator.swift` — SDK lifecycle ownership, published wallet state (balance), and chain sync
- `CurrencyExchanger.swift` — fiat currency conversion
- `DatabaseConnection.swift` + `Migrations.bundle/` — SQLite (schema changes require a new timestamped migration)
- `MainTabbarController.swift` — tab-based navigation
- `UIHostingController+DashWallet.swift` — UIKit ↔ SwiftUI bridge

## DashSync → SwiftDashSDK Migration (active)

The app is mid-migration off DashSync. **Source of truth: `DASHSYNC_MIGRATION.md`** (per-function status; staged shadow → flipped → solo → done model). Process playbook: the `dashsync-migration` skill. Invariants that have each already caused a real bug when violated:

- **DashSync is frozen post-M6** — nothing starts its sync. `DWEnvironment.currentChain` / `currentAccount` still exist, but their balances, UTXOs, and `allTransactions` read stale/zero. Read wallet state from `SwiftDashSDKWalletState.shared`; DashSync reads are valid only for the not-yet-migrated surfaces tracked in DASHSYNC_MIGRATION.md.
- **Sync gating**: never gate on SPV `state == .synced` — dash-spv's steady state when fully synced is `waitForEvents` at progress ≈ 1.0 (`.synced` is a transient window). Gate on `SyncingActivityMonitor` (`.syncDone`).
- **Sends**: every spend goes through `WalletSendService` (standard) or `SwiftDashSDKTransactionSender` (selected-input / sweep). Never call `CoreTransactionBuilder` from UI code. `prepare*` never broadcasts; broadcast happens only on explicit confirm.
- **Mnemonic ownership**: stored as plain keychain bytes via SwiftDashSDK `WalletStorage` (the iOS keychain is the security boundary — there is no PIN-encryption layer). Writers: `SwiftDashSDKWalletCreator` / `SwiftDashSDKKeyMigrator`; deletion: `SwiftDashSDKWalletWiper`. Don't add ad-hoc `WalletStorage()` readers — resolve through `SwiftDashSDKHost`.
- **TestNet by design (temporary)**: fresh installs deliberately default to testnet in ALL build configurations while mainnet Platform DAPI is unreachable in the current SDK build (`DWEnvironment.m`; owner decision 2026-07-03). Do not "fix" this; revisit before any release branch.

## UI Development — SwiftUI-First (Mandatory)

All new UI MUST be built in SwiftUI with a ViewModel. Do **not** add new Storyboards, XIBs, or UIViewControllers containing UI logic.

- Keep views lightweight; put business logic in `ObservableObject` ViewModels (`@MainActor`, `@Published` state).
- Concretely banned inside SwiftUI `View` structs: FFI/SDK calls, fee math, auth (`DSAuthenticationManager`) calls, `DSChain`→network mapping, protocol constants. Those live in the ViewModel or a service.
- When integrating with existing UIKit navigation, use a thin `UIHostingController` wrapper only.
- Maintain existing UIKit code but don't extend it; migrate a screen to SwiftUI when substantially reworking it.

## Architecture Guardrails (check before every commit)

Distilled from the 2026-07 branch review (`ARCH_REVIEW_2026-07-03.md`) — each rule exists because we shipped its violation:

1. **Never copy-then-adapt.** If a helper you need is `private`/`fileprivate` in another file (auth gate, main-thread trampoline, SwiftData lookup), promote it to `internal` and reuse it — do not paste a copy, even "temporarily". Copies drift: one clone silently lost the auth watchdog, another missed a cold-launch bug fix. Shared primitives to reuse by name: `AuthenticationGate` (WalletSendService.swift) for PIN/biometric prompts; `ScriptAddressCodec` for address↔script.
2. **Comments state what the code does, never what it should do.** Before writing "X does Y", verify Y's symbol exists and is called (grep it). A deferred behavior is written as `TODO(label): <the gap>` — never as present-tense description. (We shipped a comment claiming a method "does the mirror writes" that didn't exist, and a "confirmation with the real fee" that was neither.)
3. **No stub-and-assert.** A stubbed path must not report success: no UI copy claiming a check passed that never ran, no no-op methods that pretend to act, no silently discarded user input. Stubs throw, disable the control, or are compile-gated. Model unknown data as unknown (`nil` / `.unknown` case) — never fabricate plausible defaults (`.classic`, `.ok`, `[]`, `false`).
4. **New singletons need a reason.** Don't add another `static let shared` in `Sources/Infrastructure/` without a protocol seam or a written justification in the type doc; prefer injecting. One file = one responsibility — a "coordinator" that accumulates published UI counters, storage wipes, and money movement gets split.
5. **Never re-emit another system's notification names.** Re-posting `DS*` notification strings from new state poisons every future grep audit. New state gets a new typed publisher/notification; consumers migrate.
6. **No debug residue in commits:** no session tags in log lines (à la `CJTEST`), no plan-diary comments ("Row #17 stage A", "M5/M6"), no stale line-number cross-references in doc comments. Use `TODO(label)` and link docs instead.
7. **Migration seams stay honest.** Dual DashSync/SDK paths are fine (staged migration), but business logic must not be duplicated on both sides of a seam, and a seam method's name must match its behavior (`prepare` must not spend; `broadcast` must broadcast).

## Code Style

- **Swift**: SwiftFormat / SwiftLint (configs in `.swiftformat`, `.swiftlint.yml`). Avoid wholesale `@objcMembers` exposure (enforced by a custom SwiftLint rule).
- **Objective-C**: NYTimes Objective-C Style Guide.
- 4-space indentation, 180-character line limit (100 recommended).

## Feature Flags (conditional compilation)

- `DASHPAY` — DashPay features (username registration, contacts, invitations, governance voting); built via the `dashpay` scheme.
- `DASH_TESTNET` — defined only in the **dashwallet** target's Debug + TestNet configurations. The **dashpay** scheme's Debug build has `DEBUG` + `DASHPAY` but **not** `DASH_TESTNET` — so anything that must apply to dev builds of both schemes gates on `#if (DEBUG || DASH_TESTNET)`, never `DASH_TESTNET` alone.

## Security

- Legacy surface: jailbreak detection, hardware encryption, Secure Enclave integration (DashSync-era).
- Migration posture changes to keep in mind: the wallet mnemonic is plain keychain data (`WalletStorage`) — device passcode/keychain is the boundary, with no app-side PIN encryption of the seed; ChainLock/InstantSend status is trusted from SwiftDashSDK's context byte (the app no longer does local BLS quorum verification).

## Gotchas (read before touching these areas)

### Versioning — never hardcode versions
All targets use `$(MARKETING_VERSION)`. Never edit version strings in `Info.plist` directly — update **Marketing Version** in Xcode target settings (General tab). When bumping for release, update **every** target (dashwallet, dashpay, TodayExtension, WatchApp, WatchApp Extension). Verify all entries agree:
```bash
# Should print exactly 1
grep -o "MARKETING_VERSION = [^;]*" DashWallet.xcodeproj/project.pbxproj | sort -u | wc -l
```

### DWUpholdMainnetConstants.m gets reformatted on build
A "Run Script - clang-format" build phase adds a stray blank line to this file. If `git status` shows only-whitespace changes there, restore it before committing:
```bash
git restore DashWallet/Sources/Models/Uphold/DWUpholdMainnetConstants.m
```

### CocoaPods deployment targets (post_install)
The Podfile `post_install` script must set deployment targets per platform — setting `IPHONEOS_DEPLOYMENT_TARGET` on watchOS targets breaks the build (CocoaPods 1.15.2+ is strict):
```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if target.platform_name == :ios
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
      elsif target.platform_name == :watchos
        config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '4.0'
      end
    end
  end
end
```

### Localization files are UTF-16LE
iOS `*.lproj/Localizable.strings` files are UTF-16 little-endian, so plain `grep` fails ("Binary file matches"). Convert before searching:
```bash
iconv -f UTF-16LE -t UTF-8 DashWallet/de.lproj/Localizable.strings | grep '"Spend"'
```
Translations sync via Transifex: `tx push -s` (push source) / `tx pull -a` (pull all). Let Xcode and BartyCrouch manage the files; keep them UTF-16LE.

### Figma MCP assets need cleaning for iOS
Figma MCP serves assets at ephemeral `http://localhost:3845/assets/{hash}.svg` URLs (valid only while Figma Desktop + Dev Mode are running). Download them into the asset catalog (`DashWallet/Resources/AppAssets.xcassets/...`) — never reference localhost URLs in code. Then strip web-only SVG features iOS can't render:
- `fill="var(--fill-0, #78C4F5)"` → `fill="#78C4F5"` (CSS variables render invisible)
- `width="100%" height="100%"` → explicit pixel dimensions from the viewBox
- remove `preserveAspectRatio="none"`, `style="display: block;"`, `overflow="visible"`

If icons appear blank after adding an SVG, check for `var(--fill-0, ...)` or `width="100%"` first.
