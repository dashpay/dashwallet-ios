# CLAUDE.md

Guidance for Claude Code when working in this repository.

## 🚨 CRITICAL: Git Workflow Policy

**NEVER commit or push changes without explicit user permission.**

1. Make the requested changes
2. Show the diff
3. **STOP and WAIT** for explicit commit/push instruction
4. Each set of changes requires its own explicit permission — earlier approval does NOT carry over

Permission phrases: "commit these changes", "push to github", "commit and push".

After tasks like "address review comments" or "fix these issues", do NOT automatically commit — the user typically wants to test first.

## Project Overview

Dash Wallet is an iOS cryptocurrency wallet for the Dash network (fork of breadwallet, SPV-based). Features include DashPay, CoinJoin, and integrations with Uphold, Coinbase, CTX, and PiggyCards.

## Build & Setup

```bash
pod install                      # Install dependencies
open DashWallet.xcworkspace      # Always use workspace, not project
fastlane test                    # Run tests (iPhone 17 simulator)
swiftformat . && swiftlint       # Lint/format Swift
```

**Schemes**: `dashwallet` (main), `dashpay` (DashPay-enabled). **Configurations**: Debug, Release, TestNet, TestFlight.

**Requirements**: Xcode 16+, CocoaPods, iOS 17.0+, Rust toolchain. Expects sibling dirs `../DashSync/`, `../dapi-grpc/`, and `../platform/` (for `SwiftDashSDK` local SPM package at `../platform/packages/swift-sdk`).

## Architecture

