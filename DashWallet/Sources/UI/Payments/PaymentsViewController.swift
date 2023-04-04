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

@objc(DWPaymentsViewControllerIndex)
enum PaymentsViewControllerState: Int {
    @objc(DWPaymentsViewControllerIndex_None)
    case none = -1
    
    @objc(DWPaymentsViewControllerIndex_Receive)
    case receive = 0
    
    @objc(DWPaymentsViewControllerIndex_Pay)
    case pay = 1
}

@objc(DWPaymentsViewControllerDelegate)
protocol PaymentsViewControllerDelegate: AnyObject {
    func paymentsViewControllerDidCancel(_ controller: PaymentsViewController)
    func paymentsViewControllerDidFinishPayment(_ controller: PaymentController, contact: DWDPBasicUserItem?)
}

@objc(DWPaymentsViewController)
class PaymentsViewController: UIViewController {
    @IBOutlet var segmentedControl: UISegmentedControl!
    @IBOutlet var containerView: UIView!
    
    @objc
    weak var delegate: PaymentsViewControllerDelegate?
    
    @objc
    var demoMode: Bool = false
    
    @objc
    weak var demoDelegate: DWDemoDelegate?
    
    @objc
    var currentState: PaymentsViewControllerState = .pay {
        didSet {
            pageController?.selectedIndex = currentState.rawValue
        }
    }
    
    private var receiveModel: DWReceiveModelProtocol!
    private var payModel: DWPayModelProtocol!
    private var dataProvider: DWTransactionListDataProviderProtocol?
    
    private var payViewController: PayViewController!
    private var receiveViewController: DWReceiveViewController!
    
    private var pageController: SendReceivePageController!
    
    @IBAction func segmentedControlAction() {
        let idx = segmentedControl.selectedSegmentIndex
        pageController.setSelectedIndex(idx, animated: true)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
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
        
        payViewController = PayViewController.controller(with: payModel)
        
        receiveViewController = DWReceiveViewController()
        receiveViewController.model = receiveModel
        
        pageController = SendReceivePageController()
        pageController.helperDelegate = self
        addChild(pageController)
        pageController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(pageController.view)
        pageController.didMove(toParent: self)
        pageController.controllers = [receiveViewController, payViewController]
        pageController.selectedIndex = currentState.rawValue
        
        NSLayoutConstraint.activate([
            pageController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            pageController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            pageController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
    }
}

extension PaymentsViewController: NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }
}

extension PaymentsViewController: SendReceivePageControllerDelegate {
    func sendReceivePageControllerWillChangeSelectedIndex(to index: Int) {
        segmentedControl.selectedSegmentIndex = index
    }
}
