# Development Patterns and Conventions

This document outlines the key development patterns, architectural decisions, and coding conventions used throughout the Dash Wallet iOS project.

## Architectural Patterns

### Protocol-Oriented Programming
The codebase extensively uses protocols for dependency injection and testability:

```objc
// Objective-C protocol example
@protocol DWHomeProtocol <NSObject>
- (void)updateBalance:(uint64_t)balance;
- (void)showTransactionDetail:(DSTransaction *)transaction;
@end
```

```swift
// Swift protocol example
protocol CurrencyExchangerProtocol {
    func exchangeRate(for currency: String) async throws -> Double
    func convertToFiat(amount: UInt64, currency: String) -> String
}
```

### MVVM Pattern Implementation
Modern view controllers use ViewModels for business logic separation:

```swift
class FeatureViewController: UIViewController {
    private let viewModel: FeatureViewModel
    
    init(viewModel: FeatureViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBindings()
    }
    
    private func setupBindings() {
        viewModel.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateUI(with: state)
            }
            .store(in: &cancellables)
    }
}
```

### Service Layer Architecture
Business logic is encapsulated in dedicated service classes:

```swift
class FeatureService {
    static let shared = FeatureService()
    private init() {}
    
    func performOperation() async throws -> ResultType {
        // Validation
        guard isValidState() else {
            throw FeatureError.invalidState
        }
        
        // Business logic
        let result = try await networkOperation()
        
        // Post-processing
        await updateLocalState(result)
        
        return result
    }
}
```

## Code Organization Patterns

### Feature-Based Organization
UI components are organized by feature rather than by type:

```
UI/
├── Home/
│   ├── HomeViewController.swift
│   ├── HomeViewModel.swift
│   ├── Models/
│   └── Views/
├── Payments/
│   ├── Pay/
│   ├── Receive/
│   └── ScanQR/
└── DashPay/
    ├── Contacts/
    ├── Profile/
    └── Voting/
```

### Mixed Language Integration
The codebase seamlessly integrates Swift and Objective-C:

**Bridging Header Pattern:**
```objc
// dashwallet-Bridging-Header.h
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWPaymentProcessor.h"
```

**Swift to Objective-C Exposure:**
```swift
@objc(DWApp)
class AppObjcWrapper: NSObject {
    @objc static var localCurrencyCode: String {
        get { App.fiatCurrency }
        set { App.shared.fiatCurrency = newValue }
    }
}
```

### Conditional Compilation
DashPay features use conditional compilation:

```swift
#if DASHPAY
    // DashPay-specific functionality
    func setupDashPayFeatures() {
        // Implementation
    }
#endif
```

## Data Management Patterns

### Database Access Pattern (DAO)
Data access is abstracted through Data Access Objects:

```swift
protocol TransactionMetadataDAOProtocol {
    func save(_ metadata: TransactionMetadata) throws
    func fetch(txHash: String) throws -> TransactionMetadata?
    func fetchAll() throws -> [TransactionMetadata]
    func delete(txHash: String) throws
}

class TransactionMetadataDAOImpl: TransactionMetadataDAOProtocol {
    private let database: DatabaseConnection
    
    func save(_ metadata: TransactionMetadata) throws {
        let sql = """
            INSERT OR REPLACE INTO transaction_metadata 
            (tx_hash, service_name, custom_name, icon_bitmap_id) 
            VALUES (?, ?, ?, ?)
        """
        try database.execute(sql, parameters: [
            metadata.txHash,
            metadata.serviceName,
            metadata.customName,
            metadata.iconBitmapId
        ])
    }
}
```

### Migration Pattern
Database schema changes use timestamped migration files:

```sql
-- 20250418145536_more_metadata_tx_userinfo.sql
ALTER TABLE tx_userinfo ADD COLUMN merchant_name TEXT;
ALTER TABLE tx_userinfo ADD COLUMN location TEXT;
CREATE INDEX idx_tx_userinfo_merchant ON tx_userinfo(merchant_name);
```

### UserDefaults Wrapper Pattern
Settings use typed wrappers for UserDefaults:

```objc
@interface DWGlobalOptions : NSObject
@property (nonatomic, assign, getter=isBiometricAuthEnabled) BOOL biometricAuthEnabled;
@property (nonatomic, copy) NSString *localCurrencyCode;
+ (instancetype)sharedInstance;
@end

@implementation DWGlobalOptions
- (BOOL)isBiometricAuthEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"BiometricAuthEnabled"];
}
@end
```

## UI Development Patterns

### Base View Controller Pattern
Common functionality is inherited from base classes:

```swift
class BaseViewController: UIViewController, ErrorPresentable, NetworkReachabilityObservable {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBaseConfiguration()
        observeNetworkReachability()
    }
    
    func setupBaseConfiguration() {
        // Common setup for all view controllers
        view.backgroundColor = UIColor.dw_background()
        setupNavigationBar()
    }
    
    func showError(_ error: Error) {
        // Standardized error presentation
        let alert = errorAlert(for: error)
        present(alert, animated: true)
    }
}
```