- **DashWallet/** — main app (mixed Objective-C legacy + Swift/SwiftUI modern)
- **DashPay/** — DashPay UI components
- **TodayExtension/**, **WatchApp/** — extensions
- **Shared/** — shared utilities

Key dirs: `Sources/Application/` (lifecycle), `Sources/UI/` (feature-organized), `Sources/Models/` (business logic), `Sources/Infrastructure/` (networking, DB, currency).

**Patterns**: Protocol-based DI, MVVM (SwiftUI), service layer, coordinator (`DWAppRootViewController`), repository/DAO.

## MCP: Figma Dev Mode

Config at `~/Library/Application Support/Claude/claude_desktop_config.json`; project uses `.mcp.json` pointing to `http://127.0.0.1:3845/mcp`.

Enable in Figma Desktop: `Shift+D` → Dev Mode → "Enable desktop MCP server". Restart Claude Code (MCP connects only at startup). Troubleshoot: `curl -s http://127.0.0.1:3845/mcp`.

## UI Development (MANDATORY)

### SwiftUI-First Policy
**All new UI MUST be SwiftUI.** NO new Storyboards, XIBs, or UIViewController subclasses with UI logic.

- New screens: SwiftUI `View` + `@StateObject` `ViewModel` (business logic in ViewModel, not View)
- UIKit bridging: thin `UIHostingController` wrappers only
- Existing UIKit: maintain, don't extend; migrate gradually; extract logic to ViewModels
- Use Combine / `@Published` for reactive data flow

### Navigation
- SwiftUI: `NavigationStack` + `.navigationDestination`
- UIKit integration: helper extensions pushing `UIHostingController`

## Asset & Icon Management

### SVG Assets (Prefer SVG over PNG)
```json
{
  "images": [{"filename": "icon.svg", "idiom": "universal"}],
  "info": {"author": "xcode", "version": 1},
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template"
  }
}
```

**Shortcut bar icons**: use `"original"` rendering — `template` strips fill colors and applies system tint, causing grey icons in SwiftUI `Button` labels.

### Figma MCP Asset Download (MANDATORY)
Figma MCP image URLs (`http://localhost:3845/assets/{hash}.svg`) are **ephemeral** — download immediately to asset catalog, verify visually in app, then commit.

```bash
curl -s -o /path/to/IconName.imageset/icon.svg "http://localhost:3845/assets/{hash}.svg"
file /path/to/icon.svg   # Verify: SVG Scalable Vector Graphics image
```

### ⚠️ Clean SVGs from Figma (iOS Compatibility)
Figma exports web-specific features iOS cannot render:

| Feature | Problem | Fix |
|---|---|---|
| `fill="var(--fill-0, #78C4F5)"` | CSS vars unsupported — invisible paths | Replace with `fill="#78C4F5"` |
| `width="100%" height="100%"` | iOS needs explicit dimensions | Use viewBox dimensions |
| `preserveAspectRatio="none"` | Web-specific | Remove |
| `style="display: block;"` | Web-specific | Remove |
| `overflow="visible"` | Web-specific | Remove |

If icons appear blank after adding SVGs, check for `var(--fill-0,...)` or `width="100%"` first.

### Home Screen Shortcut Bar
Four states based on balance + passphrase verification. Files:
- `HomeViewModel.swift` — `reloadShortcuts()`
- `ShortcutAction.swift` — enum, icon/title mappings
- `HomeViewController+Shortcuts.swift` — action handlers
- `ShortcutsView.swift` — UI

## Localization (Transifex)

25+ languages, managed via BartyCrouch + Transifex. Config in `.tx/config`.

```bash
xcodebuild -workspace DashWallet.xcworkspace -scheme dashwallet  # Build to generate strings
tx push -s       # Push source
tx pull -a       # Pull all
tx pull -l de    # Pull one language
```

### ⚠️ iOS .strings files are UTF-16LE

Standard Unix tools fail on raw files. Always convert via `iconv`:
```bash
iconv -f UTF-16LE -t UTF-8 DashWallet/de.lproj/Localizable.strings | grep '"Spend" = '
```
Xcode handles encoding transparently — keep files as UTF-16LE.

## Version Management

**NEVER** hardcode versions in Info.plist. All targets use `$(MARKETING_VERSION)`.

Update via Xcode project settings → target → General → Marketing Version. **All targets must match** (dashwallet, dashpay, TodayExtension, WatchApp, WatchApp Extension — 20+ entries in project.pbxproj).

Verify:
```bash
grep "MARKETING_VERSION" DashWallet.xcodeproj/project.pbxproj | grep -v "MARKETING_VERSION = X.Y.Z;"
grep -o "MARKETING_VERSION = [^;]*" DashWallet.xcodeproj/project.pbxproj | sort -u | wc -l  # expect 1
```

## Files That Get Unintentionally Modified

⚠️ **`DWUpholdMainnetConstants.m`** — clang-format build phase adds blank lines. Before commit: `git restore DashWallet/Sources/Models/Uphold/DWUpholdMainnetConstants.m` if only whitespace changes.

## CocoaPods Deployment Target

⚠️ Post-install script **must set targets per platform** (CocoaPods 1.15.2+ is strict):

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

Setting `IPHONEOS_DEPLOYMENT_TARGET` on watchOS targets will fail the build.

## Conditional Compilation Patterns

Feature flags: `DASHPAY`, `PIGGYCARDS_ENABLED`.

### Avoid These Pitfalls

**SwiftUI ViewBuilder** — `#if` inside `if` expressions causes "buildExpression unavailable". Extract to computed property:
```swift
private var shouldShow: Bool {
    if baseCondition { return true }
    #if FEATURE_ENABLED
    return extra
    #else
    return false
    #endif
}
```

**Dictionary/array literals** — use closure initialization:
```swift
let dict: [K: V] = {
    var r = [.a: 1]
    #if FEATURE_ENABLED
    r[.b] = 2
    #endif
    return r
}()
```

**Boolean expressions** — don't leave dangling operators. Assign to a flag via `#if` first.

## Network Switching (Testnet/Mainnet)

API endpoints **must switch dynamically** without app restart. Never cache base URL as constant:

```swift
// ❌ WRONG
private let kBaseURL = URL(string: CTXConstants.baseURI)!
public var baseURL: URL { return kBaseURL }

// ✅ CORRECT
public var baseURL: URL { return URL(string: CTXConstants.baseURI)! }
```

**CTX endpoints**: mainnet `https://spend.ctx.com/`, staging `https://staging.spend.ctx.com/` (HTTPS — not HTTP).

## Database

SQLite via `DatabaseConnection.swift`. Migrations in `Migrations.bundle/` — schema changes need new timestamped migration files.

### Location Query: Rectangular vs Circular Filtering

**Critical pattern**: SQL uses indexed lat/lon rectangular bounds, but users expect circular radius. Always apply **two-step filter**:

```swift
// Step 1: Expand rectangular bounds by 50% for SQL query
func calculateExpandedBounds(from bounds: ExploreMapBounds) -> ExploreMapBounds {
    let centerLat = (bounds.minLatitude + bounds.maxLatitude) / 2
    let centerLon = (bounds.minLongitude + bounds.maxLongitude) / 2
    let latSpan = (bounds.maxLatitude - bounds.minLatitude) * 1.5
    let lonSpan = (bounds.maxLongitude - bounds.minLongitude) * 1.5
    return ExploreMapBounds(/* expanded */)
}

