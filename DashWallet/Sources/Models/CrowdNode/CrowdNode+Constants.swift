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

extension CrowdNode {
    private static let crowdNodeTestNetAddress = "yMY5bqWcknGy5xYBHSsh2xvHZiJsRucjuy"
    private static let crowdNodeMainNetAddress = "XjbaGWaGnvEtuQAUoBgDxJWe8ZNv45upG2"

    static var crowdNodeAddress: String {
        if DWEnvironment.sharedInstance().currentChain.isMainnet() {
            return crowdNodeMainNetAddress
        }
        else {
            return crowdNodeTestNetAddress
        }
    }

    static let minimumRequiredDash: UInt64 = 1_000_000
    static let requiredForSignup = minimumRequiredDash - 100_000
    static let requiredForAcceptTerms: UInt64 = 100_000
    static let apiOffset: UInt64 = 20000
    static let minimumDeposit = UInt64(kOneDash / 2)
    static let minimumLeftoverBalance: UInt64 = 30_000
    static let apiConfirmationDashAmount: UInt64 = 54321

    static let notificationID = "CrowdNode"

    private static let mainnetBaseUrl = "https://app.crowdnode.io/"
    private static let testnetBaseUrl = "https://test.crowdnode.io/"

    static var baseUrl: String {
        if DWEnvironment.sharedInstance().currentChain.isMainnet() {
            return mainnetBaseUrl
        }
        else {
            return testnetBaseUrl
        }
    }

    static var fundsOpenUrl: String { baseUrl + "FundsOpen/" }
    static var apiLinkUrl: String { baseUrl + "APILink/" }
    static var profileUrl: String { baseUrl + "Profile" }

    private static let mainnetLoginUrl = "https://login.crowdnode.io"
    private static let testnetLoginUrl = "https://logintest.crowdnode.io"

    static var loginUrl: String {
        if DWEnvironment.sharedInstance().currentChain.isMainnet() {
            return mainnetLoginUrl
        }
        else {
            return testnetLoginUrl
        }
    }

    static let websiteUrl = "https://crowdnode.io/"
    static let termsOfUseUrl = "https://crowdnode.io/terms/"
    static let privacyPolicyUrl = "https://crowdnode.io/privacy/"
    static let supportUrl = "https://knowledge.crowdnode.io/"
    static let withdrawalLimitsUrl = "https://knowledge.crowdnode.io/en/articles/6387601-api-withdrawal-limits"
    static let howToVerifyUrl = "https://knowledge.crowdnode.io/en/articles/6114502-how-to-confirm-your-api-dash-address"
}
