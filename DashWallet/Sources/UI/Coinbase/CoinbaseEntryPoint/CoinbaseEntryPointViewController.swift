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

final class CoinbaseEntryPointViewController: BaseViewController {
    @IBOutlet var connectionStatusView: UIView!
    @IBOutlet var connectionStatusLabel: UILabel!
    @IBOutlet var balanceTitleLabel: UILabel!
    @IBOutlet var balanceView: BalanceView!
    @IBOutlet var tableView: UITableView!
    @IBOutlet var signOutButton: UIButton!
    @IBOutlet var networkUnavailableView: UIView!
    @IBOutlet var mainContentView: UIView!
    @IBOutlet var lastKnownBalanceLabel: UILabel!
    
    private let model = CoinbaseEntryPointModel()
    
    @IBAction func signOutAction() {
        model.signOut()
        navigationController?.popToRootViewController(animated: true)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
    }
    
    class func controller() -> CoinbaseEntryPointViewController {
        return vc(CoinbaseEntryPointViewController.self, from: sb("Coinbase"))
    }
}

extension CoinbaseEntryPointViewController {
    private func configureModel() {
        model.networkStatusDidChange = { [weak self] status in
            self?.reloadView()
        }
    }
    
    private func reloadView() {
        let isOnline = model.networkStatus == .online
        lastKnownBalanceLabel.isHidden = isOnline
        networkUnavailableView.isHidden = isOnline
        mainContentView.isHidden = !isOnline
        connectionStatusView.backgroundColor = isOnline ? .systemGreen : .systemRed
        connectionStatusLabel.text = isOnline ? NSLocalizedString("Connected", comment: "Coinbase Entry Point") : NSLocalizedString("Disconnected", comment: "Coinbase Entry Point")
        balanceView.balance = model.balance
    }
    
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()
        
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never
        
        lastKnownBalanceLabel.text = NSLocalizedString("Last known balance", comment: "Coinbase Entry Point")
        lastKnownBalanceLabel.isHidden = true
        networkUnavailableView.isHidden = true
        
        connectionStatusView.layer.cornerRadius = 2
        
        balanceTitleLabel.text = NSLocalizedString("Dash balance on Coinbase", comment: "Coinbase Entry Point")

        balanceView.dashSymbolColor = .dw_dashBlue()
        
        tableView.isScrollEnabled = false
        tableView.layer.cornerRadius = 10
        tableView.clipsToBounds = true
        tableView.backgroundColor = .white
        
        signOutButton.backgroundColor = .white
        signOutButton.titleLabel?.font = UIFont.dw_font(forTextStyle: .body).withWeight(UIFont.Weight.medium.rawValue)
        signOutButton.layer.cornerRadius = 10
        signOutButton.setTitle(NSLocalizedString("Disconnect Coinbase Account", comment: "Coinbase Entry Point"), for: .normal)
        
        reloadView()
    }
}

extension CoinbaseEntryPointViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return model.items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath) as! ItemCell
        cell.update(with: model.items[indexPath.item])
        cell.separatorInset = .init(top: 0, left: indexPath.item == (model.items.count - 1) ? 2000 : 63, bottom: 0, right: 0)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 62.0
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let item = model.items[indexPath.item]
        
        if item == .sellDash {
            let vc = FailedOperationStatusViewController.initiate(from: storyboard!)
            vc.headerText = NSLocalizedString("Transfer Failed", comment: "Coinbase")
            vc.descriptionText = NSLocalizedString("There was a problem transferring it to Dash Wallet on this device", comment: "Coinbase")
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
            return
        }
        
        if item == .buyDash {
            let vc = SuccessfulOperationStatusViewController.initiate(from: storyboard!)
            vc.headerText = NSLocalizedString("Transfer successful", comment: "Coinbase")
            vc.descriptionText = NSLocalizedString("It could take up to 10 minutes to transfer Dash from Coinbase to Dash Wallet on this device", comment: "Coinbase")
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
            return
        }
        
        let vc = TransferAmountViewController()
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }
}

final class ItemCell: UITableViewCell {
    @IBOutlet var iconView: UIImageView!
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var secondaryLabel: UILabel!
    
    fileprivate func update(with item: CoinbaseEntryPointItem) {
        iconView.image = .init(named: item.icon)
        nameLabel.text = item.title
        secondaryLabel.text = item.description
    }
}
