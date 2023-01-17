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

import UIKit

// MARK: - CustodialSwapsViewController

class CustodialSwapsViewController: TransferAmountViewController {

    override var actionButtonTitle: String? {
        NSLocalizedString("Get Quote", comment: "Coinbase/Convert Crypto")
    }

    private var custodialSwapsModel: CustodialSwapsModel { model as! CustodialSwapsModel }

    override func actionButtonAction(sender: UIView) {
        showActivityIndicator()
        custodialSwapsModel.convert()
    }

    override func didChangeDirection() { }

    override func didTapOnFromView() {
        let vc = AccountListController.controller()
        vc.selectHandler = { [weak self] account in
            self?.custodialSwapsModel.selectedAccount = account
            self?.reloadView()
            self?.converterView.reloadView()
            self?.amountView.inputTypeSwitcher.reloadData()
            self?.amountView.amountInputControl.reloadData()
        }

        let nvc = BaseNavigationController(rootViewController: vc)
        present(nvc, animated: true)
    }

    override func initializeModel() {
        model = CustodialSwapsModel()
    }

    override func configureModel() {
        super.configureModel()

        custodialSwapsModel.delegate = self
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        navigationItem.title = NSLocalizedString("Convert Crypto", comment: "Coinbase")

        converterView.isChevronHidden = false
        converterView.isSwappingAllowed = false

        // Hide all by default, except converter view
        amountView.isHidden = true
        keyboardContainer.isHidden = true
    }

    override func reloadView() {
        super.reloadView()

        amountView.isHidden = !custodialSwapsModel.hasAccount
        keyboardContainer.isHidden = !custodialSwapsModel.hasAccount
        buttonContainer.isHidden = !custodialSwapsModel.hasAccount
    }
}

// MARK: CustodialSwapsModelDelegate

extension CustodialSwapsViewController: CustodialSwapsModelDelegate {
    func custodialSwapsModelDidPlace(order: CoinbaseSwapeTrade) {
        guard let selectedAccount = custodialSwapsModel.selectedAccount else { return }

        let vc = ConvertCryptoOrderPreviewController(selectedAccount: selectedAccount,
                                                     plainAmount: UInt64(model.amount.plainAmount),
                                                     order: order)
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
        hideActivityIndicator()
    }
}
