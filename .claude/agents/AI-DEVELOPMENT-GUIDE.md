# AI Development Guide

This document provides specific guidance for AI developers working with the Dash Wallet iOS codebase, including common tasks, troubleshooting patterns, and development workflows.

## 🚨 CRITICAL: Git Commit and Push Policy

**NEVER commit or push changes without explicit user permission.**

### Rules:
1. **Make code changes** as requested by the user
2. **Show the user what was changed** using `git diff` or by explaining the changes
3. **WAIT for explicit permission** before running `git commit` or `git push`
4. **Never assume** the user wants changes committed just because they asked for code changes

### Acceptable workflow:
```
User: "Fix the JSON parsing to be less strict"
AI: [Makes changes to code files]
AI: "I've updated CTXSpendModels.swift to make these fields optional: ..."
AI: [Shows diff or explains changes]
AI: [STOPS and WAITS - does NOT commit]

User: "Please commit and push these changes"
AI: [NOW commits and pushes]
```

### Unacceptable workflow:
```
User: "Fix the JSON parsing"
AI: [Makes changes]
AI: [Commits without asking] ❌ WRONG
AI: [Pushes without asking] ❌ WRONG
```

**Exception**: Only commit/push without asking if the user's message explicitly includes phrases like:
- "commit these changes"
- "push to github"
- "create a commit"
- "commit and push"

## Getting Started for AI Developers

### Understanding the Codebase
1. **Read CLAUDE.md first** - Essential context about build commands and architecture
2. **Review .claude/agents/PROJECT-FUNCTIONS.md** - Key APIs and function references
3. **Study DEVELOPMENT-PATTERNS.md** - Coding conventions and architectural patterns
4. **Check EXTERNAL-INTEGRATIONS.md** - Third-party service integration patterns

### Key Files for AI Development
```
Essential Files to Understand:
├── CLAUDE.md                              # Main development guide
├── .claude/agents/PROJECT-FUNCTIONS.md    # API and function reference
├── DEVELOPMENT-PATTERNS.md                # Code patterns and conventions
├── EXTERNAL-INTEGRATIONS.md               # Third-party integration guide
├── Podfile                       # Dependencies and build configuration
├── DashWallet/Sources/
│   ├── Application/App.swift     # App lifecycle and utilities
│   ├── Models/DWEnvironment.h/m  # Global wallet state
│   └── UI/RootNavigation/        # Main navigation coordinator
```

## 🔴 CRITICAL: Git Workflow Policy - NEVER COMMIT WITHOUT PERMISSION

### ⛔ ABSOLUTE RULE: NO AUTONOMOUS COMMITS OR PUSHES

**THIS IS THE MOST IMPORTANT RULE FOR AI ASSISTANTS:**

1. **NEVER run `git commit` without explicit user permission**
2. **NEVER run `git push` without explicit user permission**
3. **ALWAYS stop after making code changes and ASK before committing**

### The ONLY Acceptable Workflow:

```
1. Make code changes as requested
2. Show the changes (git diff or explanation)
3. ✋ FULL STOP - WAIT for user permission
4. Only commit/push when user EXPLICITLY says:
   - "commit these changes"
   - "push to github"
   - "create a commit and push"
   - "commit and push all changes"
```

### ❌ Common Violations to Avoid:

- **VIOLATION**: User asks to "add a feature" → AI adds feature AND commits/pushes
- **VIOLATION**: User asks to "fix a bug" → AI fixes bug AND commits/pushes
- **VIOLATION**: User asks to "update documentation" → AI updates AND commits/pushes

### ✅ Correct Behavior:

- **CORRECT**: User asks to "add a feature" → AI adds feature, shows changes, WAITS
- **CORRECT**: User asks to "fix a bug" → AI fixes bug, shows changes, WAITS
- **CORRECT**: User asks to "update documentation" → AI updates, shows changes, WAITS

### Why This Matters:

- Users need to review changes before they become permanent
- Commits cannot be easily undone once pushed
- Users may want to adjust commit messages
- Users may want to combine multiple changes into one commit
- Users may be working on a specific branch strategy

### Exception: NONE

There are **NO EXCEPTIONS** to this rule. Even if the user seems to imply they want changes committed, always confirm explicitly. When in doubt, ASK before committing.

## Common AI Development Tasks

### Adding New Features

#### 🚨 CRITICAL: SwiftUI-First Development Policy
**MANDATORY**: All new screens MUST use SwiftUI-first architecture. UIKit is only allowed for thin wrapper components when absolutely necessary (camera, complex gestures, third-party integration).

