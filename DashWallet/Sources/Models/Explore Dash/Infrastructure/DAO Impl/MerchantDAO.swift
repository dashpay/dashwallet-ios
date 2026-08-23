//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreLocation
import Foundation
import SQLite
private typealias Expression = SQLite.Expression

// MARK: - MerchantDAO

class MerchantDAO: PointOfUseDAO {
    typealias Item = ExplorePointOfUse

    private let connection: ExploreDatabaseConnection

    let serialQueue = DispatchQueue(label: "org.dashfoundation.dashpaytnt.explore.serial.queue")

    private var cachedTerritories: [Territory] = []

    init(dbConnection: ExploreDatabaseConnection) {
        connection = dbConnection
    }

    /// Extracts sourceId from a database row, handling String, Int64, Int types and nil/empty values
    /// - Parameters:
    ///   - row: The database row (Statement.Element)
    ///   - index: The column index for sourceId
    /// - Returns: The sourceId as a String, or nil if missing/empty/invalid
    private func extractSourceId(from row: Statement.Element, at index: Int) -> String? {
        guard row.count > index else { return nil }

        if let sourceId = row[index] as? String, !sourceId.isEmpty {
            return sourceId
        } else if let sourceId = row[index] as? Int64 {
            return String(sourceId)
        } else if let sourceId = row[index] as? Int {
            return String(sourceId)
        } else if let sourceId = row[index] {
            let stringValue = String(describing: sourceId)
            if stringValue == "<null>" || stringValue == "nil" {
                return nil
            }
            return stringValue
        }

        return nil
    }

    func items(filters: PointOfUseDAOFilters, offset: Int?,
               completion: @escaping (Swift.Result<PaginationResult<Item>, Error>) -> Void) { }

