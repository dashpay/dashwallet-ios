# AI Development Guide

This document provides specific guidance for AI developers working with the Dash Wallet iOS codebase, including common tasks, troubleshooting patterns, and development workflows.

## Getting Started for AI Developers

### Understanding the Codebase
1. **Read CLAUDE.md first** - Essential context about build commands and architecture
2. **Review PROJECTFUNCTIONS.md** - Key APIs and function references
3. **Study DEVELOPMENT-PATTERNS.md** - Coding conventions and architectural patterns
4. **Check EXTERNAL-INTEGRATIONS.md** - Third-party service integration patterns

### Key Files for AI Development
```
Essential Files to Understand:
├── CLAUDE.md                     # Main development guide
├── PROJECTFUNCTIONS.md           # API and function reference
├── DEVELOPMENT-PATTERNS.md       # Code patterns and conventions  
├── EXTERNAL-INTEGRATIONS.md      # Third-party integration guide
├── Podfile                       # Dependencies and build configuration
├── DashWallet/Sources/
│   ├── Application/App.swift     # App lifecycle and utilities
│   ├── Models/DWEnvironment.h/m  # Global wallet state
│   └── UI/RootNavigation/        # Main navigation coordinator
```

## Common AI Development Tasks

### Adding New Features

#### 1. UI Feature Addition
**Pattern**: Create feature-based directory structure
```bash
# Create directory structure
mkdir -p "DashWallet/Sources/UI/NewFeature/{Controllers,Views,Models}"

# Follow naming conventions
NewFeatureViewController.swift          # Main controller
NewFeatureViewModel.swift              # Business logic
NewFeatureModel.swift                  # Data model
NewFeatureView.swift                   # SwiftUI components (if applicable)
```

**Implementation Template**:
```swift
// NewFeatureViewController.swift
class NewFeatureViewController: BaseViewController {
    private let viewModel: NewFeatureViewModel
    
    init(viewModel: NewFeatureViewModel = NewFeatureViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
    }
    
    private func setupBindings() {
        // Implement view model bindings
    }
}
```

#### 2. Service Layer Addition
**Pattern**: Create dedicated service with protocol
```swift
// Protocol definition
protocol NewServiceProtocol {
    func performOperation() async throws -> ResultType
}

// Implementation
class NewService: NewServiceProtocol {
    static let shared = NewService()
    private init() {}
    
    func performOperation() async throws -> ResultType {
        // Implementation
    }
}

// Registration (if using DI)
container.register(NewService.shared, for: NewServiceProtocol.self)
```

#### 3. Database Changes
**Steps**:
1. Create migration file with timestamp: `YYYYMMDDHHMMSS_description.sql`
2. Place in `DashWallet/Sources/Infrastructure/Database/Migrations.bundle/`
3. Create DAO for data access
4. Update relevant models

**Example Migration**:
```sql
-- 20250418145536_add_new_feature_table.sql
CREATE TABLE new_feature_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    data TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_new_feature_user_id ON new_feature_data(user_id);
```

### External Service Integration

#### Adding New External Service
**Template**:
```swift
// 1. Define service protocol
protocol NewExternalServiceProtocol {
    func authenticate() async throws
    func performRequest<T: Codable>(_ endpoint: APIEndpoint) async throws -> T
}

// 2. Create service implementation
class NewExternalService: NewExternalServiceProtocol {
    private let httpClient: HTTPClient<APIResponse>
    private var authToken: String?
    
    init() {
        self.httpClient = HTTPClient<APIResponse>()
    }
    
    func authenticate() async throws {
        // Implementation
    }
    
    func performRequest<T: Codable>(_ endpoint: APIEndpoint) async throws -> T {
        // Implementation with error handling
    }
}

// 3. Create API endpoints
enum NewServiceEndpoint {
    case authenticate
    case getData(id: String)
    case postData(request: DataRequest)
}

extension NewServiceEndpoint: TargetType {
    // Moya TargetType implementation
}
```

### Modifying Existing Features

#### Extending View Controllers
**Safe Modification Pattern**:
```swift
// Use extensions to add functionality
extension ExistingViewController {
    func addNewFunctionality() {
        // New functionality without modifying existing code
    }
    
    @objc func handleNewAction() {
        // Action handlers
    }
}

// Or create subclass if significant changes needed
class ExtendedViewController: ExistingViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNewFeatures()
    }
    
    private func setupNewFeatures() {
        // Additional setup
    }
}
```

#### Adding Properties to Existing Models
**Use Categories/Extensions**:
```objc
// Objective-C category
@interface ExistingModel (NewFeature)
@property (nonatomic, copy) NSString *newProperty;
@end

@implementation ExistingModel (NewFeature)
// Implementation
@end
```

```swift
// Swift extension
extension ExistingModel {
    var newComputedProperty: String {
        // Implementation
    }
    
    func newMethod() {
        // Implementation
    }
}
```

## Troubleshooting Common Issues

### Build Issues

#### CocoaPods Problems
```bash
# Clean and reinstall pods
rm -rf Pods/ Podfile.lock
pod install

# If DashSync dependency issues
cd ../DashSync && git pull
cd ../dashwallet-ios && pod install
```

