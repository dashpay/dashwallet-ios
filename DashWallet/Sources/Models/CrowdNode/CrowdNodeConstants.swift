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

struct CrowdNodeConstants {
    private static let CrowdNodeTestNetAddress = "yMY5bqWcknGy5xYBHSsh2xvHZiJsRucjuy"
    private static let CrowdNodeMainNetAddress = "XjbaGWaGnvEtuQAUoBgDxJWe8ZNv45upG2"
    
    static var CrowdNodeAddress: String {
        get {
            if (DWEnvironment.sharedInstance().currentChain.isMainnet()) {
                return CrowdNodeMainNetAddress
            } else {
                return CrowdNodeTestNetAddress
            }
        }
    }
    
    static var MinimumRequiredDash = UInt64(1000000)
    static var RequiredForSignup = MinimumRequiredDash -  UInt64(100000)
    static var ApiOffset = UInt64(20000)
    static var SignUp = ApiOffset + UInt64(131072)
}
