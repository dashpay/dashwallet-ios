# iOS Swift Safety Patterns Agent

This agent specializes in iOS/Swift safety patterns, crash prevention, and code quality best practices based on real-world debugging sessions in the DashWallet iOS project.

## Critical Safety Patterns

### Force Unwrapping Prevention

#### ⚠️ Most Common Crash Risks
Based on CodeRabbit reviews and build failures encountered:

1. **Coordinate Force Unwrapping**
   ```swift
   // DANGEROUS - Will crash if latitude/longitude is nil
   let distance = CLLocation(latitude: latitude!, longitude: longitude!).distance(from: currentLocation)
   
   // SAFE - Use guard statements
   guard let latitude = latitude, let longitude = longitude else { return }
   let distance = CLLocation(latitude: latitude, longitude: longitude).distance(from: currentLocation)
   ```

2. **Optional Property Force Unwrapping**
   ```swift
   // DANGEROUS - Will crash if lastBounds is nil
   fetch(by: lastQuery, in: lastBounds!, userPoint: lastUserPoint)
   
   // SAFE - Use guard with error handling
   guard let lastBounds = lastBounds else {
       completion(.failure(NSError(domain: "DataProvider", code: -1, 
                                 userInfo: [NSLocalizedDescriptionKey: "No bounds available"])))
       return
   }
   fetch(by: lastQuery, in: lastBounds, userPoint: lastUserPoint)
   ```

3. **Map Annotation Creation**
   ```swift
   // DANGEROUS - Crashes if merchant has no coordinates
   .map { MerchantAnnotation(merchant: $0, location: .init(latitude: $0.latitude!, longitude: $0.longitude!)) }
   
   // SAFE - Use compactMap with guard
   .compactMap { merchant -> MerchantAnnotation? in
       guard let latitude = merchant.latitude, let longitude = merchant.longitude else {
           return nil
       }
       return MerchantAnnotation(merchant: merchant, location: .init(latitude: latitude, longitude: longitude))
   }
   ```

### Implicitly Unwrapped Optionals (IUO) Guidelines

#### When IUOs Are Acceptable
```swift
// ✅ SAFE - UI elements initialized in viewDidLoad/configureHierarchy
class ViewController: UIViewController {
    private var tableView: UITableView!
    private var mapView: MKMapView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy() // Always called, guarantees initialization
    }
    
    private func configureHierarchy() {
        tableView = UITableView()
        mapView = MKMapView()
        // ... setup code
    }
}
```

#### When IUOs Are Dangerous
```swift
// ❌ DANGEROUS - Runtime properties that might not be set
class DataProvider {
    var lastBounds: ExploreMapBounds! // Could be nil if nextPage() called before items()
    
    func nextPage() {
        // This will crash if lastBounds was never set
        fetch(in: lastBounds)
    }
}

// ✅ SAFE - Use optional with guard
class DataProvider {
    var lastBounds: ExploreMapBounds?
    
    func nextPage() {
        guard let lastBounds = lastBounds else {
            // Handle error gracefully
            return
        }
        fetch(in: lastBounds)
    }
}
```

### Generic Type Inference Issues

#### Common Compilation Errors
```swift
// ❌ FAILS - Generic parameter 'Element' could not be inferred
let newItems = merchants.compactMap { merchant in
    guard let lat = merchant.latitude, let lng = merchant.longitude else { return nil }
    return MerchantAnnotation(merchant: merchant, location: .init(latitude: lat, longitude: lng))
}

// ✅ FIXED - Explicit return type annotation
let newItems = merchants.compactMap { merchant -> MerchantAnnotation? in
    guard let lat = merchant.latitude, let lng = merchant.longitude else { return nil }
    return MerchantAnnotation(merchant: merchant, location: .init(latitude: lat, longitude: lng))
}
```

## Map and Location Safety Patterns

