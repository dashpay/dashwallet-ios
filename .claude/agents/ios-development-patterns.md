# iOS Development Patterns Agent

This agent specializes in iOS development patterns, data architecture, and integration workflows specific to the DashWallet project. It provides guidance based on real development sessions and common pitfalls to help future development sessions work more efficiently.

## 🎯 MANDATORY UI Development Policy

### SwiftUI-First Architecture
**CRITICAL**: All new UI components MUST be implemented using SwiftUI. Do NOT create new UIKit ViewControllers, Storyboards, or XIB files.

#### ✅ Required Pattern for New UI
```swift
// 1. SwiftUI View (UI only)
struct NewFeatureView: View {
    @StateObject private var viewModel: NewFeatureViewModel

    var body: some View {
        // SwiftUI declarative UI
    }
}

// 2. ObservableObject ViewModel (Business Logic)
@MainActor
class NewFeatureViewModel: ObservableObject {
    @Published var state: ViewState = .loading

    private let repository: FeatureRepository

    func loadData() {
        // Business logic implementation
    }
}

// 3. Thin UIKit wrapper ONLY if needed for navigation integration
class NewFeatureHostingController: UIHostingController<NewFeatureView> {
    init() {
        let viewModel = NewFeatureViewModel()
        let swiftUIView = NewFeatureView(viewModel: viewModel)
        super.init(rootView: swiftUIView)
    }
}
```

#### ❌ Prohibited Patterns
- Creating new `.storyboard` files
- Creating new `.xib` files
- Subclassing `UIViewController` for UI logic
- Using Interface Builder for new components
- Implementing UI logic directly in UIKit ViewControllers

### Architecture Enforcement
When implementing any new feature:
1. **Start with SwiftUI View** - Define the UI declaratively
2. **Create ViewModel** - Handle business logic and state management
3. **Use Repository Pattern** - Keep data access separate
4. **Add UIKit wrapper** - ONLY if existing navigation requires it

## Database Architecture Understanding

### Key Database Concepts

#### Local vs Remote Database Confusion
**Critical Understanding**: There are two distinct database systems:

1. **Local Database (`explore.db`)**
   - SQLite database stored locally on device
   - Contains cached merchant data and user preferences
   - Managed through `DatabaseConnection.swift`
   - Used for offline functionality and quick lookups

2. **Remote Database (`gs://dash-wallet-firebase.appspot.com/explore/explore-v3.db`)**
   - Firebase-hosted SQLite database
   - Source of truth for merchant information
   - Downloaded and synced periodically
   - Contains the complete merchant directory

**Common Mistake**: Confusing which database contains what data. Always verify if you're looking at local cached data or remote authoritative data.

#### Table Structure and Evolution

**Merchants Table Structure**:
```sql
-- Current merchant table fields (as of recent development)
CREATE TABLE merchant (
    id INTEGER PRIMARY KEY,
    name TEXT,
    logoLocation TEXT,
    website TEXT,
    
    -- Payment configuration
    denominationsType TEXT,  -- EVOLVED FROM: redeemType
    acceptsDash BOOLEAN,
    acceptsGiftCards BOOLEAN,
    
    -- Location data
    latitude REAL,
    longitude REAL,
    
    -- CTX integration
    ctxMerchantId TEXT,
    enabled BOOLEAN DEFAULT 1
);
```

**Field Name Evolution**:
- `redeemType` → `denominationsType` (represents payment type flexibility)
- Always check for both old and new field names when debugging legacy issues

**Gift Card Providers vs Merchants**:
- `gift_card_providers`: Separate table for gift card vendors (GameStop, Target, etc.)
- `merchant`: Main merchant directory table
- **Relationship**: Some merchants may be linked to gift card providers, but they are separate entities

### Data Flow Architecture

