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

            // Filter out PiggyCards-only merchants when PIGGYCARDS_ENABLED is not defined
            #if !PIGGYCARDS_ENABLED
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
                var boundsFilter = Expression<Bool>(literal: "latitude > \(bounds.swCoordinate.latitude)") &&
                    Expression<Bool>(literal: "latitude < \(bounds.neCoordinate.latitude)") &&
                    Expression<Bool>(literal: "longitude > \(bounds.swCoordinate.longitude)") &&
                    Expression<Bool>(literal: "longitude < \(bounds.neCoordinate.longitude)")

                if types.contains(.online) {
                    boundsFilter = boundsFilter || Expression<Bool>(literal: "type = 'online'")
                }

                queryFilter = queryFilter && boundsFilter
            }

            var query = merchantTable
                .select(merchantTable[*])
                .filter(queryFilter)

            // For each merchant, we want to show only the closest location when userLocation is available
            if let anchorLatitude = userLocation?.latitude, let anchorLongitude = userLocation?.longitude {
                print("🔍🔍🔍 MerchantDAO.items: Using closest location logic for userLocation=(\(anchorLatitude), \(anchorLongitude))")
                // Use a post-processing approach instead of complex SQL
                // First get all matching locations, then filter to closest per merchant in Swift


                // Execute the query to get all matching locations (without grouping)
                let allLocationsQuery = query.limit(1000) // Increase limit to get more locations
                print("🔍🔍🔍 MerchantDAO.items: Fetching all locations (up to 1000) for closest location processing")

                do {
                    var allItems: [ExplorePointOfUse] = try wSelf.connection.execute(query: allLocationsQuery)
                    print("🔍🔍🔍 MerchantDAO.items: Found \(allItems.count) total locations before closest location processing")

                    // Fetch gift card providers for each merchant that accepts gift cards
                    for (index, item) in allItems.enumerated() {
                        if let merchant = item.merchant, merchant.paymentMethod == .giftCard {
                            let providersQuery = """
                                SELECT provider, savingsPercentage, denominationsType FROM gift_card_providers
                                WHERE merchantId = '\(merchant.merchantId)'
                            """

                            do {
                                let rows = try wSelf.connection.db.prepare(providersQuery)
                                var providers: [ExplorePointOfUse.Merchant.GiftCardProviderInfo] = []

                                for row in rows {
                                    if let providerId = row[0] as? String,
                                       let savingsPercentage = row[1] as? Int64,
                                       let denominationsType = row[2] as? String {
                                        providers.append(ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                                            providerId: providerId,
                                            savingsPercentage: Int(savingsPercentage),
                                            denominationsType: denominationsType
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

                                    allItems[index] = updatedItem
                                }
                            } catch {
                                print("Error fetching gift card providers for merchant \(merchant.merchantId): \(error)")
                            }
                        }
                    }

                    // Group locations by merchant and find closest location for each merchant
                    let userCoord = CLLocation(latitude: anchorLatitude, longitude: anchorLongitude)
                    var merchantToClosestLocation: [String: ExplorePointOfUse] = [:]

                    for item in allItems {
                        guard let merchant = item.merchant,
                              let lat = item.latitude,
                              let lon = item.longitude else { continue }

                        let locationCoord = CLLocation(latitude: lat, longitude: lon)
                        let distance = userCoord.distance(from: locationCoord)

                        // Special logging for Famous Dave's to debug the 10.9 mile issue
                        if merchant.merchantId == "245443ee-ac84-4ed6-a0a7-def312894bc3" {
                            print("🔍🔍🔍 MerchantDAO.items: FAMOUS DAVE'S location at (\(lat), \(lon)) = \(distance/1609.34) miles, name='\(item.name)'")
                        }

                        if let existingItem = merchantToClosestLocation[merchant.merchantId],
                           let existingLat = existingItem.latitude,
                           let existingLon = existingItem.longitude {
                            let existingLocationCoord = CLLocation(latitude: existingLat, longitude: existingLon)
                            let existingDistance = userCoord.distance(from: existingLocationCoord)

                            if distance < existingDistance {
                                if merchant.merchantId == "245443ee-ac84-4ed6-a0a7-def312894bc3" {
                                    print("🔍🔍🔍 MerchantDAO.items: FAMOUS DAVE'S Updated closest location: \(distance/1609.34) miles (was \(existingDistance/1609.34) miles)")
                                } else {
                                    print("🔍🔍🔍 MerchantDAO.items: Updated closest location for \(merchant.merchantId): \(distance/1609.34) miles (was \(existingDistance/1609.34) miles)")
                                }
                                merchantToClosestLocation[merchant.merchantId] = item
                            }
                        } else {
                            if merchant.merchantId == "245443ee-ac84-4ed6-a0a7-def312894bc3" {
                                print("🔍🔍🔍 MerchantDAO.items: FAMOUS DAVE'S First location: \(distance/1609.34) miles")
                            } else {
                                print("🔍🔍🔍 MerchantDAO.items: First location for \(merchant.merchantId): \(distance/1609.34) miles")
                            }
                            merchantToClosestLocation[merchant.merchantId] = item
                        }
                    }

                    print("🔍🔍🔍 MerchantDAO.items: After closest location processing: \(merchantToClosestLocation.count) unique merchants")

                    // Convert back to array and apply sorting
                    var items = Array(merchantToClosestLocation.values)

                    if let sortBy = sortBy {
                        switch sortBy {
                        case .name:
                            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                        case .distance:
                            items.sort { item1, item2 in
                                let dist1 = item1.latitude.flatMap { lat in item1.longitude.map { lon in userCoord.distance(from: CLLocation(latitude: lat, longitude: lon)) } } ?? Double.greatestFiniteMagnitude
                                let dist2 = item2.latitude.flatMap { lat in item2.longitude.map { lon in userCoord.distance(from: CLLocation(latitude: lat, longitude: lon)) } } ?? Double.greatestFiniteMagnitude
                                return dist1 < dist2
                            }
                        case .discount:
                            items.sort { ($0.merchant?.savingsBasisPoints ?? 0) > ($1.merchant?.savingsBasisPoints ?? 0) }
                        }
                    } else {
                        // Default to distance sorting when userLocation is available
                        items.sort { item1, item2 in
                            let dist1 = item1.latitude.flatMap { lat in item1.longitude.map { lon in userCoord.distance(from: CLLocation(latitude: lat, longitude: lon)) } } ?? Double.greatestFiniteMagnitude
                            let dist2 = item2.latitude.flatMap { lat in item2.longitude.map { lon in userCoord.distance(from: CLLocation(latitude: lat, longitude: lon)) } } ?? Double.greatestFiniteMagnitude
                            return dist1 < dist2
                        }
                    }

                    // Apply pagination
                    let startIndex = offset
                    let endIndex = min(startIndex + pageLimit, items.count)
                    let paginatedItems = startIndex < items.count ? Array(items[startIndex..<endIndex]) : []

                    // Create pagination result
                    let result = PaginationResult(items: paginatedItems, offset: offset)

                    DispatchQueue.main.async {
                        completion(.success(result))
                    }
                    return
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
            } else {
                query = query.group([ExplorePointOfUse.merchantId])
            }

            var distanceSorting = Expression<Bool>(value: true)

            if let userLocation {
                let anchorLatitude = userLocation.latitude
                let anchorLongitude = userLocation.longitude

                distanceSorting =
                    Expression<Bool>(literal: "((latitude-\(anchorLatitude))*(latitude-\(anchorLatitude))) + ((longitude - \(anchorLongitude))*(longitude - \(anchorLongitude))) ASC")
            }

            let nameOrdering = name.collate(.nocase).asc
            let discountOrdering = ExplorePointOfUse.savingPercentage.desc

            if let sortBy {
                switch sortBy {
                case .name:
                    query = query.order(nameOrdering)
                case .distance:
                    if userLocation != nil {
                        query = query.order([distanceSorting, nameOrdering])
                    } else {
                        query = query.order(nameOrdering)
                    }
                case .discount:
                    query = query.order([discountOrdering, nameOrdering])
                }
            } else if userLocation != nil {
                query = query.order([distanceSorting, nameOrdering])
            } else if bounds == nil && types.count == 3 {
                let typeOrdering = Expression<Void>(literal: """
                    CASE
                        WHEN type = 'online' THEN 1
                        WHEN type = 'physical' THEN 3
                        WHEN type = 'both' THEN 2
                    END
                    ASC
                    """)

                query = query.order([typeOrdering, nameOrdering])
            } else {
                query = query.order(nameOrdering)
            }

            query = query.limit(pageLimit, offset: offset)

            do {
                var items: [ExplorePointOfUse] = try wSelf.connection.execute(query: query)
                
                // Fetch gift card providers for each merchant that accepts gift cards
                for (index, item) in items.enumerated() {
                    if let merchant = item.merchant, merchant.paymentMethod == .giftCard {
                        let providersQuery = """
                            SELECT provider, savingsPercentage, denominationsType FROM gift_card_providers 
                            WHERE merchantId = '\(merchant.merchantId)'
                        """
                        
                        do {
                            let rows = try wSelf.connection.db.prepare(providersQuery)
                            var providers: [ExplorePointOfUse.Merchant.GiftCardProviderInfo] = []
                            
                            for row in rows {
                                if let providerId = row[0] as? String,
                                   let savingsPercentage = row[1] as? Int64,
                                   let denominationsType = row[2] as? String {
                                    providers.append(ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                                        providerId: providerId,
                                        savingsPercentage: Int(savingsPercentage),
                                        denominationsType: denominationsType
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
}

extension MerchantDAO {
    func onlineMerchants(query: String?, onlineOnly: Bool, userPoint: CLLocationCoordinate2D?, sortBy: PointOfUseListFilters.SortBy?,
                         paymentMethods: [PointOfUseListFilters.SpendingOptions]?, denominationType: PointOfUseListFilters.DenominationType?, offset: Int = 0,
                         completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        // When onlineOnly is true, only include pure online merchants
        // When onlineOnly is false, include both online and onlineAndPhysical merchants
        let types: [ExplorePointOfUse.Merchant.`Type`] = onlineOnly ? [.online] : [.online, .onlineAndPhysical]
        print("🔍 MerchantDAO.onlineMerchants: onlineOnly=\(onlineOnly), types=\(types)")

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

    func allLocations(for merchantId: String, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                      completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }

            let merchantTable = Table("merchant")
            let merchantIdColumn = ExplorePointOfUse.merchantId

            var queryFilter = Expression<Bool>(value: true)

            queryFilter = queryFilter && Expression<Bool>(merchantIdColumn == merchantId)

            // Apply the same redemption type filter as the main items() method for consistency
            // Filter out URL-based redemption merchants (not supported)
            queryFilter = queryFilter && Expression<Bool>(literal: "(redeemType IS NULL OR redeemType != 'url')")

            if let bounds {
                let boundsFilter = Expression<Bool>(literal: "latitude > \(bounds.swCoordinate.latitude)") &&
                    Expression<Bool>(literal: "latitude < \(bounds.neCoordinate.latitude)") &&
                    Expression<Bool>(literal: "longitude > \(bounds.swCoordinate.longitude)") &&
                    Expression<Bool>(literal: "longitude < \(bounds.neCoordinate.longitude)")

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

            query = query.order(distanceSorting)

            do {
                let items: [ExplorePointOfUse] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: Int.max)))
            } catch {
                print(error)
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
