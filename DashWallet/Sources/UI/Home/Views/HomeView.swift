//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - HomeViewDelegate

@objc(DWHomeViewDelegate)
protocol HomeViewDelegate: AnyObject {
    func homeView(_ homeView: HomeView, showTxFilter sender: UIView)
    func homeView(_ homeView: HomeView, showSyncingStatus sender: UIView)
    func homeView(_ homeView: HomeView, didSelectTransaction transaction: DSTransaction)
    func homeViewShowDashPayRegistrationFlow(_ homeView: HomeView)
    func homeView(_ homeView: HomeView, showReclassifyYourTransactionsFlowWithTransaction transaction: DSTransaction)
    func homeView(_ homeView: HomeView, showCrowdNodeTxs transactions: [DSTransaction])
    
#if DASHPAY
    func homeView(_ homeView: HomeView, didUpdateProfile identity: DSBlockchainIdentity?, unreadNotifications: UInt)
#endif
}

// MARK: - HomeView

@objc(DWHomeView)
final class HomeView: UIView, DWHomeModelUpdatesObserver, DWDPRegistrationErrorRetryDelegate {

    @objc
    weak var delegate: HomeViewDelegate?

    private(set) var headerView: HomeHeaderView!
    private(set) var topOverscrollView: UIView!
    private(set) var tableView: UITableView!

    weak var syncingHeaderView: SyncingHeaderView?

    // Strong ref to current dataSource to make sure it always exists while tableView uses it
    var currentDataSource: TransactionListDataSource?

    @objc
    var model: DWHomeProtocol? {
        didSet {
            model?.updatesObserver = self
            #if DASHPAY
            updateHeaderView()
            #endif
        }
    }

    @objc
    weak var shortcutsDelegate: ShortcutsActionDelegate? {
        get { headerView.shortcutsDelegate }
        set { headerView.shortcutsDelegate = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    @objc
    func hideBalanceIfNeeded() {
        headerView?.balanceView.hideBalanceIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let size = bounds.size
        topOverscrollView.frame = CGRect(x: 0.0, y: -size.height, width: size.width, height: size.height)

        if let tableHeaderView = tableView.tableHeaderView {
            let headerSize = tableHeaderView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if tableHeaderView.frame.height != headerSize.height {
                tableHeaderView.frame = CGRect(x: 0.0, y: 0.0, width: headerSize.width, height: headerSize.height)
                tableView.tableHeaderView = tableHeaderView
            }
        }
    }

    private func setupView() {
        backgroundColor = UIColor.dw_secondaryBackground()

        headerView = HomeHeaderView(frame: CGRect.zero)
        headerView.delegate = self

        topOverscrollView = UIView(frame: CGRect.zero)
        topOverscrollView.backgroundColor = UIColor.dw_dashNavigationBlue()

        tableView = UITableView(frame: bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.tableHeaderView = headerView
        tableView.backgroundColor = UIColor.dw_secondaryBackground()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 74.0
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 64.0
        tableView.separatorStyle = .none
        // NOTE: tableView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: DW_TABBAR_NOTCH, right: 0.0)
        tableView.addSubview(topOverscrollView)
        addSubview(tableView)

        let cellIds = [
            TxListEmptyTableViewCell.reuseIdentifier,
            TxListTableViewCell.reuseIdentifier,
            DWDPRegistrationStatusTableViewCell.dw_reuseIdentifier,
            DWDPRegistrationErrorTableViewCell.dw_reuseIdentifier,
            DWDPRegistrationDoneTableViewCell.dw_reuseIdentifier,
        ]
        for cellId in cellIds {
            let nib = UINib(nibName: cellId, bundle: nil)
            tableView.register(nib, forCellReuseIdentifier: cellId)
        }

        let nib = UINib(nibName: "CNCreateAccountCell", bundle: nil)
        tableView.register(nib, forCellReuseIdentifier: "CNCreateAccountCell")
        tableView.registerClassforHeaderFooterView(for: SyncingHeaderView.self)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(setNeedsLayout),
                                               name: UIContentSizeCategory.didChangeNotification,
                                               object: nil)
        
        #if DASHPAY
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateHeaderView),
                                               name:NSNotification.Name.DWDashPayRegistrationStatusUpdated,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateHeaderView),
                                               name:NSNotification.Name.DWNotificationsProviderDidUpdate,
                                               object:nil);
        #endif
    }

    // MARK: - DWHomeModelUpdatesObserver

    func homeModel(_ model: DWHomeProtocol, didUpdate dataSource: TransactionListDataSource, shouldAnimate: Bool) {
        currentDataSource = dataSource
        dataSource.retryDelegate = self

        if dataSource.isEmpty {
            tableView.dataSource = self
        } else {
            tableView.dataSource = dataSource
        }
        tableView.reloadData()

        headerView.reloadBalance()
        reloadShortcuts()
    }

    func homeModel(_ model: DWHomeProtocol, didReceiveNewIncomingTransaction transaction: DSTransaction) {
        delegate?.homeView(self, showReclassifyYourTransactionsFlowWithTransaction: transaction)
    }

    func homeModelDidChangeInnerModels(_ model: DWHomeProtocol) {
        headerView.reloadBalance()
        reloadShortcuts()
    }

    func homeModelWant(toReloadShortcuts model: DWHomeProtocol) {
        reloadShortcuts()
        #if DASHPAY
        updateHeaderView()
        #endif
    }
    
    func homeModelWant(toReloadVoting model: DWHomeProtocol) {
        #if DASHPAY
        updateHeaderView()
        #endif
    }


    // MARK: - DWDPRegistrationErrorRetryDelegate

    func registrationErrorRetryAction() {
        if model?.dashPayModel.canRetry() ?? false {
            model?.dashPayModel.retry()
        } else {
            delegate?.homeViewShowDashPayRegistrationFlow(self)
        }
    }

    @objc
    func reloadShortcuts() {
        headerView?.reloadShortcuts()
    }
    
    // MARK: DWDashPayRegistrationStatusUpdated
    
    #if DASHPAY
    @objc
    func updateHeaderView() {
        if let model = self.model {
            let isDPInfoHidden = DWGlobalOptions.sharedInstance().dashPayRegistrationOpenedOnce || model.shouldShowCreateUserNameButton() != true
            let isVotingEnabled = VotingPrefs.shared.votingEnabled
            
            if let usernameRequestId = VotingPrefs.shared.requestedUsernameId, isVotingEnabled {
                setVotingState(dpInfoHidden: isDPInfoHidden, requestId: usernameRequestId)
            } else {
                setIdentity(dpInfoHidden: isDPInfoHidden, model: model)
            }
        }
    }
    
    private func setIdentity(dpInfoHidden: Bool, model: DWHomeProtocol) {
        headerView.isDPWelcomeViewHidden = dpInfoHidden
        headerView.isVotingViewHidden = true
        let status = model.dashPayModel.registrationStatus
        let completed = model.dashPayModel.registrationCompleted
        
        if status?.state == .done || completed {
            let identity = model.dashPayModel.blockchainIdentity
            let notificaitonAmount = model.dashPayModel.unreadNotificationsCount
            
            delegate?.homeView(self, didUpdateProfile: identity, unreadNotifications: notificaitonAmount)
        } else {
            delegate?.homeView(self, didUpdateProfile: nil, unreadNotifications: 0)
        }
        
        setNeedsLayout()
    }
    
    private func setVotingState(dpInfoHidden: Bool, requestId: String) {
        let wasClosed = VotingPrefs.shared.votingPanelClosed
        let now = Date().timeIntervalSince1970
        headerView.isVotingViewHidden = dpInfoHidden || wasClosed || now < VotingConstants.votingEndTime
        headerView.isDPWelcomeViewHidden = true
        let dao = UsernameRequestsDAOImpl.shared
        
        Task {
            let request = await dao.get(byRequestId: requestId)
            // TODO: change this logic
            self.headerView.votingState = (request?.isApproved ?? false) ? .approved : .notApproved
            setNeedsLayout()
        }
    }
    #endif
}

