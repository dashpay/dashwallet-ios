//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

enum UpholdError: LocalizedError {
    case dueDiligence
    case submitIdentity
    case proofOfAddress
    case unknown

    var errorDescription: String? {
        switch self {
        case .dueDiligence:
            String(localized: "Please go to your Uphold account to answer some questions about yourself.", comment: "Uphold")
        case .submitIdentity:
            String(localized: "Please go to your Uphold account to verify your identity.", comment: "Uphold")
        case .proofOfAddress:
            String(localized: "Please contact Uphold to update your proof of address.", comment: "Uphold")
        default:
            ""
        }
    }
    
    var failureReason: String? {
        String(localized: "Uphold error", comment: "Uphold")
    }
    
    var recoverySuggestion: String? {
        String(localized: "Go to Website", comment: "Uphold")
    }
    
    static func errorCodeToError(code: String) -> UpholdError {
        switch code {
        case "user-must-submit-enhanced-due-diligence":
            .dueDiligence
        case "user-must-submit-identity":
            .submitIdentity
        case "user-must-submit-proof-of-address":
            .proofOfAddress
        default:
            .unknown
        }
    }
}
