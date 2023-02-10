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

final class CustodialSwapsViewController: CoinbaseAmountViewController {

    override var actionButtonTitle: String? {
        NSLocalizedString("Get Quote", comment: "Coinbase/Convert Crypto")
    }

    private var custodialSwapsModel: CustodialSwapsModel { model as! CustodialSwapsModel }
    private var converterView: ConverterView!

    init() {
        super.init(model: CustodialSwapsModel())
    }

    override func actionButtonAction(sender: UIView) {
        showActivityIndicator()
        custodialSwapsModel.convert()
    }

    // MARK: Life cycle
    override func configureModel() {
        super.configureModel()

        custodialSwapsModel.delegate = self
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        view.backgroundColor = .dw_secondaryBackground()

        navigationItem.title = NSLocalizedString("Convert Crypto", comment: "Coinbase")
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.alignment = .fill
        contentView.addSubview(stackView)

        // Move amount view into stack view
        stackView.addArrangedSubview(amountView)

        converterView = ConverterView(frame: .zero)
        converterView.translatesAutoresizingMaskIntoConstraints = false
        converterView.delegate = self
        converterView.dataSource = model as? ConverterViewDataSource
        converterView.isChevronHidden = false
        converterView.isSwappingAllowed = false
        stackView.addArrangedSubview(converterView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
        ])

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

// MARK: ConverterViewDelegate

extension CustodialSwapsViewController: ConverterViewDelegate {
    func didChangeDirection() {
        // NOP
    }

    func didTapOnFromView() {
        let vc = AccountListController.controller()
        vc.selectHandler = { [weak self] account in
            guard let self else { return }
            self.custodialSwapsModel.selectedAccount = account
            self.reloadView()
            self.converterView.reloadView()
            self.amountView.inputTypeSwitcher.reloadData()
            self.amountView.amountInputControl.reloadData()
            self.actionButton?.isEnabled = self.model.isAllowedToContinue
            self.dismiss(animated: true)
        }

        let nvc = BaseNavigationController(rootViewController: vc)
        present(nvc, animated: true)
    }
}
