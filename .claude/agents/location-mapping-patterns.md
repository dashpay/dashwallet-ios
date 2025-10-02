# Location and Mapping Patterns Agent

This agent specializes in location-based features, mapping functionality, and distance calculations in the DashWallet iOS application. It documents critical patterns and lessons learned from debugging radius filtering and distance calculation issues.

## Critical Distance Filtering Architecture

### The Two-Stage Filtering Pattern (MANDATORY)

All location-based queries in the app MUST implement a two-stage filtering approach to ensure both performance and accuracy:

#### Stage 1: Rectangular Bounds Filtering (SQL Optimization)
- Uses min/max latitude/longitude for initial database filtering
- Reduces dataset size for performance
- Implemented in SQL WHERE clauses

#### Stage 2: Circular Distance Filtering (Accuracy)
- Uses `CLLocation.distance(from:)` for great-circle calculations
- Ensures results are within the true circular radius
- Applied after database query results

### Recent Bug Fix: "Show All Locations" Radius Issue

#### Problem Statement
The "Show all locations" button from the Nearby tab was incorrectly including locations outside the selected radius filter. For example, GameStop was showing 11 locations instead of the correct 7 locations within a 20-mile radius.

#### Root Cause Analysis
The `MerchantDAO.allLocations` function (lines 512-519) was only applying rectangular bounds filtering instead of the circular distance filtering that the main `items` function uses.

#### Solution Implementation
Updated `MerchantDAO.allLocations` function (lines 540-566) to apply the same two-stage filtering:

```swift
func allLocations(by query: String, in bounds: ExploreMapBounds?, userPoint: CLLocation?) -> [ExplorePointOfUse] {
    // Stage 1: SQL query with rectangular bounds
    var whereClauses: [String] = []
    if let bounds = bounds {
        whereClauses.append("latitude BETWEEN \(bounds.southWestCorner.latitude) AND \(bounds.northEastCorner.latitude)")
        whereClauses.append("longitude BETWEEN \(bounds.southWestCorner.longitude) AND \(bounds.northEastCorner.longitude)")
    }

    let sql = """
        SELECT * FROM merchant
        WHERE \(whereClauses.joined(separator: " AND "))
        ORDER BY name ASC
    """

    var merchants = executeQuery(sql)

    // Stage 2: Circular distance filtering
    if let userPoint = userPoint, let bounds = bounds {
        // Calculate radius from bounds using degree-to-meter conversion
        let centerLat = (bounds.northEastCorner.latitude + bounds.southWestCorner.latitude) / 2.0
        let metersPerDegreeLatitude = 111_111.0
        let metersPerDegreeLongitude = 111_111.0 * cos(centerLat * .pi / 180.0)

        let latDiff = abs(bounds.northEastCorner.latitude - bounds.southWestCorner.latitude)
        let lngDiff = abs(bounds.northEastCorner.longitude - bounds.southWestCorner.longitude)

        let latRadius = latDiff * metersPerDegreeLatitude / 2.0
        let lngRadius = lngDiff * metersPerDegreeLongitude / 2.0
        let radius = min(latRadius, lngRadius)

        print("🎯 Calculated radius from bounds: \(radius) meters")

        // Filter by actual circular distance
        merchants = merchants.filter { merchant in
            guard let lat = merchant.latitude, let lng = merchant.longitude else {
                print("🎯 Filtering out merchant with nil coordinates: \(merchant.name ?? "unknown")")
                return false
            }

            let merchantLocation = CLLocation(latitude: lat, longitude: lng)
            let distance = merchantLocation.distance(from: userPoint)
            let isWithinRadius = distance <= radius

            if !isWithinRadius {
                print("🎯 Filtering out \(merchant.name ?? "unknown"): distance \(distance)m > radius \(radius)m")
            }

            return isWithinRadius
        }
    }

    return merchants
}
```

## Distance Calculation Best Practices

### Always Use CLLocation for Distance Calculations

```swift
// ✅ CORRECT: Great-circle distance using Core Location
let distance = CLLocation(latitude: lat1, longitude: lng1)
                 .distance(from: CLLocation(latitude: lat2, longitude: lng2))

// ❌ INCORRECT: Mathematical approximations
let distance = sqrt(pow(lat2 - lat1, 2) + pow(lng2 - lng1, 2)) * someConstant
```

### Radius Conversion from Map Bounds

```swift
func calculateRadiusFromBounds(_ bounds: ExploreMapBounds, centerPoint: CLLocation) -> Double {
    // Calculate the center of the bounds
    let centerLat = (bounds.northEastCorner.latitude + bounds.southWestCorner.latitude) / 2.0
    let centerLng = (bounds.northEastCorner.longitude + bounds.southWestCorner.longitude) / 2.0
    let boundsCenter = CLLocation(latitude: centerLat, longitude: centerLng)

    // Calculate distances to corners
    let neLoc = CLLocation(latitude: bounds.northEastCorner.latitude,
                          longitude: bounds.northEastCorner.longitude)
    let swLoc = CLLocation(latitude: bounds.southWestCorner.latitude,
                          longitude: bounds.southWestCorner.longitude)

    // Use the distance from center to corner
    let neDistance = boundsCenter.distance(from: neLoc)
    let swDistance = boundsCenter.distance(from: swLoc)

    // Return the smaller radius to ensure all displayed items are within bounds
    return min(neDistance, swDistance)
}
```

## Architecture Components

### Key Classes and Their Responsibilities

