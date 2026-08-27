# Project Functions and APIs

This document provides comprehensive information about the key functions, APIs, and development patterns in the Dash Wallet iOS codebase.

## Core Transaction Functions

### Transaction Creation and Sending
**File**: `DashWallet/Sources/Models/Transactions/SendCoinsService.swift`
- `SendCoinsService` - Primary service for creating and broadcasting transactions
- Methods for handling standard payments, DashPay transactions, and InstantSend
- Integration with fee calculation and transaction validation

**File**: `DashWallet/Sources/UI/Payments/PaymentModels/DWPaymentProcessor.h/m`
- `DWPaymentProcessor` - Complex payment flow coordination
- Handles payment input validation, address resolution, and transaction creation
- Manages payment protocol and QR code payment processing

### Transaction History and Balance
**File**: `DashWallet/Sources/Models/Transactions/BalanceNotifier.swift`
- `BalanceNotifier` - Real-time balance updates and notifications
- Observes wallet state changes and notifies UI components

**File**: `DashWallet/Sources/Models/Tx/Transactions.swift`
- Core transaction data models and utilities
- Transaction filtering and categorization
- Integration with metadata system

### QR Code and Address Validation
**File**: `DashWallet/Sources/UI/Payments/ScanQR/DWQRScanViewController.h/m`
- `DWQRScanViewController` - QR code scanning interface
- Camera integration with custom capture session management
- Payment URI parsing and validation

**File**: `DashWallet/Sources/Models/URL Handling/DWURLParser.h/m`
- `DWURLParser` - Dash URI and payment request parsing
- Supports BIP21 payment URIs and DashPay invitations
- URL scheme handling for deep linking

## Wallet Management APIs

### Wallet Creation and Recovery
**File**: `DashWallet/Sources/UI/Setup/RecoverWallet/DWRecoverModel.h/m`
- `DWRecoverModel` - Wallet recovery from seed phrase
- BIP39 mnemonic validation and wallet restoration
- Error handling for invalid seeds and network issues

**File**: `DashWallet/Sources/UI/Setup/SecureWallet/DWSecureWalletDelegate.h`
- Wallet backup and security protocols
- PIN setup and biometric authentication integration

### Authentication and Security
**File**: `DashWallet/Sources/UI/Setup/BiometricAuth/DWBiometricAuthModel.h/m`
- `DWBiometricAuthModel` - Face ID/Touch ID integration
- LocalAuthentication framework wrapper
- Fallback to PIN when biometrics unavailable

**File**: `DashWallet/Sources/UI/Setup/SetPin/DWSetPinModel.h/m`
- `DWSetPinModel` - PIN creation and validation
- Secure PIN storage in Keychain
- PIN change and reset functionality

### Wallet State Management
**File**: `DashWallet/Sources/Models/DWEnvironment.h/m`
- `DWEnvironment` - Global wallet state singleton
- Current wallet instance access
- Network configuration management

## DashPay Integration

### Username System
**File**: `DashWallet/Sources/Models/Usernames/UsernamePrefs.swift`
- Username registration preferences and state
- Local username caching and validation

**File**: `DashWallet/Sources/Models/Voting/UsernameRequest.swift`
- Username request data model for voting system
- Integration with masternode voting mechanism

### Contact Management
**File**: `DashWallet/Sources/UI/DashPay/Contacts/DWBaseContactsViewController.h/m`
- `DWBaseContactsViewController` - Contact list management
- Contact search, filtering, and organization
- Integration with blockchain identity system

**File**: `DashWallet/Sources/UI/DashPay/Global/DWDashPayContactsActions.h/m`
- Contact-related actions and operations
- Add, remove, and update contact functionality

### Voting System
**File**: `DashWallet/Sources/UI/DashPay/Voting/VotingViewModel.swift`
- Voting interface business logic
- Masternode key management for voting
- Vote casting and result tracking

**File**: `DashWallet/Sources/Models/Voting/MasternodeKey.swift`
- Masternode key data model
- Key validation and cryptographic operations

## External Service Integrations

### Coinbase Integration
**File**: `DashWallet/Sources/Models/Coinbase/Coinbase.swift`
- `Coinbase` - Main service class with async/await patterns
- OAuth authentication flow
- Account management and transaction processing

**File**: `DashWallet/Sources/Models/Coinbase/Services/CoinbaseService.swift`
- HTTP client for Coinbase API
- Request/response models and error handling
- Rate limiting and retry logic

