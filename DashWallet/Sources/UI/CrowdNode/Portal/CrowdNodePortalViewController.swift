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

    @objc static func controller() -> CrowdNodePortalController {
        vc(CrowdNodePortalController.self, from: sb("CrowdNode"))
    }

    @objc func infoButtonAction() {
        if viewModel.signUpState == .linkedOnline {
            present(OnlineAccountDetailsController.controller(), animated: true)
        } else {
            present(StakingInfoDialogController.controller(), animated: true)
        }
    }
    
    @IBAction func verifyButtonAction() {
        let vc = OnlineAccountConfirmationController.controller()
        present(vc, animated: true, completion: nil)
    }
}

extension CrowdNodePortalController {
    private func configureHierarchy() {
        balanceView.tint = .white
        balanceView.dataSource = self

        tableView.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.1, x: 0, y: 0, blur: 10)
        tableView.clipsToBounds = true
        tableView.isScrollEnabled = false
        tableView.rowHeight = UITableView.automaticDimension

        let colorStart = UIColor(red: 31 / 255.0, green: 134 / 255.0, blue: 201 / 255.0, alpha: 1.0).cgColor
        let colorEnd = UIColor(red: 99 / 255.0, green: 181 / 255.0, blue: 237 / 255.0, alpha: 1.0).cgColor
        let gradientMaskLayer = CAGradientLayer()
        gradientMaskLayer.frame = gradientHeader.bounds
        gradientMaskLayer.colors = [colorStart, colorEnd]
        gradientMaskLayer.locations = [0, 1]
        gradientMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientHeader.layer.insertSublayer(gradientMaskLayer, at: 0)
    }

    private func configureNavBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        let image = UIImage(systemName: "chevron.backward")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        appearance.setBackIndicatorImage(image, transitionMaskImage: image)
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
            .sink(receiveValue: { [weak self] balance in
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
                    self?.navigateToErrorScreen(error as! CrowdNode.Error)
                }
            })
            .store(in: &cancellableBag)
    }

    private func navigateToErrorScreen(_ error: CrowdNode.Error) {
        viewModel.error = nil

        let vc = FailedOperationStatusViewController.initiate(from: sb("OperationStatus"))
        vc.headerText = NSLocalizedString("Transfer Error", comment: "CrowdNode")
        vc.descriptionText = error.errorDescription
        vc.supportButtonText = NSLocalizedString("Send Report", comment: "Coinbase")
        let backHandler: (() -> ()) = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        vc.retryHandler = backHandler
        vc.cancelHandler = backHandler
        vc.supportHandler = {
            let url = DWAboutModel.supportURL()
            let safariViewController = SFSafariViewController.dw_controller(with: url)
            self.present(safariViewController, animated: true)
        }
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - CrowdNodeCell

class CrowdNodeCell: UITableViewCell {
    @IBOutlet var title : UILabel!
    @IBOutlet var subtitle : UILabel!
    @IBOutlet var icon : UIImageView!
    @IBOutlet var iconCircle : UIView!
    @IBOutlet var additionalInfo: UIView!
    @IBOutlet var additionalInfoLabel : UILabel!
    @IBOutlet var additionalInfoIcon : UIImageView!
    @IBOutlet var verifyButton : UIButton!
    
    @IBOutlet var showInfoConstraint: NSLayoutConstraint!
    @IBOutlet var collapseInfoConstraint: NSLayoutConstraint!
    @IBOutlet var infoBottomAnchorConstraint: NSLayoutConstraint!

    fileprivate func update(with item: CrowdNodePortalItem,
                            _ crowdNodeBalance: UInt64,
                            _ walletBalance: UInt64,
                            _ onlineAccountState: CrowdNode.OnlineAccountState) {
        title.text = item.title
        subtitle.text = item.subtitle
        icon.image = UIImage(named: item.icon)

        if item.isDisabled(crowdNodeBalance, walletBalance, onlineAccountState.isLinkingInProgress) {
            let grayColor = UIColor(red: 176/255.0, green: 182/255.0, blue: 188/255.0, alpha: 1.0)
            iconCircle.backgroundColor = grayColor
            title.textColor = .dw_secondaryText()
            selectionStyle = .none
        } else {
            iconCircle.backgroundColor = item.iconCircleColor
            title.textColor = .label
            selectionStyle = .default
        }

        var showInfo: Bool
        
        switch item {
        case .deposit:
            showInfo = crowdNodeBalance < CrowdNode.minimumDeposit && !onlineAccountState.isLinkingInProgress
        case .withdraw:
            showInfo = onlineAccountState.isLinkingInProgress
        default:
            showInfo = false
        }
        
        additionalInfo.isHidden = !showInfo
        showInfoConstraint.isActive = showInfo
        collapseInfoConstraint.isActive = !showInfo
        infoBottomAnchorConstraint.isActive = showInfo
        
        if showInfo {
            additionalInfo.backgroundColor = item.infoBackgroundColor
            additionalInfoLabel.text = item.info(crowdNodeBalance, onlineAccountState)
            additionalInfoLabel.textColor = item.infoTextColor

            if !item.infoActionButton(for: onlineAccountState).isEmpty {
                additionalInfoLabel.textAlignment = .left
                additionalInfoIcon.isHidden = false
                verifyButton.isHidden = false
            } else {
                additionalInfoLabel.textAlignment = .center
                additionalInfoIcon.isHidden = true
                verifyButton.isHidden = true
            }
        }
    }
}

// MARK: - CrowdNodePortalController + UITableViewDelegate, UITableViewDataSource

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
        let cell = tableView.dequeueReusableCell(withIdentifier: "CrowdNodeCell",
                                                 for: indexPath) as! CrowdNodeCell

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
            navigationController?.pushViewController(CrowdNodeTransferController.controller(mode: TransferDirection.deposit), animated: true)
        case .withdraw:
            navigationController?.pushViewController(CrowdNodeTransferController.controller(mode: TransferDirection.withdraw), animated: true)
        case .onlineAccount:
            if !viewModel.onlineAccountState.isLinkingInProgress {
                UIApplication.shared.open(URL(string: CrowdNode.fundsOpenUrl + viewModel.accountAddress)!)
            }
        case .support:
            UIApplication.shared.open(URL(string: CrowdNode.supportUrl)!)
        }
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
