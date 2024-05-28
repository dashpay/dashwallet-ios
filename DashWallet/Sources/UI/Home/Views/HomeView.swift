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
import SwiftUI

// MARK: - HomeViewDelegate

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

class HomeViewModel: ObservableObject {
    @Published var txItems: [String: [TransactionListDataItem]] = [:]
    
    func updateItems(items: [String: [TransactionListDataItem]]) {
        self.txItems = items
    }
}

// MARK: - HomeView

final class HomeView: UIView, DWHomeModelUpdatesObserver, DWDPRegistrationErrorRetryDelegate {

    weak var delegate: HomeViewDelegate?

    private(set) var headerView: HomeHeaderView!
    private(set) var syncingHeaderView: SyncingHeaderView!

    // Strong ref to current dataSource to make sure it always exists while tableView uses it
    var currentDataSource: TransactionListDataSource?
    var viewModel: HomeViewModel = HomeViewModel()

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

//        if let tableHeaderView = tableView.tableHeaderView {
//            let headerSize = tableHeaderView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
//            if tableHeaderView.frame.height != headerSize.height {
//                tableHeaderView.frame = CGRect(x: 0.0, y: 0.0, width: headerSize.width, height: headerSize.height)
//                tableView.tableHeaderView = tableHeaderView
//            }
//        }
    }

    private func setupView() {
        backgroundColor = UIColor.dw_secondaryBackground()

        headerView = HomeHeaderView(frame: CGRect.zero)
        headerView.delegate = self
        
        syncingHeaderView = SyncingHeaderView(frame: CGRect.zero)
        syncingHeaderView.delegate = self
        
        let content = TransactionList(
            viewModel: self.viewModel,
            balanceHeader: { UIViewWrapper(uiView: self.headerView) },
            syncingHeader: { UIViewWrapper(uiView: self.syncingHeaderView) }
        )
        let swiftUIController = UIHostingController(rootView: content)
        swiftUIController.view.backgroundColor = UIColor.dw_secondaryBackground()
        
        self.addSubview(swiftUIController.view)
        swiftUIController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            swiftUIController.view.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            swiftUIController.view.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            swiftUIController.view.topAnchor.constraint(equalTo: self.topAnchor),
            swiftUIController.view.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
                
        swiftUIController.didMove(toParent: nil)
        

//        tableView = UITableView(frame: bounds, style: .plain)
//        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//        tableView.tableHeaderView = headerView
//        tableView.backgroundColor = UIColor.dw_secondaryBackground()
//        tableView.dataSource = self
//        tableView.delegate = self
//        tableView.rowHeight = UITableView.automaticDimension
//        tableView.estimatedRowHeight = 74.0
//        tableView.sectionHeaderHeight = UITableView.automaticDimension
//        tableView.estimatedSectionHeaderHeight = 64.0
//        tableView.separatorStyle = .none
//        // NOTE: tableView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: DW_TABBAR_NOTCH, right: 0.0)
//        tableView.addSubview(topOverscrollView)
//        addSubview(tableView)

//        let cellIds = [
//            TxListEmptyTableViewCell.reuseIdentifier,
//            TxListTableViewCell.reuseIdentifier,
//            DWDPRegistrationStatusTableViewCell.dw_reuseIdentifier,
//            DWDPRegistrationErrorTableViewCell.dw_reuseIdentifier,
//            DWDPRegistrationDoneTableViewCell.dw_reuseIdentifier,
//        ]
//        for cellId in cellIds {
//            let nib = UINib(nibName: cellId, bundle: nil)
//            tableView.register(nib, forCellReuseIdentifier: cellId)
//        }

//        let nib = UINib(nibName: "CNCreateAccountCell", bundle: nil)
//        tableView.register(nib, forCellReuseIdentifier: "CNCreateAccountCell")
//        tableView.registerClassforHeaderFooterView(for: SyncingHeaderView.self)
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
        
        self.viewModel.updateItems(items: dataSource._items)

//        if dataSource.isEmpty {
//            tableView.dataSource = self
//        } else {
//            tableView.dataSource = dataSource
//        }
//        tableView.reloadData()

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

struct TxPreviewModel: Identifiable, Equatable {
    var id: String
    var title: String
    var timeFormatted: String
    var dateFormatted: String
    var details: String?
    var icon: IconName
    var dashAmount: String
    var fiatAmount: String
    var date: Date
    
    static func == (lhs: TxPreviewModel, rhs: TxPreviewModel) -> Bool {
        return lhs.id == rhs.id
    }
}

struct TransactionList<Content: View>: View {
    @StateObject var viewModel: HomeViewModel
//    @State private var currentTag: String?
    
    @ViewBuilder var balanceHeader: () -> Content
    @ViewBuilder var syncingHeader: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let topOverscrollSize = geometry.size.height * 1.5
            
            ScrollView {
                ZStack {
                    Color.dashBlue // Top overscroll area
                }
                .frame(height: topOverscrollSize)
                .padding(EdgeInsets(top: -topOverscrollSize, leading: 0, bottom: 0, trailing: 0))
                
                LazyVStack(pinnedViews: [.sectionHeaders]) {
                    balanceHeader()
                        .frame(height: 210)
                    
                    VStack {
                        syncingHeader()
                            .frame(height: 50)
                    }
                    
                    ForEach(viewModel.txItems.keys.sorted(by: { key1, key2 in
                        viewModel.txItems[key1]![0].date > viewModel.txItems[key2]![0].date
                    }), id: \.self) { key in
                        Section(header: Text(key)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ) {
                            ForEach(viewModel.txItems[key]!, id: \.id) { txItem in
                                ZStack {
                                    //                        NavigationLink(destination: TXDetailVCWrapper(tx: tx), tag: tx.txHashHexString, selection: self.$currentTag) {
                                    //                            SwiftUI.EmptyView()
                                    //                        }
                                    //                        .opacity(0)
                                    
                                    TransactionPreviewFrom(txItem: txItem)
                                }
                            }
                        }
                    }
                }
                .padding(EdgeInsets(top: -20, leading: 0, bottom: 0, trailing: 0))
            }
        }
    }
    
    @ViewBuilder
    private func TransactionPreviewFrom(txItem txDataItem: TransactionListDataItem) -> some View {
        switch txDataItem {
        case .crowdnode(let txItems):
            let amount = self.crowdNodeAmount(txItems)
            let sign: String = amount < 0 ? "-" : "+"
            let dashAmount = UInt64(abs(amount))
            let dashAmountStr = sign + abs(self.crowdNodeAmount(txItems)).formattedDashAmount
                            
            TransactionPreview(
                title: NSLocalizedString("CrowdNode Account", comment: "Crowdnode"),
                subtitle: txItems.last?.tx.formattedShortTxTime ?? "",
                details: String(format: NSLocalizedString("%d transaction(s)", comment: "#bc-ignore!"), txItems.count),
                icon: .custom("tx.item.cn.icon"),
                dashAmount: dashAmountStr,
                fiatAmount: self.fiatCrowdNodeAmount(dashAmount: dashAmount)
            ) {
                //                            self.currentTag = tx.txHashHexString
            }
            
        case .tx(let txItem):
            TransactionPreview(
                title: txItem.stateTitle,
                subtitle: txItem.tx.formattedShortTxTime,
                icon: .custom(txItem.direction.iconName),
                dashAmount: txItem.formattedDashAmountWithDirectionalSymbol,
                fiatAmount: txItem.fiatAmount
            ) {
                //                            self.currentTag = tx.txHashHexString
            }
        }
    }
    
    private func crowdNodeAmount(_ transactions: [Transaction]) -> Int64 {
        return transactions.reduce(0) { partialResult, tx in
            var r = partialResult
            let direction = tx.direction

            switch direction {
            case .sent:
                r -= Int64(tx.dashAmount)
            case .received:
                r += Int64(tx.dashAmount)
            default:
                break
            }

            return r
        }
    }
    
    private func fiatCrowdNodeAmount(dashAmount: UInt64) -> String {
        (try? CurrencyExchanger.shared.convertDash(amount: dashAmount.dashAmount, to: App.fiatCurrency).formattedFiatAmount) ??
                    NSLocalizedString("Updating Price", comment: "Updating Price")
    }
}

struct UIViewWrapper: UIViewRepresentable {
    let uiView: UIView!
    
    func makeUIView(context: Context) -> UIView {
        return uiView
    }

    func updateUIView(_ uiView: UIView, context: Context) { }
}