### SwiftUI Integration Pattern
SwiftUI components are integrated using hosting controllers:

```swift
extension UIViewController {
    func presentSwiftUISheet<Content: View>(
        _ content: Content,
        detents: [UISheetPresentationController.Detent] = [.medium(), .large()]
    ) {
        let hostingController = UIHostingController(rootView: content)
        
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = detents
            sheet.prefersGrabberVisible = true
        }
        
        present(hostingController, animated: true)
    }
}
```

### Custom View Pattern
Reusable UI components follow a consistent pattern:

```swift
class CustomComponentView: UIView {
    // MARK: - UI Components
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.dw_mediumFont(ofSize: 16)
        label.textColor = UIColor.dw_primaryText()
        return label
    }()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    private func setupView() {
        addSubview(titleLabel)
        setupConstraints()
        applyStyle()
    }
    
    private func setupConstraints() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
```

## Error Handling Patterns

### Structured Error Types
Errors are defined as enums with associated values:

```swift
enum CoinbaseError: Error, LocalizedError {
    case authenticationRequired
    case insufficientBalance
    case networkError(underlying: Error)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return NSLocalizedString("Please authenticate with Coinbase", comment: "")
        case .insufficientBalance:
            return NSLocalizedString("Insufficient balance", comment: "")
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return NSLocalizedString("Invalid response from server", comment: "")
        }
    }
}
```

### Result Type Usage
Async operations return Result types for explicit error handling:

```swift
func performNetworkOperation() async -> Result<DataModel, NetworkError> {
    do {
        let data = try await networkClient.fetchData()
        let model = try JSONDecoder().decode(DataModel.self, from: data)
        return .success(model)
    } catch {
        return .failure(.networkFailure(error))
    }
}
```

## Testing Patterns

### Mock Objects Pattern
Test doubles are created for external dependencies:

```swift
class MockRatesProvider: RatesProvider {
    var shouldReturnError = false
    var mockRates: [String: Double] = [:]
    
    func fetchRates() async throws -> [String: Double] {
        if shouldReturnError {
            throw RatesError.networkError
        }
        return mockRates
    }
}

class CurrencyExchangerTests: XCTestCase {
    var sut: CurrencyExchanger!
    var mockProvider: MockRatesProvider!
    
    override func setUp() {
        super.setUp()
        mockProvider = MockRatesProvider()
        sut = CurrencyExchanger(provider: mockProvider)
    }
    
    func testSuccessfulRateFetch() async throws {
        // Given
        mockProvider.mockRates = ["USD": 25.50]
        
        // When
        let rate = try await sut.exchangeRate(for: "USD")
        
        // Then
        XCTAssertEqual(rate, 25.50)
    }
}
```

## Integration Patterns

### External Service Integration
External services follow a consistent integration pattern:

```swift
protocol ExternalServiceProtocol {
    associatedtype AuthType
    associatedtype ResponseType
    
    func authenticate(_ auth: AuthType) async throws
    func performRequest<T: Codable>(_ endpoint: APIEndpoint) async throws -> T
}

class ExternalService: ExternalServiceProtocol {
    private let httpClient: HTTPClient<APIResponse>
    private var authToken: String?
    
    func authenticate(_ credentials: Credentials) async throws {
        let response = try await httpClient.post("/auth", body: credentials)
        self.authToken = response.token
    }
    
    func performRequest<T: Codable>(_ endpoint: APIEndpoint) async throws -> T {
        guard let token = authToken else {
            throw ServiceError.notAuthenticated
        }
        
        return try await httpClient.request(endpoint, headers: ["Authorization": "Bearer \(token)"])
    }
}
```

## Localization Patterns

### String Management
All user-facing strings use NSLocalizedString:

```swift
extension String {
    static let welcomeMessage = NSLocalizedString("Welcome to Dash Wallet", 
                                                 comment: "Main welcome message")
    static let balanceFormat = NSLocalizedString("Balance: %@", 
                                                comment: "Balance display format")
}

// Usage
titleLabel.text = .welcomeMessage
balanceLabel.text = String.localizedStringWithFormat(.balanceFormat, formattedAmount)
```

### Pluralization Support
Complex pluralization uses stringsdict files:

```xml
<!-- Localizable.stringsdict -->
<key>transaction_count</key>
<dict>
    <key>NSStringLocalizedFormatKey</key>
    <string>%#@transactions@</string>
    <key>transactions</key>
    <dict>
        <key>NSStringFormatSpecTypeKey</key>
        <string>NSStringPluralRuleType</string>
        <key>NSStringFormatValueTypeKey</key>
        <string>d</string>
        <key>zero</key>
        <string>No transactions</string>
        <key>one</key>
        <string>1 transaction</string>
        <key>other</key>
        <string>%d transactions</string>
    </dict>
</dict>
```

These patterns provide a solid foundation for maintaining consistency and quality while developing new features or maintaining existing code in the Dash Wallet iOS project.