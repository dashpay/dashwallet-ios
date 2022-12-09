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

// MARK: - CoinbaseEntryPointViewController

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

    private var isNeedToShowSignOutError = true

    @IBAction func signOutAction() {
        isNeedToShowSignOutError = false
        model.signOut()
    }

    private func popCoinbaseFlow() {
        if isNeedToShowSignOutError {
            showAlert(with: NSLocalizedString("Error", comment: ""),
                      message: NSLocalizedString("You were signed out from Coinbase, please sign in again", comment: "Sign out from coinbase due to error"),
                      presentingViewController: navigationController)
        }

        let portalVC = navigationController!.controller(by: PortalViewController.self)!
        navigationController!.popToViewController(portalVC, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureModel()
        configureHierarchy()
    }

    class func controller() -> CoinbaseEntryPointViewController {
        vc(CoinbaseEntryPointViewController.self, from: sb("Coinbase"))
    }
}

extension CoinbaseEntryPointViewController {
    private func configureModel() {
        model.userDidSignOut = { [weak self] in
            self?.popCoinbaseFlow()
        }
        model.userDidChange = { [weak self] in
            self?.reloadView()
        }
        model.networkStatusDidChange = { [weak self] _ in
            self?.reloadView()
        }
    }

    private func reloadView() {
        let isOnline = model.networkStatus == .online
        lastKnownBalanceLabel.isHidden = isOnline
        networkUnavailableView.isHidden = isOnline
        mainContentView.isHidden = !isOnline
        connectionStatusView.backgroundColor = isOnline ? .systemGreen : .systemRed
        connectionStatusLabel.text = isOnline
            ? NSLocalizedString("Connected", comment: "Coinbase Entry Point")
            : NSLocalizedString("Disconnected", comment: "Coinbase Entry Point")
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

// MARK: UITableViewDelegate, UITableViewDataSource

extension CoinbaseEntryPointViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath) as! ItemCell
        cell.update(with: model.items[indexPath.item])
        cell.separatorInset = .init(top: 0, left: indexPath.item == (model.items.count - 1) ? 2000 : 63, bottom: 0, right: 0)

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        62.0
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = model.items[indexPath.item]
        let vc: UIViewController

        switch item {
        case .buyDash:
            vc = BuyDashViewController()
        case .sellDash:
            vc = BuyDashViewController()
        case .convertCrypto:
            vc = TransferAmountViewController()
        case .transferDash:
            vc = TransferAmountViewController()
        }

        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - ItemCell

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