### Uphold Integration
**File**: `DashWallet/Sources/Models/Uphold/UpholdClient.swift`
- `UpholdClient` - Uphold service integration
- Card management and transaction processing
- OAuth token management

**File**: `DashWallet/Sources/Models/Uphold/Topper.swift`
- Topper payment method integration
- Asset conversion and payment processing

### CrowdNode Staking
**File**: `DashWallet/Sources/Models/CrowdNode/CrowdNode.swift`
- `CrowdNode` - Staking service integration
- Account creation and management
- Staking rewards tracking

**File**: `DashWallet/Sources/Models/CrowdNode/Services/CrowdNodeWebService.swift`
- HTTP client for CrowdNode API
- Transaction monitoring and status updates

## Navigation and UI Patterns

### Main Navigation Flow
**File**: `DashWallet/Sources/UI/RootNavigation/DWAppRootViewController.h/m`
- `DWAppRootViewController` - Main app coordinator
- Handles navigation between major app sections
- Manages setup flow and authenticated states

**File**: `DashWallet/Sources/UI/Main/MainTabbarController.swift`
- `MainTabbarController` - Tab-based navigation
- Home, DashPay, and Menu sections
- Tab customization and badge management

### SwiftUI Integration Examples
**File**: `DashWallet/Sources/UI/SwiftUI Components/`
- Modern SwiftUI components and utilities
- `BottomSheet.swift` - Modal presentation helper
- `Button.swift` - Styled button components
- `TextInput.swift` - Custom input field components

**File**: `DashWallet/Sources/Categories/UIHostingController+DashWallet.swift`
- Bridge between UIKit and SwiftUI
- Custom hosting controller extensions
- Navigation integration helpers

### Error Handling and Alerts
**File**: `DashWallet/Sources/Categories/UIViewController+DWDisplayError.h/m`
- Standard error presentation across the app
- Alert formatting and localization
- Error categorization and user-friendly messages

**File**: `DashWallet/Sources/Categories/ErrorPresentable.swift`
- Swift protocol for consistent error presentation
- Integration with SwiftUI error handling

## Data Persistence

### Database Operations
**File**: `DashWallet/Sources/Infrastructure/Database/DatabaseConnection.swift`
- `DatabaseConnection` - SQLite wrapper singleton
- Connection management and transaction handling
- Migration system integration

**File**: `DashWallet/Sources/Infrastructure/Database/Migrations.bundle/`
- Timestamped SQL migration files
- Schema evolution and data transformation
- Format: `YYYYMMDDHHMMSS_description.sql`

### Data Access Patterns
**File**: `DashWallet/Sources/Models/Tx Metadata/DAO/TransactionMetadataDAO.swift`
- `TransactionMetadataDAO` - Transaction metadata operations
- CRUD operations with SQLite integration
- Caching and performance optimization

**File**: `DashWallet/Sources/Models/Taxes/Address/AddressUserInfo.swift`
- Address-related user information storage
- Tax reporting and transaction categorization
- User-defined labels and notes

### UserDefaults Usage
**File**: `DashWallet/Sources/Models/DWGlobalOptions.h/m`
- `DWGlobalOptions` - App-wide settings management
- Typed accessors for user preferences
- Setting synchronization and validation

**File**: `DashWallet/Sources/Models/Voting/VotingPrefs.swift`
- Voting-related preferences and state
- Masternode configuration persistence

## Key Protocols and Base Classes

### Base View Controllers
**File**: `DashWallet/Sources/UI/Views/BaseController/BaseViewController.swift`
- `BaseViewController` - Common functionality for Swift view controllers
- Network reachability handling
- Loading state management

**File**: `DashWallet/Sources/UI/Views/BaseController/DWBaseViewController.h/m`
- `DWBaseViewController` - Base class for Objective-C controllers
- Device adaptation and layout helpers
- Common UI setup patterns

### Protocol Definitions
**File**: `DashWallet/Sources/UI/Home/Protocols/DWHomeProtocol.h`
- Home screen delegate protocols
- Data source and action handling interfaces

**File**: `DashWallet/Sources/UI/DashPay/Setup/DWDashPayProtocol.h`
- DashPay setup and configuration protocols
- Registration flow coordination

### Service Protocols
**File**: `DashWallet/Sources/Models/Coinbase/Infrastructure/`
- Service protocol definitions for external integrations
- Async/await patterns and error handling
- Request/response model conventions

## Utility Functions and Extensions

