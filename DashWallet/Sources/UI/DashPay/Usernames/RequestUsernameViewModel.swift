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

import Combine

class RequestUsernameViewModel {
    private var cancellableBag = Set<AnyCancellable>()
    @Published private(set) var hasEnoughBalance = false
    var minimumRequiredBalance: String {
        return DWDP_MIN_BALANCE_TO_CREATE_USERNAME.formattedDashAmount
    }
    
    public static let shared: RequestUsernameViewModel = .init()
    
    init() {
        observeBalance()
    }
    
    private func observeBalance() {
        checkBalance()
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in self?.checkBalance() }
            .store(in: &cancellableBag)
    }
    
    private func checkBalance() {
        let balance = DWEnvironment.sharedInstance().currentAccount.balance
        hasEnoughBalance = balance >= DWDP_MIN_BALANCE_TO_CREATE_USERNAME
    }
}
