# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🚨 CRITICAL: Git Workflow Policy

**NEVER commit or push changes without explicit user permission.**

When the user asks you to make code changes:
1. Make the requested changes to the code
2. Show what was changed (using `git diff` or explanation)
3. **STOP and WAIT** for explicit permission to commit/push
4. Only commit/push when the user explicitly says to do so

**Example phrases that give permission to commit/push:**
- "commit these changes"
- "push to github"
- "create a commit and push"
- "commit and push all changes"

**Do NOT commit/push** just because the user asked for code changes. They may want to review first.

## Project Overview

Dash Wallet is an iOS cryptocurrency wallet application built for the Dash network. It's a fork of breadwallet that implements SPV (Simplified Payment Verification) for fast mobile performance. The app includes advanced features like DashPay for user-to-user transactions, CoinJoin for privacy, and integrations with external services like Uphold and Coinbase.

## MCP (Model Context Protocol) Server Configuration

### Overview
MCP servers extend Claude Code's capabilities by providing access to external services and tools. This project uses MCP servers for Figma design integration.

### Required Configuration
MCP servers must be configured in Claude Desktop's configuration file. Without this configuration, MCP tools will not be available even if they were used in previous sessions.

**Configuration file location**: `~/Library/Application Support/Claude/claude_desktop_config.json`

### Setting Up Figma MCP Server

1. **Create or update the configuration file**:
```bash
cat > ~/Library/Application\ Support/Claude/claude_desktop_config.json << 'EOF'
{
  "mcpServers": {
    "figma-dev-mode": {
      "command": "npx",
      "args": ["-y", "@figma/mcp-server-figma-dev-mode"],
      "description": "Figma Dev Mode MCP server for extracting design specifications, code, and images from Figma files"
    }
  }
}
EOF
```

2. **Restart Claude Code**:
   - Stop Claude Code with `Ctrl+C` in the terminal
   - Restart with the `claude` command
   - MCP servers are only connected at startup

3. **Verify MCP tools are available**:
   - After restart, MCP tools should appear as:
     - `mcp__figma-dev-mode-mcp-server__get_code`
     - `mcp__figma-dev-mode-mcp-server__get_image`
     - `mcp__figma-dev-mode-mcp-server__get_metadata`

### Figma Requirements

For the Figma MCP server to work properly:
1. **Figma Desktop App** must be running
2. **Dev Mode** must be enabled (press `Shift+D` in Figma)
3. **File permissions** must allow public access or you must be logged in

### Troubleshooting MCP Issues

If MCP tools are not available:
1. **Check configuration exists**: `cat ~/Library/Application\ Support/Claude/claude_desktop_config.json`
2. **Verify Figma is running**: `ps aux | grep -i figma`
3. **Restart Claude Code**: MCP connections are only established at startup
4. **Check npx availability**: Ensure Node.js/npm is installed for npx command

### Why MCP Configuration is Required

- MCP servers are external processes that Claude Code connects to
- Configuration tells Claude where to find and how to start MCP servers
- Without the configuration file, Claude Code has no knowledge of available MCP servers
- Previous sessions' MCP usage (recorded in `.claude/settings.local.json`) doesn't automatically enable MCP in new sessions

## Build Commands

### Setup
```bash
# Install dependencies
pod install

# Open workspace (always use workspace, not project)
open DashWallet.xcworkspace
```

### Building
- **Primary build**: Use Xcode to build the `dashwallet` scheme
- **DashPay build**: Use the `dashpay` scheme for DashPay-enabled version
- **Configurations**: Debug, Release, TestNet, TestFlight

### Testing
```bash
# Run tests via fastlane
fastlane test

# Or in Xcode, run tests on iPhone 8 simulator (as configured in Fastfile)
```

### Linting and Formatting
```bash
# Swift formatting (if installed)
swiftformat .

# Swift linting (if installed) 
swiftlint

# Objective-C formatting (if installed)
clang-format -i **/*.{h,m}

# Localization updates (if installed)
bartycrouch update
```

## Architecture Overview

### Project Structure
- **DashWallet/**: Main application target
- **DashPay/**: DashPay-specific UI components
- **TodayExtension/**: Today widget
- **WatchApp/**: Apple Watch companion app
- **Shared/**: Shared utilities between targets

### Core Components

#### Language Distribution
- **Objective-C**: Legacy wallet functionality, core models, view controllers
- **Swift**: Modern UI, SwiftUI components, new features
- **Mixed**: Many view controllers bridge between ObjC and Swift

#### Key Directories
- `DashWallet/Sources/Application/`: App lifecycle, constants, configuration
- `DashWallet/Sources/UI/`: All UI components organized by feature
- `DashWallet/Sources/Models/`: Business logic, data models, services
- `DashWallet/Sources/Infrastructure/`: Core services (networking, database, currency)

#### External Dependencies
- **DashSync**: Core Dash protocol implementation (local dependency)
- **CocoaPods**: Dependency manager for 20+ external libraries
- **Firebase**: Dynamic links and storage
- **SQLite**: Local database with migration support

### Data Flow Architecture

#### Models and Services
- **CoinJoin**: Privacy mixing transactions (`CoinJoinService.swift`)
- **Transactions**: Transaction management and metadata
- **Currency Exchange**: Real-time fiat conversion
- **Database**: SQLite with migration system

#### Key Services
- `SendCoinsService.swift`: Transaction creation and broadcasting
- `CurrencyExchanger.swift`: Fiat currency conversion
- `DatabaseConnection.swift`: SQLite abstraction layer
- `HTTPClient.swift`: Network requests

### UI Architecture

#### Navigation Structure
- `DWAppRootViewController`: Main app coordinator
- `MainTabbarController.swift`: Tab-based navigation
- Feature-based view controller organization

#### SwiftUI Integration
- Modern SwiftUI components in `SwiftUI Components/`
- Legacy UIKit views being gradually migrated
- `UIHostingController+DashWallet.swift`: Bridge between UIKit and SwiftUI

## Development Guidelines

### Code Style
- Follow NYTimes Objective-C Style Guide for ObjC code
- Use SwiftFormat/SwiftLint for Swift code formatting (configurations in `.swiftformat` and `.swiftlint.yml`)
- Mixed language files should follow the primary language's conventions
- 4-space indentation, 180-character line limit (100 recommended)
- Avoid `@objcMembers` wholesale exposure (enforced by custom SwiftLint rule)

### Testing Strategy  
- Unit tests in `DashWalletTests/` with mock providers for isolation
- UI tests in `DashWalletScreenshotsUITests/` for App Store screenshot generation
- Test framework uses XCTest with `@testable` imports
- JSON-based test data for consistent API mocking
- Fastlane automation for testing on iPhone 8 simulator

### Localization Workflow
- 25+ languages supported via Transifex integration
- BartyCrouch automates string extraction and normalization
- Process: Build project → `tx push -s` → `tx pull` for translations
- UTF-8 encoding with automatic key sorting and harmonization
- Supports App Store metadata localization

#### Important: UTF-16 Encoding in Translation Files
**Critical Issue**: Translation files downloaded from Transifex may use different encodings:
- **English source file** (`en.lproj/Localizable.strings`): UTF-8 encoding
- **Translated files**: Often UTF-16 little-endian encoding

This causes command-line tools like `grep` to fail when searching for translations:
```bash
# ❌ WRONG - Won't find strings in UTF-16 files
grep '"Spend"' DashWallet/de.lproj/Localizable.strings

# ✅ CORRECT - Convert encoding first
iconv -f UTF-16 -t UTF-8 DashWallet/de.lproj/Localizable.strings | grep '"Spend"'
```

**To check translations properly:**
```bash
# Check file encoding
file DashWallet/*/lproj/Localizable.strings