// Step 2: Apply precise circular filter in memory using CLLocation.distance(from:)
```

Rectangular bounds don't guarantee circular compliance. Without the buffer, results are inconsistent depending on map bounds timing.

### Merchant Search: All Tab vs Nearby Tab

`MerchantDAO.items()` has two paths based on `userLocation` parameter:
- **With `userLocation`**: in-memory grouping, finds closest location per merchant, excludes online merchants without coords
- **Without `userLocation`**: pure SQL with GROUP BY/ORDER BY, includes online merchants

Pass **appropriate params per tab**:
- **Nearby tab**: pass both `bounds` and `userPoint`
- **All tab / Online tab**: pass `nil` for both

In-memory grouping **must handle merchants without coordinates** (online merchants) explicitly, or they'll be dropped.

## Swift Code Quality

- **Never force-unwrap** `latitude!`, `longitude!`, `lastBounds!` — use `guard let`
- **Generic inference failures**: add explicit closure return type, e.g. `compactMap { m -> MerchantAnnotation? in ... }`
- **Template images**: `.withRenderingMode(.alwaysTemplate)` for SVG tint
- **Radius constant**: use `kDefaultRadius` (32000m), not hardcoded values
- **Debug prints**: wrap in `#if DEBUG`; 100+ prints cause visible jank. Use `os.log` `Logger` for production-safe logging (stripped in release).
- **Empty switch cases**: when removing debug prints, use `break` or drop the case.

Debug log prefixes: 🔍 search, 📍 location, 🗺️ map, 🎯 PiggyCards, 🌐 network, 💾 DB, 🎨 UI.

## CTX/DashSpend Integration

### Environment Differences

| | Production | Staging |
|---|---|---|
| **Base URL** | `https://spend.ctx.com/` | `https://staging.spend.ctx.com/` (HTTPS!) |
| **Discount field** | `savingsPercentage` | `userDiscount` |
| **getMerchant auth** | Public | Requires `Authorization` header |
| **Gift card response** | Single object | Paginated `{data: [...], meta}` |

Handle both with fallback chains and shape detection:
```swift
let discount = json["savingsPercentage"] as? Double
    ?? json["userDiscount"] as? Double ?? 0.0

if let arr = json["data"] as? [[String: Any]], let first = arr.first {
    return GiftCard(json: first)    // staging
}
if let _ = json["uuid"] as? String { return GiftCard(json: json) }  // production
```

### Transaction ID vs Gift Card UUID
Gift card fetch endpoint uses blockchain **txid**, not the card's internal UUID:
```swift
let endpoint = "/api/v1/purchases/gift_cards/\(transaction.txid)"  // ✅
```

### Multi-Provider Database Architecture
Database stores duplicate merchant data per provider. **Always filter by active provider**:

```swift
private var activeProvider: String {
    #if PIGGYCARDS_ENABLED
    return UserDefaults.standard.string(forKey: "selectedProvider") ?? "ctx"
    #else
    return "ctx"
    #endif
}
// SELECT * FROM gift_card_providers WHERE merchant_id = ? AND provider = ?
```

Without provider filtering, you get duplicate rows / wrong discount display.

### Key Files
`CTXSpendEndpoint.swift`, `CTXSpendService.swift`, `CTXSpendConstants.swift`, `MerchantDAO.swift`, `GiftCardProvider.swift`.

## PiggyCards Integration

### Critical: sourceId in gift_card_providers
The `sourceId` column maps merchants to provider-specific IDs:
- **CTX**: UUID strings (`"84793fe2-603d-..."`)
- **PiggyCards**: numeric IDs (`"18"`, `"45"`, `"89"`)

All SQL queries **MUST include `sourceId`** or API calls fail with empty `giftCardProviders` arrays.

```swift
struct GiftCardProviderInfo {
    let providerId: String
    let provider: GiftCardProvider?
    let savingsPercentage: Int
    let denominationsType: String
    let sourceId: String?  // CRITICAL
}
```