#### Model → Database → API Integration Pattern
```swift
// 1. Model Definition (ExplorePointOfUse.Merchant)
struct Merchant {
    let id: Int
    let name: String
    let denominationsType: DenominationsType?
    let enabled: Bool?  // CTX-specific field
    
    // Initializer updates required when adding properties
    init(id: Int, name: String, denominationsType: DenominationsType? = nil, enabled: Bool? = nil) {
        self.id = id
        self.name = name
        self.denominationsType = denominationsType
        self.enabled = enabled
    }
}

// 2. Database Access Pattern
class MerchantDAO {
    func fetchMerchant(id: Int) -> Merchant? {
        // Always implement fallback patterns for new fields
        let ctxEnabled = row["enabled"] as? Bool
        let localEnabled = row["acceptsDash"] as? Bool
        let finalEnabled = ctxEnabled ?? localEnabled ?? true
        
        return Merchant(id: id, enabled: finalEnabled)
    }
}

// 3. API Integration (CTX Service)
class CTXSpendService {
    func refreshTokenAndMerchantInfo() {
        // Network call to update merchant data
        // Triggers updatingMerchant observable
    }
}
```

## CTX API Integration Patterns

### Service Integration Architecture

#### CTXSpendService Integration
```swift
class CTXSpendService: ObservableObject {
    @Published var updatingMerchant = false
    
    // Core integration pattern
    func refreshTokenAndMerchantInfo() {
        updatingMerchant = true
        
        // 1. Network request
        performNetworkRequest { [weak self] result in
            DispatchQueue.main.async {
                // 2. Update local data
                self?.processResponse(result)
                
                // 3. Notify UI
                self?.updatingMerchant = false
            }
        }
    }
    
    // Fallback pattern for API integration
    func getMerchantInfo(id: Int) -> MerchantInfo {
        let ctxInfo = ctxMerchantData[id]
        let localInfo = localMerchantData[id]
        
        // Always implement fallbacks
        return MerchantInfo(
            enabled: ctxInfo?.enabled ?? localInfo?.enabled ?? true,
            denominationsType: ctxInfo?.denominationsType ?? localInfo?.denominationsType
        )
    }
}
```

#### Reactive UI Integration
```swift
// PointOfUseDetailsView.swift pattern
struct PointOfUseDetailsView: View {
    @StateObject private var ctxService = CTXSpendService()
    
    var body: some View {
        VStack {
            // UI elements
        }
        .onAppear {
            // Trigger data refresh
            ctxService.refreshTokenAndMerchantInfo()
        }
        .onReceive(ctxService.$updatingMerchant) { isUpdating in
            // React to loading states
            if !isUpdating {
                // Refresh UI with new data
                updateMerchantDisplay()
            }
        }
    }
}
```

### Data Synchronization Patterns

#### CTX to Local Database Sync
```swift
class MerchantSyncManager {
    func syncMerchantData() {
        // 1. Fetch from CTX API
        ctxService.fetchAllMerchants { merchants in
            // 2. Update local database
            self.databaseManager.updateMerchants(merchants)
            
            // 3. Notify UI components
            NotificationCenter.default.post(name: .merchantsUpdated, object: nil)
        }
    }
    
    // Fallback resolution pattern
    func resolveMerchantData(ctxData: CTXMerchant?, localData: LocalMerchant?) -> MerchantData {
        return MerchantData(
            enabled: ctxData?.enabled ?? localData?.enabled ?? true,
            denominationsType: ctxData?.denominationsType ?? localData?.denominationsType ?? .fixed
        )
    }
}
```

## iOS/Swift Development Patterns

### Model Property Additions

#### Required Initializer Updates
**Rule**: When adding properties to Swift structs/classes, always update initializers.

```swift
// Before: Simple merchant model
struct Merchant {
    let id: Int
    let name: String
    
    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

// After: Adding enabled property
struct Merchant {
    let id: Int
    let name: String
    let enabled: Bool?  // New property
    
    // REQUIRED: Update initializer
    init(id: Int, name: String, enabled: Bool? = nil) {
        self.id = id
        self.name = name
        self.enabled = enabled
    }
}
```

