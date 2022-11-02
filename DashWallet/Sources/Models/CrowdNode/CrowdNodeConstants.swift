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

enum CrowdNodeConstants {
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

    static var minimumRequiredDash = UInt64(1_000_000)
    static var requiredForSignup = minimumRequiredDash - UInt64(100_000)
    static var requiredForAcceptTerms = UInt64(100_000)
    static var apiOffset = UInt64(20000)
}
