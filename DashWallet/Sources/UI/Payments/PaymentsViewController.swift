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

// MARK: - PaymentsViewControllerState

@objc(DWPaymentsViewControllerIndex)
enum PaymentsViewControllerState: Int {
    @objc(DWPaymentsViewControllerIndex_None)
    case none = -1

    @objc(DWPaymentsViewControllerIndex_Receive)
    case receive = 0

    @objc(DWPaymentsViewControllerIndex_Pay)
    case pay = 1
}

// MARK: - PaymentsViewControllerDelegate

@objc(DWPaymentsViewControllerDelegate)
protocol PaymentsViewControllerDelegate: AnyObject {
    func paymentsViewControllerWantsToImportPrivateKey(_ controller: PaymentsViewController)
    func paymentsViewControllerDidCancel(_ controller: PaymentsViewController)
    func paymentsViewControllerDidFinishPayment(_ controller: PaymentsViewController, contact: DWDPBasicUserItem?)
}

// MARK: - PaymentsViewController

@objc(DWPaymentsViewController)
class PaymentsViewController: BaseViewController {
    @IBOutlet var segmentedControl: UISegmentedControl!
    @IBOutlet var containerView: UIView!
    @IBOutlet var closeButton: UIButton!

    @objc
    weak var delegate: PaymentsViewControllerDelegate?

    @objc
    var demoMode = false

    @objc
    weak var demoDelegate: DWDemoDelegate?

    @objc
    var currentState: PaymentsViewControllerState = .pay {
        didSet {
            if currentState == .none {
                currentState = PaymentsViewControllerState(rawValue: DWGlobalOptions.sharedInstance().paymentsScreenCurrentTab)!
            }

            let idx = currentState.rawValue

            segmentedControl?.selectedSegmentIndex = idx
            pageController?.selectedIndex = idx
        }
    }

    private var receiveModel: DWReceiveModelProtocol!
    private var payModel: DWPayModelProtocol!
    private var dataProvider: DWTransactionListDataProviderProtocol?

    private var payViewController: PayViewController!
    private var receiveViewController: ReceiveViewController!

    private var pageController: SendReceivePageController!

    @IBAction
    func segmentedControlAction() {
        let idx = segmentedControl.selectedSegmentIndex
        pageController.setSelectedIndex(idx, animated: true)

        DWGlobalOptions.sharedInstance().paymentsScreenCurrentTab = idx
    }

    @IBAction
    func closeButtonAction() {
        delegate?.paymentsViewControllerDidCancel(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    @objc
    class func controller(withReceiveModel receiveModel: DWReceiveModelProtocol?,
                          payModel: DWPayModelProtocol?,
                          dataProvider: DWTransactionListDataProviderProtocol?) -> PaymentsViewController {
        let controller = sb("Payments").vc(PaymentsViewController.self)
        controller.receiveModel = receiveModel
        controller.payModel = payModel
        controller.dataProvider = dataProvider
        return controller
    }
}

extension PaymentsViewController {
    func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        segmentedControl.setTitle(NSLocalizedString("Receive", comment: "Receive/Send"), forSegmentAt: 0)
        segmentedControl.setTitle(NSLocalizedString("Send", comment: "Receive/Send"), forSegmentAt: 1)
        segmentedControl.selectedSegmentIndex = currentState.rawValue

        payViewController = PayViewController.controller(with: payModel)
        payViewController.delegate = self

        receiveViewController = ReceiveViewController(model: receiveModel)
        receiveViewController.delegate = self

        pageController = SendReceivePageController()
        pageController.helperDelegate = self
        addChild(pageController)
        pageController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(pageController.view)
        pageController.didMove(toParent: self)
        pageController.controllers = [receiveViewController, payViewController]
        pageController.selectedIndex = currentState.rawValue

        closeButton.layer.cornerRadius = 24

        NSLayoutConstraint.activate([
            pageController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            pageController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            pageController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
    }
}

// MARK: NavigationBarDisplayable

extension PaymentsViewController: NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }
}

// MARK: SendReceivePageControllerDelegate

extension PaymentsViewController: SendReceivePageControllerDelegate {
    func sendReceivePageControllerWillChangeSelectedIndex(to index: Int) {
        segmentedControl.selectedSegmentIndex = index

        DWGlobalOptions.sharedInstance().paymentsScreenCurrentTab = index
    }
}

// MARK: PayViewControllerDelegate

extension PaymentsViewController: PayViewControllerDelegate {
    func payViewControllerDidFinishPayment(_ controller: PayViewController, contact: DWDPBasicUserItem?) {
        delegate?.paymentsViewControllerDidFinishPayment(self, contact: contact)
    }
}

// MARK: ReceiveViewControllerDelegate

extension PaymentsViewController: ReceiveViewControllerDelegate {
    func receiveViewControllerExitButtonAction(_ controller: ReceiveViewController) {
        // NOP
    }

    func importPrivateKeyButtonAction(_ controller: ReceiveViewController) {
        delegate?.paymentsViewControllerWantsToImportPrivateKey(self)
    }
}