#### 1. SwiftUI UI Feature Addition (REQUIRED)
**Pattern**: SwiftUI View + ViewModel architecture
```bash
# Create directory structure
mkdir -p "DashWallet/Sources/UI/NewFeature/{Views,ViewModels,Models}"

# Follow SwiftUI-first naming conventions
NewFeatureView.swift                   # SwiftUI View (REQUIRED)
NewFeatureViewModel.swift              # ObservableObject ViewModel (REQUIRED)
NewFeatureModel.swift                  # Data model
NewFeatureNavigationView.swift         # Navigation wrapper if needed
```

**SwiftUI Implementation Template** (REQUIRED):
```swift
// NewFeatureView.swift - SwiftUI View (MANDATORY)
struct NewFeatureView: View {
    @StateObject private var viewModel = NewFeatureViewModel()

    var body: some View {
        VStack {
            Text(viewModel.title)
            // SwiftUI content here
        }
        .navigationTitle("New Feature")
        .task {
            await viewModel.loadData()
        }
    }
}

// NewFeatureViewModel.swift - ObservableObject (MANDATORY)
@MainActor
class NewFeatureViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var isLoading = false

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        // Async business logic here
    }
}
```

#### 2. UIKit Wrapper (ONLY When Required)
**Use ONLY for**: Camera, complex gestures, third-party library integration
```swift
// CameraWrapperView.swift - Thin UIKit wrapper when needed
struct CameraWrapperView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Minimal updates only
    }
}

// Usage in SwiftUI (when wrapper is necessary)
struct NewFeatureView: View {
    var body: some View {
        VStack {
            CameraWrapperView() // Only when absolutely necessary
                .frame(height: 300)
        }
    }
}
```

#### ❌ PROHIBITED Patterns:
- New UIViewController subclasses with UI logic
- New Storyboard (.storyboard) files
- New XIB (.xib) files
- @IBOutlet and @IBAction declarations
- Segue-based navigation

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

#### 🚨 CRITICAL: CocoaPods Deployment Target Issues (CocoaPods 1.15.2+)
**Problem**: Setting iOS deployment targets for watchOS pods causes build failures
**Solution**: Platform-specific deployment target configuration in Podfile:

```ruby
# SAFE - Platform-specific deployment targets
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

## Feature Flag Development (Critical Session Learnings)

### Conditional Compilation Safety Patterns
**Based on real debugging experience from PiggyCards feature hiding**

#### ✅ SAFE - SwiftUI ViewBuilder Compatibility
```swift
// Use computed properties for conditional compilation in SwiftUI
var body: some View {
    VStack {
        if shouldShowFeature {
            FeatureView()
        }
    }
}

private var shouldShowFeature: Bool {
    #if FEATURE_ENABLED
    return userHasFeature
    #else
    return false
    #endif
}
```

#### ✅ SAFE - Dictionary Initialization with Feature Flags
```swift
// Use closure-based initialization
private let repositories: [Provider: Repository] = {
    var dict = [.provider1: Repository1()]
    #if FEATURE_ENABLED
    dict[.provider2] = Repository2()
    #endif
    return dict
}()
```

#### ✅ SAFE - Boolean Expression Safety
```swift
// Split conditional compilation from boolean operators
private var hasChanges: Bool {
    let baseChanges = basicChange || otherChange
    #if FEATURE_ENABLED
    return baseChanges || featureChange
    #else
    return baseChanges
    #endif
}
```

#### ❌ DANGEROUS - Common Compilation Errors
```swift
// CAUSES: 'buildExpression' is unavailable
if condition
#if FEATURE_ENABLED
|| featureCondition  // Breaks ViewBuilder
#endif
{ }

// CAUSES: Syntax errors when flag undefined
let dict = [
    .key1: value1,
    #if FEATURE_ENABLED
    .key2: value2  // Dangling comma when disabled
    #endif
]

// CAUSES: Dangling operator
return change1 ||
#if FEATURE_ENABLED
change2 ||  // Orphaned operator
#endif
change3
```

### Feature Flag Testing Checklist
- [ ] Test compilation with feature flag enabled AND disabled
- [ ] Verify SwiftUI views use computed properties for conditionals
- [ ] Check dictionary initializations use closure pattern
- [ ] Ensure boolean expressions don't have dangling operators
- [ ] Confirm enum switch statements handle all conditional cases

This guide provides a comprehensive foundation for AI developers to work effectively and safely with the Dash Wallet iOS codebase, with mandatory SwiftUI-first development requirements and real-world debugging patterns.