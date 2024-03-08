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

struct SupportedTopperPaymentMethods: Codable {
    let paymentMethods: [TopperPaymentMethod]
}

struct TopperPaymentMethod: Codable {
    let billingAsset: String
    let countries: [String]
    let limits: [PaymentMethodLimit]
    let network: String
    let type: String
}

struct PaymentMethodLimit: Codable {
    let asset: String
    let maximum: String
    let minimum: String
}