### CLLocationCoordinate2D Handling
```swift
// Safe coordinate validation
extension CLLocationCoordinate2D {
    var isValid: Bool {
        return CLLocationCoordinate2DIsValid(self) && 
               latitude != 0 && longitude != 0
    }
}

// Usage in UI
func updateDistanceLabel(for merchant: ExplorePointOfUse) {
    if let currentLocation = DWLocationManager.shared.currentLocation,
       DWLocationManager.shared.isAuthorized,
       let latitude = merchant.latitude,
       let longitude = merchant.longitude,
       CLLocationCoordinate2D(latitude: latitude, longitude: longitude).isValid {
        
        let distance = CLLocation(latitude: latitude, longitude: longitude).distance(from: currentLocation)
        let distanceText = ExploreDash.distanceFormatter.string(from: Measurement(value: distance, unit: UnitLength.meters))
        distanceLabel.text = distanceText
    } else {
        distanceLabel.isHidden = true
    }
}
```

### MapKit Bounds and Region Safety
```swift
// Safe map bounds calculation
extension ExploreMapView {
    var safeMapBounds: ExploreMapBounds? {
        let visibleRect = mapView.visibleMapRect
        guard visibleRect.isValid && !visibleRect.isEmpty else {
            return nil
        }
        return ExploreMapBounds(rect: visibleRect)
    }
    
    func setCenter(_ location: CLLocation, animated: Bool) {
        guard location.coordinate.isValid else {
            print("⚠️ Invalid coordinate provided: \(location.coordinate)")
            return
        }
        
        let miles: Double = centerRadius
        let scalingFactor: Double = abs(cos(2 * Double.pi * location.coordinate.latitude / 360.0))
        let span = MKCoordinateSpan(latitudeDelta: miles / 69.0, 
                                   longitudeDelta: miles / (scalingFactor * 69.0))
        
        let region = MKCoordinateRegion(center: location.coordinate, span: span)
        mapView.setRegion(region, animated: animated)
    }
}
```

## Image and Asset Safety

### Template Image Rendering
```swift
// Ensure SVG icons render properly as templates
extension UIImageView {
    func setSVGTemplateImage(named imageName: String, tintColor: UIColor? = nil) {
        if let image = UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate) {
            self.image = image
            if let tintColor = tintColor {
                self.tintColor = tintColor
            }
        } else {
            print("⚠️ Could not load template image: \(imageName)")
        }
    }
}

// Usage for gift card icons and other SVG assets
paymentIconView.setSVGTemplateImage(named: "gift-card-icon", tintColor: .dw_orange())
```

## Radius and Distance Constants

### Unified Radius Management
```swift
// Central radius constants (based on existing kDefaultRadius = 32000m = 20 miles)
extension ExploreDash {
    static let defaultSearchRadius: Double = kDefaultRadius // 32000 meters (20 miles)
    static let merchantDetailZoomRadius: Double = 1609.34 // 1 mile in meters for map centering
    static let filterRadiusOptions: [PointOfUseListFilters.Radius] = [.one, .five, .twenty, .fifty]
}

// Avoid hardcoded radius values scattered throughout codebase
class ExploreMapView {
    // ✅ Use constant instead of hardcoded value
    var centerRadius: Double = ExploreDash.merchantDetailZoomRadius / 1609.34 // Convert to miles
    
    // ❌ Avoid inconsistent hardcoded values
    // var centerRadius: Double = 5 // Inconsistent with requirements
}
```

## Crash Prevention Checklist

### Pre-Commit Safety Review
- [ ] Search for `!` force unwraps in modified files
- [ ] Check coordinate handling uses guard statements
- [ ] Verify compactMap closures have explicit return types if compilation fails
- [ ] Ensure template images use `.withRenderingMode(.alwaysTemplate)`
- [ ] Remove unused properties that create inconsistency
- [ ] Check IUOs are only used for UI elements initialized in lifecycle methods

### Build Validation Commands
```bash
# Check for dangerous force unwraps
grep -r "latitude!" --include="*.swift" DashWallet/Sources/
grep -r "longitude!" --include="*.swift" DashWallet/Sources/
grep -r "lastBounds!" --include="*.swift" DashWallet/Sources/

# Verify builds succeed after changes
xcodebuild -workspace DashWallet.xcworkspace -scheme dashwallet -destination 'platform=iOS Simulator,name=iPhone 16 Pro' clean build
```

## Error Handling Patterns

