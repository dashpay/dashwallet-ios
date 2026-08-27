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
}

// MARK: - ReceiveViewController

@objc(DWReceiveViewController)
class ReceiveViewController: BaseViewController {
    var model: DWReceiveModelProtocol!

    @objc
    weak var delegate: ReceiveViewControllerDelegate?

    @objc
    init(model: DWReceiveModelProtocol) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
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

        mainStackView.addArrangedSubview(EmptyUIView())

        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: view.topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
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