**Common Mistake**: Adding properties without updating initializers leads to compilation errors.

### UIKit + Combine Reactive Patterns

#### Observable Data Flow
```swift
class MerchantViewModel: ObservableObject {
    @Published var merchant: Merchant?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    func loadMerchant(id: Int) {
        isLoading = true
        
        merchantService.fetchMerchant(id: id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] merchant in
                    self?.merchant = merchant
                }
            )
            .store(in: &cancellables)
    }
}
```

#### UIKit Integration with Combine
```swift
class MerchantViewController: UIViewController {
    private let viewModel = MerchantViewModel()
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBindings()
    }
    
    private func setupBindings() {
        // Bind loading state
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.loadingIndicator.isHidden = !isLoading
            }
            .store(in: &cancellables)
        
        // Bind merchant data
        viewModel.$merchant
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] merchant in
                self?.updateUI(with: merchant)
            }
            .store(in: &cancellables)
    }
}
```

### Fallback Pattern Implementation

#### Safe Property Access
```swift
extension Merchant {
    var safeEnabled: Bool {
        // Implement fallback hierarchy
        return ctxEnabled ?? localEnabled ?? true
    }
    
    var safeDenominationsType: DenominationsType {
        return denominationsType ?? .fixed
    }
}

// Usage in UI
class MerchantDisplayService {
    func shouldShowFlexibleAmounts(for merchant: Merchant) -> Bool {
        return merchant.safeEnabled && merchant.safeDenominationsType == .flexible
    }
}
```

## Common Pitfalls and Solutions

### Database-Related Issues

#### Pitfall 1: Confusing Local vs Remote Data
**Problem**: Querying wrong database or assuming data exists locally.
**Solution**: 
```swift
// Always specify data source clearly
func fetchMerchant(id: Int, source: DataSource) -> Merchant? {
    switch source {
    case .local:
        return localDatabase.fetchMerchant(id: id)
    case .remote:
        return remoteDatabase.fetchMerchant(id: id)
    case .hybrid:
        return remoteMerchant ?? localMerchant ?? defaultMerchant
    }
}
```

#### Pitfall 2: Field Name Evolution Confusion
**Problem**: Using deprecated field names (`redeemType` instead of `denominationsType`).
**Solution**: 
```swift
// Create migration-aware accessors
extension DatabaseRow {
    var denominationsType: DenominationsType? {
        // Try new field name first, fall back to old
        if let newValue = self["denominationsType"] as? String {
            return DenominationsType(rawValue: newValue)
        }
        if let oldValue = self["redeemType"] as? String {
            return DenominationsType(rawValue: oldValue)
        }
        return nil
    }
}
```

### CTX Integration Issues

#### Pitfall 3: Missing Fallback Values
**Problem**: Assuming CTX API data is always available.
**Solution**:
```swift
// Always implement fallback chains
func getMerchantStatus(merchant: Merchant) -> MerchantStatus {
    let ctxValue = ctxService.getMerchantInfo(merchant.id)?.enabled
    let localValue = merchant.acceptsDash
    let defaultValue = true
    
    let isEnabled = ctxValue ?? localValue ?? defaultValue
    
    return MerchantStatus(
        enabled: isEnabled,
        source: ctxValue != nil ? .ctx : .local
    )
}
```

### UI Update Issues

#### Pitfall 4: GameStop Flexible Amounts Display
**Problem**: Flexible amounts not displaying correctly due to data source confusion.
**Solution**:
```swift
// Proper data flow validation
class GameStopDisplayManager {
    func shouldShowFlexibleAmounts(merchantId: Int) -> Bool {
        // 1. Check CTX data first
        if let ctxMerchant = ctxService.getMerchant(id: merchantId),
           let ctxEnabled = ctxMerchant.enabled {
            return ctxEnabled && ctxMerchant.denominationsType == .flexible
        }
        
        // 2. Fall back to local data
        if let localMerchant = localDatabase.getMerchant(id: merchantId) {
            return localMerchant.acceptsGiftCards && localMerchant.denominationsType == .flexible
        }
        
        // 3. Default behavior
        return false
    }
}
```