### Network and Service Failures
```swift
// Comprehensive error handling for merchant data
class MerchantDataProvider {
    func fetchMerchant(id: Int, completion: @escaping (Result<Merchant, Error>) -> Void) {
        guard id > 0 else {
            completion(.failure(MerchantError.invalidID))
            return
        }
        
        networkService.fetchMerchant(id: id) { [weak self] result in
            switch result {
            case .success(let merchantData):
                // Validate required fields
                guard let name = merchantData.name, !name.isEmpty else {
                    completion(.failure(MerchantError.invalidData("Missing merchant name")))
                    return
                }
                
                let merchant = Merchant(
                    id: id,
                    name: name,
                    enabled: merchantData.enabled ?? true, // Safe fallback
                    latitude: merchantData.latitude,
                    longitude: merchantData.longitude
                )
                completion(.success(merchant))
                
            case .failure(let error):
                print("⚠️ Failed to fetch merchant \(id): \(error)")
                completion(.failure(error))
            }
        }
    }
}
```

### UI State Management
```swift
// Safe UI updates with proper error states
class MerchantViewController {
    private func updateMerchantInfo() {
        loadingIndicator.isHidden = false
        errorLabel.isHidden = true
        
        merchantService.fetchMerchant(id: merchantID) { [weak self] result in
            DispatchQueue.main.async {
                self?.loadingIndicator.isHidden = true
                
                switch result {
                case .success(let merchant):
                    self?.displayMerchant(merchant)
                case .failure(let error):
                    self?.showError(error.localizedDescription)
                }
            }
        }
    }
    
    private func displayMerchant(_ merchant: Merchant) {
        nameLabel.text = merchant.name
        
        // Safe distance calculation
        if let currentLocation = DWLocationManager.shared.currentLocation,
           let latitude = merchant.latitude,
           let longitude = merchant.longitude {
            let merchantLocation = CLLocation(latitude: latitude, longitude: longitude)
            let distance = merchantLocation.distance(from: currentLocation)
            distanceLabel.text = formatDistance(distance)
            distanceLabel.isHidden = false
        } else {
            distanceLabel.isHidden = true
        }
    }
}
```

## Testing Safety Patterns

### Coordinate Edge Cases
```swift
// Test coordinate validation thoroughly
class LocationSafetyTests: XCTestCase {
    func testInvalidCoordinateHandling() {
        let invalidCases = [
            (nil, nil),
            (0.0, 0.0),
            (91.0, 180.0), // Out of bounds
            (-91.0, -181.0)
        ]
        
        for (lat, lng) in invalidCases {
            let merchant = createMerchant(latitude: lat, longitude: lng)
            
            // Should not crash
            XCTAssertNoThrow {
                let result = calculateDistance(for: merchant)
                XCTAssertNil(result, "Should return nil for invalid coordinates")
            }
        }
    }
}
```

## Memory Management

### Weak References and Retain Cycles
```swift
// Prevent retain cycles in closures
class MerchantService {
    func loadMerchantData(completion: @escaping (Merchant?) -> Void) {
        networkService.fetchData { [weak self] result in
            guard let self = self else { return }
            
            // Process result safely
            let merchant = self.processMerchantData(result)
            
            DispatchQueue.main.async {
                completion(merchant)
            }
        }
    }
}

// Safe observation patterns
class MerchantViewController {
    private var observations: [NSObjectProtocol] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let observation = NotificationCenter.default.addObserver(
            forName: .merchantDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshMerchantDisplay()
        }
        
        observations.append(observation)
    }
    
    deinit {
        observations.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
```

## Conditional Compilation Safety Patterns (Updated from Current Session)

### SwiftUI ViewBuilder Compilation Safety

#### ⚠️ SwiftUI ViewBuilder with Conditional Compilation
**Common Error**: `'buildExpression' is unavailable: this expression does not conform to 'View'`

```swift
// DANGEROUS - Causes ViewBuilder compilation errors
var body: some View {
    VStack {
        Text("Always visible")

        if condition
        #if FEATURE_ENABLED
        || featureCondition
        #endif
        {
            Text("Conditional content")
        }
    }
}
```

```swift
// SAFE - Use computed properties
var body: some View {
    VStack {
        Text("Always visible")

        if shouldShowContent {
            Text("Conditional content")
        }
    }
}

private var shouldShowContent: Bool {
    if condition {
        return true
    }
    #if FEATURE_ENABLED
    return featureCondition
    #else
    return false
    #endif
}
```

### Dictionary Initialization Safety

