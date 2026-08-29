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

import UIKit

// MARK: - PayViewControllerDelegate

protocol PayViewControllerDelegate: AnyObject {
    /// `txidWire` is the broadcast transaction's wire-order txid (`Transaction.txHashData` convention).
    func payViewControllerDidFinishPayment(_ controller: PayViewController, txidWire: Data)
}

// MARK: - PayViewController

class PayViewController: BaseViewController, PayableViewController {
    @IBOutlet weak var tableView: UITableView!

    var paymentController: PaymentController!

    var payModel: DWPayModelProtocol!
    

    var maxActionButtonWidth: CGFloat = 0

    var demoMode = false

    var delegate: PayViewControllerDelegate?

    // MARK: Actions

    public func showEnterAddressController(animated: Bool = true) {
        let vc = EnterAddressViewController()
        vc.delegate = self
        navigationController?.pushViewController(vc, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configurePaymentController()
        configureHierarchy()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.flashScrollIndicators()
        if demoMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.performPayToPasteboardAction()
            }
        }
    }

    static func controller(with payModel: DWPayModelProtocol) -> PayViewController {
        let storyboard = UIStoryboard(name: "Pay", bundle: nil)
        let controller = storyboard.instantiateInitialViewController() as! PayViewController
        controller.payModel = payModel

        return controller
    }
}

extension PayViewController {
    private func configurePaymentController() {
        paymentController = PaymentController()
        paymentController.delegate = self
        paymentController.presentationContextProvider = self
    }

    private func configureHierarchy() {
        let cellId = PayTableViewCell.reuseIdentifier
        let nib = UINib(nibName: cellId, bundle: nil)
        tableView.register(nib, forCellReuseIdentifier: cellId)
        tableView.rowHeight = 59
        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = EmptyUIView()
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 0.0, height: CGFloat.leastNormalMagnitude))
        tableView.isScrollEnabled = false
        tableView.separatorStyle = .none
        tableView.sectionHeaderHeight = CGFloat.leastNonzeroMagnitude
    }
}

// MARK: UITableViewDataSource, UITableViewDelegate

extension PayViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        payModel.options.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellId = PayTableViewCell.reuseIdentifier
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! PayTableViewCell
        let option = payModel.options[indexPath.row]
        cell.model = option
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let payOption = payModel.options[indexPath.row]

        switch payOption.type {
        case .scanQR:
            presentPaymentScanner { [weak self] paymentInput in
                self?.dismiss(animated: true) {
                    self?.paymentController.performPayment(with: paymentInput)
                }
            }
        case .pasteboard:
            showEnterAddressController()
        case .NFC:
            performNFCReadingAction()
    #if DASHPAY
        case .dashPayUser:
            performPayToDashPayUser()
    #endif
        @unknown default:
            break
        }
    }
}

// MARK: PaymentControllerDelegate, PaymentControllerPresentationContextProviding

extension PayViewController: PaymentControllerDelegate, PaymentControllerPresentationContextProviding {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        navigationController?.visibleViewController ?? self
    }

    func paymentControllerDidFinishTransaction(_ controller: PaymentController, txidWire: Data) {
        delegate?.payViewControllerDidFinishPayment(self, txidWire: txidWire)
    }

    func paymentControllerDidCancelTransaction(_ controller: PaymentController) { }

    func paymentControllerDidFailTransaction(_ controller: PaymentController) { }
}

// MARK: EnterAddressViewControllerDelegate

extension PayViewController: EnterAddressViewControllerDelegate {
    func enterAddressViewControllerDidPreparePaymentInput(_ viewController: EnterAddressViewController, input: DWPaymentInput) {
        processPaymentInput(input)
    }
}

