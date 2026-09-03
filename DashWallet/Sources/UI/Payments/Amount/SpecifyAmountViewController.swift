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

import DashUIKit
import SwiftUI
import UIKit

// MARK: - SpecifyAmountViewControllerDelegate

@objc(DWSpecifyAmountViewControllerDelegate)
protocol SpecifyAmountViewControllerDelegate: AnyObject {
    func specifyAmountViewController(_ vc: SpecifyAmountViewController, didInput amount: UInt64)
}

// MARK: - SpecifyAmountViewController

@objc(DWSpecifyAmountViewController)
final class SpecifyAmountViewController: ActionButtonViewController {
    @objc weak var delegate: SpecifyAmountViewControllerDelegate?

    override var showsActionButton: Bool { false }

    private let amountModel: BaseAmountModel

    init(model: BaseAmountModel) {
        self.amountModel = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "PrimaryBackground", in: .dashUIKit, compatibleWith: .current)
        configureHierarchy()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    @objc
    static func controller() -> SpecifyAmountViewController {
        SpecifyAmountViewController(model: BaseAmountModel())
    }

    private func configureHierarchy() {
        let rootView = SpecifyAmountView(
            model: amountModel,
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onReceive: { [weak self] in
                guard let self else { return }
                self.delegate?.specifyAmountViewController(self, didInput: UInt64(self.amountModel.amount.plainAmount))
            },
            onCurrencyTap: { [weak self] in
                self?.showCurrencyList()
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = UIColor(named: "PrimaryBackground", in: .dashUIKit, compatibleWith: .current)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        setupContentView(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    private func showCurrencyList() {
        let currencyController = DWLocalCurrencyViewController(
            navigationAppearance: .white,
            presentationMode: .dialog,
            currencyCode: amountModel.localCurrencyCode
        )
        currencyController.isGlobal = false
        currencyController.delegate = self
        let navigationController = BaseNavigationController(rootViewController: currencyController)
        present(navigationController, animated: true)
    }
}

extension SpecifyAmountViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }

    var isNavigationBarHidden: Bool { true }
}

// MARK: - DWLocalCurrencyViewControllerDelegate

extension SpecifyAmountViewController: DWLocalCurrencyViewControllerDelegate {
    func localCurrencyViewController(_ controller: DWLocalCurrencyViewController, didSelectCurrency currencyCode: String) {
        amountModel.setupCurrencyCode(currencyCode)
        controller.dismiss(animated: true)
    }

    func localCurrencyViewControllerDidCancel(_ controller: DWLocalCurrencyViewController) {
        controller.dismiss(animated: true)
    }
}
