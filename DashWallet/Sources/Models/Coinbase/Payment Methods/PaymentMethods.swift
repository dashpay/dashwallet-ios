//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

import Foundation

actor PaymentMethods {
    var methods: [CoinbasePaymentMethod]!

    private weak var authInterop: CBAuthInterop?

    init(authInterop: CBAuthInterop) {
        self.authInterop = authInterop
    }

    public func fetchPaymentMethods() async throws -> [CoinbasePaymentMethod] {
        guard let methods, !methods.isEmpty else {
            let result: BaseDataCollectionResponse<CoinbasePaymentMethod> = try await CoinbaseAPI.shared.request(.activePaymentMethods)
            methods = result.data
            return methods!
        }

        return methods
    }
}
