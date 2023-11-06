//
//  Created by PT
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


// MARK: - ReceiveViewControllerDelegate

@objc(DWReceiveViewControllerDelegate)
protocol ReceiveViewControllerDelegate: AnyObject {
    func importPrivateKeyButtonAction(_ controller: ReceiveViewController)
}

// MARK: - ReceiveViewController

@objc(DWReceiveViewController)
class ReceiveViewController: BaseViewController {
    var model: DWReceiveModelProtocol!

    @objc
    weak var delegate: ReceiveViewControllerDelegate?

    @objc
    var allowedToImportPrivateKey = true

    @objc
    init(model: DWReceiveModelProtocol) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @objc
    func importPrivateKeyButtonAction() {
        let controller = sb("ImportWalletInfo").instantiateInitialViewController() as! DWImportWalletInfoViewController
        controller.delegate = self

        let nvc = BaseNavigationController(rootViewController: controller)
        present(nvc, animated: true)

        nvc.setCancelButtonHidden(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }
}

extension ReceiveViewController {
    private func configureHierarchy() {
        let mainStackView = UIStackView()
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.axis = .vertical
        mainStackView.spacing = stackSpacing
        view.addSubview(mainStackView)

        let receiveContentView = ReceiveContentView.view(with: model)
        receiveContentView.specifyAmountHandler = { [weak self] in
            guard let self else { return }

            let vc = SpecifyAmountViewController.controller()
            vc.delegate = self
            self.navigationController?.pushViewController(vc, animated: true)
        }
        receiveContentView.shareHandler = { [weak self] sender in
            guard let self else { return }
            self.dw_shareReceiveInfo(self.model, sender: sender)
        }

        receiveContentView.backgroundColor = .dw_background()
        receiveContentView.layer.cornerRadius = radius
        mainStackView.addArrangedSubview(receiveContentView)

        let importPrivateKeyButton = UIButton(type: .custom)
        importPrivateKeyButton.addTarget(self, action: #selector(importPrivateKeyButtonAction), for: .touchUpInside)
        importPrivateKeyButton.backgroundColor = .dw_background()
        importPrivateKeyButton.contentHorizontalAlignment = .leading
        importPrivateKeyButton.imageEdgeInsets = .init(top: 0, left: 17, bottom: 0, right: 0)
        importPrivateKeyButton.titleEdgeInsets = .init(top: 0, left: 39, bottom: 0, right: 0)
        importPrivateKeyButton.layer.cornerRadius = radius
        importPrivateKeyButton.setImage(UIImage(named: "import-icon"), for: .normal)
        importPrivateKeyButton.titleLabel?.font = .dw_font(forTextStyle: .subheadline)
        importPrivateKeyButton.setTitleColor(.dw_label(), for: .normal)
        importPrivateKeyButton.setTitle(NSLocalizedString("Import Private Key", comment: "Import Private Key"), for: .normal)
        importPrivateKeyButton.isHidden = !allowedToImportPrivateKey
        mainStackView.addArrangedSubview(importPrivateKeyButton)

        mainStackView.addArrangedSubview(EmptyView())
        
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: view.topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            importPrivateKeyButton.heightAnchor.constraint(equalToConstant: 64)
        ])
    }
}

// MARK: SpecifyAmountViewControllerDelegate

extension ReceiveViewController: SpecifyAmountViewControllerDelegate {
    func specifyAmountViewController(_ vc: SpecifyAmountViewController, didInput amount: UInt64) {
        let model = DWReceiveModel(amount: amount)

        let requestController = DWRequestAmountViewController(model: model)
        requestController.delegate = self
        present(requestController, animated: true)
    }
}

// MARK: DWRequestAmountViewControllerDelegate

extension ReceiveViewController: DWRequestAmountViewControllerDelegate {
    func requestAmountViewController(_ controller: DWRequestAmountViewController, didReceiveAmountWithInfo info: String) {
        controller.dismiss(animated: true) {
            self.navigationController?.popViewController(animated: true)

            let popAnimationDuration = 300
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(popAnimationDuration)) {
                self.navigationController?.view.dw_showInfoHUD(withText: info)
            }
        }
    }
}

// MARK: DWImportWalletInfoViewControllerDelegate

extension ReceiveViewController: DWImportWalletInfoViewControllerDelegate {
    func importWalletInfoViewControllerScanPrivateKeyAction(_ controller: DWImportWalletInfoViewController) {
        controller.dismiss(animated: true) {
            self.delegate?.importPrivateKeyButtonAction(self)
        }
    }
}
