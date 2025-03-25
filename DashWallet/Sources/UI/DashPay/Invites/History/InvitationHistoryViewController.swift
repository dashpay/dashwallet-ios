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

// MARK: - InvitationHistoryViewController

@objc
class InvitationHistoryViewController: BaseInvitesViewController {
    private var model: DWInvitationHistoryModel!
    private var _tableView: UITableView?
    
    private var tableView: UITableView {
        if _tableView == nil {
            let tableView = UITableView(frame: UIScreen.main.bounds, style: .plain)
            tableView.translatesAutoresizingMaskIntoConstraints = false
            tableView.backgroundColor = UIColor.dw_secondaryBackground()
            tableView.delegate = self
            tableView.dataSource = self
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = 74.0
            tableView.separatorStyle = .none
            tableView.sectionHeaderHeight = UITableView.automaticDimension
            tableView.estimatedSectionHeaderHeight = 100.0
            tableView.register(DWInvitationTableViewCell.self, forCellReuseIdentifier: DWInvitationTableViewCell.dw_reuseIdentifier)
            _tableView = tableView
        }
        return _tableView!
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = NSLocalizedString("Invite", comment: "")
        
        model = DWInvitationHistoryModel()
        model.delegate = self
        
        view.backgroundColor = UIColor.dw_secondaryBackground()
        
        view.addSubview(tableView)
        NSLayoutConstraint.dw_activate([
            tableView.pinEdges(view)
        ])
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        _tableView?.reloadData()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    @objc func createInvitationAction(_ sender: UIControl) {
        runInvitationFlow { [weak self] link, invitation in
            let controller = BaseInvitationViewController(with: invitation, fullLink: link, index: 0)
            controller.title = NSLocalizedString("Invite", comment: "")
            controller.hidesBottomBarWhenPushed = true
            controller.view.backgroundColor = UIColor.dw_secondaryBackground()
            self?.navigationController?.pushViewController(controller, animated: true)
            self?.model.reload()
        }
    }
    
    @objc func optionsButtonAction(_ sender: UIControl) {
        let controller = DWHistoryFilterViewController()
        controller.delegate = self
        present(controller, animated: true, completion: nil)
    }
}

// MARK: - UITableViewDataSource

extension InvitationHistoryViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return model.items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DWInvitationTableViewCell.dw_reuseIdentifier, for: indexPath) as! DWInvitationTableViewCell
        let item = model.items[indexPath.row]
        cell.item = item
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = DWHistoryHeaderView()
        header.createButton.addTarget(self, action: #selector(createInvitationAction(_:)), for: .touchUpInside)
        header.optionsButton.addTarget(self, action: #selector(optionsButtonAction(_:)), for: .touchUpInside)
        return header
    }
}

// MARK: - UITableViewDelegate

extension InvitationHistoryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let wallet = DWEnvironment.sharedInstance().currentWallet
        var identity = wallet.defaultBlockchainIdentity
        
        if identity == nil && MOCK_DASHPAY.boolValue {
            if let username = DWGlobalOptions.sharedInstance().dashpayUsername {
                identity = DWEnvironment.sharedInstance().currentWallet.createBlockchainIdentity(forUsername: username)
            }
        }
        
        guard let myBlockchainIdentity = identity else { return }
        
        let item = model.items[indexPath.row]
        let index = model.items.count - indexPath.row
        
        item.blockchainInvitation.createInvitationFullLink(from: myBlockchainIdentity) { [weak self] cancelled, invitationFullLink in
            guard let self = self else { return }
            guard let invitationLink = invitationFullLink else { return }
            
            DispatchQueue.main.async {
                let controller = BaseInvitationViewController(with: item.blockchainInvitation, fullLink: invitationLink, index: index)
                controller.title = NSLocalizedString("Invite", comment: "")
                controller.hidesBottomBarWhenPushed = true
                controller.view.backgroundColor = UIColor.dw_secondaryBackground()
                self.navigationController?.pushViewController(controller, animated: true)
            }
        }
    }
}

// MARK: - DWSendInviteFlowControllerDelegate

extension InvitationHistoryViewController: SendInviteFlowControllerDelegate {
    func sendInviteFlowControllerDidFinish(_ controller: SendInviteFlowController) {
        controller.dismiss(animated: true, completion: nil)
        model.reload()
    }
}

// MARK: - DWInvitationHistoryModelDelegate

extension InvitationHistoryViewController: DWInvitationHistoryModelDelegate {
    func invitationHistoryModelDidUpdate(_ model: DWInvitationHistoryModel) {
        tableView.reloadData()
    }
}

// MARK: - DWHistoryFilterViewControllerDelegate

extension InvitationHistoryViewController: DWHistoryFilterViewControllerDelegate {
    func historyFilterViewController(_ controller: DWHistoryFilterViewController, didSelect filter: DWInvitationHistoryFilter) {
        controller.dismiss(animated: true, completion: nil)
        model.filter = filter
    }
}
