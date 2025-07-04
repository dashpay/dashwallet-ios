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

protocol DashSpendRepository: ObservableObject {
    var isUserSignedIn: Bool { get }
    var isUserSignedInPublisher: AnyPublisher<Bool, Never> { get }
    var userEmailPublisher: AnyPublisher<String?, Never> { get }
    
    func signUp(email: String) async throws -> Bool
    func login(email: String) async throws -> Bool
    func verifyEmail(code: String) async throws -> Bool
    func logout()
}
