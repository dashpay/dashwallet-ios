//
//  Created by tkhp
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

import UIKit

// MARK: - PaymentMethodsController

final class PaymentMethodsController: BaseViewController {
    @IBOutlet var tableView: UITableView!

    public var paymentMethods: [CoinbasePaymentMethod] = []
    public var selectedPaymentMethod: CoinbasePaymentMethod?
    public var selectPaymentMethodAction: ((CoinbasePaymentMethod) -> Void)?

    private let modalTransition = DWModalTransition()
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        configurePresentation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configurePresentation()
    }

    @IBAction
    func closeAction() {
        dismiss(animated: true)
    }

    private func configurePresentation() {
        modalPresentationStyle = .custom

        modalTransition.modalPresentationControllerDelegate = self
        transitioningDelegate = modalTransition
    }

    private func configureHierarchy() {
        view.layer.cornerRadius = 15
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        tableView.rowHeight = 62
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }

    class func controller() -> PaymentMethodsController {
        vc(PaymentMethodsController.self, from: sb("Coinbase"))
    }
}

// MARK: UITableViewDelegate, UITableViewDataSource

extension PaymentMethodsController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        paymentMethods.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let paymentMethod = paymentMethods[indexPath.row]

        let cell = tableView.dequeueReusableCell(withIdentifier: PaymentMethodCell.reuseIdentifier, for: indexPath) as! PaymentMethodCell
        cell.update(with: paymentMethod)
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let method = paymentMethods[indexPath.row]

        DispatchQueue.main.async {
            self.selectPaymentMethodAction?(method)
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let method = paymentMethods[indexPath.row]

        if method == selectedPaymentMethod {
            tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        }
    }
}

// MARK: DWModalPresentationControllerDelegate

extension PaymentMethodsController: DWModalPresentationControllerDelegate {
    func contentViewHeight() -> CGFloat {
        CGFloat(paymentMethods.count*62 + 54) + view.safeAreaInsets.bottom
    }
}

