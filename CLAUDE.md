# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dash Wallet is an iOS cryptocurrency wallet application built for the Dash network. It's a fork of breadwallet that implements SPV (Simplified Payment Verification) for fast mobile performance. The app includes advanced features like DashPay for user-to-user transactions, CoinJoin for privacy, and integrations with external services like Uphold and Coinbase.

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