    // TODO: Refactor: Use a data struct for filters and sorting
    func items(query: String?,
               bounds: ExploreMapBounds?,
               userLocation: CLLocationCoordinate2D?,
               types: [ExplorePointOfUse.Merchant.`Type`],
               paymentMethods: [PointOfUseListFilters.SpendingOptions]?,
               sortBy: PointOfUseListFilters.SortBy?,
               territory: Territory?,
               denominationType: PointOfUseListFilters.DenominationType?,
               offset: Int,
               completion: @escaping (Swift.Result<PaginationResult<Item>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }

            let merchantTable = Table("merchant")
            let name = ExplorePointOfUse.name
            let typeColumn = ExplorePointOfUse.type
            let paymentMethodColumn = ExplorePointOfUse.paymentMethod
            let territoryColumn = ExplorePointOfUse.territory

            var queryFilter = Expression<Bool>(value: true)

            // Add query
            if let query {
                queryFilter = queryFilter && name.like("%\(query)%")
            }

            queryFilter = queryFilter && types.map { $0.rawValue }.contains(typeColumn) // Add types

            // Add payment methods
            if let methods = paymentMethods {
                var tempMethods: [ExplorePointOfUse.Merchant.PaymentMethod] = []

                if methods.contains(PointOfUseListFilters.SpendingOptions.dash) {
                    tempMethods.append(ExplorePointOfUse.Merchant.PaymentMethod.dash)
                }

                let hasCTX = methods.contains(PointOfUseListFilters.SpendingOptions.ctx)
                #if PIGGYCARDS_ENABLED
                let hasPiggy = methods.contains(PointOfUseListFilters.SpendingOptions.piggyCards)
                #else
                let hasPiggy = false
                #endif

                if hasCTX || hasPiggy {
                    tempMethods.append(ExplorePointOfUse.Merchant.PaymentMethod.giftCard)
                }

                queryFilter = queryFilter && tempMethods.map { $0.rawValue }.contains(paymentMethodColumn)

                // If only specific gift card providers are selected (not both), add merchantId filter
                if !methods.contains(PointOfUseListFilters.SpendingOptions.dash) && (hasCTX != hasPiggy) {
                    var providerList: [String] = []
                    if hasCTX {
                        providerList.append("'CTX'")
                    }
                    #if PIGGYCARDS_ENABLED
                    if hasPiggy {
                        providerList.append("'PiggyCards'")
                    }
                    #endif
                    
                    let providerString = providerList.joined(separator: ", ")
                    queryFilter = queryFilter && Expression<Bool>(literal: "merchantId IN (SELECT DISTINCT merchantId FROM gift_card_providers WHERE provider IN (\(providerString)))")
                }
            }
            
            // Filter out URL-based redemption merchants (not supported)
            // Using literal expression to handle cases where redeemType column might not exist
            queryFilter = queryFilter && Expression<Bool>(literal: "(redeemType IS NULL OR redeemType != 'url')")

            // Filter out PiggyCards-only merchants when:
            // 1. PIGGYCARDS_ENABLED is not defined, OR
            // 2. PIGGYCARDS_ENABLED is defined but user is in a restricted region (Russia or Cuba)
            #if PIGGYCARDS_ENABLED
            if isPiggyCardsGeoRestricted() {
                queryFilter = queryFilter && Expression<Bool>(literal: "merchantId NOT IN (SELECT DISTINCT merchantId FROM gift_card_providers WHERE provider = 'PiggyCards' AND merchantId NOT IN (SELECT DISTINCT merchantId FROM gift_card_providers WHERE provider != 'PiggyCards'))")
            }
            #else
            queryFilter = queryFilter && Expression<Bool>(literal: "merchantId NOT IN (SELECT DISTINCT merchantId FROM gift_card_providers WHERE provider = 'PiggyCards' AND merchantId NOT IN (SELECT DISTINCT merchantId FROM gift_card_providers WHERE provider != 'PiggyCards'))")
            #endif
            
            // Add denomination type filter (only applies to gift card merchants)
            if let denominationType = denominationType {
                switch denominationType {
                case .fixed:
                    // Include all dash merchants OR gift card merchants with "fixed" denomination
                    queryFilter = queryFilter && (paymentMethodColumn == "dash" || Expression<Bool>(literal: "denominationsType = 'fixed'"))
                case .flexible:
                    // Include all dash merchants OR gift card merchants with "min-max" denomination
                    queryFilter = queryFilter && (paymentMethodColumn == "dash" || Expression<Bool>(literal: "denominationsType = 'min-max'"))
                case .both:
                    // No additional filter needed - include all
                    break
                }
            }

            if let territory {
                queryFilter = queryFilter && territoryColumn.like(territory)
            } else if let bounds {
                // Make the rectangular bounds more generous to ensure we don't exclude locations
                // that should be within the circular radius. Add 50% buffer to each dimension.
                let latBuffer = (bounds.neCoordinate.latitude - bounds.swCoordinate.latitude) * 0.5
                let lonBuffer = (bounds.neCoordinate.longitude - bounds.swCoordinate.longitude) * 0.5

                let expandedSWLat = bounds.swCoordinate.latitude - latBuffer
                let expandedNELat = bounds.neCoordinate.latitude + latBuffer
                let expandedSWLon = bounds.swCoordinate.longitude - lonBuffer
                let expandedNELon = bounds.neCoordinate.longitude + lonBuffer

                // Build the bounds filter for physical locations
                let physicalBoundsFilter = Expression<Bool>(literal: "latitude > \(expandedSWLat)") &&
                    Expression<Bool>(literal: "latitude < \(expandedNELat)") &&
                    Expression<Bool>(literal: "longitude > \(expandedSWLon)") &&
                    Expression<Bool>(literal: "longitude < \(expandedNELon)")

                // If we're querying for online merchants (e.g., "All" tab), include them regardless of bounds
                // Online merchants don't have physical locations so they shouldn't be filtered by bounds
                if types.contains(.online) {
                    let boundsFilter = physicalBoundsFilter || Expression<Bool>(literal: "type = 'online'")
                    queryFilter = queryFilter && boundsFilter
                } else {
                    // For nearby tab (physical only), just use the bounds filter
                    queryFilter = queryFilter && physicalBoundsFilter
                }
            }

            var query = merchantTable
                .select(merchantTable[*])
                .filter(queryFilter)

            // Collapse the location rows to one row per merchant. When the user's location is
            // known, SQLite picks the location closest to the user: in an aggregate query with a
            // single MIN() in the result set, bare columns take their values from the row where
            // the minimum occurs. The distance is an equirectangular approximation in meters —
            // accurate enough for ranking and radius filtering at the app's search scales.
            var hasDistanceColumn = false

            if let anchorLatitude = userLocation?.latitude, let anchorLongitude = userLocation?.longitude {
                let metersPerLatitudeDegree = 111_111.0
                let metersPerLongitudeDegree = 111_111.0 * cos(anchorLatitude * .pi / 180)
                let distanceSq =
                    "((latitude - \(anchorLatitude)) * \(metersPerLatitudeDegree) * (latitude - \(anchorLatitude)) * \(metersPerLatitudeDegree) + " +
                    "(longitude - \(anchorLongitude)) * \(metersPerLongitudeDegree) * (longitude - \(anchorLongitude)) * \(metersPerLongitudeDegree))"

                query = merchantTable
                    .select(merchantTable[*], Expression<Double?>(literal: "MIN(\(distanceSq)) AS minDistanceSq"))
                    .filter(queryFilter)
                hasDistanceColumn = true

                if let bounds {
                    // The WHERE clause only pre-filters with a generous rectangle; enforce the real
                    // circular radius on each merchant's closest location here. Groups with a NULL
                    // distance are online merchants without coordinates — keep them, the bounds
                    // filter above already decided whether online rows belong in the result.
                    let radius = wSelf.circularFilterRadius(for: bounds)
                    let having = Expression<Bool>(literal: "(minDistanceSq IS NULL OR minDistanceSq <= \(radius * radius))")
                    query = query.group([ExplorePointOfUse.merchantId], having: having)
                } else {
                    query = query.group([ExplorePointOfUse.merchantId])
                }
            } else {
                query = query.group([ExplorePointOfUse.merchantId])
            }

            // Closest locations first; merchants without coordinates (online) go last.
            let distanceOrdering = Expression<Bool>(literal: "minDistanceSq IS NULL, minDistanceSq ASC")
            let nameOrdering = name.collate(.nocase).asc
            let discountOrdering = ExplorePointOfUse.savingPercentage.desc

            if let sortBy {
                switch sortBy {
                case .name:
                    query = query.order(nameOrdering)
                case .distance:
                    if hasDistanceColumn {
                        query = query.order([distanceOrdering, nameOrdering])
                    } else {
                        query = query.order(nameOrdering)
                    }
                case .discount:
                    query = query.order([discountOrdering, nameOrdering])
                }
            } else if bounds == nil && types.count == 3 {
                // "All" tab default: online merchants first, then mixed, then physical — by name.
                // The grouping above still represents each merchant by its closest location.
                let typeOrdering = Expression<Void>(literal: """
                    CASE
                        WHEN type = 'online' THEN 1
                        WHEN type = 'physical' THEN 3
                        WHEN type = 'both' THEN 2
                    END
                    ASC
                    """)

                query = query.order([typeOrdering, nameOrdering])
            } else if hasDistanceColumn {
                query = query.order([distanceOrdering, nameOrdering])
            } else {
                query = query.order(nameOrdering)
            }

            query = query.limit(pageLimit, offset: offset)

            do {
                var items: [ExplorePointOfUse] = try wSelf.connection.execute(query: query)
                
                // Fetch gift card providers for each merchant that accepts gift cards
                #if PIGGYCARDS_ENABLED
                let excludePiggyCards = isPiggyCardsGeoRestricted()
                #endif
                for (index, item) in items.enumerated() {
                    if let merchant = item.merchant, merchant.paymentMethod == .giftCard {
                        // Only fetch CTX providers when PiggyCards is disabled or user is in restricted region
                        #if PIGGYCARDS_ENABLED
                        let providersQuery: String
                        if excludePiggyCards {
                            providersQuery = """
                                SELECT provider, savingsPercentage, denominationsType, sourceId FROM gift_card_providers
                                WHERE merchantId = '\(merchant.merchantId)' AND provider != 'PiggyCards'
                            """
                        } else {
                            providersQuery = """
                                SELECT provider, savingsPercentage, denominationsType, sourceId FROM gift_card_providers
                                WHERE merchantId = '\(merchant.merchantId)'
                            """
                        }
                        #else
                        let providersQuery = """
                            SELECT provider, savingsPercentage, denominationsType FROM gift_card_providers
                            WHERE merchantId = '\(merchant.merchantId)' AND provider = 'CTX'
                        """
                        #endif

                        do {
                            guard let db = wSelf.connection.db else {
                                continue
                            }

                            let rows = try db.prepare(providersQuery)
                            var providers: [ExplorePointOfUse.Merchant.GiftCardProviderInfo] = []
                            var rowCount = 0

                            for row in rows {
                                rowCount += 1
                                if let providerId = row[0] as? String,
                                   let savingsPercentage = row[1] as? Int64,
                                   let denominationsType = row[2] as? String {

                                    providers.append(ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                                        providerId: providerId,
                                        savingsPercentage: Int(savingsPercentage),
                                        denominationsType: denominationsType,
                                        sourceId: wSelf.extractSourceId(from: row, at: 3)
                                    ))
                                }
                            }


                            if !providers.isEmpty {
                                // Create updated merchant with providers
                                let updatedMerchant = ExplorePointOfUse.Merchant(
                                    merchantId: merchant.merchantId,
                                    paymentMethod: merchant.paymentMethod,
                                    type: merchant.type,
                                    deeplink: merchant.deeplink,
                                    savingsBasisPoints: merchant.savingsBasisPoints,
                                    denominationsType: merchant.denominationsType,
                                    denominations: merchant.denominations,
                                    redeemType: merchant.redeemType,
                                    giftCardProviders: providers
                                )
                                
                                // Create updated ExplorePointOfUse
                                let updatedItem = ExplorePointOfUse(
                                    id: item.id,
                                    name: item.name,
                                    category: .merchant(updatedMerchant),
                                    active: item.active,
                                    city: item.city,
                                    territory: item.territory,
                                    address1: item.address1,
                                    address2: item.address2,
                                    address3: item.address3,
                                    address4: item.address4,
                                    latitude: item.latitude,
                                    longitude: item.longitude,
                                    website: item.website,
                                    phone: item.phone,
                                    logoLocation: item.logoLocation,
                                    coverImage: item.coverImage,
                                    source: item.source
                                )
                                
                                items[index] = updatedItem
                            }
                        } catch {
                            // If we can't fetch providers, just continue with empty providers
                        }
                    }
                }

                completion(.success(PaginationResult(items: items, offset: offset)))
            } catch {
                print(error)
                completion(.failure(error))
            }
        }
    }
}

