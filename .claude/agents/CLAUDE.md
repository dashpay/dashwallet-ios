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

## Important Files

### Configuration
- `Podfile`: CocoaPods dependencies and post-install scripts
- `DashWallet.xcworkspace`: Main workspace file
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
- Xcode 11+
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

### Dynamic Map Filtering Architecture
The app implements sophisticated map-based filtering where:
- Map bounds changes trigger search result updates
- `ExploreMapBounds` struct handles coordinate regions
- `currentMapBounds` parameter flows through view hierarchy
- Priority: map bounds > filter radius > default radius

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