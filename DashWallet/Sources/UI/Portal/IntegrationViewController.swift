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

// MARK: - IntegrationViewController

final class IntegrationViewController: BaseViewController, NetworkReachabilityHandling {
    /// Conform to NetworkReachabilityHandling
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!

    public var userSignedOutBlock: ((Bool) -> Void)?

    @IBOutlet var connectionStatusView: UIView!
    @IBOutlet var connectionStatusLabel: UILabel!
    @IBOutlet var balanceTitleLabel: UILabel!
    @IBOutlet var balanceView: BalanceView!
    @IBOutlet var tableView: UITableView!
    @IBOutlet var signOutButton: UIButton!
    @IBOutlet var networkUnavailableView: UIView!
    @IBOutlet var mainContentView: UIView!
    @IBOutlet var lastKnownBalanceLabel: UILabel!

    private var model: BaseIntegrationModel!

    private var isNeedToShowSignOutError = true

    @IBAction
    func signOutAction() {
        isNeedToShowSignOutError = false
        model.signOut()
    }

    private func popIntegrationFlow() {
        userSignedOutBlock?(isNeedToShowSignOutError)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureModel()
        configureHierarchy()

        networkStatusDidChange = { [weak self] _ in
            self?.reloadView()
        }
        startNetworkMonitoring()
    }

    deinit {
        stopNetworkMonitoring()
    }

    class func controller(model: BaseIntegrationModel) -> IntegrationViewController {
        let vc = vc(IntegrationViewController.self, from: sb("BuySellPortal"))
        vc.model = model
        
        return vc
    }
}

extension IntegrationViewController {
    private func configureModel() {
        model.userDidSignOut = { [weak self] in
            self?.popIntegrationFlow()
        }
        model.userDidChange = { [weak self] in
            self?.reloadView()
        }
    }

    private func reloadView() {
        let isOnline = networkStatus == .online
        lastKnownBalanceLabel.isHidden = isOnline
        networkUnavailableView.isHidden = isOnline
        mainContentView.isHidden = !isOnline
        connectionStatusView.backgroundColor = isOnline ? .systemGreen : .systemRed
        connectionStatusLabel.text = isOnline
            ? NSLocalizedString("Connected", comment: "Integration Entry Point")
            : NSLocalizedString("Disconnected", comment: "Integration Entry Point")
        balanceView.dataSource = model
    }

    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never

        lastKnownBalanceLabel.text = NSLocalizedString("Last known balance", comment: "Integration Entry Point")
        lastKnownBalanceLabel.isHidden = true
        networkUnavailableView.isHidden = true

        connectionStatusView.layer.cornerRadius = 2

        balanceTitleLabel.text = model.balanceTitle

        balanceView.dashSymbolColor = .dw_dashBlue()

        tableView.isScrollEnabled = false
        tableView.layer.cornerRadius = 10
        tableView.clipsToBounds = true
        tableView.backgroundColor = .dw_background()

        signOutButton.backgroundColor = .dw_background()
        signOutButton.titleLabel?.font = UIFont.dw_mediumFont(ofSize: 14)
        signOutButton.layer.cornerRadius = 10
        signOutButton.setTitle(model.signOutTitle, for: .normal)

        reloadView()
    }

    private func showError(_ error: LocalizedError) {
        let title = error.failureReason
        let message = error.localizedDescription
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let confirmAction = UIAlertAction(title: error.recoverySuggestion, style: .default) { [weak self] _ in
            self?.model.handle(error: error)
        }
        alert.addAction(confirmAction)

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
        alert.addAction(cancelAction)
        present(alert, animated: true)
    }
}

// MARK: UITableViewDelegate, UITableViewDataSource

extension IntegrationViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let isLastItem = indexPath.item == (model.items.count - 1)

        let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath) as! ItemCell
        cell.update(with: model.items[indexPath.item])
        cell.separatorInset = .init(top: 0, left: isLastItem ? 2000 : 63, bottom: 0, right: 0)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        62.0
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = model.items[indexPath.item]
        let vc: UIViewController

        if let error = model.validate(operation: item.type) {
            showError(error)
            return
        }
        
        switch model.service {
        case .coinbase:
            vc = getCoinbaseVcFor(operation: item.type)
        case .uphold:
            vc = getUpholdVcFor(operation: item.type)
        default:
            return
        }

        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - ItemCellDataProvider

protocol ItemCellDataProvider {
    var icon: String { get }
    var title: String { get }
    var description: String { get }
}

// MARK: - ItemCell

final class ItemCell: UITableViewCell {
    @IBOutlet var iconView: UIImageView!
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var secondaryLabel: UILabel!

    fileprivate func update(with item: ItemCellDataProvider) {
        iconView.image = .init(named: item.icon)
        nameLabel.text = item.title
        secondaryLabel.text = item.description
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        contentView.backgroundColor = .dw_background()
    }
}

// MARK: - Coinbase
extension IntegrationViewController {
    private func getCoinbaseVcFor(operation: IntegrationItemType) -> UIViewController {
        switch operation {
        case .buyDash:
            return BuyDashViewController()
        case .sellDash:
            return BuyDashViewController()
        case .convertCrypto:
            return CustodialSwapsViewController()
        case .transferDash:
            return TransferAmountViewController()
        }
    }
}

// MARK: - Uphold
extension IntegrationViewController {
    private func getUpholdVcFor(operation: IntegrationItemType) -> UIViewController {
        return DWUpholdViewController.init() // TODO
//        switch operation {
//        case .buyDash:
//            return BuyDashViewController()
//        case .sellDash:
//            return BuyDashViewController()
//        case .convertCrypto:
//            return CustodialSwapsViewController()
//        case .transferDash:
//            return TransferAmountViewController()
//        }
    }
}