extension MerchantDAO {
    private struct ExpandedBounds {
        let swLat: Double
        let neLat: Double
        let swLon: Double
        let neLon: Double
    }

    private func expandedCoordinates(for bounds: ExploreMapBounds) -> ExpandedBounds {
        let latBuffer = (bounds.neCoordinate.latitude - bounds.swCoordinate.latitude) * 0.5
        let lonBuffer = (bounds.neCoordinate.longitude - bounds.swCoordinate.longitude) * 0.5

        return ExpandedBounds(
            swLat: bounds.swCoordinate.latitude - latBuffer,
            neLat: bounds.neCoordinate.latitude + latBuffer,
            swLon: bounds.swCoordinate.longitude - lonBuffer,
            neLon: bounds.neCoordinate.longitude + lonBuffer
        )
    }

    private func circularFilterRadius(for bounds: ExploreMapBounds) -> Double {
        let latDiff = bounds.neCoordinate.latitude - bounds.swCoordinate.latitude
        let lonDiff = bounds.neCoordinate.longitude - bounds.swCoordinate.longitude
        return min(latDiff, lonDiff) * 111000 / 2
    }

    private func coordinateValue(from rawValue: Any?) -> Double? {
        if let value = rawValue as? Double {
            return value
        }

        if let value = rawValue as? Int64 {
            return Double(value)
        }

        return nil
    }

