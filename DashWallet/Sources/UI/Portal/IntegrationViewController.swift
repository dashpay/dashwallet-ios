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
import AuthenticationServices

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
    @IBOutlet var signInOutButton: UIButton!
    @IBOutlet var networkUnavailableView: UIView!
    @IBOutlet var mainContentView: UIView!
    @IBOutlet var lastKnownBalanceLabel: UILabel!

    private var model: BaseIntegrationModel!

    private var isNeedToShowSignOutError = true
    private var authSession: ASWebAuthenticationSession? = nil

    @IBAction
    func signOutAction() {
        isNeedToShowSignOutError = false
        
        if model.isLoggedIn {
            model.logOut()
            onLogout()
        } else {
            initAuthentication(url: model.authenticationUrl)
        }
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
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.refresh()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        cancellableBag.removeAll()
        model.onFinish()
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
                guard let strongSelf = self else { return }
                
                if strongSelf.model.shouldPopOnLogout && !isLoggedIn {
                    strongSelf.popIntegrationFlow()
                } else {
                    strongSelf.reloadView()
                }
            }
            .store(in: &cancellableBag)
        
        NotificationCenter.default.publisher(for: NSNotification.Name.authURLReceived)
            .sink { [weak self] n in
                guard let url = n.object as? URL else { return }
                self?.handleCallbackURL(url: url)
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
        tableView.reloadData()
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
            signInOutButton.setTitle(model.signOutTitle, for: .normal)
            signInOutButton.setTitleColor(.dw_label(), for: .normal)
            signInOutButton.backgroundColor = .dw_background()
            signInOutButton.setImage(UIImage(named: "logout"), for: .normal)
            signInOutButton.contentHorizontalAlignment = .left
        } else {
            signInOutButton.setTitle(model.signInTitle, for: .normal)
            signInOutButton.setTitleColor(UIColor(named: "DashBlueColor"), for: .normal)
            signInOutButton.backgroundColor = UIColor(named: "LightBlueButtonColor")
            signInOutButton.setImage(nil, for: .normal)
            signInOutButton.contentHorizontalAlignment = .center
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
        
        signInOutButton.titleLabel?.font = UIFont.dw_mediumFont(ofSize: 15)
        signInOutButton.layer.cornerRadius = 10

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

        if let error = model.validate(operation: item.type) {
            showError(error)
            return
        }
    
        if let vc = getViewControllerFor(operation: item.type) {
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

// MARK: - Authentication

extension IntegrationViewController: ASWebAuthenticationPresentationContextProviding {
    private func initAuthentication(url: URL?) {
        guard let url = url else { return }
        
        signInOutButton.isUserInteractionEnabled = false

        // Starting iOS 14.5 `callbackURLScheme` is required to have the following format:
        // "The provided scheme is not valid. A scheme should not include special characters such as ":" or "/"."
        // See https://developer.apple.com/forums/thread/679251
        let callbackURLScheme = "dashwallet://".addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        
        let completionHandler: (URL?, Error?) -> Void = { [weak self] callbackURL, error in
            guard let strongSelf = self else {
                return
            }

            if let callbackURL = callbackURL {
                strongSelf.handleCallbackURL(url: callbackURL)
            }
            
            strongSelf.signInOutButton.isUserInteractionEnabled = true
        }
        
        let authenticationSession = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme, completionHandler: completionHandler)
        
        authenticationSession.presentationContextProvider = self
        authenticationSession.start()
        self.authSession = authenticationSession
    }
    
    private func handleCallbackURL(url: URL) {
        guard model.isValidCallbackUrl(url: url) else {
            return
        }

        self.authSession = nil
        model.logIn(callbackUrl: url)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        self.view.window!
    }
}

// MARK: - Service Routing

extension IntegrationViewController {
    func getViewControllerFor(operation: IntegrationItemType) -> UIViewController? {
        switch model.service {
        case .coinbase:
            return getCoinbaseVcFor(operation: operation)
        case .uphold:
            return getUpholdVcFor(operation: operation)
        default:
            return nil
        }
    }
    
    func onLogout() {
        if model.service == .uphold {
            onUpholdLogout()
        }
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

extension IntegrationViewController: DWUpholdLogoutTutorialViewControllerDelegate, UpholdTransferViewControllerDelegate {
    
    private func getUpholdVcFor(operation: IntegrationItemType) -> UIViewController? {
        switch operation {
        case .buyDash:
            return BuyDashViewController() // TODO: topper
        case .transferDash:
            return createUpholdTransferController()
        default:
            return nil
        }
    }
    
    func onUpholdLogout() {
        let logoutTutorialController = DWUpholdLogoutTutorialViewController.controller()
        logoutTutorialController.delegate = self
        let alertController = DWAlertController(contentController: logoutTutorialController)
        alertController.setupActions(logoutTutorialController.providedActions)
        alertController.preferredAction = logoutTutorialController.preferredAction
        present(alertController, animated: true, completion: nil)
    }
    
    func upholdLogoutTutorialViewControllerDidCancel(_ controller: DWUpholdLogoutTutorialViewController) {
        controller.dismiss(animated: true)
    }
    
    func upholdLogoutTutorialViewControllerOpenUpholdWebsite(_ controller: DWUpholdLogoutTutorialViewController) {
        controller.dismiss(animated: true, completion: { [weak self] in
            guard let url = self?.model.logoutUrl else { return }
            self?.initAuthentication(url: url)
        })
    }
    
    private func createUpholdTransferController() -> UIViewController? {
        guard model.isLoggedIn else { return nil }
        guard let dashCard = (self.model as? UpholdPortalModel)?.dashCard else { return nil }
        
        let controller = UpholdTransferViewController.init(card: dashCard)
        controller.delegate = self
        controller.hidesBottomBarWhenPushed = true
        
        return controller
    }
    
    func upholdTransferViewController(_ vc: UpholdTransferViewController, didSend transaction: DWUpholdTransactionObject) {
        navigationController?.popViewController(animated: true)

        let model = self.model as! UpholdPortalModel
        let alert = UIAlertController(title: NSLocalizedString("Uphold", comment: ""),
                                      message: model.successMessageText(for: transaction),
                                      preferredStyle: .alert)

        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                     style: .cancel,
                                     handler: nil)
        alert.addAction(okAction)

        let openAction = UIAlertAction(title: NSLocalizedString("See on Uphold", comment: ""),
                                       style: .default) { _ in
            if let url = model.transactionURL(for: transaction) {
                UIApplication.shared.open(url)
            }
        }
        alert.addAction(openAction)
        alert.preferredAction = openAction

        navigationController?.present(alert, animated: true, completion: nil)
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

// MARK: - Notifications

extension Notification.Name {
    static let authURLReceived: Notification.Name = .init(rawValue: "DWAuthURLNotification")
}


@objc extension NSNotification {
    public static let authURLReceived = Notification.Name.authURLReceived
}