// MARK: HomeHeaderViewDelegate

extension HomeView: HomeHeaderViewDelegate {
    func homeHeaderView(_ headerView: HomeHeaderView, retrySyncButtonAction sender: UIView) {
        model?.retrySyncing()
    }

    func homeHeaderViewDidUpdateContents(_ view: HomeHeaderView) {
        setNeedsLayout()
    }
    
    #if DASHPAY
    func homeHeaderViewJoinDashPayAction(_ headerView: HomeHeaderView) {
        delegate?.homeViewShowDashPayRegistrationFlow(self)
    }
    #endif
}

// MARK: SyncingHeaderViewDelegate

extension HomeView: SyncingHeaderViewDelegate {
    func syncingHeaderView(_ view: SyncingHeaderView, syncingButtonAction sender: UIButton) {
        delegate?.homeView(self, showSyncingStatus: sender)
    }

    func syncingHeaderView(_ view: SyncingHeaderView, filterButtonAction sender: UIButton) {
        delegate?.homeView(self, showTxFilter: sender)
    }
}

// MARK: UITableViewDataSource, UITableViewDelegate

extension HomeView: UITableViewDataSource, UITableViewDelegate {
    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellId = TxListEmptyTableViewCell.reuseIdentifier
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(type: SyncingHeaderView.self)
        headerView.delegate = self
        syncingHeaderView = headerView
        return headerView
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let currentDataSource,
              !currentDataSource.isEmpty else { return }

        let type = currentDataSource.itemType(by: indexPath)

        if type == .crowdnode {
            delegate?.homeView(self, showCrowdNodeTxs: currentDataSource.crowdnodeTxs())
            return
        }

        if let transaction = currentDataSource.transactionForIndexPath(indexPath) {
            delegate?.homeView(self, didSelectTransaction: transaction)
        } else { // registration status cell
            delegate?.homeViewShowDashPayRegistrationFlow(self)
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        headerView.parentScrollViewDidScroll(scrollView)
    }
}