### Currency and Formatting
**File**: `DashWallet/Sources/Categories/NumberFormatter+DashWallet.swift`
- `NumberFormatter.dashFormatter` - Dash amount formatting
- Fiat currency formatting with locale support
- Precision handling for small amounts

**File**: `DashWallet/Sources/Categories/Numbers+Dash.swift`
- Numeric extensions for Dash calculations
- Unit conversions (Dash, mDash, µDash, duffs)
- Precision arithmetic helpers

### UI Utilities
**File**: `DashWallet/Sources/Categories/UIView+DWAnimations.h/m`
- Common animation patterns and transitions
- Fade, slide, and bounce effects
- Animation completion handling

**File**: `DashWallet/Sources/UI/Views/TappableLabel.swift`
- Interactive text components
- Link handling and gesture recognition
- Accessibility support

### String and Text Processing
**File**: `DashWallet/Sources/Categories/String+DashWallet.swift`
- String validation and formatting utilities
- Dash address validation
- QR code content parsing

**File**: `DashWallet/Sources/Categories/NSAttributedString+Builder.swift`
- Attributed string builder pattern
- Rich text formatting helpers
- Dynamic styling support

## Development Integration Patterns

### Service Layer Pattern
```swift
// Standard service implementation pattern
class ServiceName {
    static let shared = ServiceName()
    
    func performOperation() async throws -> ResultType {
        // Implementation with error handling
    }
}
```

### DAO Pattern
```swift
protocol DAOProtocol {
    func create(_ item: ItemType) throws
    func read(id: String) throws -> ItemType?
    func update(_ item: ItemType) throws  
    func delete(id: String) throws
}
```

### SwiftUI-First Architecture Patterns (MANDATORY)
**CRITICAL**: All new development MUST follow SwiftUI-first patterns

#### Required SwiftUI + ViewModel Pattern
```swift
// REQUIRED - SwiftUI View + ViewModel architecture
struct FeatureView: View {
    @StateObject private var viewModel = FeatureViewModel()

    var body: some View {
        VStack {
            Text(viewModel.title)
            // SwiftUI content
        }
        .task {
            await viewModel.loadData()
        }
    }
}

@MainActor
class FeatureViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var isLoading = false

    func loadData() async {
        // Business logic
    }
}
```

#### Navigation Pattern (Required)
```swift
// REQUIRED - NavigationStack with type-safe destinations
struct MainNavigationView: View {
    var body: some View {
        NavigationStack {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        List(items) { item in
            NavigationLink(value: item) {
                ItemRowView(item: item)
            }
        }
        .navigationDestination(for: ItemType.self) { item in
            ItemDetailView(item: item)
        }
    }
}
```

#### UIKit Wrapper (ONLY When Absolutely Necessary)
```swift
// ONLY for: Camera, complex gestures, third-party integration
struct CameraWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Minimal updates only
    }
}
```

### Feature Flag Implementation Patterns
**Based on PiggyCards implementation experience**

#### Safe Conditional Compilation for Functions
```swift
// SAFE - Repository factory with feature flags
class ServiceFactory {
    static func createRepository(provider: Provider) -> any RepositoryProtocol {
        switch provider {
        case .provider1:
            return Provider1Repository.shared
        #if PIGGYCARDS_ENABLED
        case .provider2:
            return Provider2Repository.shared
        #endif
        }
    }
}

// SAFE - Service collection with closure initialization
class ServiceManager {
    private let services: [Provider: any ServiceProtocol] = {
        var dict: [Provider: any ServiceProtocol] = [
            .provider1: Service1.shared
        ]
        #if PIGGYCARDS_ENABLED
        dict[.provider2] = Service2.shared
        #endif
        return dict
    }()
}
```

### Database Functions with Feature Flags
```swift
// Safe conditional query building
class DataAccessObject {
    func fetchItems() throws -> [Item] {
        var whereClause = "enabled = 1"

        #if PIGGYCARDS_ENABLED
        whereClause += " OR provider = 'piggycards'"
        #endif

        let sql = "SELECT * FROM items WHERE \(whereClause)"
        return try database.execute(sql)
    }
}
```

### Prohibited Patterns
#### ❌ NEVER Create These:
- New UIViewController subclasses with UI logic
- New Storyboard (.storyboard) files
- New XIB (.xib) files
- @IBOutlet and @IBAction patterns
- Segue-based navigation

This comprehensive function reference provides the foundation for understanding and extending the Dash Wallet iOS codebase effectively, with mandatory SwiftUI-first architecture and safe feature flag implementation patterns.