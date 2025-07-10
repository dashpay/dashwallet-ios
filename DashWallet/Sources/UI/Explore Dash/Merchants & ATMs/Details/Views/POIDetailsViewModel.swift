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

@MainActor
class POIDetailsViewModel: ObservableObject, SyncingActivityMonitorObserver, NetworkReachabilityHandling, DWLocationObserver {
    private var cancellableBag = Set<AnyCancellable>()
    
    private let repositories: [GiftCardProvider: any DashSpendRepository] = [
        GiftCardProvider.ctx : CTXSpendRepository.shared,
        GiftCardProvider.piggyCards : PiggyCardsRepository.shared
    ]
    
    private let syncMonitor = SyncingActivityMonitor.shared
    private let merchant: ExplorePointOfUse
    
    // NetworkReachabilityHandling requirements
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!
    
    @Published private(set) var userEmail: String? = nil
    @Published private(set) var isUserSignedIn = false
    @Published private(set) var networkStatus: NetworkStatus = .offline
    @Published private(set) var syncState: SyncingActivityMonitor.State = .unknown
    @Published private(set) var distanceText: String? = nil
    @Published private(set) var supportedProviders: [GiftCardProvider: Bool] = [:]
    @Published private(set) var selectedProvider: GiftCardProvider? = nil
    @Published private(set) var showProviderPicker: Bool = false
    
    init(merchant: ExplorePointOfUse) {
        self.merchant = merchant
        
        setupProviders()
        setupObservers()
        updateDistance()
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
        // TODO: temp - randomly determine provider configuration
        guard case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard else {
            return
        }
        
        let random = Int.random(in: 0...2)
        
        switch random {
        case 0: // Multiple providers
            supportedProviders[.ctx] = merchant.merchant?.denominationsType == DenominationType.Fixed.rawValue
            supportedProviders[.piggyCards] = false
            selectedProvider = .ctx
            showProviderPicker = true
        case 1: // Only CTX
            supportedProviders[.ctx] = merchant.merchant?.denominationsType == DenominationType.Fixed.rawValue
            selectedProvider = .ctx
            showProviderPicker = false
        case 2: // Only PiggyCards
            supportedProviders[.piggyCards] = merchant.merchant?.denominationsType == DenominationType.Fixed.rawValue
            selectedProvider = .piggyCards
            showProviderPicker = false
        default:
            supportedProviders[.ctx] = merchant.merchant?.denominationsType == DenominationType.Fixed.rawValue
            selectedProvider = .ctx
            showProviderPicker = false
        }
        
        // Start observing the selected provider
        if let selectedProvider = selectedProvider {
            observeDashSpendState(provider: selectedProvider)
        }
    }
    
    // MARK: - SyncingActivityMonitorObserver
    
    nonisolated func syncingActivityMonitorProgressDidChange(_ progress: Double) { }
    
    nonisolated func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        Task { @MainActor in
            self.syncState = state
        }
    }
}
