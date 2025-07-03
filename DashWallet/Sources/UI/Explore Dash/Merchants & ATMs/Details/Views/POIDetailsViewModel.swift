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

@MainActor
class POIDetailsViewModel: ObservableObject, SyncingActivityMonitorObserver, NetworkReachabilityHandling {
    private var cancellableBag = Set<AnyCancellable>()
    
    private let repositories: [GiftCardProvider: any DashSpendRepository] = [
        GiftCardProvider.ctx : CTXSpendRepository.shared,
        GiftCardProvider.piggyCards : PiggyCardsRepository.shared
    ]
    
    private let syncMonitor = SyncingActivityMonitor.shared
    
    // NetworkReachabilityHandling requirements
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!
    
    @Published private(set) var userEmail: String? = nil
    @Published private(set) var isUserSignedIn = false
    @Published private(set) var networkStatus: NetworkStatus = .offline
    @Published private(set) var syncState: SyncingActivityMonitor.State = .unknown
    
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
    
    func logout(provider: GiftCardProvider) {
        repositories[provider]?.logout()
    }
    
    init() {
        setupObservers()
    }
    
    deinit {
        syncMonitor.remove(observer: self)
        stopNetworkMonitoring()
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
    }
    
    // MARK: - SyncingActivityMonitorObserver
    
    nonisolated func syncingActivityMonitorProgressDidChange(_ progress: Double) { }
    
    nonisolated func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        Task { @MainActor in
            self.syncState = state
        }
    }
}
