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

protocol MainMenuContentViewDelegate: AnyObject {
    func mainMenuContentView(_ view: MainMenuContentView, didSelectMenuItem item: DWMainMenuItem)
    
    #if DASHPAY
    func mainMenuContentView(joinDashPayAction view: MainMenuContentView)
    func mainMenuContentView(showQRAction view: MainMenuContentView)
    func mainMenuContentView(editProfileAction view: MainMenuContentView)
    func mainMenuContentView(showCoinJoin view: MainMenuContentView)
    func mainMenuContentView(showRequestDetails view: MainMenuContentView)
    #endif
}

class MainMenuContentView: UIView {
    
    // MARK: - Properties
    
    var model: DWMainMenuModel {
        didSet {
            tableView.reloadData()
        }
    }
    weak var delegate: MainMenuContentViewDelegate?
    
    private let tableView: UITableView
    
    #if DASHPAY
    var userModel: CurrentUserProfileModel? = nil
    let joinDPViewModel = JoinDashPayViewModel(initialState: .none)
    private let headerView: DWUserProfileContainerView
    private var welcomeView: JoinDashPayView!
    
    var shouldShowMixDashDialog: Bool {
        get { CoinJoinService.shared.mode == .none || !UsernamePrefs.shared.mixDashShown }
        set(value) { UsernamePrefs.shared.mixDashShown = !value }
    }
    
    var shouldShowDashPayInfo: Bool {
        get { !UsernamePrefs.shared.joinDashPayInfoShown }
        set(value) { UsernamePrefs.shared.joinDashPayInfoShown = !value }
    }
    #endif
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        self.model = DWMainMenuModel()
        self.tableView = UITableView(frame: .zero, style: .plain)
        
        #if DASHPAY
        self.headerView = DWUserProfileContainerView(frame: .zero)
        #endif
        
        super.init(frame: frame)
        
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private var height = 0.0
    
    private func setupViews() {
        #if DASHPAY
        welcomeView = JoinDashPayView(
            viewModel: self.joinDPViewModel,
            onTap: { state in
                if state == .registered {
                    self.delegate?.mainMenuContentView(editProfileAction: self)
                } else if state == .voting {
                    self.delegate?.mainMenuContentView(showRequestDetails: self)
                } else if state == .none {
                    self.joinButtonAction()
                }
            }, onActionButton: { state in
                if state == .blocked || state == .failed || state == .contested {
                    self.joinButtonAction()
                } else {
                    self.delegate?.mainMenuContentView(editProfileAction: self)
                    self.joinDPViewModel.markAsDismissed()
                }
            }, onDismissButton: { state in
                self.joinDPViewModel.markAsDismissed()
            }, onSizeChange: { size in
                self.height = size.height
                if let header = self.tableView.tableHeaderView {
                    header.frame = CGRect(x: 0, y: 0, width: self.tableView.bounds.width, height: self.height)
                    self.tableView.tableHeaderView = header
                }
            }
        )
        #endif
        
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
        #endif
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        tableView.frame = self.bounds
    }
    
    // MARK: - Public Methods
    
    #if DASHPAY
    func updateUserHeader() {
        if userModel?.showJoinDashpay == true {
            let hostingController = UIHostingController(
                rootView: welcomeView
                    .padding(.bottom, 20)
                    .padding(.horizontal, 18)
            )
            hostingController.view.backgroundColor = .clear
            let header = hostingController.view
            tableView.tableHeaderView = header
        } else {
            tableView.tableHeaderView = nil
        }
        
        setNeedsLayout()
    }
    
    private func joinButtonAction() {
        if shouldShowMixDashDialog {
            self.showMixDashDialog(
                purposeText: NSLocalizedString("your username", comment: "Usernames"),
                onSkip: {
                    if UsernamePrefs.shared.joinDashPayInfoShown {
                        self.delegate?.mainMenuContentView(joinDashPayAction: self)
                    } else {
                        UsernamePrefs.shared.joinDashPayInfoShown = true
                        self.showDashPayInfo()
                    }
                }
            )
        } else if shouldShowDashPayInfo {
            self.showDashPayInfo()
        } else {
            self.delegate?.mainMenuContentView(joinDashPayAction: self)
        }
    }
    
    func showMixDashDialog(purposeText: String, onSkip: @escaping () -> Void) {
        let swiftUIView = MixDashDialog(
            purposeText: purposeText,
            positiveAction: {
                self.delegate?.mainMenuContentView(showCoinJoin: self)
            }, negativeAction: onSkip
        )
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(260)
        
        if let parentVC = self.parentViewController() {
            parentVC.present(hostingController, animated: true, completion: nil)
        }
    }
    
    private func showDashPayInfo() {
        let swiftUIView = JoinDashPayInfoDialog {
            self.delegate?.mainMenuContentView(joinDashPayAction: self)
        }
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(600)
        
        if let parentVC = self.parentViewController() {
            parentVC.present(hostingController, animated: true, completion: nil)
        }
    }

    func showInvitationFeeDialog(onAction: @escaping () -> Void) {
        let swiftUIView = InvitationFeeDialog(action: onAction)
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(520)
        
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
        delegate?.mainMenuContentView(showQRAction: self)
    }
    
    public func currentUserProfileView(_ view: DWCurrentUserProfileView, editProfileAction sender: UIButton) {
        delegate?.mainMenuContentView(editProfileAction: self)
    }
}
#endif