    func onlineMerchants(query: String?, onlineOnly: Bool, userPoint: CLLocationCoordinate2D?, sortBy: PointOfUseListFilters.SortBy?,
                         paymentMethods: [PointOfUseListFilters.SpendingOptions]?, denominationType: PointOfUseListFilters.DenominationType?, offset: Int = 0,
                         completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        // When onlineOnly is true, only include pure online merchants
        // When onlineOnly is false, include both online and onlineAndPhysical merchants
        let types: [ExplorePointOfUse.Merchant.`Type`] = onlineOnly ? [.online] : [.online, .onlineAndPhysical]

        items(query: query, bounds: nil, userLocation: userPoint, types: types,
              paymentMethods: paymentMethods, sortBy: sortBy, territory: nil, denominationType: denominationType, offset: offset, completion: completion)
    }

    func nearbyMerchants(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                         paymentMethods: [PointOfUseListFilters.SpendingOptions]?, sortBy: PointOfUseListFilters.SortBy?, territory: Territory?, denominationType: PointOfUseListFilters.DenominationType?, offset: Int = 0,
                         completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        items(query: query, bounds: bounds, userLocation: userPoint, types: [.physical, .onlineAndPhysical],
              paymentMethods: paymentMethods, sortBy: sortBy, territory: territory, denominationType: denominationType, offset: offset, completion: completion)
    }

    func allMerchants(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                      paymentMethods: [PointOfUseListFilters.SpendingOptions]?, sortBy: PointOfUseListFilters.SortBy?, territory: Territory?, denominationType: PointOfUseListFilters.DenominationType?, offset: Int = 0,
                      completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        items(query: query, bounds: bounds, userLocation: userPoint, types: [.online, .onlineAndPhysical, .physical], paymentMethods: paymentMethods, sortBy: sortBy, territory: territory, denominationType: denominationType, offset: offset,
              completion: completion)
    }

