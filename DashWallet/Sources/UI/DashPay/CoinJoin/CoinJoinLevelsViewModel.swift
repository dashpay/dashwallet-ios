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
        CoinJoinLevelViewModel.shared.infoShown
    }
}

private let kInfoShown = "coinJoinInfoShownKey"
private let kKeepOpenShown = "coinJoinKeepOpenShownKey"


class CoinJoinLevelViewModel: ObservableObject {
    static let shared = CoinJoinLevelViewModel()
    private var cancellableBag = Set<AnyCancellable>()
    private let coinJoinService = CoinJoinService.shared
    
    @Published var selectedMode: CoinJoinMode = .none
    @Published private(set) var isMixing: Bool = false
    
    private var _infoShown: Bool? = nil
    var infoShown: Bool {
        get { _infoShown ?? UserDefaults.standard.bool(forKey: kInfoShown) }
        set(value) {
            _infoShown = value
            UserDefaults.standard.set(value, forKey: kInfoShown)
        }
    }
    
    private var _keepOpenInfoShown: Bool? = nil
    var keepOpenInfoShown: Bool {
        get { _keepOpenInfoShown ?? UserDefaults.standard.bool(forKey: kKeepOpenShown) }
        set(value) {
            _keepOpenInfoShown = value
            UserDefaults.standard.set(value, forKey: kKeepOpenShown)
        }
    }
    
    var hasWiFi: Bool { coinJoinService.hasWiFi }
    
    init() {
        coinJoinService.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.selectedMode = mode
                self?.isMixing = mode != .none
            }
            .store(in: &cancellableBag)
        
        resetSelectedMode()
    }

    func resetSelectedMode() {
        self.selectedMode = coinJoinService.mode
        self.isMixing = coinJoinService.mode != .none
    }
    
    func startMixing() {
        if self.selectedMode != .none {
            Task {
                await coinJoinService.updateMode(mode: self.selectedMode)
            }
        }
    }
    
    func stopMixing() {
        selectedMode = .none
        Task {
            await coinJoinService.updateMode(mode: .none)
        }
    }

    func isTimeSkewedForCoinJoin() async -> Bool {
        do {
            let timeSkew = try await TimeUtils.getTimeSkew()
            coinJoinService.updateTimeSkew(timeSkew: timeSkew)
            
            if timeSkew > 0 {
                return timeSkew > kMaxAllowedAheadTimeskew
            } else {
                return -timeSkew > kMaxAllowedBehindTimeskew
            }
        } catch {
            return false
        }
    }
}
