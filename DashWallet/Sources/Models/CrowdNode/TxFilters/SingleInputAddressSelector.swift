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

/// Call-site seam for CrowdNode's selected-input signal sends: the SDK send
/// path (`SwiftDashSDKTransactionSender.buildAndSignFromAddress`) funds the
/// transaction from this address's UTXO pool and returns change to it.
public final class SingleInputAddressSelector {
    let address: String

    init(address: String) {
        self.address = address
    }
}