#### ⚠️ Conditional Compilation in Dictionary Literals
**Common Error**: Syntax errors when feature flags are undefined

```swift
// DANGEROUS - Causes syntax errors when FEATURE_ENABLED is undefined
let repositories = [
    .provider1: Repository1(),
    #if FEATURE_ENABLED
    .provider2: Repository2()
    #endif
]
```

```swift
// SAFE - Use closure-based initialization
let repositories: [Provider: Repository] = {
    var dict = [.provider1: Repository1()]
    #if FEATURE_ENABLED
    dict[.provider2] = Repository2()
    #endif
    return dict
}()
```

### Boolean Expression Safety

#### ⚠️ Mid-Expression Conditional Compilation
**Common Error**: Dangling operators when flags are undefined

```swift
// DANGEROUS - Creates dangling || operator
private var hasChanges: Bool {
    return basicChange ||
    #if FEATURE_ENABLED
    featureChange ||
    #endif
    otherChange
}
```

```swift
// SAFE - Split into conditional blocks
private var hasChanges: Bool {
    let baseChanges = basicChange || otherChange
    #if FEATURE_ENABLED
    return baseChanges || featureChange
    #else
    return baseChanges
    #endif
}
```

## CocoaPods Configuration Safety

### Deployment Target Mismatches

#### ⚠️ Platform-Specific Deployment Targets
**Critical Build Error**: Setting iOS deployment targets for watchOS pods

```ruby
# DANGEROUS - Causes build failures on CocoaPods 1.15.2+
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
    end
  end
end
```

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

### Workspace vs Project File Safety

#### ⚠️ Always Use Workspace Files
**Build Issues**: Using `.xcodeproj` instead of `.xcworkspace` with CocoaPods

```bash
# DANGEROUS - Missing pod dependencies
open DashWallet.xcodeproj

# SAFE - Includes all pod dependencies
open DashWallet.xcworkspace
```

## Feature Flag Implementation Safety

### Enum Case Conditional Compilation

#### ⚠️ CaseIterable with Conditional Cases
**Compilation Safety**: Ensure conditional enum cases work with protocols

```swift
// SAFE - Conditional enum cases with CaseIterable
enum GiftCardProvider: CaseIterable {
    case ctx
    #if PIGGYCARDS_ENABLED
    case piggyCards
    #endif

    // All switch statements must handle conditional cases
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

### Repository Pattern Safety

#### ⚠️ Factory Method Conditional Compilation
**Runtime Safety**: Ensure factory methods handle all cases

```swift
// SAFE - Factory with conditional compilation
func create(provider: GiftCardProvider) -> any Repository {
    switch provider {
    case .ctx:
        return CTXRepository.shared
    #if PIGGYCARDS_ENABLED
    case .piggyCards:
        return PiggyCardsRepository.shared
    #endif
    }
}

#if PIGGYCARDS_ENABLED
private func createPiggyCardsRepository() -> PiggyCardsRepository {
    return PiggyCardsRepository.shared
}
#endif
```

## Compilation Safety Checklist

### Before Committing Feature Flag Code:
- [ ] Test compilation with feature flag enabled and disabled
- [ ] Verify SwiftUI views don't use inline conditional compilation
- [ ] Check dictionary initializations use closure pattern
- [ ] Ensure boolean expressions don't have dangling operators
- [ ] Verify all switch statements handle conditional cases
- [ ] Test that CaseIterable works correctly in both states
- [ ] Confirm factory methods create appropriate repositories

### CocoaPods Safety Checklist:
- [ ] Podfile post_install sets platform-specific deployment targets
- [ ] Always use `.xcworkspace` file, not `.xcodeproj`
- [ ] Run `pod install` after Podfile changes, not `pod update`
- [ ] Check that both iOS and watchOS targets build successfully

### Debug Verification Commands:
```bash
# Test feature flag disabled (default)
swift -parse MyFile.swift

# Test feature flag enabled
swift -D PIGGYCARDS_ENABLED -parse MyFile.swift

# Test SwiftUI compilation
swift test_swiftui_file.swift
swift -D PIGGYCARDS_ENABLED test_swiftui_file.swift
```

This safety patterns guide should help prevent the most common crashes and compilation issues encountered in iOS/Swift development on the DashWallet project.