//
//  GeoRestrictionService.swift
//  dashwallet
//
//  Created for Dash Wallet
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

#if PIGGYCARDS_ENABLED

import Foundation
import CoreLocation
import StoreKit
import Combine

/// UserDefaults key for thread-safe geo-restriction check
private let kGeoRestrictionPiggyCardsRestrictedKey = "geo_restriction_piggycards_restricted"

/// Thread-safe check if PiggyCards is restricted (can be called from any thread)
/// This is a free function that reads directly from UserDefaults
func isPiggyCardsGeoRestricted() -> Bool {
    let isRestricted = UserDefaults.standard.bool(forKey: kGeoRestrictionPiggyCardsRestrictedKey)
    DSLogger.log("🌍 isPiggyCardsGeoRestricted() called, returning: \(isRestricted)")
    return isRestricted
}

/// Service to check if the user is in a geo-restricted region for PiggyCards
/// Restricted regions: Russia (RU) and Cuba (CU)
@MainActor
class GeoRestrictionService {
    static let shared = GeoRestrictionService()

    /// Country codes that are restricted from using PiggyCards
    private let restrictedCountryCodes: Set<String> = ["RU", "CU"]

    /// UserDefaults keys for thread-safe access
    private enum Keys {
        static let isPiggyCardsRestricted = kGeoRestrictionPiggyCardsRestrictedKey
        static let detectedCountryCode = "geo_restriction_country_code"
        static let detectionSource = "geo_restriction_source"
    }

    /// Cached restriction status to avoid repeated checks
    /// Also persisted to UserDefaults for thread-safe access from background queues
    @Published private(set) var isPiggyCardsRestricted: Bool = false {
        didSet {
            UserDefaults.standard.set(isPiggyCardsRestricted, forKey: Keys.isPiggyCardsRestricted)
        }
    }

    /// The detected country code (for debugging)
    @Published private(set) var detectedCountryCode: String? = nil {
        didSet {
            UserDefaults.standard.set(detectedCountryCode, forKey: Keys.detectedCountryCode)
        }
    }

    /// The source of the country detection
    @Published private(set) var detectionSource: DetectionSource? = nil {
        didSet {
            UserDefaults.standard.set(detectionSource?.rawValue, forKey: Keys.detectionSource)
        }
    }

    enum DetectionSource: String {
        case gpsLocation = "GPS Location"
        case ipGeolocation = "IP Geolocation"
        case appStore = "App Store"
        case unknown = "Unknown"
    }

    private var cancellables = Set<AnyCancellable>()
    private var hasCheckedRestriction = false

    private init() {
        // Load persisted restriction status
        isPiggyCardsRestricted = UserDefaults.standard.bool(forKey: Keys.isPiggyCardsRestricted)
        detectedCountryCode = UserDefaults.standard.string(forKey: Keys.detectedCountryCode)
        if let sourceString = UserDefaults.standard.string(forKey: Keys.detectionSource) {
            detectionSource = DetectionSource(rawValue: sourceString)
        }

        DSLogger.log("🌍 GeoRestrictionService: Initialized")
        DSLogger.log("🌍 GeoRestrictionService: Persisted restriction status: \(isPiggyCardsRestricted)")
        DSLogger.log("🌍 GeoRestrictionService: Persisted country code: \(detectedCountryCode ?? "nil")")
        DSLogger.log("🌍 GeoRestrictionService: Persisted detection source: \(detectionSource?.rawValue ?? "nil")")

        // Listen for location changes to update restriction status
        setupLocationObserver()
    }

    private func setupLocationObserver() {
        DWLocationManager.shared.$currentPlacemark
            .sink { [weak self] placemark in
                guard let self = self else { return }
                if let countryCode = placemark?.isoCountryCode {
                    self.updateRestrictionStatus(countryCode: countryCode, source: .gpsLocation)
                }
            }
            .store(in: &cancellables)
    }

