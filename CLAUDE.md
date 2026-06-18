# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dash Wallet is an iOS cryptocurrency wallet for the Dash network — a fork of breadwallet implementing SPV (Simplified Payment Verification) for fast mobile performance. Advanced features include DashPay (user-to-user transactions), CoinJoin (privacy), and integrations with external services such as Uphold and Coinbase.

## Build & Setup

```bash
pod install                   # Install dependencies (run after Podfile changes; avoid `pod update` unless needed)
open DashWallet.xcworkspace   # Always open the workspace, not the .xcodeproj
```

- **Schemes**: `dashwallet` (main app), `dashpay` (DashPay-enabled build)
- **Configurations**: Debug, Release, TestNet, TestFlight
- **Tests**: `fastlane test` (runs on iPhone 8 simulator per `fastlane/Fastfile`), or run in Xcode.
  Unit tests live in `DashWalletTests/` (XCTest, `@testable`); UI/screenshot tests in `DashWalletScreenshotsUITests/`.

### Required tools
- Xcode 16+
- CocoaPods (`gem install cocoapods`)
- iOS 14.0+ deployment target
- Rust toolchain (for DashSync integration)

### Optional tools
- `swiftformat`, `swiftlint`, `clang-format` (Objective-C), `bartycrouch` (localization)

### External repo dependencies (expected as sibling directories)
```
../DashSync/        # Core Dash protocol library (local dependency)
../dapi-grpc/       # gRPC API definitions
../dashwallet-ios/  # This repository
```

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

### Targets
Main app, `TodayExtension` (widget), and `WatchApp`, with shared code in `Shared/`. Each target has its own deployment target and capabilities.

### Patterns
- **MVVM** — ViewModels for SwiftUI views and modern controllers
- **Protocol-based dependency injection**
- **Service layer** — dedicated services for major functionality (e.g. `SendCoinsService`, `CurrencyExchanger`)
- **Repository / DAO** — data access objects over SQLite
- **Coordinator** — `DWAppRootViewController` manages navigation flow

### Notable services & files
- `SendCoinsService.swift` — transaction creation and broadcasting
- `CurrencyExchanger.swift` — fiat currency conversion
- `DatabaseConnection.swift` + `Migrations.bundle/` — SQLite (schema changes require a new timestamped migration)
- `MainTabbarController.swift` — tab-based navigation
- `UIHostingController+DashWallet.swift` — UIKit ↔ SwiftUI bridge

## UI Development — SwiftUI-First (Mandatory)

All new UI MUST be built in SwiftUI with a ViewModel. Do **not** add new Storyboards, XIBs, or UIViewControllers containing UI logic.

- Keep views lightweight; put business logic in `ObservableObject` ViewModels (`@MainActor`, `@Published` state).
- When integrating with existing UIKit navigation, use a thin `UIHostingController` wrapper only.
- Maintain existing UIKit code but don't extend it; migrate a screen to SwiftUI when substantially reworking it.

## Code Style

- **Swift**: SwiftFormat / SwiftLint (configs in `.swiftformat`, `.swiftlint.yml`). Avoid wholesale `@objcMembers` exposure (enforced by a custom SwiftLint rule).
- **Objective-C**: NYTimes Objective-C Style Guide.
- 4-space indentation, 180-character line limit (100 recommended).

## Feature Flags (conditional compilation)

- `DASHPAY` — DashPay features (username registration, contacts, invitations, governance voting); built via the `dashpay` scheme.

## Security

Jailbreak detection, hardware encryption, private-key protection, and Secure Enclave integration.

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
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
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
