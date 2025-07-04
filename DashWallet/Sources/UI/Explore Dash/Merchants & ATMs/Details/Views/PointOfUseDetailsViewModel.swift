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

@MainActor
class MerchantDetailsViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    
    private let repositories: [GiftCardProvider: any DashSpendRepository] = [
        GiftCardProvider.ctx : CTXSpendRepository.shared,
        GiftCardProvider.piggyCards : PiggyCardsRepository.shared
    ]
    
    @Published private(set) var userEmail: String? = nil
    @Published private(set) var isUserSignedIn = false
    
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
}
