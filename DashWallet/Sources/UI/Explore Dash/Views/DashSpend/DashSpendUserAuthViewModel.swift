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
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var screenType: DashSpendUserAuthType = .createAccount
    @Published var isUserSignedIn: Bool = false
    
    private let service = CTXSpendService.shared
    
    func setup(screenType: DashSpendUserAuthType) {
        self.isUserSignedIn = service.isUserSignedIn
        self.screenType = screenType
    }
    
    func onContinue() {
        isLoading = true
        showError = false
        
        Task {
            do {
                switch screenType {
                case .createAccount, .signIn:
                    if try await service.signIn(email: input) {
                        screenType = .otp
                    }
                case .otp:
                    if try await service.verifyEmail(code: input) {
                        isUserSignedIn = true
                    }
                }
            } catch CTXSpendError.invalidCode {
                showError = true
                errorMessage = NSLocalizedString("The code is incorrect. Please check and try again!", comment: "DashSpend")
            } catch CTXSpendError.networkError {
                showError = true
                errorMessage = NSLocalizedString("Please check your network connection", comment: "")
            } catch CTXSpendError.unauthorized {
                showError = true
                errorMessage = NSLocalizedString("Authorization error. Please try logging in again.", comment: "DashSpend")
            } catch {
                showError = true
                errorMessage = NSLocalizedString("An error occurred", comment: "")
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
        service.logout()
    }
}

private extension String {
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }
}