#### Xcode Build Errors
```bash
# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/

# Clean build folder in Xcode
Product → Clean Build Folder (⇧⌘K)

# Reset package cache
File → Packages → Reset Package Caches
```

#### Swift/Objective-C Bridge Issues
```objc
// Add missing imports to bridging header
#import "MissingClass.h"

// Ensure proper @objc exposure
@objc class SwiftClass: NSObject {
    @objc func exposedMethod() { }
}
```

### Runtime Issues

#### Memory Issues
```swift
// Use weak references in closures
viewModel.dataPublisher
    .sink { [weak self] data in
        self?.updateUI(data)
    }
    .store(in: &cancellables)

// Avoid retain cycles in delegates
weak var delegate: ProtocolDelegate?
```

#### Threading Issues
```swift
// Ensure UI updates on main thread
DispatchQueue.main.async {
    self.updateUI()
}

// Or with async/await
await MainActor.run {
    updateUI()
}
```

#### Database Issues
```swift
// Always handle database errors
do {
    let result = try database.fetch(query)
    return result
} catch {
    print("Database error: \(error)")
    throw DatabaseError.queryFailed(error)
}
```

### Testing Issues

#### Test Data Setup
```swift
class TestCase: XCTestCase {
    var mockProvider: MockServiceProvider!
    
    override func setUp() {
        super.setUp()
        mockProvider = MockServiceProvider()
        mockProvider.setupTestData()
    }
    
    override func tearDown() {
        mockProvider.cleanupTestData()
        super.tearDown()
    }
}
```

#### UI Testing
```swift
func testUserFlow() {
    // Launch app
    let app = XCUIApplication()
    app.launch()
    
    // Navigate to feature
    app.buttons["Feature Button"].tap()
    
    // Verify expected state
    XCTAssertTrue(app.staticTexts["Expected Text"].exists)
}
```

## Best Practices for AI Development

### Code Quality
1. **Follow existing patterns** - Don't introduce new patterns unless necessary
2. **Use proper error handling** - Always handle potential failures
3. **Add appropriate comments** - Explain complex logic and business rules
4. **Write tests** - Unit tests for business logic, UI tests for user flows
5. **Follow naming conventions** - Consistent with existing codebase

### Performance Considerations
1. **Database queries** - Use efficient queries and proper indexing
2. **Image loading** - Use SDWebImage for remote images
3. **Network requests** - Implement proper caching and retry logic
4. **Memory management** - Avoid retain cycles and large object accumulation

### Security Considerations
1. **Sensitive data** - Never log private keys or sensitive information
2. **Network security** - Use certificate pinning for critical APIs
3. **Keychain usage** - Store sensitive data in iOS Keychain
4. **Input validation** - Validate all user inputs and API responses

### Localization Requirements
1. **All user-facing text** - Must use NSLocalizedString
2. **String formatting** - Use localized string formats
3. **Date/number formatting** - Use locale-appropriate formatting
4. **RTL support** - Consider right-to-left language support

## Debugging Tools and Techniques

### Xcode Debugging
```swift
// Strategic breakpoints
debugPrint("Debug point reached: \(variable)")

// Conditional breakpoints
// Set condition: variable == expectedValue

// Symbolic breakpoints
// Break on: objc_exception_throw
// Break on: malloc_error_break
```

### Network Debugging
```swift
#if DEBUG
// Log network requests
func debugNetworkRequest(_ request: URLRequest) {
    print("🌐 Request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
    if let body = request.httpBody {
        print("📤 Body: \(String(data: body, encoding: .utf8) ?? "Unable to decode")")
    }
}
#endif
```

### Database Debugging
```swift
#if DEBUG
extension DatabaseConnection {
    func debugQuery(_ sql: String, parameters: [Any] = []) {
        print("🗃️ SQL: \(sql)")
        print("📋 Parameters: \(parameters)")
    }
}
#endif
```

### UI Debugging
```swift
#if DEBUG
extension UIView {
    func debugViewHierarchy(level: Int = 0) {
        let indent = String(repeating: "  ", count: level)
        print("\(indent)\(type(of: self)) - \(frame)")
        
        for subview in subviews {
            subview.debugViewHierarchy(level: level + 1)
        }
    }
}
#endif
```

## Code Review Checklist

### Before Submitting Changes
- [ ] Code follows existing patterns and conventions
- [ ] All user-facing strings are localized
- [ ] Proper error handling is implemented
- [ ] No sensitive information is logged or exposed
- [ ] Tests are written and passing
- [ ] Memory management is correct (no retain cycles)
- [ ] UI updates are performed on main thread
- [ ] Database migrations are created if schema changes
- [ ] Documentation is updated if API changes
- [ ] Build succeeds on all configurations (Debug, Release, TestNet)

### Security Review
- [ ] No private keys or sensitive data in code
- [ ] Input validation is implemented
- [ ] Network requests use proper authentication
- [ ] Keychain is used for sensitive data storage
- [ ] No hardcoded credentials or API keys

### Performance Review
- [ ] Database queries are efficient
- [ ] Images are loaded asynchronously
- [ ] Network requests include proper caching
- [ ] Memory usage is reasonable
- [ ] UI remains responsive during operations

This guide provides a comprehensive foundation for AI developers to work effectively and safely with the Dash Wallet iOS codebase.