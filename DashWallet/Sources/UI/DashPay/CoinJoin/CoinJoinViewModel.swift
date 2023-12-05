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

@objc
public class CoinJoinObjcWrapper: NSObject {
    @objc
    public class func infoShown() -> Bool {
        CoinJoinViewModel.shared.infoShown
    }
}


enum CoinJoinMode {
    case none
    case intermediate
    case advanced
}

enum MixingStatus {
    case notStarted
    case mixing
    case paused
    case finished
    case error
}

private let kInfoShown = "coinJoinInfoShownKey"

class CoinJoinViewModel {
    static let shared = CoinJoinViewModel()
    
    private(set) var mode: CoinJoinMode = .none
    @Published private(set) var status: MixingStatus = .notStarted
    
    private var _infoShown: Bool? = nil
    var infoShown: Bool {
        get { _infoShown ?? UserDefaults.standard.bool(forKey: kInfoShown) }
        set(value) {
            _infoShown = value
            UserDefaults.standard.set(value, forKey: kInfoShown)
        }
    }
    
    func startMixing(mode: CoinJoinMode) {
        self.mode = mode
        status = .mixing
    }
    
    func stopMixing() {
        status = .notStarted
    }
}