## Effective Debugging Strategies

### Targeted Debug Logging

#### Debug Markers System
```swift
// Use emoji markers for easy log filtering
class DebugLogger {
    static func merchantInfo(_ message: String) {
        print("🎯 MERCHANT: \(message)")
    }
    
    static func ctxAPI(_ message: String) {
        print("🌐 CTX_API: \(message)")
    }
    
    static func database(_ message: String) {
        print("💾 DATABASE: \(message)")
    }
    
    static func ui(_ message: String) {
        print("🎨 UI_UPDATE: \(message)")
    }
}

// Usage throughout codebase
class MerchantService {
    func updateMerchant(id: Int) {
        DebugLogger.merchantInfo("Starting update for merchant \(id)")
        
        ctxService.refreshMerchant(id: id) { result in
            DebugLogger.ctxAPI("Received CTX response: \(result)")
            
            self.updateLocalDatabase(result) { success in
                DebugLogger.database("Local update result: \(success)")
                
                DispatchQueue.main.async {
                    DebugLogger.ui("Triggering UI refresh")
                    self.notifyUIUpdate()
                }
            }
        }
    }
}
```

#### Conditional Debug Output
```swift
#if DEBUG
extension MerchantViewModel {
    func debugDataFlow() {
        print("🎯 CTX Data: \(ctxMerchant?.enabled ?? "nil")")
        print("🎯 Local Data: \(localMerchant?.acceptsDash ?? "nil")")
        print("🎯 Final Value: \(merchant?.safeEnabled ?? "nil")")
    }
}
#endif
```

### Problem Isolation Techniques

#### Data Source Verification
```swift
class DataSourceDebugger {
    static func verifyMerchantData(id: Int) {
        let ctxData = ctxService.getMerchant(id: id)
        let localData = localDatabase.getMerchant(id: id)
        
        print("🎯 Merchant \(id) Data Sources:")
        print("   CTX: enabled=\(ctxData?.enabled ?? "nil"), type=\(ctxData?.denominationsType ?? "nil")")
        print("   Local: enabled=\(localData?.acceptsDash ?? "nil"), type=\(localData?.denominationsType ?? "nil")")
        
        // Verify data consistency
        if let ctxEnabled = ctxData?.enabled,
           let localEnabled = localData?.acceptsDash,
           ctxEnabled != localEnabled {
            print("⚠️ WARNING: CTX and local enabled status mismatch!")
        }
    }
}
```

## Data Model Update Procedures

### Safe Model Evolution

#### 1. Property Addition Checklist
- [ ] Add property to model struct/class
- [ ] Update all initializers with default values
- [ ] Update database schema if needed
- [ ] Add migration script for existing data
- [ ] Update API serialization/deserialization
- [ ] Add unit tests for new property
- [ ] Update UI components that use the model

#### 2. Database Migration Pattern
```swift
// Migration for adding new fields
class DatabaseMigration_AddEnabledField: DatabaseMigration {
    override func migrate() {
        database.execute("ALTER TABLE merchant ADD COLUMN enabled BOOLEAN DEFAULT 1")
        
        // Backfill existing data
        database.execute("UPDATE merchant SET enabled = acceptsDash WHERE enabled IS NULL")
        
        markMigrationComplete()
    }
}
```

#### 3. API Integration Updates
```swift
// Backwards-compatible API handling
extension Merchant {
    init(from apiResponse: [String: Any]) {
        self.id = apiResponse["id"] as? Int ?? 0
        self.name = apiResponse["name"] as? String ?? ""
        
        // Handle field evolution gracefully
        if let enabled = apiResponse["enabled"] as? Bool {
            self.enabled = enabled
        } else if let acceptsDash = apiResponse["acceptsDash"] as? Bool {
            self.enabled = acceptsDash
        } else {
            self.enabled = true
        }
    }
}
```