    func allLocations(for merchantId: String, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, offset: Int = 0,
                      completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }

            let merchantTable = Table("merchant")
            let merchantIdColumn = ExplorePointOfUse.merchantId

            var queryFilter = Expression<Bool>(value: true)

            queryFilter = queryFilter && Expression<Bool>(merchantIdColumn == merchantId)

            if let bounds {
                let expandedBounds = wSelf.expandedCoordinates(for: bounds)

                let boundsFilter = Expression<Bool>(literal: "latitude > \(expandedBounds.swLat)") &&
                    Expression<Bool>(literal: "latitude < \(expandedBounds.neLat)") &&
                    Expression<Bool>(literal: "longitude > \(expandedBounds.swLon)") &&
                    Expression<Bool>(literal: "longitude < \(expandedBounds.neLon)")

                queryFilter = queryFilter && boundsFilter
            }

            var query = merchantTable
                .select(merchantTable[*])
                .filter(queryFilter)

            var distanceSorting = Expression<Bool>(value: true)

            if let userLocation = userPoint {
                let anchorLatitude = userLocation.latitude
                let anchorLongitude = userLocation.longitude

                distanceSorting =
                    Expression<Bool>(literal: "ABS(latitude-\(anchorLatitude)) + ABS(longitude - \(anchorLongitude)) ASC")
            }

            // Stable secondary sort (id) so offset pagination is deterministic across pages.
            query = query.order([distanceSorting, ExplorePointOfUse.id])
            query = query.limit(pageLimit, offset: offset)

            do {
                var items: [ExplorePointOfUse] = try wSelf.connection.execute(query: query)

                // Apply circular distance filtering if we have bounds and a user location
                // This ensures that "Show all locations" respects radius filtering from the Nearby tab
                if let bounds = bounds, let userLocation = userPoint {
                    let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)

                    let filterRadius = wSelf.circularFilterRadius(for: bounds)

                    items = items.filter { item in
                        guard let lat = item.latitude, let lon = item.longitude else { return false }
                        let distance = userCLLocation.distance(from: CLLocation(latitude: lat, longitude: lon))
                        return distance <= filterRadius
                    }
                }

