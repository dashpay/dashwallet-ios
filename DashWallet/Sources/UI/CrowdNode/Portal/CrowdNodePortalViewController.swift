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

import Foundation
import Combine

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
        configureObservers()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancellableBag.removeAll()
    }
    
    @objc static func controller() -> CrowdNodePortalController {
        let storyboard = UIStoryboard(name: "CrowdNode", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "CrowdNodePortalController") as! CrowdNodePortalController
        return vc
    }
    
    @objc func infoButtonAction() {
        UIPasteboard.general.string = viewModel.accountAddress
    }
}

extension CrowdNodePortalController {
    private func configureHierarchy() {
        balanceView.tint = .white
        balanceView.balance = viewModel.crowdNodeBalance
        
        tableView.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.1, x: 0, y: 0, blur: 10)
        tableView.clipsToBounds = true
        tableView.isScrollEnabled = false
        tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.frame.size.width, height: 1))
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
        
        let buttonImage = UIImage.init(systemName: "info.circle")
        let button = UIBarButtonItem.init(image: buttonImage, style: UIBarButtonItem.Style.plain, target: self, action: #selector(infoButtonAction))
        button.tintColor = UIColor.white
        navigationItem.rightBarButtonItem = button
    }
    
    private func configureObservers() {
        viewModel.$crowdNodeBalance
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink(receiveValue: { [weak self] balance in
                self?.balanceView.balance = balance
                self?.tableView.reloadRows(at: [
                    IndexPath.init(item: 0, section: 0),
                    IndexPath.init(item: 1, section: 0)
                ],
                with: .none)
            })
            .store(in: &cancellableBag)
        
        viewModel.$walletBalance
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink(receiveValue: { [weak self] balance in
                self?.tableView.reloadRows(at: [
                    IndexPath.init(item: 0, section: 0),
                ],
                with: .none)
            })
            .store(in: &cancellableBag)
        
        viewModel.$animateBalanceLabel
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] animate in
                if animate {
                    UIView.animate(
                        withDuration: 0.5,
                        delay:0.0,
                        options:[.allowUserInteraction, .curveEaseInOut, .autoreverse, .repeat],
                        animations: { self?.balanceLabel.alpha = 0 },
                        completion: nil
                    )
                } else {
                    self?.balanceLabel.layer.removeAllAnimations()
                    self?.balanceLabel.alpha = 1
                }
            })
            .store(in: &cancellableBag)
    }
}

class CrowdNodeCell: UITableViewCell {
    @IBOutlet var title : UILabel!
    @IBOutlet var subtitle : UILabel!
    @IBOutlet var icon : UIImageView!
    @IBOutlet var iconCircle : UIView!
    @IBOutlet var additionalInfo: UIView!
    @IBOutlet var additionalInfoLabel : UILabel!
    
    private lazy var showInfoConstraint = additionalInfo.heightAnchor.constraint(equalToConstant: 30)
    private lazy var collapseInfoConstraint = additionalInfo.heightAnchor.constraint(equalToConstant: 0)
    
    fileprivate func update(
        with item: CrowdNodePortalItem,
        _ crowdNodeBalance: UInt64,
        _ walletBalance: UInt64
    ) {
        title.text = item.title
        subtitle.text = item.subtitle
        icon.image = UIImage(named: item.icon)
        
        if item.isDisabled(crowdNodeBalance, walletBalance) {
            let grayColor = UIColor(red: 176/255.0, green: 182/255.0, blue: 188/255.0, alpha: 1.0)
            iconCircle.backgroundColor = grayColor
            title.textColor = .dw_secondaryText()
            selectionStyle = .none
        } else {
            iconCircle.backgroundColor = item.iconCircleColor
            title.textColor = .label
            selectionStyle = .default
        }
        
        if item == .deposit && crowdNodeBalance < CrowdNode.minimumDeposit {
            showInfoConstraint.isActive = true
            collapseInfoConstraint.isActive = false
            additionalInfoLabel.text = item.info(crowdNodeBalance)
        } else {
            showInfoConstraint.isActive = false
            collapseInfoConstraint.isActive = true
        }
    }
}

extension CrowdNodePortalController : UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        2
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return CGFloat.leastNormalMagnitude
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CrowdNodeCell",
                              for: indexPath) as! CrowdNodeCell
             
        let item = viewModel.portalItems[(indexPath.section * 2) + indexPath.item]
        cell.update(with: item, viewModel.crowdNodeBalance, viewModel.walletBalance)
        
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
        
        if item.isDisabled(viewModel.crowdNodeBalance, viewModel.walletBalance) {
            return
        }

        switch item {
        case .deposit, .withdraw:
            navigationController?.pushViewController(CrowdNodeTransferController.controller(), animated: true)
        case .onlineAccount:
            UIApplication.shared.open(URL(string: CrowdNode.fundsOpenUrl + viewModel.accountAddress)!)
            break
        case .support:
            UIApplication.shared.open(URL(string: CrowdNode.supportUrl)!)
        }
    }
}