#### MerchantDAO
- **Location**: `DashWallet/Sources/Models/Persistence/MerchantDAO.swift`
- **Responsibilities**: Database queries for merchant locations
- **Key Methods**:
  - `items()`: Main query method with proper two-stage filtering
  - `allLocations()`: Show all locations with proper filtering (fixed in lines 540-566)

#### AllMerchantLocationsDataProvider
- **Purpose**: Creates circular bounds from radius filters
- **Key Pattern**: Converts user-selected radius to map bounds for display

#### ExploreMapBounds
- **Purpose**: Handles coordinate region calculations
- **Key Properties**:
  - `northEastCorner`: CLLocationCoordinate2D
  - `southWestCorner`: CLLocationCoordinate2D

### Data Flow Hierarchy

1. **User Selection** → Radius filter (1, 5, 20, 50 miles)
2. **AllMerchantLocationsDataProvider** → Creates circular bounds from radius
3. **MerchantDAO.items()** → Applies two-stage filtering for main list
4. **MerchantDAO.allLocations()** → Applies two-stage filtering for "Show all"
5. **UI Display** → Shows only merchants within true circular radius

## Debugging Patterns

### Effective Debug Logging

Use emoji markers for easy log filtering in console output:

```swift
// Debug pattern for distance filtering
print("🎯 Distance Filter Debug:")
print("🎯   Merchant: \(merchantName)")
print("🎯   User Location: \(userLocation.coordinate)")
print("🎯   Merchant Location: (\(latitude), \(longitude))")
print("🎯   Calculated Distance: \(distance)m")
print("🎯   Filter Radius: \(radius)m")
print("🎯   Include in Results: \(distance <= radius)")
```

### Common Debug Scenarios

1. **Missing Merchants**: Check if circular filtering is too restrictive
2. **Extra Merchants**: Verify both stages of filtering are applied
3. **Performance Issues**: Ensure SQL bounds filtering is applied first
4. **Coordinate Issues**: Validate coordinates with `CLLocationCoordinate2DIsValid()`

## Testing Patterns

### Unit Testing Distance Filtering

```swift
func testRadiusFiltering() {
    // Setup
    let userLocation = CLLocation(latitude: 37.7749, longitude: -122.4194) // San Francisco
    let twentyMilesInMeters = 32186.88

    // Test merchants at various distances
    let testCases = [
        (name: "Very Close", lat: 37.7750, lng: -122.4195, distance: 100, shouldInclude: true),
        (name: "10 Miles", lat: 37.9100, lng: -122.4194, distance: 16093, shouldInclude: true),
        (name: "20 Miles Edge", lat: 38.0649, lng: -122.4194, distance: 32180, shouldInclude: true),
        (name: "25 Miles Out", lat: 38.1349, lng: -122.4194, distance: 40233, shouldInclude: false)
    ]

    for testCase in testCases {
        let merchantLocation = CLLocation(latitude: testCase.lat, longitude: testCase.lng)
        let actualDistance = merchantLocation.distance(from: userLocation)
        let isIncluded = actualDistance <= twentyMilesInMeters

        XCTAssertEqual(isIncluded, testCase.shouldInclude,
                      "\(testCase.name) at \(actualDistance)m should be \(testCase.shouldInclude ? "included" : "excluded")")
    }
}
```

### Integration Testing Checklist

- [ ] Test with radius filters: 1, 5, 20, 50 miles
- [ ] Verify "Show all locations" respects current radius
- [ ] Test at city boundaries where merchants are sparse
- [ ] Test in dense urban areas with many merchants
- [ ] Verify performance with large datasets (1000+ merchants)
- [ ] Test with user at map edge vs center

## Common Pitfalls and Solutions

### Pitfall 1: Rectangular vs Circular Confusion
**Problem**: Assuming rectangular bounds from map view equals circular radius
**Solution**: Always apply circular distance filtering after bounds query

### Pitfall 2: Coordinate System Mixing
**Problem**: Mixing degrees with meters in calculations
**Solution**: Use CLLocation for all distance calculations

### Pitfall 3: Null Coordinate Handling
**Problem**: Force unwrapping latitude/longitude causing crashes
**Solution**: Always use guard statements and filter out nil coordinates

### Pitfall 4: Performance Issues
**Problem**: Filtering large datasets in memory without SQL optimization
**Solution**: Use two-stage filtering with SQL bounds first

## Quick Reference

### Constants
- `kDefaultRadius`: 32000 meters (20 miles)
- Default map zoom: 1 mile radius for merchant details

### Key Methods
```swift
// Proper distance check
CLLocation(latitude: lat, longitude: lng).distance(from: userLocation)

// Coordinate validation
CLLocationCoordinate2DIsValid(coordinate)

// Bounds calculation
ExploreMapBounds(center: location, radius: radiusInMeters)
```

### Debug Commands
```bash
# Search for distance filtering in logs
xcrun simctl spawn booted log stream --predicate 'eventMessage contains "🎯"'

# Check for forced unwraps in location code
grep -r "latitude!" DashWallet/Sources/
grep -r "longitude!" DashWallet/Sources/
```

## Lessons Learned

1. **Always Test Edge Cases**: The "Show all locations" bug was only visible when comparing counts between tabs
2. **Use Real Device Testing**: GPS coordinates behave differently on device vs simulator
3. **Document Filtering Logic**: Complex two-stage filtering needs clear documentation
4. **Consistent Debug Output**: Emoji markers make debugging much easier
5. **Trust Core Location**: Don't implement custom distance calculations

This documentation captures the critical patterns and fixes related to location-based features in the DashWallet iOS application, particularly the recent fix for the radius filtering bug in the "Show all locations" functionality.