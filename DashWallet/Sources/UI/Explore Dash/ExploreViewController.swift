//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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
import SwiftUI

private let kMerchantTypesShown = "merchantTypesInfoDialogShownKey"
private let kExploreHeaderViewHeight: CGFloat = 351.0

// MARK: - DWExploreTestnetViewControllerDelegate

@objc(DWExploreViewControllerDelegate)
protocol ExploreViewControllerDelegate: AnyObject {
    func exploreTestnetViewControllerShowSendPayment(_ controller: ExploreViewController)
    func exploreTestnetViewControllerShowReceivePayment(_ controller: ExploreViewController)
}

// MARK: - DWExploreTestnetViewController

@objc(DWExploreViewController)
class ExploreViewController: UIViewController, NavigationFullscreenable {
    
    @objc weak var delegate: ExploreViewControllerDelegate?
    
    var requiresNoNavigationBar: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .dw_darkBlue()
        setupLayout()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - Layout Setup
    
    private func setupLayout() {
        let headerView = ExploreHeaderView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.image = UIImage(named: "image.explore.dash.wallet")
        headerView.title = NSLocalizedString("Explore Dash", comment: "")
        headerView.subtitle = NSLocalizedString("Find merchants that accept Dash, where to buy it and how to earn income with it.", comment: "")
        
        headerView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        
        let contentsView = ExploreContentsView()
        contentsView.translatesAutoresizingMaskIntoConstraints = false
        headerView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        
        contentsView.getTestDashHandler = { [weak self] in
            self?.getTestDashAction()
        }
        
        contentsView.whereToSpendHandler = { [weak self] in
            self?.showWhereToSpendViewController()
        }
        contentsView.atmHandler = { [weak self] in
            self?.showAtms()
        }
        contentsView.stakingHandler = { [weak self] in
            self?.showStakingIfSynced()
        }
        
        let parentView = UIStackView()
        parentView.translatesAutoresizingMaskIntoConstraints = false
        parentView.distribution = .equalSpacing
        parentView.axis = .vertical
        parentView.spacing = 34
        
        parentView.addArrangedSubview(headerView)
        parentView.addArrangedSubview(contentsView)
        view.addSubview(parentView)
        
        NSLayoutConstraint.activate([
            headerView.heightAnchor.constraint(lessThanOrEqualToConstant: kExploreHeaderViewHeight),
            parentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            parentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            parentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            parentView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    // MARK: - Actions
    
    private func getTestDashAction() {
        let account = DWEnvironment.sharedInstance().currentAccount
        
        if let paymentAddress = account.receiveAddress {
            UIPasteboard.general.string = paymentAddress
        }
        
        if let url = URL(string: "http://faucet.testnet.networks.dash.org/") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    private func showAtms() {
        let vc = AtmListViewController()
        vc.payWithDashHandler = { [weak self] in
            guard let self = self else { return }
            self.delegate?.exploreTestnetViewControllerShowReceivePayment(self)
        }
        vc.sellDashHandler = { [weak self] in
            guard let self = self else { return }
            self.delegate?.exploreTestnetViewControllerShowSendPayment(self)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func showStakingIfSynced() {
        if SyncingActivityMonitor.shared.state == .syncDone {
            let vc = CrowdNodeModelObjcWrapper.getRootVC()
            navigationController?.pushViewController(vc, animated: true)
        } else {
            notifyChainSyncing()
        }
    }
    
    private func notifyChainSyncing() {
        let title = NSLocalizedString("The chain is syncing…", comment: "")
        let message = NSLocalizedString("Wait until the chain is fully synced, so we can review your transaction history. Visit CrowdNode website to log in or sign up.", comment: "")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        let websiteAction = UIAlertAction(
            title: NSLocalizedString("Go to CrowdNode website", comment: ""),
            style: .default
        ) { _ in
            UIApplication.shared.open(CrowdNodeObjcWrapper.crowdNodeWebsiteUrl(), options: [:], completionHandler: nil)
        }
        alert.addAction(websiteAction)
        
        let closeAction = UIAlertAction(
            title: NSLocalizedString("Close", comment: ""),
            style: .cancel,
            handler: nil
        )
        alert.addAction(closeAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: - Where to Spend
    
    private func showWhereToSpendViewController() {
        if UserDefaults.standard.bool(forKey: kMerchantTypesShown) != true {
            let hostingController = UIHostingController(rootView: MerchantTypesDialog { [weak self] in
                UserDefaults.standard.setValue(true, forKey: kMerchantTypesShown)
                self?.showMerchants()
            })
            hostingController.setDetent(640)
            present(hostingController, animated: true)
        } else {
            showMerchants()
        }
    }
    
    private func showMerchants() {
        let vc = MerchantListViewController()
        vc.payWithDashHandler = { [weak self] in
            guard let self = self else { return }
            self.delegate?.exploreTestnetViewControllerShowSendPayment(self)
        }
        
        navigationController?.pushViewController(vc, animated: true)
    }
}
