//  
//  Created by Andrei Ashikhmin
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

import Foundation
import Combine

@objc
public class CoinJoinObjcWrapper: NSObject {
    @objc
    public class func infoShown() -> Bool {
        CoinJoinViewModel.shared.infoShown
    }
}

private let kInfoShown = "coinJoinInfoShownKey"

class CoinJoinViewModel: ObservableObject {
    static let shared = CoinJoinViewModel()
    private var cancellableBag = Set<AnyCancellable>()
    private let coinJoinService = CoinJoinService.shared
    
    @Published var selectedMode: CoinJoinMode = .none
    @Published private(set) var mixingState: MixingStatus = .notStarted
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var totalBalance: UInt64 = 0
    @Published private(set) var coinJoinBalance: UInt64 = 0
    
    private var _infoShown: Bool? = nil
    var infoShown: Bool {
        get { _infoShown ?? UserDefaults.standard.bool(forKey: kInfoShown) }
        set(value) {
            _infoShown = value
            UserDefaults.standard.set(value, forKey: kInfoShown)
        }
    }
    
    init() {
        coinJoinService.$mixingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.mixingState = state
            }
            .store(in: &cancellableBag)
        
        coinJoinService.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self = self else { return }
                self.progress = progress
                self.totalBalance = coinJoinService.totalBalance
                self.coinJoinBalance = coinJoinService.coinJoinBalance
            }
            .store(in: &cancellableBag)
    }
    
    func startMixing() {
        if self.selectedMode != .none {
            coinJoinService.updateMode(mode: self.selectedMode)
        }
    }
    
    func stopMixing() {
        selectedMode = .none
        coinJoinService.updateMode(mode: .none)
    }
}