## Project-Specific Integration Points

### CTXSpendService Architecture
- **Location**: `DashWallet/Sources/Models/Services/CTXSpendService.swift`
- **Purpose**: Handles communication with CTX API for merchant data
- **Key Methods**: 
  - `refreshTokenAndMerchantInfo()`: Updates merchant data from CTX
  - `getMerchantInfo(id:)`: Retrieves specific merchant information
- **Integration Pattern**: Observable service with `@Published` properties

### PointOfUseDetailsView Architecture
- **Location**: `DashWallet/Sources/UI/Explore/PointOfUseDetailsView.swift`
- **Purpose**: Displays detailed merchant information with real-time updates
- **Data Flow**: CTXSpendService → updatingMerchant → UI refresh
- **Key Pattern**: Combine publishers trigger UI updates

### ExplorePointOfUse.Merchant Model
- **Location**: Model definitions for merchant data structures
- **Evolution**: Handles both legacy and current field names
- **Integration**: Works with both CTX API and local database

## Best Practices Summary

### Development Workflow
1. **Always verify data sources** before implementing features
2. **Implement fallback patterns** for all external data dependencies  
3. **Use targeted debugging** with emoji markers for easy log filtering
4. **Test with both CTX and local data** scenarios
5. **Update models safely** following the property addition checklist

### Code Quality
1. **Prefer explicit over implicit** when dealing with optionals
2. **Document field evolution** in comments for future developers
3. **Use descriptive variable names** that indicate data source (`ctxEnabled`, `localEnabled`)
4. **Implement proper error handling** for all network operations
5. **Follow reactive programming patterns** with Combine for UI updates

## Feature Flag Architecture (Updated from Current Session)

### Gift Card Provider System Architecture
The app implements a sophisticated gift card provider system with conditional compilation for feature hiding:

#### Provider Enum Structure
```swift
enum GiftCardProvider: CaseIterable {
    case ctx
    #if PIGGYCARDS_ENABLED
    case piggyCards
    #endif

    var displayName: String {
        switch self {
        case .ctx: return "CTX"
        #if PIGGYCARDS_ENABLED
        case .piggyCards: return "PiggyCards"
        #endif
        }
    }
}
```

#### Repository Factory Pattern
```swift
class DashSpendRepositoryFactory {
    func create(provider: GiftCardProvider) -> any DashSpendRepository {
        switch provider {
        case .ctx:
            return createCTXSpendRepository()
        #if PIGGYCARDS_ENABLED
        case .piggyCards:
            return createPiggyCardsRepository()
        #endif
        }
    }

    #if PIGGYCARDS_ENABLED
    private func createPiggyCardsRepository() -> PiggyCardsRepository {
        return PiggyCardsRepository.shared
    }
    #endif
}
```

#### ViewModel Repository Management
Uses closure-based dictionary initialization for conditional compilation:

```swift
private let repositories: [GiftCardProvider: any DashSpendRepository] = {
    var dict: [GiftCardProvider: any DashSpendRepository] = [
        .ctx: CTXSpendRepository.shared
    ]
    #if PIGGYCARDS_ENABLED
    dict[.piggyCards] = PiggyCardsRepository.shared
    #endif
    return dict
}()
```

### Feature Flag Implementation Patterns

#### Database Conditional Filtering
```swift
// MerchantDAO filtering with conditional compilation
let hasCTX = methods.contains(.ctx)
#if PIGGYCARDS_ENABLED
let hasPiggy = methods.contains(.piggyCards)
#else
let hasPiggy = false
#endif

if hasCTX || hasPiggy {
    // Gift card filtering logic
    var providerList: [String] = []
    if hasCTX { providerList.append("'CTX'") }
    #if PIGGYCARDS_ENABLED
    if hasPiggy { providerList.append("'PiggyCards'") }
    #endif
}
```

