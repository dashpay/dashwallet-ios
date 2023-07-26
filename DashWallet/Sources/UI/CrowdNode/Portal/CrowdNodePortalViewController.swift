//
//  Created by Andrei Ashikhmin
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

import Combine

// MARK: - CrowdNodePortalController

final class CrowdNodePortalController: UIViewController {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()

    @IBOutlet var gradientHeader: UIView!
    @IBOutlet var tableView: UITableView!
    @IBOutlet var balanceLabel: UILabel!
    @IBOutlet var balanceView: BalanceView!

    override func viewDidLoad() {
        super.viewDidLoad()

        configureNavBar()
        configureHierarchy()
        viewModel.refreshBalance()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.showNotificationOnResult = false

        if cancellableBag.isEmpty {
            configureObservers()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancellableBag.removeAll()
        viewModel.showNotificationOnResult = true
    }

    @objc
    static func controller() -> CrowdNodePortalController {
        vc(CrowdNodePortalController.self, from: sb("CrowdNode"))
    }

    @objc
    func backButtonAction() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    func infoButtonAction() {
        if viewModel.signUpState == .linkedOnline {
            present(OnlineAccountDetailsController.controller(), animated: true)
        } else {
            present(StakingInfoDialogController.controller(), animated: true)
        }
    }

    @IBAction
    func verifyButtonAction() {
        let vc = OnlineAccountConfirmationController.controller()
        present(vc, animated: true, completion: nil)
    }
}

extension CrowdNodePortalController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        balanceView.tint = .white
        balanceView.dataSource = self

        tableView.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.1, x: 0, y: 0, blur: 10)
        tableView.clipsToBounds = true
        tableView.isScrollEnabled = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorColor = .dw_separatorLine()

        let colorStart = UIColor(red: 31 / 255.0, green: 134 / 255.0, blue: 201 / 255.0, alpha: 1.0).cgColor
        let colorEnd = UIColor(red: 99 / 255.0, green: 181 / 255.0, blue: 237 / 255.0, alpha: 1.0).cgColor
        let gradientMaskLayer = CAGradientLayer()
        gradientMaskLayer.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: gradientHeader.bounds.height)
        gradientMaskLayer.colors = [colorStart, colorEnd]
        gradientMaskLayer.locations = [0, 1]
        gradientMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientHeader.layer.insertSublayer(gradientMaskLayer, at: 0)
    }

    private func configureNavBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()

        let backButton = UIButton(type: .custom)
        backButton.frame = .init(x: 0, y: 0, width: 30, height: 30)
        backButton.setImage(UIImage(systemName: "arrow.backward"), for: .normal)
        backButton.tintColor = .white
        backButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
        backButton.addTarget(self, action: #selector(backButtonAction), for: .touchUpInside)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backButton)

        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance

        let buttonImage = UIImage(systemName: "info.circle")
        let button = UIBarButtonItem(image: buttonImage, style: UIBarButtonItem.Style.plain, target: self, action: #selector(infoButtonAction))
        button.tintColor = UIColor.white
        navigationItem.rightBarButtonItem = button
    }

    private func configureObservers() {
        viewModel.$crowdNodeBalance
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink(receiveValue: { [weak self] _ in
                self?.balanceView.dataSource = self
                self?.tableView.reloadRows(at: [
                    IndexPath(item: 0, section: 0),
                    IndexPath(item: 1, section: 0),
                ],
                with: .none)
            })
            .store(in: &cancellableBag)

        viewModel.$walletBalance
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink(receiveValue: { [weak self] _ in
                self?.tableView.reloadRows(at: [
                    IndexPath(item: 0, section: 0),
                ],
                with: .none)
            })
            .store(in: &cancellableBag)

        viewModel.$onlineAccountState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadRows(at: [
                    IndexPath(item: 1, section: 0),
                    IndexPath(item: 0, section: 1),
                ],
                with: .none)

                if self?.viewModel.shouldShowConfirmationDialog == true {
                    let vc = OnlineAccountConfirmationController.controller()
                    self?.present(vc, animated: true, completion: nil)
                    self?.viewModel.shouldShowConfirmationDialog = false
                }
            }
            .store(in: &cancellableBag)

        viewModel.$animateBalanceLabel
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] animate in
                if animate {
                    UIView.animate(withDuration: 0.5,
                                   delay:0.0,
                                   options:[.allowUserInteraction, .curveEaseInOut, .autoreverse, .repeat],
                                   animations: { self?.balanceLabel.alpha = 0 },
                                   completion: nil)
                } else {
                    self?.balanceLabel.layer.removeAllAnimations()
                    self?.balanceLabel.alpha = 1
                }
            })
            .store(in: &cancellableBag)

        viewModel.$error
            .receive(on: DispatchQueue.main)
            .filter { error in error != nil }
            .sink(receiveValue: { [weak self] error in
                if error is CrowdNode.Error {
                    self?.viewModel.clearError()
                    self?.navigationController?.toErrorScreen(error: error as! CrowdNode.Error)
                }
            })
            .store(in: &cancellableBag)
    }
}

