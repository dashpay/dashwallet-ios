//  
//  Created by Andrei Ashikhmin
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

import Combine
import Foundation
import CoreLocation
import MapKit

@MainActor
class POIDetailsViewModel: ObservableObject, SyncingActivityMonitorObserver, NetworkReachabilityHandling, DWLocationObserver {
    private var cancellableBag = Set<AnyCancellable>()
    
    private let repositories: [GiftCardProvider: any DashSpendRepository] = {
        var dict: [GiftCardProvider: any DashSpendRepository] = [
            .ctx: CTXSpendRepository.shared
        ]
        #if PIGGYCARDS_ENABLED
        dict[.piggyCards] = PiggyCardsRepository.shared
        #endif
        return dict
    }()
    
    private let syncMonitor = SyncingActivityMonitor.shared
    private let merchant: ExplorePointOfUse
    private var currentSearchRadius: Double = kDefaultRadius
    private var searchCenterCoordinate: CLLocationCoordinate2D?

    // NetworkReachabilityHandling requirements
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!
    
    @Published private(set) var userEmail: String? = nil
    @Published private(set) var isUserSignedIn = false
    @Published private(set) var networkStatus: NetworkStatus = .offline
    @Published private(set) var syncState: SyncingActivityMonitor.State = .unknown
    @Published private(set) var distanceText: String? = nil
    @Published private(set) var supportedProviders: [GiftCardProvider: (isFixed: Bool, discount: Int)] = [:]
    @Published private(set) var selectedProvider: GiftCardProvider? = nil
    @Published private(set) var showProviderPicker: Bool = false
    @Published private(set) var locationCount: Int = 0
    @Published private(set) var merchantEnabled: Bool = true

    var formattedPhoneNumber: String? {
        guard let phone = merchant.phone, !phone.isEmpty else { return nil }
        return formatPhoneNumber(phone)
    }
    
    init(merchant: ExplorePointOfUse, searchRadius: Double? = nil, searchCenterCoordinate: CLLocationCoordinate2D? = nil) {
        self.merchant = merchant
        self.searchCenterCoordinate = searchCenterCoordinate

        if let radius = searchRadius {
            self.currentSearchRadius = radius
        }

        setupProviders()
        setupObservers()
        updateDistance()
        fetchLocationCount()
    }
    
    func observeDashSpendState(provider: GiftCardProvider?) {
        cancellableBag.removeAll()
        guard let provider = provider, let repository = repositories[provider] else { return }
        
        repository.isUserSignedInPublisher
            .sink { [weak self] isSignedIn in
                self?.isUserSignedIn = isSignedIn
            }
            .store(in: &cancellableBag)
        
        repository.userEmailPublisher
            .sink { [weak self] email in
                self?.userEmail = email
            }
            .store(in: &cancellableBag)
    }
    
    func selectProvider(_ provider: GiftCardProvider) {
        selectedProvider = provider
        observeDashSpendState(provider: provider)
    }
    
    // MARK: - DWLocationObserver
    
    nonisolated func locationManagerDidChangeCurrentLocation(_ manager: DWLocationManager, location: CLLocation) {
        Task { @MainActor in
            self.updateDistance()
        }
    }
    
    nonisolated func locationManagerDidChangeCurrentReversedLocation(_ manager: DWLocationManager) { }
    
    nonisolated func locationManagerDidChangeServiceAvailability(_ manager: DWLocationManager) {
        Task { @MainActor in
            self.updateDistance()
        }
    }
    
    func logout(provider: GiftCardProvider) {
        repositories[provider]?.logout()
    }
    
    deinit {
        syncMonitor.remove(observer: self)
        stopNetworkMonitoring()
        DWLocationManager.shared.remove(observer: self)
    }
    
    private func setupObservers() {
        // Monitor network status
        networkStatusDidChange = { [weak self] status in
            Task { @MainActor in
                self?.networkStatus = status
            }
        }
        startNetworkMonitoring()
        
        // Monitor sync status
        syncMonitor.add(observer: self)
        syncState = syncMonitor.state
        
        // Monitor location changes
        DWLocationManager.shared.add(observer: self)
    }
    
