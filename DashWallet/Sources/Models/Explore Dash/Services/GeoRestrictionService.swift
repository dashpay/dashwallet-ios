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
    // Called from per-merchant DAO query loops — do NOT log here (caused 800+ duplicate log lines).
    return UserDefaults.standard.bool(forKey: kGeoRestrictionPiggyCardsRestrictedKey)
}

/// Service to check if the user is in a geo-restricted region for PiggyCards
/// Restricted regions: Russia (RU) and Cuba (CU)
@MainActor
class GeoRestrictionService {
    static let shared = GeoRestrictionService()

    /// Country codes that are restricted from using PiggyCards, listed in both
    /// ISO 3166-1 alpha-2 and alpha-3 form because the sources disagree:
    /// CoreLocation's `isoCountryCode` and `Locale.Region` are alpha-2, while
    /// StoreKit's `Storefront.countryCode` is alpha-3.
    private let restrictedCountryCodes: Set<String> = ["RU", "RUS", "CU", "CUB"]

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
        case appStore = "App Store"
        case deviceRegion = "Device Region"
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

    /// Resolve the user's country and cache the resulting restriction status.
    ///
    /// Every source consulted here is local to the device — none of them
    /// contacts a remote service, so opening the app does not disclose the
    /// user's IP address to a third party.
    ///
    /// Runs at most once per launch: the first call that resolves a country
    /// sets `hasCheckedRestriction`. Later GPS fixes still refresh the status
    /// through `setupLocationObserver`, and `refreshRestriction()` forces a
    /// re-check.
    func checkRestriction() async {
        guard !hasCheckedRestriction else { return }

        // Priority: GPS -> App Store storefront -> device region.
        if DWLocationManager.shared.isAuthorized,
           let countryCode = DWLocationManager.shared.currentPlacemark?.isoCountryCode {
            updateRestrictionStatus(countryCode: countryCode, source: .gpsLocation)
            return
        }

        if let countryCode = await fetchAppStoreCountry() {
            updateRestrictionStatus(countryCode: countryCode, source: .appStore)
            return
        }

        if let countryCode = Locale.current.region?.identifier {
            updateRestrictionStatus(countryCode: countryCode, source: .deviceRegion)
            return
        }

        // Nothing resolved. Leave `hasCheckedRestriction` false so a later call
        // can retry once a source becomes available.
        DWLogger.log("GeoRestrictionService: country undetermined, leaving PiggyCards unrestricted")
        isPiggyCardsRestricted = false
        detectedCountryCode = nil
        detectionSource = .unknown
    }

    /// Fetch country code from App Store storefront. Returns an ISO 3166-1
    /// alpha-3 code, which `restrictedCountryCodes` accounts for.
    private func fetchAppStoreCountry() async -> String? {
        guard let storefront = await Storefront.current else { return nil }
        return storefront.countryCode
    }

    /// Update the restriction status based on detected country
    private func updateRestrictionStatus(countryCode: String, source: DetectionSource) {
        let normalizedCode = countryCode.uppercased()
        let isRestricted = restrictedCountryCodes.contains(normalizedCode)

        self.detectedCountryCode = normalizedCode
        self.detectionSource = source
        self.isPiggyCardsRestricted = isRestricted
        self.hasCheckedRestriction = true

        DWLogger.log("GeoRestrictionService: \(normalizedCode) via \(source.rawValue), PiggyCards restricted: \(isRestricted)")
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
