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

import Foundation
import Combine

@MainActor
class DashSpendUserAuthViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var isLoading = false
    @Published private(set) var showError = false
    @Published private(set) var errorMessage = ""
    @Published var screenType: DashSpendUserAuthType
    @Published private(set) var isUserSignedIn: Bool = false
    private let provider: GiftCardProvider
    
    private let repositories: [GiftCardProvider: any DashSpendRepository] = [
        GiftCardProvider.ctx : CTXSpendRepository.shared,
        GiftCardProvider.piggyCards : PiggyCardsRepository.shared
    ]
    
    init(provider: GiftCardProvider, screenType: DashSpendUserAuthType) {
        self.screenType = screenType
        self.provider = provider
        self.isUserSignedIn = repositories[provider]?.isUserSignedIn == true
    }
    
    func onContinue() {
        guard let repository = repositories[provider] else { return }
        isLoading = true
        showError = false
        
        Task {
            do {
                switch screenType {
                case .createAccount, .signIn:
                    if try await repository.login(email: input) {
                        screenType = .otp
                    }
                case .otp:
                    if try await repository.verifyEmail(code: input) {
                        isUserSignedIn = true
                    }
                }
            } catch {
                showError = true
                
                if let dashSpendError = error as? DashSpendError {
                    errorMessage = dashSpendError.errorDescription ?? NSLocalizedString("An error occurred", comment: "")
                } else {
                    errorMessage = error.localizedDescription.isEmpty ? NSLocalizedString("An error occurred", comment: "") : error.localizedDescription
                }
            }
            
            isLoading = false
        }
    }
    
    func isInputValid(authType: DashSpendUserAuthType) -> Bool {
        if authType == .otp {
            return !input.isEmpty
        }
        return input.isValidEmail
    }
    
    func clearInput() {
        input = ""
        showError = false
    }
    
    func logout() {
        repositories[provider]?.logout()
    }
}

private extension String {
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }
}
