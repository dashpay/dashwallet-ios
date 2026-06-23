//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import UIKit

final class SwapFlowCoordinator {
    private let swapProvider: SwapProvider
    private weak var navigationController: UINavigationController?

    init(swapProvider: SwapProvider) {
        self.swapProvider = swapProvider
    }

    func start(in navigationController: UINavigationController?) {
        self.navigationController = navigationController

        let selectCoinVC = SelectCoinHostingController(swapProvider: swapProvider)
        selectCoinVC.onCoinSelected = { [weak self] coin in
            DSLogger.log("Maya: Selected coin \(coin.code) (\(coin.name))")
            self?.navigateToEnterAddress(for: coin)
        }
        navigationController?.pushViewController(selectCoinVC, animated: true)
    }

    private func navigateToEnterAddress(for coin: MayaCryptoCurrency) {
        let enterAddressVC = EnterAddressHostingController(coin: coin, swapProvider: swapProvider)
        enterAddressVC.onAddressConfirmed = { [weak self] coin, address in
            self?.navigateToConvert(coin: coin, address: address)
        }
        navigationController?.pushViewController(enterAddressVC, animated: true)
    }

    private func navigateToConvert(coin: MayaCryptoCurrency, address: String) {
        guard !(navigationController?.topViewController is SwapConvertHostingController) else { return }
        let convertVC = SwapConvertHostingController(coin: coin, address: address, swapProvider: swapProvider)
        navigationController?.pushViewController(convertVC, animated: true)
    }
}
