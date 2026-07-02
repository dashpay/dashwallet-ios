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
    private var direction: SwapDirection = .sell
    private weak var navigationController: UINavigationController?

    init(swapProvider: SwapProvider) {
        self.swapProvider = swapProvider
    }

    func start(in navigationController: UINavigationController?, direction: SwapDirection = .sell) {
        self.navigationController = navigationController
        self.direction = direction

        if direction == .buy, !(swapProvider is SwapKitSwapProvider) {
            DSLogger.log("Swap flow: Buy requires SwapKit backend; got \(swapProvider.displayName)")
            assertionFailure("Buy flow requires SwapKit backend")
            return
        }

        let selectCoinVC = SelectCoinHostingController(swapProvider: swapProvider, direction: direction)
        selectCoinVC.onCoinSelected = { [weak self] coin in
            guard let self else { return }
            DSLogger.log("Maya: Selected coin \(coin.code) (\(coin.name)) direction=\(self.direction)")
            switch self.direction {
            case .sell:
                self.navigateToEnterAddress(for: coin)
            case .buy:
                self.navigateToBuyEnterAmount(for: coin)
            }
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

    private func navigateToBuyEnterAmount(for coin: MayaCryptoCurrency) {
        guard !(navigationController?.topViewController is BuyEnterAmountHostingController) else { return }
        guard swapProvider is SwapKitSwapProvider else {
            DSLogger.log("Swap flow: Buy requires SwapKit backend; got \(swapProvider.displayName)")
            assertionFailure("Buy flow requires SwapKit backend")
            return
        }

        let buyEnterAmountVC = BuyEnterAmountHostingController(coin: coin, swapProvider: swapProvider)
        buyEnterAmountVC.onContinue = { [weak self] coin, sellAmount in
            self?.navigateToRefundAddress(coin: coin, sellAmount: sellAmount)
        }
        navigationController?.pushViewController(buyEnterAmountVC, animated: true)
    }

    private func navigateToRefundAddress(coin: MayaCryptoCurrency, sellAmount: String) {
        let refundVC = RefundAddressHostingController(coin: coin)
        refundVC.onRefundAddressConfirmed = { [weak self] coin, refundAddress in
            self?.navigateToReceive(coin: coin, sellAmount: sellAmount, refundAddress: refundAddress)
        }
        navigationController?.pushViewController(refundVC, animated: true)
    }

    private func navigateToReceive(coin: MayaCryptoCurrency, sellAmount: String, refundAddress: String) {
        DSLogger.log("Swap: Buy receive \(coin.code) amount=\(sellAmount) refund=\(refundAddress)")
        guard let swapKitProvider = swapProvider as? SwapKitSwapProvider else {
            DSLogger.log("Swap flow: Buy receive requires SwapKit backend")
            assertionFailure("Buy flow requires SwapKit backend")
            return
        }

        let receiveVC = BuyReceiveHostingController(
            coin: coin,
            refundAddress: refundAddress,
            sellAmount: sellAmount,
            swapProvider: swapKitProvider
        )
        navigationController?.pushViewController(receiveVC, animated: true)
    }
}