#### UI Filter Implementation
Uses helper computed properties to avoid SwiftUI ViewBuilder conflicts:

```swift
struct FilterView: View {
    // Helper computed properties for conditional UI logic
    private var shouldShowPiggyCards: Bool {
        #if PIGGYCARDS_ENABLED
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        VStack {
            // CTX always available
            FilterOption("CTX")

            // PiggyCards conditionally available
            if shouldShowPiggyCards {
                FilterOption("PiggyCards")
            }
        }
    }
}
```

### Boolean Expression Conditional Compilation
Avoid inline conditional compilation in complex boolean expressions:

#### ❌ Problematic Pattern
```swift
// Causes syntax errors when PIGGYCARDS_ENABLED is undefined
private var hasChanges: Bool {
    return ctxChanged ||
    #if PIGGYCARDS_ENABLED
    piggyChanged ||
    #endif
    otherChanged
}
```

#### ✅ Correct Pattern
```swift
private var hasChanges: Bool {
    let baseChanges = ctxChanged || otherChanged
    #if PIGGYCARDS_ENABLED
    return baseChanges || piggyChanged
    #else
    return baseChanges
    #endif
}
```

### Architecture Benefits
1. **Clean Separation**: Features can be completely hidden without runtime checks
2. **Easy Rollback**: Simply remove/add compilation flags to enable/disable features
3. **Build-Time Optimization**: Unused code is completely eliminated from binary
4. **Testing**: Can test both enabled and disabled states easily
5. **Deployment Flexibility**: Different builds can have different feature sets

### Common Pitfalls and Solutions
1. **SwiftUI ViewBuilder Issues**: Use computed properties instead of inline conditionals
2. **Dictionary Syntax Errors**: Use closure-based initialization
3. **Boolean Expression Errors**: Split complex expressions with conditional variables
4. **Repository Missing**: Ensure conditional compilation covers both declaration and usage
5. **Filter Logic Inconsistency**: Always provide fallback values for disabled features

## SwiftUI Development Patterns (MANDATORY for New UI)

### MVVM Architecture with SwiftUI

#### View-ViewModel Binding Patterns
```swift
// Views should be stateless and delegate all business logic to ViewModels
struct MerchantListView: View {
    @StateObject private var viewModel = MerchantListViewModel()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List(viewModel.filteredMerchants) { merchant in
                MerchantRowView(merchant: merchant)
                    .onTapGesture {
                        viewModel.selectMerchant(merchant)
                    }
            }
            .searchable(text: $searchText)
            .onChange(of: searchText) { _, newValue in
                viewModel.filterMerchants(by: newValue)
            }
            .refreshable {
                await viewModel.refreshData()
            }
            .task {
                await viewModel.loadInitialData()
            }
            .alert("Error", isPresented: $viewModel.hasError) {
                Button("Retry") { viewModel.retryLastAction() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
}
```

#### ViewModel State Management
```swift
@MainActor
class MerchantListViewModel: ObservableObject {
    @Published var merchants: [Merchant] = []
    @Published var filteredMerchants: [Merchant] = []
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""

    private let merchantRepository: MerchantRepository
    private let locationService: LocationService

    init(merchantRepository: MerchantRepository = .shared) {
        self.merchantRepository = merchantRepository
        self.locationService = LocationService.shared
    }

    func loadInitialData() async {
        isLoading = true

        do {
            merchants = try await merchantRepository.fetchMerchants()
            filteredMerchants = merchants
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    func filterMerchants(by searchText: String) {
        filteredMerchants = searchText.isEmpty ?
            merchants : merchants.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func handleError(_ error: Error) {
        hasError = true
        errorMessage = error.localizedDescription
    }
}
```

### Navigation Patterns

#### SwiftUI Navigation (Preferred)
```swift
// Use NavigationStack for programmatic navigation
struct MainNavigationView: View {
    var body: some View {
        NavigationStack {
            MerchantListView()
                .navigationDestination(for: Merchant.self) { merchant in
                    MerchantDetailsView(merchant: merchant)
                }
                .navigationDestination(for: PaymentRequest.self) { request in
                    PaymentView(request: request)
                }
        }
    }
}
```