    private func updateDistance() {
        guard let currentLocation = DWLocationManager.shared.currentLocation,
              DWLocationManager.shared.isAuthorized,
              let latitude = merchant.latitude,
              let longitude = merchant.longitude else {
            distanceText = nil
            return
        }
        
        let distance = CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: currentLocation)
        let measurement = Measurement(value: floor(distance), unit: UnitLength.meters)
        distanceText = ExploreDash.distanceFormatter.string(from: measurement)
    }
    
    private func setupProviders() {
        guard case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard else {
            return
        }

        // Get gift card providers from the merchant data
        for providerInfo in m.giftCardProviders {
            guard let provider = providerInfo.provider else { continue }

            let isFixed = providerInfo.denominationsType == DenominationType.Fixed.rawValue
            let discount = providerInfo.savingsPercentage

            supportedProviders[provider] = (isFixed: isFixed, discount: discount)
        }

        // Determine if we need to show the provider picker
        showProviderPicker = supportedProviders.count > 1

        // Select the first available provider
        selectedProvider = supportedProviders.keys.first

        // Start observing the selected provider
        if let selectedProvider = selectedProvider {
            observeDashSpendState(provider: selectedProvider)
        }

        // Fetch merchant enabled status from API
        Task {
            await fetchMerchantStatus()
        }
    }

    private func fetchMerchantStatus() async {
        guard case .merchant(let m) = merchant.category,
              m.paymentMethod == .giftCard,
              let provider = selectedProvider,
              let repository = repositories[provider] as? CTXSpendRepository else {
            return
        }

        do {
            let merchantResponse = try await repository.getMerchant(merchantId: m.merchantId)
            merchantEnabled = merchantResponse.enabled
        } catch {
            // On error, default to enabled to avoid blocking legitimate purchases
            merchantEnabled = true
        }
    }
    
    func updateSearchRadius(_ radius: Double) {
        currentSearchRadius = radius
        fetchLocationCount()
    }

    private func fetchLocationCount() {
        // Check if we should ignore radius filtering (when coming from "All" tab)
        let shouldIgnoreRadius = currentSearchRadius == Double.greatestFiniteMagnitude

        if shouldIgnoreRadius {
            // For "All" tab: Get total location count without any radius filtering
            ExploreDash.shared.allLocations(for: merchant.pointOfUseId, in: nil, userPoint: nil) { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let locations):
                        let count = locations.items.count
                        self?.locationCount = count
                    case .failure(let error):
                        self?.locationCount = 0
                    }
                }
            }
            return
        }

        // For other tabs: Apply radius filtering as before
        // Use search center if available (when user panned the map), otherwise use GPS location
        let locationToUse: CLLocation?
        if let searchCenter = searchCenterCoordinate {
            locationToUse = CLLocation(latitude: searchCenter.latitude, longitude: searchCenter.longitude)
        } else {
            locationToUse = DWLocationManager.shared.currentLocation
        }

        guard let currentLocation = locationToUse else {
            locationCount = 0
            return
        }

        // Create bounds using current search radius around the search location
        let bounds = ExploreMapBounds(rect: MKCircle(center: currentLocation.coordinate, radius: currentSearchRadius).boundingMapRect)


        ExploreDash.shared.allLocations(for: merchant.pointOfUseId, in: bounds, userPoint: currentLocation.coordinate) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let locations):
                    let count = locations.items.count
                    self?.locationCount = count
                case .failure(let error):
                    self?.locationCount = 0
                }
            }
        }
    }

    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        // Remove all non-numeric characters
        let digits = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        // Format as US phone number if it has 10 digits
        if digits.count == 10 {
            let areaCode = String(digits.prefix(3))
            let exchange = String(digits.dropFirst(3).prefix(3))
            let number = String(digits.suffix(4))
            return "+1 \(areaCode) \(exchange) \(number)"
        } else if digits.count == 11 && digits.hasPrefix("1") {
            let areaCode = String(digits.dropFirst().prefix(3))
            let exchange = String(digits.dropFirst(4).prefix(3))
            let number = String(digits.suffix(4))
            return "+1 \(areaCode) \(exchange) \(number)"
        }

        // Return original if can't format
        return phoneNumber
    }

    // MARK: - SyncingActivityMonitorObserver

    nonisolated func syncingActivityMonitorProgressDidChange(_ progress: Double) { }

    nonisolated func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        Task { @MainActor in
            self.syncState = state
        }
    }
}