`sourceId` can be String, Int64, Int, or NULL — handle all cases:
```swift
var sourceIdString: String? = nil
if let s = row[3] as? String, !s.isEmpty { sourceIdString = s }
else if let i = row[3] as? Int64 { sourceIdString = String(i) }
else if let i = row[3] as? Int { sourceIdString = String(i) }
```

### Denomination Types: API is Source of Truth
When signed in, **API response overrides database** values. Different providers may have different types for the same merchant (e.g., Domino's: CTX flexible, PiggyCards fixed $25).

When setting denomination state, **clear the opposite fields**:
```swift
if normalizedPriceType == PiggyCardsPriceType.range.rawValue {
    isFixedDenomination = false
    minimumAmount = Decimal(card.minDenomination)
    maximumAmount = Decimal(card.maxDenomination)
    denominations = []  // CRITICAL
} else if normalizedPriceType == PiggyCardsPriceType.fixed.rawValue {
    isFixedDenomination = true
    denominations = parseDenominations(card.denomination)
    minimumAmount = 0  // CRITICAL
    maximumAmount = 0
}
```

Enable via `PIGGYCARDS_ENABLED` in Swift Compiler Custom Flags.

### Key Files
`PiggyCardsRepository.swift`, `PiggyCardsAPI.swift`, `PiggyCardsTokenService.swift` (Actor), `PiggyCardsModels.swift`.

## Gift Card Payment Authorization

**CTX vs PiggyCards use different payment methods — this is critical.**

- **CTX**: returns BIP70 URL `dash:?r=https://api.ctx.com/...` → use `sendCoinsService.payWithDashUrl()`. PIN auth via BIP70 flow.
- **PiggyCards**: returns plain `dash:XpEBa5...?amount=1.234567` → use `sendCoinsService.sendCoins(address:amount:)` directly. PIN auth via `account.sign()`.

```swift
switch provider {
case .ctx:
    transaction = try await sendCoinsService.payWithDashUrl(url: paymentUrl)
case .piggyCards:
    let sats = UInt64(giftCardInfo.amount * 100_000_000)
    transaction = try await sendCoinsService.sendCoins(
        address: giftCardInfo.paymentAddress, amount: sats)
}
```

Using `payWithDashUrl` for PiggyCards fails (no `r` param) and blocks PIN authorization.

## Gift Card Token Expiration

| | CTX | PiggyCards |
|---|---|---|
| **When** | `viewDidLoad()` (proactive) | Buy button click (on-demand) |
| **Method** | `tryRefreshCtxToken()` | `tryRefreshPiggyCardsToken()` |
| **Why** | Fetches updated merchant info | Avoids delay during browsing |

On `DashSpendError.tokenRefreshFailed`: logout user (`PiggyCardsRepository.shared.logout()` for PiggyCards) and show "session expired" dialog. Wrap PiggyCards code in `#if PIGGYCARDS_ENABLED`.

## Gift Card Barcodes & Claim Links

### Barcode Scanner Architecture
`BarcodeScanner.swift` tries URL query parameter extraction first (fast, simulator-compatible), then falls back to image download + Vision scan.

```swift
static func downloadAndScan(from url: String) async -> BarcodeResult? {
    if let value = extractBarcodeFromURL(url) {  // primary: fast, reliable
        return BarcodeResult(value: value, format: .code128)
    }
    // fallback: download and scan image via Vision
}

private static func extractBarcodeFromURL(_ url: String) -> String? {
    // Checks common param names: "text", "data", "code", "barcode"
}
```

Example: `https://piggy.cards/index.php?route=tool/barcode&text=12345727` → extracts `12345727`.

Vision framework fails in simulator (Neural Engine unavailable) — URL extraction avoids this.

### Supported Formats
CODE_128 (most common for gift cards), QR, CODE_39/93, EAN_13/8, UPC_A/E, PDF417, Aztec, DataMatrix, ITF. Core Image filters: `CICode128BarcodeGenerator`, `CIQRCodeGenerator`, `CIPDF417BarcodeGenerator`, `CIAztecCodeGenerator`, `CIDataMatrixCodeGenerator`.

QR codes use UTF-8 input; linear barcodes use ASCII. QR scale 5.0/5.0, linear scale 3.0/5.0.

### Barcode Flow Per Provider
- **CTX**: `response.barcodeUrl` → download+scan, else generate from `cardNumber` as CODE_128
- **PiggyCards**: `card.barcodeLink` → download+scan, else generate from `claimCode` as CODE_128

After `updateBarcode`, **always** `await loadGiftCard()` to reload UI.

### Claim Links (Online Redemption)
Some merchants (e.g., Applebees) deliver URLs instead of barcodes. Store link in `number` field with `pin: nil`. UI detects via `number.starts(with: "http")` and renders as tappable button opening Safari.

### Vision Framework Pattern
Use `resumed` flag to prevent double-resumption crashes:
```swift
return await withCheckedContinuation { continuation in
    DispatchQueue.global(qos: .userInitiated).async {
        var resumed = false
        let request = VNDetectBarcodesRequest { req, err in
            guard !resumed else { return }
            resumed = true
            // ... resume once
        }
        // ... handler.perform
    }
}
```

### Key Files
`BarcodeScanner.swift`, `GiftCardDetailsViewModel.swift`, `GiftCardsDAO.swift`, `PiggyCardsModels.swift`, `CTXSpendModels.swift`.

## Discount Formatting

Display with appropriate precision:
```swift
private func formatDiscount(_ basisPoints: Int) -> String {
    let pct = Double(basisPoints) / 100.0
    return pct < 1.0
        ? String(format: "-%.1f%%", pct)  // 0.5% → "-0.5%"
        : String(format: "-%.0f%%", pct)  // 10.0% → "-10%"
}
```

**Common pitfall**: use `.doubleValue`, not `.intValue` — truncation loses sub-1% precision.

Apply in: `POIDetailsView.swift`, `DashSpendPayViewModel.swift`, merchant list displays.

## Adding Test Merchants to Database

Database location:
```bash
DB_PATH=$(find ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Documents/explore.db -type f -exec stat -f '%Sm %N' -t '%Y-%m-%d %H:%M:%S' {} \; 2>/dev/null | sort -r | head -1 | awk '{print $3}')
```

### ⚠️ FTS Triggers Block INSERT
The `merchant` table has FTS AFTER INSERT triggers that fail with "unsafe use of virtual table". Must:
1. Drop FTS triggers
2. Insert into `merchant` AND `gift_card_providers` (both required)
3. Manually `INSERT INTO merchant_fts(docid, name) SELECT rowid, name FROM merchant WHERE ...`
4. Recreate triggers

### Standard PiggyCards Test Merchant
- **merchantId**: `'2e393eee-4508-47fe-954d-66209333fc96'` (UUID format)
- **name**: `'Piggy Cards Test Merchant'`
- **source**: `'PiggyCards'` (case-sensitive)
- **sourceId**: `'177'`
- **savingsPercentage**: `1000` (basis points: 10% × 100)
- **denominationsType**: `'Fixed'`
- **paymentMethod**: `'gift card'`

**provider field enum values**: `'ctx'` lowercase, `'piggyCards'` camelCase.

### Cleanup
```sql
DELETE FROM gift_card_providers WHERE merchantId = '2e393eee-4508-47fe-954d-66209333fc96';
DELETE FROM merchant WHERE merchantId = '2e393eee-4508-47fe-954d-66209333fc96';
INSERT INTO merchant_fts(merchant_fts) VALUES('rebuild');
```

## Testing

- Unit: `DashWalletTests/` with mock providers, XCTest `@testable`, JSON fixtures
- UI: `DashWalletScreenshotsUITests/` for App Store screenshots
- Fastlane: iPhone 17 simulator

## Security

Jailbreak detection, hardware encryption, private key protection, Secure Enclave integration.

## Git Branch Tracking for Xcode

If Xcode's Changes tab doesn't show committed changes on a local-only branch, create a local remote ref at divergence point:

```bash
git update-ref refs/remotes/origin/feature/my-branch $(git merge-base feature/my-branch master)
```

This is local only — doesn't push anything. Restart Xcode after.

## Systematic Debugging

1. **Log everything first** before forming hypotheses
2. **Compare working vs non-working** inputs
3. **Question assumptions** — "different results" ≠ "race condition"; may be architectural
4. **Clean debug code** before committing (prints cause jank, empty switch cases break compilation)
