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
import Combine

// MARK: - IntegrationViewController

final class IntegrationViewController: BaseViewController, NetworkReachabilityHandling {
    private var cancellableBag = Set<AnyCancellable>()
    /// Conform to NetworkReachabilityHandling
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!

    public var userSignedOutBlock: ((Bool) -> Void)?

    @IBOutlet var serviceNameLabel: UILabel!
    @IBOutlet var serviceNameIcon: UIImageView!
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
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancellableBag.removeAll()
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
        model.userDidChange = { [weak self] in
            self?.reloadView()
        }
        
        model.$isLoggedIn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoggedIn in
                guard let wSelf = self else { return }
                
                if wSelf.model.shouldPopOnLogout && !isLoggedIn {
                    wSelf.popIntegrationFlow()
                } else {
                    wSelf.reloadView()
                }
            }
            .store(in: &cancellableBag)
    }

    private func reloadView() {
        let isOnline = networkStatus == .online
        lastKnownBalanceLabel.isHidden = isOnline || !model.isLoggedIn
        networkUnavailableView.isHidden = isOnline
        mainContentView.isHidden = !isOnline
        balanceView.dataSource = model
        balanceView.isHidden = !model.isLoggedIn
        balanceTitleLabel.isHidden = !model.isLoggedIn
        configureLogoutButton(isLoggedIn: model.isLoggedIn)
    }
    
    private func setTableHeight() {
        var height: CGFloat = 0
        for section in 0..<tableView.numberOfSections {
            for row in 0..<tableView.numberOfRows(inSection: section) {
                let indexPath = IndexPath(row: row, section: section)
                height += tableView.delegate?.tableView?(tableView, heightForRowAt: indexPath) ?? 62.0
            }
        }
        
        tableView.heightAnchor.constraint(equalToConstant: height).isActive = true
        view.layoutIfNeeded()
    }
    
    private func configureLogoutButton(isLoggedIn: Bool) {
        if isLoggedIn {
            signOutButton.titleLabel?.textColor = .dw_label()
            signOutButton.backgroundColor = .dw_background()
            signOutButton.setImage(UIImage(named: "logout"), for: .normal)
            signOutButton.setTitle(model.signOutTitle, for: .normal)
            signOutButton.contentHorizontalAlignment = .left
            signOutButton.heightAnchor.constraint(equalToConstant: 62).isActive = true
        } else {
            signOutButton.titleLabel?.textColor = UIColor(named: "DashBlueColor")
            signOutButton.backgroundColor = UIColor(named: "LightBlueButtonColor")
            signOutButton.setImage(nil, for: .normal)
            signOutButton.setTitle(model.signInTitle, for: .normal)
            signOutButton.contentHorizontalAlignment = .center
            signOutButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        }
    }

    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never
        
        serviceNameLabel.text = model.service.title
        serviceNameIcon.image = UIImage(named: model.service.icon)

        lastKnownBalanceLabel.text = NSLocalizedString("Last known balance", comment: "Integration Entry Point")
        lastKnownBalanceLabel.isHidden = true
        networkUnavailableView.isHidden = true

        balanceTitleLabel.text = model.balanceTitle

        balanceView.dashSymbolColor = .dw_dashBlue()

        tableView.isScrollEnabled = false
        tableView.layer.cornerRadius = 10
        tableView.clipsToBounds = true
        tableView.backgroundColor = .dw_background()
        
        signOutButton.titleLabel?.font = UIFont.dw_mediumFont(ofSize: 15)
        signOutButton.layer.cornerRadius = 10

        reloadView()
        setTableHeight()
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
        cell.update(with: model.items[indexPath.item], isLoggedIn: model.isLoggedIn)
        cell.separatorInset = .init(top: 0, left: isLastItem ? 2000 : 63, bottom: 0, right: 0)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if model.items[indexPath.item].hasAdditionalInfo {
            return 90.0
        } else {
            return 62.0
        }
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
    var alwaysEnabled: Bool { get }
    var hasAdditionalInfo: Bool { get }
}

// MARK: - ItemCell

final class ItemCell: UITableViewCell {
    @IBOutlet var iconView: UIImageView!
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var secondaryLabel: UILabel!
    // The additional info view is pre-set to "Powered by Topper" for now.
    @IBOutlet var additionalInfoView: UIView!

    fileprivate func update(with item: ItemCellDataProvider, isLoggedIn: Bool) {
        iconView.image = .init(named: isLoggedIn || item.alwaysEnabled ? item.icon : item.icon + ".disabled")
        nameLabel.text = item.title
        secondaryLabel.text = item.description
        additionalInfoView.isHidden = !item.hasAdditionalInfo
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