    /// Check if PiggyCards is restricted for the current user
    /// This should be called when the app needs to determine PiggyCards availability
    func checkRestriction() async {
        DSLogger.log("🌍 GeoRestrictionService: ========== LOCATION CHECK START ==========")

        // Gather all location attributes for logging
        let gpsAuthorized = DWLocationManager.shared.isAuthorized
        let gpsCountry = DWLocationManager.shared.currentPlacemark?.isoCountryCode
        let ipCountry = await fetchCountryFromIP()
        let appStoreCountry = await fetchAppStoreCountry()

        DSLogger.log("🌍 GeoRestrictionService: 1. GPS Location:")
        DSLogger.log("🌍    - Permission granted: \(gpsAuthorized)")
        DSLogger.log("🌍    - Country code: \(gpsCountry ?? "nil")")

        DSLogger.log("🌍 GeoRestrictionService: 2. IP Geolocation:")
        DSLogger.log("🌍    - Country code: \(ipCountry ?? "nil")")

        DSLogger.log("🌍 GeoRestrictionService: 3. App Store:")
        DSLogger.log("🌍    - Country code: \(appStoreCountry ?? "nil")")

        DSLogger.log("🌍 GeoRestrictionService: ========================================")

        // Priority: GPS -> IP -> App Store
        if gpsAuthorized, let countryCode = gpsCountry {
            DSLogger.log("🌍 GeoRestrictionService: ✅ Using GPS location: \(countryCode)")
            updateRestrictionStatus(countryCode: countryCode, source: .gpsLocation)
            return
        }

        if let countryCode = ipCountry {
            DSLogger.log("🌍 GeoRestrictionService: ✅ Using IP geolocation: \(countryCode)")
            updateRestrictionStatus(countryCode: countryCode, source: .ipGeolocation)
            return
        }

        if let countryCode = appStoreCountry {
            DSLogger.log("🌍 GeoRestrictionService: ✅ Using App Store country: \(countryCode)")
            updateRestrictionStatus(countryCode: countryCode, source: .appStore)
            return
        }

        // If all methods fail, assume not restricted
        DSLogger.log("🌍 GeoRestrictionService: ⚠️ Unable to determine country, assuming not restricted")
        isPiggyCardsRestricted = false
        detectedCountryCode = nil
        detectionSource = .unknown
    }

    /// Fetch country code from IP geolocation service
    private func fetchCountryFromIP() async -> String? {
        // Using ip-api.com - free, no API key required, returns country code
        guard let url = URL(string: "https://ip-api.com/json/?fields=countryCode") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                DSLogger.log("GeoRestrictionService: IP geolocation request failed")
                return nil
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let countryCode = json["countryCode"] as? String {
                DSLogger.log("GeoRestrictionService: IP geolocation returned country: \(countryCode)")
                return countryCode
            }
        } catch {
            DSLogger.log("GeoRestrictionService: IP geolocation error: \(error.localizedDescription)")
        }

        return nil
    }

    /// Fetch country code from App Store storefront
    private func fetchAppStoreCountry() async -> String? {
        if let storefront = await Storefront.current {
            DSLogger.log("GeoRestrictionService: App Store country: \(storefront.countryCode)")
            return storefront.countryCode
        }
        return nil
    }

    /// Update the restriction status based on detected country
    private func updateRestrictionStatus(countryCode: String, source: DetectionSource) {
        let normalizedCode = countryCode.uppercased()
        let isRestricted = restrictedCountryCodes.contains(normalizedCode)

        DSLogger.log("🌍 GeoRestrictionService: updateRestrictionStatus called")
        DSLogger.log("🌍 GeoRestrictionService: Country code: \(normalizedCode)")
        DSLogger.log("🌍 GeoRestrictionService: Source: \(source.rawValue)")
        DSLogger.log("🌍 GeoRestrictionService: Is restricted country: \(isRestricted)")
        DSLogger.log("🌍 GeoRestrictionService: Restricted countries list: \(restrictedCountryCodes)")

        self.detectedCountryCode = normalizedCode
        self.detectionSource = source
        self.isPiggyCardsRestricted = isRestricted
        self.hasCheckedRestriction = true

        DSLogger.log("🌍 GeoRestrictionService: ✅ Restriction status updated - isPiggyCardsRestricted = \(isRestricted)")
    }

    /// Force refresh the restriction check
    func refreshRestriction() async {
        hasCheckedRestriction = false
        await checkRestriction()
    }

    /// Filter out PiggyCards from a list of providers if the user is in a restricted region
    func filterRestrictedProviders(_ providers: [GiftCardProvider]) -> [GiftCardProvider] {
        guard isPiggyCardsRestricted else {
            return providers
        }

        return providers.filter { $0 != .piggyCards }
    }

    /// Check if a specific provider is available in the current region
    func isProviderAvailable(_ provider: GiftCardProvider) -> Bool {
        if provider == .piggyCards && isPiggyCardsRestricted {
            return false
        }
        return true
    }
}

#endif