// MARK: UITableViewDelegate, UITableViewDataSource

extension CrowdNodePortalController : UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(type: CrowdNodeCell.self, for: indexPath)

        let item = viewModel.portalItems[(indexPath.section * 2) + indexPath.item]
        cell.update(with: item, viewModel.crowdNodeBalance, viewModel.walletBalance, viewModel.onlineAccountState)

        return cell
    }

    // Default corner radius is too small. Set to 16
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let cornerRadius = 16
        var corners = UIRectCorner()

        if indexPath.item == 0 {
            corners.insert(.topLeft)
            corners.insert(.topRight)
        } else {
            corners.insert(.bottomLeft)
            corners.insert(.bottomRight)
        }

        let shapeLayer = CAShapeLayer()
        shapeLayer.path = UIBezierPath(roundedRect: cell.bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)).cgPath
        cell.layer.mask = shapeLayer
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = viewModel.portalItems[(indexPath.section * 2) + indexPath.item]

        if item.isDisabled(viewModel.crowdNodeBalance, viewModel.walletBalance, viewModel.onlineAccountState.isLinkingInProgress) {
            return
        }

        switch item {
        case .deposit:
            DSLogger.log("CrowdNodeDeposit: navigate to transfer with deposit mode")
            navigationController?.pushViewController(CrowdNodeTransferController.controller(mode: TransferDirection.deposit), animated: true)
        case .withdraw:
            if viewModel.canWithdraw {
                navigationController?.pushViewController(CrowdNodeTransferController.controller(mode: TransferDirection.withdraw), animated: true)
            } else {
                showMinimumBalanceError()
            }
        case .onlineAccount:
            switch viewModel.onlineAccountState {
            case .none, .creating:
                showOnlineInfoOrEnterEmail()
            case .signingUp:
                showSignUpWebView()
            case .done:
                let accountAddress = viewModel.primaryAddress ?? viewModel.accountAddress
                UIApplication.shared.open(URL(string: CrowdNode.fundsOpenUrl + accountAddress)!)
            default:
                break
            }

        case .support:
            UIApplication.shared.open(URL(string: CrowdNode.supportUrl)!)
        }
    }

    private func showMinimumBalanceError() {
        let vc = BasicInfoController()
        vc.icon = "image.crowdnode.error"
        vc.headerText = NSLocalizedString("You should have a positive balance on Dash Wallet", comment: "CrowdNode")
        vc.descriptionText = String.localizedStringWithFormat(NSLocalizedString("Deposit at least %@ Dash on your Dash Wallet to complete a withdrawal", comment: "CrowdNode"),
                                                              CrowdNode.minimumLeftoverBalance.formattedDashAmountWithoutCurrencySymbol)
        vc.actionButtonText = viewModel.buyDashButtonText
        let nvc = BaseNavigationController(rootViewController: vc)

        vc.mainAction = {
            Task {
                if await self.viewModel.authenticate() {
                    let controller = PortalViewController.controller()
                    nvc.pushViewController(controller, animated: true)
                }
            }
        }

        present(nvc, animated: true)
    }
}

// MARK: BalanceViewDataSource

extension CrowdNodePortalController: BalanceViewDataSource {
    var mainAmountString: String {
        viewModel.crowdNodeBalance.formattedDashAmount
    }

    var supplementaryAmountString: String {
        let fiat: String

        if let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: viewModel.crowdNodeBalance.dashAmount, to: App.fiatCurrency) {
            fiat = NumberFormatter.fiatFormatter.string(from: fiatAmount as NSNumber)!
        } else {
            fiat = NSLocalizedString("Syncing…", comment: "Balance")
        }

        return fiat
    }
}

// MARK: - Online

extension CrowdNodePortalController {
    private func showOnlineInfoOrEnterEmail() {
        if viewModel.shouldShowOnlineInfo {
            navigationController?.pushViewController(OnlineAccountInfoController.controller(), animated: true)
            viewModel.shouldShowOnlineInfo = false
        } else {
            navigationController?.pushViewController(OnlineAccountEmailController.controller(), animated: true)
        }
    }

    private func showSignUpWebView() {
        let profileUrl = CrowdNode.profileUrl
        navigationController?.pushViewController(CrowdNodeWebViewController.controller(url: URL(string: profileUrl)!, email: viewModel.emailForAccount), animated: true)
    }
}