# Search all translation files regardless of encoding
for file in DashWallet/*.lproj/Localizable.strings; do
    lang=$(basename $(dirname "$file") .lproj)
    if file "$file" | grep -q UTF-16; then
        # UTF-16 file - convert before searching
        translation=$(iconv -f UTF-16 -t UTF-8 "$file" 2>/dev/null | grep '"Spend"' | sed 's/.*= "//; s/";//')
    else
        # UTF-8 file - search directly
        translation=$(grep '"Spend"' "$file" 2>/dev/null | sed 's/.*= "//; s/";//')
    fi
    if [ -n "$translation" ]; then
        echo "$lang: $translation"
    fi
done
```

**Note**: Xcode and iOS handle both encodings transparently, so this only affects command-line operations. The app will display translations correctly regardless of the file encoding.

### Build Configurations
- **Debug**: Development with full debugging and logging
- **Release**: Production optimized build
- **TestNet**: Connects to Dash testnet for development
- **TestFlight**: Beta distribution with automatic build number increment

### Development Patterns
- **Protocol-Based Design**: Extensive use of protocols for dependency injection
- **MVVM Pattern**: ViewModels for SwiftUI components and modern controllers
- **Service Layer**: Dedicated services for major functionality (CoinJoin, networking, database)
- **Coordinator Pattern**: `DWAppRootViewController` manages app navigation flow
- **Repository Pattern**: Data Access Objects (DAOs) for database operations

## UI Development Guidelines (CRITICAL)

### 🎯 SwiftUI-First Development Policy
**MANDATORY**: All new UI components MUST be built with SwiftUI. Do NOT create new UIKit ViewControllers or Storyboards.

#### ✅ Preferred Approach
```swift
// New screens should be SwiftUI views with ViewModels
struct MerchantDetailsView: View {
    @StateObject private var viewModel: MerchantDetailsViewModel

    var body: some View {
        VStack {
            // SwiftUI implementation
        }
    }
}

class MerchantDetailsViewModel: ObservableObject {
    @Published var merchant: Merchant
    // Business logic here
}
```

#### 🔄 UIKit Integration (When Required)
Only create thin UIViewController wrappers when integrating with existing UIKit navigation:

```swift
// Thin wrapper for UIKit integration
class MerchantDetailsHostingController: UIHostingController<MerchantDetailsView> {
    init(merchant: Merchant) {
        let viewModel = MerchantDetailsViewModel(merchant: merchant)
        let swiftUIView = MerchantDetailsView(viewModel: viewModel)
        super.init(rootView: swiftUIView)
    }
}
```

#### ❌ Prohibited Patterns
- **NO new Storyboard files** - Storyboards are legacy and should not be extended
- **NO new XIB files** - Use SwiftUI declarative syntax instead
- **NO UIViewController subclasses with UI logic** - Use hosting controllers only as thin wrappers
- **NO Interface Builder** - All UI should be programmatic via SwiftUI

### SwiftUI Architecture Patterns

#### View-ViewModel Separation
```swift
// Views should be lightweight and delegate to ViewModels
struct PaymentView: View {
    @StateObject private var viewModel: PaymentViewModel

    var body: some View {
        // UI only - no business logic
        Form {
            Section("Amount") {
                TextField("Enter amount", text: $viewModel.amount)
            }

            Button("Send Payment") {
                viewModel.processPayment()
            }
            .disabled(viewModel.isProcessing)
        }
        .alert("Error", isPresented: $viewModel.hasError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}
```

#### State Management
```swift
// ViewModels handle state and business logic
@MainActor
class PaymentViewModel: ObservableObject {
    @Published var amount: String = ""
    @Published var isProcessing: Bool = false
    @Published var hasError: Bool = false
    @Published var errorMessage: String = ""

    private let paymentService: PaymentService

    func processPayment() {
        // Business logic implementation
    }
}
```

### Navigation Patterns

#### SwiftUI Navigation
Use SwiftUI's navigation system for new screens:

```swift
NavigationStack {
    MerchantListView()
        .navigationDestination(for: Merchant.self) { merchant in
            MerchantDetailsView(merchant: merchant)
        }
}
```

#### Legacy UIKit Integration
When interfacing with existing UIKit navigation:

```swift
extension UINavigationController {
    func pushSwiftUIView<Content: View>(_ view: Content) {
        let hostingController = UIHostingController(rootView: view)
        pushViewController(hostingController, animated: true)
    }
}
```

### Migration Guidelines

#### Existing UIKit Code
- **Maintain existing UIKit code** but don't extend it
- **Gradually replace** UIKit screens with SwiftUI equivalents when updating
- **Extract business logic** from existing ViewControllers into ViewModels that can be reused with SwiftUI

#### Data Binding
Use Combine for reactive data flow between services and SwiftUI:

```swift
class DataService: ObservableObject {
    @Published var merchants: [Merchant] = []

    func fetchMerchants() {
        // API call that updates @Published properties
    }
}
```

## Icon and Asset Management Guidelines

### SVG Support and Usage
iOS supports SVG files directly in image assets since iOS 13/Xcode 12. **Always prefer SVG over PNG** for new icons when available.

#### ✅ Correct SVG Implementation
```json
// Contents.json for SVG icons
{
  "images" : [
    {
      "filename" : "icon.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
```

**Key Properties:**
- `preserves-vector-representation`: Ensures SVG scales perfectly at any size
- `template-rendering-intent`: Allows icon to adapt to app's tint colors

#### Icon Asset Location
- **Shortcut icons**: `/DashWallet/Resources/AppAssets.xcassets/Shortcuts/`
- **Explore Dash icons**: `/DashWallet/Resources/AppAssets.xcassets/Explore Dash/`
- **General app icons**: `/DashWallet/Resources/AppAssets.xcassets/`

### Home Screen Shortcut Bar Implementation

The shortcut bar displays different button combinations based on wallet state:

#### Four Shortcut States
1. **Zero balance + Not verified passphrase**: Backup, Receive, Buy & Sell, Spend
2. **Zero balance + Verified passphrase**: Receive, Send, Buy & Sell, Spend
3. **Has balance + Verified passphrase**: Receive, Send, Scan, Spend
4. **Has balance + Not verified passphrase**: Backup, Receive, Send, Spend

#### Implementation Files
- **Shortcut logic**: `HomeViewModel.swift` - `reloadShortcuts()` method
- **Action types**: `ShortcutAction.swift` - enum definitions and icon mappings
- **Action handlers**: `HomeViewController+Shortcuts.swift` - navigation logic
- **UI component**: `ShortcutsView.swift` - collection view display

#### Adding New Shortcut Icons
1. Add the case to `ShortcutActionType` enum
2. Map the icon name in the `icon` computed property
3. Add localized title in the `title` computed property
4. Implement action handler in `HomeViewController+Shortcuts.swift`
5. Update `reloadShortcuts()` logic if needed

### Icon Implementation Best Practices

#### When Updating Icons from Figma
1. **Check for existing icons first** - Many icons already exist in the project
   ```bash
   # Search for existing icons
   find /path/to/project -name "*.svg" -o -name "*.png" | grep -i "icon_name"
   ```

2. **Use SVG directly from Figma** - Don't convert to PNG unnecessarily
   - Download SVG from Figma localhost server
   - Save directly to appropriate imageset folder
   - Update Contents.json to reference SVG

3. **Verify icon usage** - Always test that the correct icon appears
   - Wrong icons often indicate using placeholder or copied assets
   - Check that imageset name matches the one referenced in code

4. **Clean up old assets** - Remove unused PNG files when replacing with SVG
   ```bash
   rm -f /path/to/imageset/*.png
   ```

### Common Icon Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Wrong icon displayed | Using placeholder/copied assets | Replace with actual icon from design |
| Icon not appearing | Missing imageset or wrong name | Verify imageset exists and name matches code |
| Icon wrong color | Not using template rendering | Add `"template-rendering-intent": "template"` |
| Icon blurry | Using PNG instead of SVG | Replace with SVG for vector scaling |
| Icon too large/small | Fixed size constraints | Use SVG with `preserves-vector-representation` |

## Important Files

### Configuration
- `Podfile`: CocoaPods dependencies and post-install scripts (⚠️ See CocoaPods section below for critical deployment target setup)
- `DashWallet.xcworkspace`: Main workspace file (always use workspace, not project file)
- `fastlane/Fastfile`: Build and deployment automation
- `Info.plist`: App metadata and capabilities

### Core Application
- `AppDelegate.h/m`: App lifecycle (Objective-C)
- `App.swift`: Modern app utilities (Swift)
- `Constants.swift`: Application-wide constants

### Database
- `DatabaseConnection.swift`: SQLite interface
- `Migrations.bundle/`: SQL migration files
- Schema changes require new migration files with timestamps

### Files That Get Unintentionally Modified

⚠️ **DWUpholdMainnetConstants.m** - This file frequently gets whitespace changes (extra blank lines) that should not be committed.

**Root Cause:** The Xcode project has a build phase script called "Run Script - clang-format" that automatically formats all Objective-C files (*.h, *.m, *.mm) during builds. This script adds an unwanted blank line after the return statement in the `logoutURLString` method.

**When working with git:**
- Before committing, always check if this file has changes: `git status`
- If it appears modified with only whitespace changes, restore it: `git restore DashWallet/Sources/Models/Uphold/DWUpholdMainnetConstants.m`
- Only commit changes to this file if you've intentionally modified the actual Uphold API constants

**To prevent this issue:**
- Option 1: Disable the "Run Script - clang-format" build phase in Xcode temporarily while working
- Option 2: Add the file to a `.clang-format-ignore` file (if supported by your clang-format version)
- Option 3: Fix the formatting in the source file to match clang-format's expectations (not recommended as it may break existing code style)

⚠️ **Info.plist files** - These files should use `$(MARKETING_VERSION)` variable, not hardcoded version strings.

**Version Management:**
- **NEVER** edit version numbers directly in Info.plist files
- **ALWAYS** update the version in Xcode project settings instead:
  - Open the project in Xcode
  - Select the target you want to update (dashwallet, dashpay, TodayExtension, WatchApp, etc.)
  - Go to "General" tab
  - Update the "Marketing Version" field under "Identity"
  - This updates the `MARKETING_VERSION` build setting which propagates to that target's Info.plist file
  - Repeat for each target that needs the version update
- If Info.plist files show changes with hardcoded versions (e.g., `<string>8.4.2</string>` instead of `<string>$(MARKETING_VERSION)</string>`), revert them
- **Note:** All targets in this project use `$(MARKETING_VERSION)` for version management, not hardcoded strings

**IMPORTANT: When Updating Versions for Release:**
- **ALL targets must be updated to the same version** to maintain consistency
- The project has multiple targets that ALL need version updates:
  - dashwallet (main app)
  - dashpay (DashPay-enabled version)
  - TodayExtension (Today widget)
  - WatchApp (Apple Watch app)
  - WatchApp Extension
- When updating versions programmatically (e.g., via script or direct editing of project.pbxproj):
  - Search for ALL occurrences of `MARKETING_VERSION` in the project.pbxproj file
  - Update ALL entries to the new version (there are typically 20+ entries across all configurations)
  - **Verification**: Ensure all MARKETING_VERSION entries are updated to the target version (replace X.Y.Z with your version):
    ```bash
    # Method 1: Check for any entries that don't match the target version
    # This should return nothing if all versions are correctly updated
    grep "MARKETING_VERSION" DashWallet.xcodeproj/project.pbxproj | grep -v "MARKETING_VERSION = X.Y.Z;"

    # Method 2: Count distinct version values (should be exactly 1)
    grep -o "MARKETING_VERSION = [^;]*" DashWallet.xcodeproj/project.pbxproj | sort -u | wc -l
    # Expected output: 1
    ```
- **Before pushing to GitHub**: Always verify all MARKETING_VERSION entries match your target version to prevent incomplete version bumps

## Dependencies and Requirements

### Required Tools
- Xcode 16+
- CocoaPods (`gem install cocoapods`)
- iOS 14.0+ deployment target
- Rust toolchain (for DashSync integration)

### Optional Tools
- `clang-format`: Objective-C formatting
- `swiftformat`: Swift formatting  
- `swiftlint`: Swift linting
- `bartycrouch`: Localization management

### External Repository Dependencies
The project expects sibling directories:
```
../DashSync/          # Core Dash protocol library
../dapi-grpc/         # gRPC API definitions  
../dashwallet-ios/    # This repository
```

## Special Considerations

### Network Switching (Testnet/Mainnet)
**Important**: External API endpoints must switch dynamically when changing between testnet and mainnet without requiring app restart.

#### CTX API Configuration
- **Mainnet**: `https://spend.ctx.com/`
- **Testnet**: `http://staging.spend.ctx.com/`
- The endpoint URL is computed dynamically in `CTXSpendEndpoint.baseURL` property
- **Never cache the base URL** as a constant - it must be evaluated on each request to ensure the correct network endpoint is used

**Implementation Pattern**:
```swift
// ❌ WRONG - Caches URL at initialization
private let kBaseURL = URL(string: CTXConstants.baseURI)!
public var baseURL: URL { return kBaseURL }

// ✅ CORRECT - Computes URL dynamically
public var baseURL: URL {
    return URL(string: CTXConstants.baseURI)!
}
```

### DashPay Features
- Conditional compilation with `#if DASHPAY`
- Username registration and management
- Contact system and invitations
- Voting system for platform governance

## CocoaPods Configuration (Critical Build Setup)

### Deployment Target Configuration
⚠️ **CRITICAL**: The Podfile's post_install script must correctly set deployment targets for different platforms:

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

**Common Build Failure**: CocoaPods 1.15.2+ is stricter about deployment target misconfigurations. Setting `IPHONEOS_DEPLOYMENT_TARGET` for watchOS targets will cause build failures.

### Pod Installation Best Practices
```bash
# Always use pod install after Podfile changes
pod install

# Never use pod update unless explicitly needed
# Clean build if you encounter pod-related issues
```

## Conditional Compilation Patterns

### Feature Flag Implementation
The project uses conditional compilation for features that can be enabled/disabled:

#### DASHPAY Feature Flag
```swift
#if DASHPAY
// DashPay-specific code
case dashpay = "dashpay"
#endif
```

#### PiggyCards Provider Flag
```swift
enum GiftCardProvider: CaseIterable {
    case ctx
    #if PIGGYCARDS_ENABLED
    case piggyCards
    #endif
}
```

### SwiftUI Conditional Compilation Best Practices

#### ❌ Problematic: Conditional Compilation in ViewBuilder
```swift
// This causes "buildExpression unavailable" errors
if condition
#if FEATURE_ENABLED
|| otherCondition
#endif
{
    // SwiftUI content
}
```

#### ✅ Solution: Computed Properties
```swift
private var shouldShowFeature: Bool {
    if baseCondition {
        return true
    }
    #if FEATURE_ENABLED
    return featureSpecificCondition
    #else
    return false
    #endif
}

var body: some View {
    if shouldShowFeature {
        // SwiftUI content
    }
}
```

### Dictionary Initialization with Conditional Compilation

#### ❌ Problematic: Inline Conditional Compilation
```swift
// This causes syntax errors when flag is undefined
let dict = [
    .key1: value1,
    #if FEATURE_ENABLED
    .key2: value2
    #endif
]
```

#### ✅ Solution: Closure-Based Initialization
```swift
let dict: [Key: Value] = {
    var result = [.key1: value1]
    #if FEATURE_ENABLED
    result[.key2] = value2
    #endif
    return result
}()
```

### Boolean Expression Patterns

#### ❌ Problematic: Mid-Expression Conditionals
```swift
// Leaves dangling operators when flag is undefined
if condition1 ||
#if FEATURE_ENABLED
condition2 ||
#endif
condition3 {
```

#### ✅ Solution: Conditional Variable Assignment
```swift
let additionalCondition: Bool
#if FEATURE_ENABLED
additionalCondition = condition2
#else
additionalCondition = false
#endif

if condition1 || additionalCondition || condition3 {
```

### Security
- Jailbreak detection
- Hardware encryption usage
- Private key protection
- Secure enclave integration

### Multi-target Builds
- Main app, Today extension, and Watch app share core components
- Different deployment targets and capabilities per target
- Shared components in `Shared/` directory

## Safety and Code Quality Guidelines (Updated from Recent Development Sessions)

### Critical Crash Prevention
Based on real issues encountered and resolved:

1. **Coordinate Force Unwrapping**: Never force unwrap `latitude!` or `longitude!` - always use guard statements
2. **Optional Property Access**: Avoid force unwrapping runtime properties like `lastBounds!` - use guard with error handling
3. **Map Annotation Creation**: Use `compactMap` with explicit return types for annotation creation
4. **Generic Type Inference**: Add explicit return type annotations to closures when compilation fails

### Common Build Failures and Solutions
- **Generic parameter inference errors**: Add explicit return types like `{ merchant -> MerchantAnnotation? in }`
- **Template image rendering**: Use `.withRenderingMode(.alwaysTemplate)` for SVG icons
- **Radius consistency**: Use `kDefaultRadius` constant (32000m) instead of hardcoded values
- **CocoaPods deployment target errors**: Ensure Podfile post_install script sets correct targets per platform
- **SwiftUI ViewBuilder conditional compilation**: Use computed properties instead of inline `#if` statements
- **Dictionary conditional compilation**: Use closure-based initialization instead of inline conditionals

### Dynamic Map Filtering Architecture
The app implements sophisticated map-based filtering where:
- Map bounds changes trigger search result updates
- `ExploreMapBounds` struct handles coordinate regions
- `currentMapBounds` parameter flows through view hierarchy
- Priority: map bounds > filter radius > default radius

#### Critical Distance Filtering Pattern (Fixed in Recent Session)
**Issue**: "Show all locations" incorrectly included locations outside radius filter
**Root Cause**: `MerchantDAO.allLocations` only applied rectangular bounds filtering instead of circular distance filtering
**Solution**: Apply both rectangular bounds (SQL optimization) AND circular distance filtering (accuracy)

```swift
// CORRECT PATTERN: Always apply both filters for location-based queries
func allLocations(by query: String, in bounds: ExploreMapBounds, userPoint: CLLocation?) -> [Location] {
    // Step 1: Rectangular bounds filtering (SQL optimization)
    let boundsFiltered = filterByBounds(bounds)

    // Step 2: Circular distance filtering (accuracy)
    guard let userPoint = userPoint else { return boundsFiltered }

    let radius = bounds.calculateRadiusFromBounds() // Convert bounds to meters
    return boundsFiltered.filter { location in
        guard let lat = location.latitude, let lng = location.longitude else { return false }
        let distance = CLLocation(latitude: lat, longitude: lng).distance(from: userPoint)
        return distance <= radius
    }
}
```

**Key Insight**: Rectangular bounds from map view don't guarantee circular radius compliance. Always use `CLLocation.distance(from:)` for accurate great-circle distance calculations.

## Location-Based Search Architecture (Critical Lessons from Production Bugs)

> **Critical Bug Fixed**: Users experienced inconsistent merchant distances when first granting location permissions. The root cause was NOT a timing issue but a fundamental mismatch between rectangular SQL bounds filtering and circular radius expectations. Solution: Always expand rectangular bounds by 50% when used for circular searches.

### The Rectangular Bounds vs Circular Radius Problem

#### Issue Discovered
When users first grant location permissions and enter the nearby tab, incorrect merchant distances and totals were displayed. The "closest merchants" algorithm produced inconsistent results depending on timing of map bounds updates.

#### Root Cause Analysis
1. **Database Query Optimization**: SQL queries use rectangular bounds filtering for performance (indexed lat/lon columns)
2. **Accuracy Requirement**: Users expect circular radius filtering (e.g., "within 20 miles")
3. **The Mismatch**: Rectangular bounds from SQL can exclude locations that fall within the circular radius
4. **Timing Dependency**: Different map bounds at different times return different datasets from database

#### The Solution: Generous Bounds with Precise Filtering
```swift
// CRITICAL: Expand rectangular bounds by 50% to ensure all potential locations are included
func calculateExpandedBounds(from bounds: ExploreMapBounds) -> ExploreMapBounds {
    let centerLat = (bounds.minLatitude + bounds.maxLatitude) / 2
    let centerLon = (bounds.minLongitude + bounds.maxLongitude) / 2
    let latSpan = (bounds.maxLatitude - bounds.minLatitude) * 1.5  // 50% buffer
    let lonSpan = (bounds.maxLongitude - bounds.minLongitude) * 1.5  // 50% buffer

    return ExploreMapBounds(
        minLatitude: centerLat - latSpan / 2,
        maxLatitude: centerLat + latSpan / 2,
        minLongitude: centerLon - lonSpan / 2,
        maxLongitude: centerLon + lonSpan / 2
    )
}
```

#### Key Principles
1. **Performance vs Accuracy Trade-off**: Use generous rectangular bounds for SQL performance, then apply precise circular filtering in memory
2. **Consistency Over Timing**: Ensure search results don't depend on when map bounds are set
3. **Buffer Zones**: Always add safety margins to rectangular bounds when they'll be used for circular searches

### iOS Location Permission & Timing Issues

#### Common Timing Scenarios
1. **First Launch**: No location permission → User grants → Location becomes available → Map bounds update
2. **Permission Already Granted**: Location available immediately → Map bounds set with location
3. **Permission Denied then Granted**: Stale bounds → Permission granted → New bounds with location

#### Debugging Strategy
```swift
// Add comprehensive debug logging with emoji prefixes for easy filtering
print("🔍 SEARCH DEBUG - Starting location search")
print("🔍 SEARCH DEBUG - User location: \(userLocation?.coordinate ?? CLLocationCoordinate2D())")
print("🔍 SEARCH DEBUG - Map bounds: \(currentMapBounds)")
print("🔍 SEARCH DEBUG - Radius: \(radius) meters")
print("🔍 SEARCH DEBUG - Results count: \(results.count)")
```

#### Best Practices
1. **Always Log Timing**: Include timestamps in debug logs to identify race conditions
2. **Log All Inputs**: User location, bounds, radius, and filter settings
3. **Log Intermediate Results**: Database query results before and after filtering
4. **Use Emoji Prefixes**: Makes filtering logs easier (🔍 for search, 📍 for location, 🗺️ for map)

## Debugging Best Practices

### Debug Message Management

#### The Performance Impact Problem
During debugging sessions, it's common to add extensive print statements. However:
- **Issue Found**: 100+ debug print statements can significantly impact app performance
- **User Impact**: Scrolling becomes janky, animations stutter
- **Memory Impact**: Console buffer can grow large with verbose logging

#### Debug Message Strategy
```swift
// Use conditional compilation for debug messages
#if DEBUG
private let debugEnabled = true
#else
private let debugEnabled = false
#endif

private func debugLog(_ message: String) {
    guard debugEnabled else { return }
    print("🔍 \(Date()) - \(message)")
}
```

#### Cleanup Guidelines
1. **Search Before Release**: Search for `print("` statements before any release
2. **Use Debug Flags**: Wrap debugging code in `#if DEBUG` blocks
3. **Remove Empty Switch Cases**: When cleaning debug messages from switch statements, ensure cases have content:

```swift
// ❌ BAD: Empty switch case causes syntax error
switch action {
case .search:
    // Removed debug print - NOW EMPTY!
case .filter:
    applyFilter()
}

// ✅ GOOD: Add break or remove the case entirely
switch action {
case .search:
    break  // Explicitly do nothing
case .filter:
    applyFilter()
}
```

### Performance vs Debugging Balance

#### Strategic Debug Points
Focus debug logging on:
1. **State Transitions**: Location permission changes, view lifecycle
2. **Data Flow Boundaries**: API calls, database queries, UI updates
3. **Error Conditions**: Failed requests, invalid data
4. **Critical Calculations**: Distance filtering, coordinate transformations

#### Production-Safe Debugging
```swift
// Use os_log for production-safe logging
import os.log

private let logger = Logger(subsystem: "com.dashwallet", category: "LocationSearch")

func performSearch() {
    logger.debug("Starting search with bounds: \(bounds)")
    // Only logged in debug builds, stripped in release
}
```

## Merchant Search Architecture (Critical Lessons)

### All Tab vs Nearby Tab: Different Query Strategies

The merchant search has three tabs with fundamentally different requirements:
1. **Online Tab**: Online merchants only (no location filtering)
2. **Nearby Tab**: Physical merchants within radius (location-based filtering)
3. **All Tab**: ALL merchants regardless of location (no location filtering)

#### Critical Design Decision: userLocation Parameter

**The Problem**: `MerchantDAO.items()` has two query paths:
1. **With userLocation**: In-memory grouping to find closest location per merchant (for Nearby tab)
2. **Without userLocation**: Pure SQL query with SQL-based sorting (for All/Online tabs)

**The Solution**: Different tabs must pass appropriate parameters:
```swift
// ✅ All Tab: No location filtering needed
class AllMerchantsDataProvider {
    override func items(...) {
        // Pass nil for bounds AND userPoint to use SQL-based sorting
        fetch(by: query, in: nil, userPoint: nil, with: filters, ...)
    }
}

// ✅ Nearby Tab: Location-based filtering needed
class NearbyMerchantsDataProvider {
    override func items(...) {
        // Pass both bounds and userPoint for distance-based grouping
        fetch(by: query, in: bounds, userPoint: userPoint, with: filters, ...)
    }
}
```

#### Why This Matters

**When userLocation is provided**, the code:
1. Fetches all matching records
2. Groups by merchantId to find closest location
3. Requires valid lat/lon coordinates (filters out online merchants)
4. Applies in-memory sorting

**When userLocation is nil**, the code:
1. Uses SQL GROUP BY for efficiency
2. Applies SQL ORDER BY for sorting
3. Includes merchants without coordinates (online merchants)
4. More efficient for large result sets

### In-Memory Grouping: Handling Online Merchants

When using the in-memory grouping path (userLocation provided), online merchants don't have coordinates. The code must handle this:

```swift
// ✅ CORRECT: Handle online merchants separately
for item in allItems {
    guard let merchant = item.merchant else { continue }

    // Online merchants don't have coordinates
    if item.latitude == nil || item.longitude == nil {
        if merchantToClosestLocation[merchant.merchantId] == nil {
            merchantToClosestLocation[merchant.merchantId] = item
        }
        continue
    }

    // Physical merchants: find closest location
    let distance = calculateDistance(...)
    // ... grouping logic
}
```

## Database Query Optimization Patterns

### The SQL Performance vs Accuracy Dilemma

#### Problem Statement
- **SQL Indexes**: Database has indexes on latitude and longitude for fast rectangular queries
- **User Expectation**: "Show me merchants within 20 miles" expects circular radius
- **Mathematical Reality**: Rectangular bounds ≠ Circular area

#### Anti-Pattern (Causes Inconsistent Results)
```swift
// ❌ BAD: Tight rectangular bounds miss valid locations
func searchNearby(center: CLLocation, radius: Double) -> [Location] {
    let bounds = calculateTightBounds(center: center, radius: radius)
    return database.query("SELECT * WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
                         bounds.minLat, bounds.maxLat, bounds.minLon, bounds.maxLon)
}
```

#### Correct Pattern (Consistent Results)
```swift
// ✅ GOOD: Generous bounds ensure all potential matches are included
func searchNearby(center: CLLocation, radius: Double) -> [Location] {
    // Step 1: Calculate bounds with 50% buffer for SQL query
    let expandedBounds = calculateExpandedBounds(center: center, radius: radius * 1.5)

    // Step 2: Get all potential matches from database
    let candidates = database.query("SELECT * WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
                                   expandedBounds.minLat, expandedBounds.maxLat,
                                   expandedBounds.minLon, expandedBounds.maxLon)

    // Step 3: Apply precise circular filtering in memory
    return candidates.filter { location in
        let distance = location.distance(from: center)
        return distance <= radius
    }
}
```

### Query Optimization Checklist
- [ ] Are rectangular bounds expanded sufficiently for circular searches?
- [ ] Is circular filtering applied after SQL queries?
- [ ] Are database indexes being utilized effectively?
- [ ] Is the two-step filter pattern documented in code comments?

## Swift Code Quality Patterns

### Force Unwrapping Safety

#### Location Coordinate Handling
```swift
// ❌ DANGEROUS: Force unwrapping can crash
let lat = location.latitude!
let lon = location.longitude!

// ✅ SAFE: Guard with meaningful fallback
guard let lat = location.latitude,
      let lon = location.longitude else {
    logger.warning("Skipping location with missing coordinates")
    return nil
}
```

### Compiler Error Solutions

#### Generic Type Inference
```swift
// ❌ Compilation fails with "Generic parameter could not be inferred"
let annotations = merchants.compactMap { merchant in
    createAnnotation(for: merchant)
}

// ✅ Add explicit return type to help compiler
let annotations = merchants.compactMap { merchant -> MerchantAnnotation? in
    createAnnotation(for: merchant)
}
```

#### SwiftUI ViewBuilder Conditionals
```swift
// ❌ "buildExpression unavailable" error
var body: some View {
    if showMap
    #if MAPS_ENABLED
    || forceShowMap
    #endif
    {
        MapView()
    }
}

// ✅ Use computed property for complex conditions
private var shouldShowMap: Bool {
    if showMap { return true }
    #if MAPS_ENABLED
    return forceShowMap
    #else
    return false
    #endif
}

var body: some View {
    if shouldShowMap {
        MapView()
    }
}
```

### Key Safety Patterns
- Always validate `CLLocationCoordinate2D.isValid` before use
- Implement fallback chains for CTX API data
- Use emoji debug markers for easy log filtering: 🎯 🌐 💾 🎨
- Test coordinate edge cases thoroughly in unit tests

### Code Review Checklist
- [ ] Search for `!` force unwraps in location/coordinate handling
- [ ] Verify template images use proper rendering mode
- [ ] Check radius constants are consistent across codebase
- [ ] Ensure compactMap closures have explicit types if needed
- [ ] Remove unused properties that create inconsistency
- [ ] Verify debug print statements are wrapped in `#if DEBUG`
- [ ] Check that rectangular bounds have sufficient buffer for circular searches
- [ ] Confirm two-step filtering (SQL then precise) is properly implemented

## Architectural Lessons Learned

### Debugging Complex iOS Location Issues

#### Initial Misdiagnosis Pattern
When debugging location-based issues, avoid jumping to conclusions about timing/race conditions. The debugging session revealed:
1. **Initial Hypothesis**: Race condition between location permissions and data loading
2. **Evidence Gathering**: Added comprehensive logging to trace execution flow
3. **Discovery**: Both code paths had correct location data, but different map bounds
4. **Root Cause**: Architectural mismatch between rectangular and circular filtering

#### Systematic Debugging Approach
1. **Log Everything First**: Before forming hypotheses, add comprehensive logging
2. **Compare Working vs Non-Working**: Find cases where it works and compare inputs
3. **Question Assumptions**: "Different results" doesn't always mean "race condition"
4. **Look for Architectural Issues**: Sometimes the bug is in the design, not the timing

### Performance Optimization Trade-offs

#### When Performance Optimizations Cause Bugs
The rectangular bounds SQL optimization was correct for performance but incorrect for user expectations:
- **Performance Win**: Using indexed lat/lon columns for fast queries
- **Accuracy Loss**: Rectangular bounds don't match circular radius expectations
- **User Impact**: Inconsistent results that appear random but aren't

#### The Right Balance
1. **Use Database Indexes**: Keep the performance optimization
2. **Add Safety Margins**: Expand bounds to ensure completeness
3. **Filter Precisely in Memory**: Apply exact business logic after retrieval
4. **Document the Pattern**: Make the two-step process explicit in code

### Code Cleanup Best Practices

#### Debug Code Management
From cleaning up 100+ debug statements:
1. **Performance Impact**: Debug prints in UI code cause visible performance issues
2. **Maintenance Burden**: Debug code makes real logic harder to follow
3. **Compilation Errors**: Removing prints can leave invalid syntax (empty switch cases)
4. **Solution**: Use conditional compilation and logging frameworks

#### Cleanup Strategy
```swift
// Before cleanup: Identify patterns
// Search for: print("
// Count occurrences: 100+ found

// During cleanup: Preserve functionality
// - Don't just delete lines
// - Check for empty blocks
// - Maintain code logic

// After cleanup: Verify compilation
// - Build the project
// - Run the app
// - Check for warnings
```

### Key Architectural Insights

1. **Separate Concerns**: Database optimization and business logic should be separate layers
2. **Make Assumptions Explicit**: If using rectangular bounds for circular searches, document why
3. **Test Edge Cases**: Location permission flows have many states - test them all
4. **Log Strategically**: Not everything, but key decision points and data transformations
5. **Clean as You Go**: Don't let debug code accumulate; remove it before committing

## CTX/DashSpend API Integration

### Overview
The app integrates with CTX (now DashSpend) for gift card purchases and merchant discounts. This integration has several environment-specific differences and critical implementation patterns that must be followed.

### API Environment Differences

#### Base URLs
- **Production**: `https://spend.ctx.com/`
- **Staging/TestNet**: `https://staging.spend.ctx.com/` (NOT http - must use HTTPS)

**Critical Implementation Note**: The staging URL was incorrectly documented as HTTP in some places. It MUST use HTTPS:
```swift
// ❌ WRONG - Will cause SSL errors
static let stagingBaseURI = "http://staging.spend.ctx.com/"

// ✅ CORRECT - Proper HTTPS endpoint
static let stagingBaseURI = "https://staging.spend.ctx.com/"
```

#### Field Name Differences
The staging and production APIs return different field names for the same data:

**Discount Percentage Field**:
- **Production**: `savingsPercentage` (number, e.g., 10)
- **Staging**: `userDiscount` (number, e.g., 10)

```swift
// Handle both field names with fallback chain
let discountPercentage = json["savingsPercentage"] as? Double
    ?? json["userDiscount"] as? Double
    ?? 0.0
```

#### Authentication Requirements
**getMerchant Endpoint** (`/api/v1/merchants/{id}`):
- **Production**: No authentication required (public endpoint)
- **Staging**: Requires `Authorization` header with user token

```swift
func getMerchant(id: String) async throws -> Merchant {
    var headers = defaultHeaders

    // Staging requires authentication, production doesn't
    if isStaging {
        headers["Authorization"] = "Bearer \(userToken)"
    }

    return try await request(endpoint: .getMerchant(id: id), headers: headers)
}
```

#### Response Structure Differences

**Gift Card Fetch Endpoint** (`/api/v1/purchases/gift_cards/{txid}`):

Production returns a single gift card object:
```json
{
    "uuid": "abc123",
    "claimCode": "CLAIM123",
    "pin": "1234",
    "amount": 25.00
}
```

Staging returns a paginated response:
```json
{
    "data": [
        {
            "uuid": "abc123",
            "claimCode": "CLAIM123",
            "pin": "1234",
            "amount": 25.00
        }
    ],
    "meta": {
        "total": 1,
        "page": 1
    }
}
```

Implementation pattern:
```swift
func parseGiftCardResponse(json: [String: Any]) -> GiftCard? {
    // Check for paginated response (staging)
    if let dataArray = json["data"] as? [[String: Any]],
       let firstCard = dataArray.first {
        return GiftCard(json: firstCard)
    }

    // Direct object (production)
    if let uuid = json["uuid"] as? String {
        return GiftCard(json: json)
    }

    return nil
}
```

### Common Issues and Solutions

#### Issue 1: CTX-Only Discount Display
**Problem**: Merchants show incorrect discounts when CTX discounts differ from PiggyCards discounts.

**Root Cause**: The database contains duplicate merchant rows (one per provider), but UI was showing combined data.

**Solution**: Filter by provider when fetching merchant details:
```swift
// ❌ WRONG - Returns multiple rows, causes incorrect discount display
let query = "SELECT * FROM merchants WHERE merchant_id = ?"

// ✅ CORRECT - Filter by active provider
let provider: String = {
    #if PIGGYCARDS_ENABLED
    return userPreference // Could be "ctx" or "piggyCards"
    #else
    return "ctx" // Only CTX available
    #endif
}()
let query = "SELECT * FROM gift_card_providers WHERE merchant_id = ? AND provider = ?"
```

#### Issue 2: Transaction ID vs Gift Card UUID
**Problem**: Confusion about which ID to use for fetching gift cards.

**Key Understanding**:
- The API uses the blockchain **transaction ID (txid)** to fetch gift cards
- NOT the gift card's internal UUID
- The txid is what gets stored when a purchase is made

```swift
// ❌ WRONG - Using gift card UUID
let endpoint = "/api/v1/purchases/gift_cards/\(giftCard.uuid)"

// ✅ CORRECT - Using transaction ID
let endpoint = "/api/v1/purchases/gift_cards/\(transaction.txid)"
```

#### Issue 3: Denomination Type Source
**Problem**: Incorrect denomination type (fixed vs variable) displayed for gift cards.

**Root Cause**: Denomination type was being read from the wrong table.

**Solution**: Use `gift_card_providers` table, not `merchant` table:
```swift
// The gift_card_providers table has the correct denomination_type per provider
struct GiftCardProvider {
    let merchantId: Int64
    let provider: String
    let denominationType: String // "fixed" or "variable"
    let minAmount: Double?
    let maxAmount: Double?
    let denominations: [Double]? // For fixed denomination cards
}
```

### Database Considerations

#### Multi-Provider Architecture
The database stores duplicate merchant data to support multiple gift card providers:

```sql
-- Each merchant can have multiple provider entries
CREATE TABLE gift_card_providers (
    merchant_id INTEGER,
    provider TEXT, -- 'ctx' or 'piggyCards'
    denomination_type TEXT, -- 'fixed' or 'variable'
    discount_percentage REAL,
    -- Provider-specific data
);

-- When PIGGYCARDS_ENABLED is not defined, always filter by provider = 'ctx'
```

#### Provider Filtering Pattern
```swift
class MerchantDAO {
    private var activeProvider: String {
        #if PIGGYCARDS_ENABLED
        // User can switch providers
        return UserDefaults.standard.string(forKey: "selectedProvider") ?? "ctx"
        #else
        // Only CTX available
        return "ctx"
        #endif
    }

    func fetchMerchant(id: Int64) -> Merchant? {
        // Always include provider filter to avoid duplicate/wrong data
        let query = """
            SELECT * FROM gift_card_providers
            WHERE merchant_id = ? AND provider = ?
        """
        return database.query(query, id, activeProvider)
    }
}
```

### Testing Guidelines

#### Environment Setup
1. **Switching Environments**: Use Xcode schemes (Debug vs TestNet) to switch between staging and production
2. **API Mocking**: Use Charles Proxy or similar to inspect actual API responses
3. **Database State**: Clear app data when switching providers to avoid stale cache

#### Test Scenarios
Critical test cases for CTX integration:

1. **Discount Display**:
   - Verify correct discount percentage shows (staging: `userDiscount`, production: `savingsPercentage`)
   - Ensure CTX-only discounts display when PiggyCards is disabled

2. **Gift Card Purchase Flow**:
   - Test with both fixed and variable denomination cards
   - Verify transaction ID is used for fetching, not gift card UUID
   - Check proper response parsing for both paginated (staging) and direct (production) responses

3. **Network Environment Switching**:
   - Switch between TestNet and MainNet in Settings
   - Verify API endpoints update without app restart
   - Confirm HTTPS is used for staging environment

4. **Provider Filtering**:
   - When PIGGYCARDS_ENABLED is undefined, verify only CTX data is shown
   - Check that database queries include proper provider filtering

#### Debug Headers
The API requires specific headers for proper operation:

```swift
struct CTXAPIHeaders {
    static func defaultHeaders(for network: Network) -> [String: String] {
        return [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Client-Id": clientId, // Required for API tracking
            "X-Device-Platform": "iOS",
            "X-App-Version": appVersion
        ]
    }
}
```

### Key Implementation Files
- `CTXEndpoint.swift` - API endpoint definitions and base URL computation
- `CTXService.swift` - Main service layer for CTX API interactions
- `CTXConstants.swift` - Environment-specific constants
- `MerchantDAO.swift` - Database queries with provider filtering
- `GiftCardProvider.swift` - Data model for provider-specific merchant data