//  
//  Created by Andrei Ashikhmin
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

class CrowdNodeModel {
    private let crowdNode = CrowdNode()
    @Published var outputMessage: String = ""
    @Published var isLoading: Bool = false
    
    @MainActor
    func signUp() {
        Task.init {
            defer { isLoading = false }
            
            if let accountAddress = DWEnvironment.sharedInstance().currentAccount.receiveAddress {
                print("CrowdNode account address: \(accountAddress)")
                outputMessage = accountAddress
                
                do {
                    let success = await DSAuthenticationManager.sharedInstance().authenticate(withPrompt: NSLocalizedString("Sign up to CrowdNode", comment: ""), usingBiometricAuthentication: false, alertIfLockout: false).0
            
                    if (success) {
                        isLoading = true
                        try await crowdNode.signUp(accountAddress: accountAddress)
                    }
                } catch {
                    outputMessage = error.localizedDescription
                }
            }
        }
    }
}
