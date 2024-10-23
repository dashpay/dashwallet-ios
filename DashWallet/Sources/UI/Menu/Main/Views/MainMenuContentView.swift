//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

@objc(DWMainMenuContentViewDelegate)
protocol MainMenuContentViewDelegate: AnyObject {
    func mainMenuContentView(_ view: MainMenuContentView, didSelectMenuItem item: DWMainMenuItem)
    
    #if DASHPAY
    func mainMenuContentView(_ view: MainMenuContentView, joinDashPayAction sender: UIButton)
    func mainMenuContentView(_ view: MainMenuContentView, showQRAction sender: UIButton)
    func mainMenuContentView(_ view: MainMenuContentView, editProfileAction sender: UIButton)
    func mainMenuContentView(_ view: MainMenuContentView, showCoinJoin sender: UIButton)
    #endif
}

@objc(DWMainMenuContentView)
class MainMenuContentView: UIView {
    
    // MARK: - Properties
    
    @objc var model: DWMainMenuModel {
        didSet {
            tableView.reloadData()
        }
    }
    @objc weak var delegate: MainMenuContentViewDelegate?
    
    private let tableView: UITableView
    
    #if DASHPAY
    @objc var userModel: DWCurrentUserProfileModel? = nil
    private let headerView: DWUserProfileContainerView
    private let joinHeaderView: DPWelcomeMenuView
    #endif
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        self.model = DWMainMenuModel()
        self.tableView = UITableView(frame: .zero, style: .plain)
        
        #if DASHPAY
        self.headerView = DWUserProfileContainerView(frame: .zero)
        self.joinHeaderView = DPWelcomeMenuView(frame: .zero)
        #endif
        
        super.init(frame: frame)
        
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        backgroundColor = UIColor.dw_secondaryBackground()
        
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = backgroundColor
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 74.0
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: DWDefaultMargin(), left: 0, bottom: DW_TABBAR_NOTCH, right: 0)
        addSubview(tableView)
        
        let cellId = DWMainMenuTableViewCell.dw_reuseIdentifier
        let nib = UINib(nibName: cellId, bundle: nil)
        tableView.register(nib, forCellReuseIdentifier: cellId)
        
        #if DASHPAY
        headerView.delegate = self
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(joinButtonAction(_:)))
        joinHeaderView.addGestureRecognizer(tapRecognizer)
        #endif
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        tableView.frame = self.bounds
        #if DASHPAY
        if let tableHeaderView = tableView.tableHeaderView {
            let headerSize = tableHeaderView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if tableHeaderView.frame.height != headerSize.height {
                tableHeaderView.frame = CGRect(x: 0, y: 0, width: headerSize.width, height: headerSize.height)
                tableView.tableHeaderView = tableHeaderView
            }
        }
        joinHeaderView.refreshState()
        #endif
    }
    
    // MARK: - Public Methods
    
    #if DASHPAY
    @objc func updateUserHeader() {
        userModel?.update()
        updateHeader()
    }
    
    private func updateHeader() {
        var header: UIView = joinHeaderView
        
        if userModel?.blockchainIdentity != nil {
            headerView.update()
            header = headerView
        }
        
        tableView.tableHeaderView = header
        setNeedsLayout()
    }
    
    @objc private func joinButtonAction(_ sender: UIButton) {
        let swiftUIView = MixDashDialog(
            positiveAction: {
                self.delegate?.mainMenuContentView(self, showCoinJoin: sender)
            }, negativeAction: {
                if UsernamePrefs.shared.joinDashPayInfoShown {
                    self.delegate?.mainMenuContentView(self, joinDashPayAction: sender)
                } else {
                    UsernamePrefs.shared.joinDashPayInfoShown = true
                    self.showDashPayInfo(sender)
                }
            }
        )
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(250)
        
        if let parentVC = self.parentViewController() {
            parentVC.present(hostingController, animated: true, completion: nil)
        } else {
            delegate?.mainMenuContentView(self, joinDashPayAction: sender)
        }
    }
    
    private func showDashPayInfo(_ sender: UIButton) {
        let swiftUIView = JoinDashPayInfoDialog() {
            self.delegate?.mainMenuContentView(self, joinDashPayAction: sender)
        }
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(600)
        
        if let parentVC = self.parentViewController() {
            parentVC.present(hostingController, animated: true, completion: nil)
        }
    }
    #endif
}

// MARK: - UITableViewDataSource

extension MainMenuContentView: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return model.items.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellId = DWMainMenuTableViewCell.dw_reuseIdentifier
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! DWMainMenuTableViewCell
        
        let menuItem = model.items[indexPath.row]
        cell.model = menuItem
        
        #if SNAPSHOT
        if menuItem.type == .security {
            cell.accessibilityIdentifier = "menu_security_item"
        }
        #endif
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension MainMenuContentView: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let menuItem = model.items[indexPath.row]
        delegate?.mainMenuContentView(self, didSelectMenuItem: menuItem)
    }
}

#if DASHPAY
// MARK: - DWCurrentUserProfileViewDelegate

extension MainMenuContentView: DWCurrentUserProfileViewDelegate {
    public func currentUserProfileView(_ view: DWCurrentUserProfileView, showQRAction sender: UIButton) {
        delegate?.mainMenuContentView(self, showQRAction: sender)
    }
    
    public func currentUserProfileView(_ view: DWCurrentUserProfileView, editProfileAction sender: UIButton) {
        delegate?.mainMenuContentView(self, editProfileAction: sender)
    }
}
#endif