#### UIKit Integration Bridge
```swift
// Extension for pushing SwiftUI views from UIKit contexts
extension UINavigationController {
    func pushSwiftUIView<Content: View>(
        _ view: Content,
        title: String? = nil,
        hidesBottomBar: Bool = false
    ) {
        let hostingController = UIHostingController(rootView: view)
        hostingController.title = title
        hostingController.hidesBottomBarWhenPushed = hidesBottomBar
        pushViewController(hostingController, animated: true)
    }

    func presentSwiftUIView<Content: View>(
        _ view: Content,
        style: UIModalPresentationStyle = .pageSheet
    ) {
        let hostingController = UIHostingController(rootView: view)
        hostingController.modalPresentationStyle = style
        present(hostingController, animated: true)
    }
}
```

### Data Flow Patterns

#### Repository Integration
```swift
// ViewModels should use repositories, not direct API calls
class PaymentViewModel: ObservableObject {
    @Published var paymentState: PaymentState = .idle

    private let paymentRepository: PaymentRepository
    private let walletService: WalletService

    init(
        paymentRepository: PaymentRepository = .shared,
        walletService: WalletService = .shared
    ) {
        self.paymentRepository = paymentRepository
        self.walletService = walletService
    }

    func processPayment(_ request: PaymentRequest) async {
        paymentState = .processing

        do {
            let transaction = try await paymentRepository.createTransaction(request)
            let result = try await walletService.broadcastTransaction(transaction)
            paymentState = .completed(result)
        } catch {
            paymentState = .failed(error)
        }
    }
}
```

#### Combine Integration for Reactive Updates
```swift
class MerchantViewModel: ObservableObject {
    @Published var merchant: Merchant?
    @Published var isOnline = false

    private var cancellables = Set<AnyCancellable>()
    private let networkMonitor: NetworkMonitor

    init(merchantId: String) {
        self.networkMonitor = NetworkMonitor.shared

        // React to network changes
        networkMonitor.$isConnected
            .assign(to: \.isOnline, on: self)
            .store(in: &cancellables)

        // Auto-refresh when coming back online
        networkMonitor.$isConnected
            .filter { $0 == true }
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshMerchantData()
                }
            }
            .store(in: &cancellables)
    }
}
```

### UI Component Patterns

#### Reusable SwiftUI Components
```swift
// Create reusable components instead of duplicating UI code
struct MerchantRowView: View {
    let merchant: Merchant

    var body: some View {
        HStack {
            AsyncImage(url: merchant.logoURL) { image in
                image.resizable()
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(merchant.name)
                    .font(.headline)

                Text(merchant.category)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if merchant.hasDiscount {
                DiscountBadge(percentage: merchant.discountPercentage)
            }
        }
        .padding(.vertical, 4)
    }
}
```

### State Management Best Practices

#### Loading States
```swift
enum ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(Error)
}

struct ContentView<Data>: View where Data: Hashable {
    let state: ViewState<Data>
    let content: (Data) -> AnyView
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle:
            Color.clear
                .onAppear { retry() }

        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let data):
            content(data)

        case .error(let error):
            ErrorView(error: error, retry: retry)
        }
    }
}
```

### Performance Patterns

#### Efficient List Updates
```swift
// Use proper identifiers for list performance
struct MerchantListView: View {
    @StateObject private var viewModel: MerchantListViewModel

    var body: some View {
        List {
            ForEach(viewModel.merchants) { merchant in
                MerchantRowView(merchant: merchant)
                    .id(merchant.id) // Explicit ID for performance
            }
        }
        .animation(.default, value: viewModel.merchants)
    }
}
```

This documentation should significantly reduce common mistakes and improve development efficiency for future iOS sessions on the DashWallet project.