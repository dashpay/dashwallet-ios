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

enum CrowdNodeError: Error {
    case signUp
    case deposit
    case withdraw
    
    public var description: String {
        switch self {
        case .signUp:
            return NSLocalizedString("We couldn’t create your CrowdNode account.", comment: "")
        case .deposit:
            return NSLocalizedString("We couldn’t make a deposit to your CrowdNode account.", comment: "")
        case .withdraw:
            return NSLocalizedString("We couldn’t withdraw from your CrowdNode account.", comment: "")
        }
    }
}