                // Fetch gift card provider information for gift card merchants
                #if PIGGYCARDS_ENABLED
                let excludePiggyCards = isPiggyCardsGeoRestricted()
                #endif
                for (index, item) in items.enumerated() {
                    if let merchant = item.merchant, merchant.paymentMethod == .giftCard {
                        // Filter out PiggyCards providers when user is in restricted region
                        #if PIGGYCARDS_ENABLED
                        let providersQuery: String
                        if excludePiggyCards {
                            providersQuery = """
                                SELECT provider, savingsPercentage, denominationsType, sourceId FROM gift_card_providers
                                WHERE merchantId = ? AND provider != 'PiggyCards'
                            """
                        } else {
                            providersQuery = """
                                SELECT provider, savingsPercentage, denominationsType, sourceId FROM gift_card_providers
                                WHERE merchantId = ?
                            """
                        }
                        #else
                        let providersQuery = """
                            SELECT provider, savingsPercentage, denominationsType, sourceId FROM gift_card_providers
                            WHERE merchantId = ? AND provider = 'CTX'
                        """
                        #endif

                        do {
                            guard let db = wSelf.connection.db else {
                                print("Error: Database connection is nil for merchant \(merchant.merchantId)")
                                continue
                            }

                            let statement = try db.prepare(providersQuery, merchant.merchantId)
                            var providers: [ExplorePointOfUse.Merchant.GiftCardProviderInfo] = []
                            var rowCount = 0

                            for row in statement {
                                rowCount += 1
                                // Access columns by index
                                let providerId = row[0] as? String
                                let savingsPercentage = row[1] as? Int64
                                let denominationsType = row[2] as? String

                                if let providerId = providerId,
                                   let savingsPercentage = savingsPercentage,
                                   let denominationsType = denominationsType {

                                    providers.append(ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                                        providerId: providerId,
                                        savingsPercentage: Int(savingsPercentage),
                                        denominationsType: denominationsType,
                                        sourceId: wSelf.extractSourceId(from: row, at: 3)
                                    ))
                                }
                            }


                            if !providers.isEmpty {
                                // Create updated merchant with providers
                                let updatedMerchant = ExplorePointOfUse.Merchant(
                                    merchantId: merchant.merchantId,
                                    paymentMethod: merchant.paymentMethod,
                                    type: merchant.type,
                                    deeplink: merchant.deeplink,
                                    savingsBasisPoints: merchant.savingsBasisPoints,
                                    denominationsType: merchant.denominationsType,
                                    denominations: merchant.denominations,
                                    redeemType: merchant.redeemType,
                                    giftCardProviders: providers
                                )

                                // Create updated ExplorePointOfUse
                                let updatedItem = ExplorePointOfUse(
                                    id: item.id,
                                    name: item.name,
                                    category: .merchant(updatedMerchant),
                                    active: item.active,
                                    city: item.city,
                                    territory: item.territory,
                                    address1: item.address1,
                                    address2: item.address2,
                                    address3: item.address3,
                                    address4: item.address4,
                                    latitude: item.latitude,
                                    longitude: item.longitude,
                                    website: item.website,
                                    phone: item.phone,
                                    logoLocation: item.logoLocation,
                                    coverImage: item.coverImage,
                                    source: item.source
                                )

                                items[index] = updatedItem
                            }
                        } catch {
                            // If we can't fetch providers, just continue with empty providers
                            print("Error fetching gift card providers for merchant \(merchant.merchantId): \(error)")
                        }
                    }
                }

                completion(.success(PaginationResult(items: items, offset: offset)))
            } catch {
                print(error)
                completion(.failure(error))
            }
        }
    }

    func allLocationsCount(for merchantId: String, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                           completion: @escaping (Swift.Result<Int, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let self else { return }
            guard let db = self.connection.db else {
                completion(.failure(NSError(domain: "MerchantDAO", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database connection is unavailable."])))
                return
            }

            do {
                if let bounds, let userPoint {
                    let expandedBounds = self.expandedCoordinates(for: bounds)
                    let radius = self.circularFilterRadius(for: bounds)
                    let centerLocation = CLLocation(latitude: userPoint.latitude, longitude: userPoint.longitude)
                    let query = """
                        SELECT latitude, longitude
                        FROM merchant
                        WHERE merchantId = ?
                          AND latitude > ?
                          AND latitude < ?
                          AND longitude > ?
                          AND longitude < ?
                    """

                    let rows = try db.prepare(
                        query,
                        merchantId,
                        expandedBounds.swLat,
                        expandedBounds.neLat,
                        expandedBounds.swLon,
                        expandedBounds.neLon
                    )

                    var count = 0
                    for row in rows {
                        guard let latitude = self.coordinateValue(from: row[0]),
                              let longitude = self.coordinateValue(from: row[1]) else {
                            continue
                        }

                        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                        guard CLLocationCoordinate2DIsValid(coordinate) else { continue }

                        let distance = centerLocation.distance(from: CLLocation(latitude: latitude, longitude: longitude))
                        if distance <= radius {
                            count += 1
                        }
                    }

                    completion(.success(count))
                } else if let bounds {
                    let expandedBounds = self.expandedCoordinates(for: bounds)
                    let query = """
                        SELECT COUNT(*)
                        FROM merchant
                        WHERE merchantId = ?
                          AND latitude > ?
                          AND latitude < ?
                          AND longitude > ?
                          AND longitude < ?
                    """

                    let rows = try db.prepare(
                        query,
                        merchantId,
                        expandedBounds.swLat,
                        expandedBounds.neLat,
                        expandedBounds.swLon,
                        expandedBounds.neLon
                    )

                    let count = Int((rows.makeIterator().next()?[0] as? Int64) ?? 0)
                    completion(.success(count))
                } else {
                    let query = "SELECT COUNT(*) FROM merchant WHERE merchantId = ?"
                    let rows = try db.prepare(query, merchantId)
                    let count = Int((rows.makeIterator().next()?[0] as? Int64) ?? 0)
                    completion(.success(count))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func territories(completion: @escaping (Swift.Result<[Territory], Error>) -> Void) {
        if !cachedTerritories.isEmpty {
            completion(.success(cachedTerritories))
            return
        }

        let query = "SELECT DISTINCT territory from merchant WHERE territory != '' ORDER BY territory"

        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            do {
                let items: [Territory] = try wSelf.connection.execute(query: query)
                self?.cachedTerritories = items
                completion(.success(items))
            } catch {
                print(error)
                completion(.failure(error))
            }
        }
    }
}
