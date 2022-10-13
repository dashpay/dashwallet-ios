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

enum ApiCode: UInt64 {
    case pleaseAcceptTerms = 2
    case welcomeToApi = 4
    case depositReceived = 8
    case withdrawalQueue = 16
    case withdrawalDenied = 32
    case withdrawAll = 1000
    case signUp = 131072
    case acceptTerms = 65536
    
    func maxCode() -> ApiCode {
        return ApiCode.signUp
    }
}
