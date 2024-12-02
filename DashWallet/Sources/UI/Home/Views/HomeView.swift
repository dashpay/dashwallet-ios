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
    func homeViewShowCoinJoin()
    func homeView(_ homeView: HomeView, showReclassifyYourTransactionsFlowWithTransaction transaction: DSTransaction)
    
#if DASHPAY
    func homeView(_ homeView: HomeView, didUpdateProfile identity: DSBlockchainIdentity?, unreadNotifications: UInt)
    func homeViewRequestUsername()
#endif
}

// MARK: - HomeView

final class HomeView: UIView, DWHomeModelUpdatesObserver {
    weak var delegate: HomeViewDelegate?

    private(set) var headerView: HomeHeaderView!
    private(set) var syncingHeaderView: SyncingHeaderView!
    let viewModel = HomeViewModel.shared

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
    
    init(frame: CGRect, delegate: HomeViewDelegate?) {
        super.init(frame: frame)
        self.delegate = delegate
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

    private func setupView() {
        backgroundColor = UIColor.dw_secondaryBackground()

        headerView = HomeHeaderView(frame: CGRect.zero)
        headerView.delegate = self
        
        syncingHeaderView = SyncingHeaderView(frame: CGRect.zero)
        syncingHeaderView.delegate = self
        
        let content = HomeViewContent(
            viewModel: self.viewModel,
            delegate: self.delegate,
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
        configureObservers()
    }
    
    private func configureObservers() {
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

    func homeModel(_ model: any DWHomeProtocol, didUpdate dataSource: [DSTransaction], shouldAnimate: Bool) {
        self.viewModel.reloadShortcuts()
        headerView.reloadBalance()
    }

    func homeModel(_ model: DWHomeProtocol, didReceiveNewIncomingTransaction transaction: DSTransaction) {
        delegate?.homeView(self, showReclassifyYourTransactionsFlowWithTransaction: transaction)
    }

    func homeModelDidChangeInnerModels(_ model: DWHomeProtocol) {
        headerView.reloadBalance()
        viewModel.reloadShortcuts()
    }

    func homeModelWant(toReloadShortcuts model: DWHomeProtocol) {
        viewModel.reloadShortcuts()
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

    func registrationErrorRetryAction() { // TODO
        if model?.dashPayModel.canRetry() ?? false {
            model?.dashPayModel.retry()
        } else {
            
        }
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
        headerView.isVotingViewHidden = true
//        viewModel.showJoinDashpay = !dpInfoHidden
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
//        viewModel.showJoinDashpay = false
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

struct HomeViewContent<Content: View>: View {
    @State private var selectedTxDataItem: TransactionListDataItem? = nil
    @State private var shouldShowMixDialog: Bool = false
    @State private var shouldShowJoinDashPayInfo: Bool = false
    @State private var navigateToDashPayFlow: Bool = false
    @State private var navigateToCoinJoin: Bool = false
    @State private var skipToCreateUsername: Bool = false
    
    @StateObject var viewModel: HomeViewModel
    weak var delegate: HomeViewDelegate?
    @ViewBuilder var balanceHeader: () -> Content
    @ViewBuilder var syncingHeader: () -> Content
    
    private let topOverscrollSize: CGFloat = 1000 // Fixed value for top overscroll area

    var body: some View {
        ZStack {
            ScrollView {
                ZStack { Color.navigationBarColor } // Top overscroll area
                    .frame(height: topOverscrollSize)
                    .padding(EdgeInsets(top: -topOverscrollSize, leading: 0, bottom: 0, trailing: 0))
                
                LazyVStack(pinnedViews: [.sectionHeaders]) {
                    balanceHeader()
                        .frame(height: viewModel.balanceHeaderHeight)
                    
                    if viewModel.coinJoinItem.isOn {
                        CoinJoinProgressView(
                            state: viewModel.coinJoinItem.state,
                            progress: viewModel.coinJoinItem.progress,
                            mixed: viewModel.coinJoinItem.mixed,
                            total: viewModel.coinJoinItem.total
                        )
                        .padding(.horizontal, 15)
                        .id(viewModel.coinJoinItem.id)
                        .onTapGesture { delegate?.homeViewShowCoinJoin() }
                    }

                    #if DASHPAY
                    if viewModel.showJoinDashpay {
                        JoinDashPayView {
                            if viewModel.shouldShowMixDashDialog {
                                self.navigateToDashPayFlow = false
                                self.navigateToCoinJoin = false
                                self.shouldShowMixDialog = true
                            } else if viewModel.shouldShowDashPayInfo {
                                self.shouldShowJoinDashPayInfo = true
                            } else {
                                delegate?.homeViewRequestUsername()
                            }
                        }
                    }
                    #endif
                    
                    syncingHeader()
                        .frame(height: 50)
                    
                    if viewModel.txItems.isEmpty {
                        Text(NSLocalizedString("There are no transactions to display", comment: ""))
                            .font(.caption)
                            .foregroundColor(Color.primary.opacity(0.5))
                            .padding(.top, 20)
                    } else {
                        ForEach(viewModel.txItems, id: \.0.key) { key, value in
                            Section(header: SectionHeader(key)
                                .padding(.bottom, -24)
                            ) {
                                VStack(spacing: 0) {
                                    ForEach(value, id: \.id) { txItem in
                                        TransactionPreviewFrom(txItem: txItem)
                                            .padding(.horizontal, 5)
                                    }
                                }
                                .padding(.bottom, 4)
                                .background(Color.secondaryBackground)
                                .clipShape(RoundedShape(corners: [.bottomLeft, .bottomRight], radii: 10))
                                .padding(15)
                                .shadow(color: .shadow, radius: 10, x: 0, y: 5)
                            }
                        }
                    }
                }
                .padding(EdgeInsets(top: -20, leading: 0, bottom: 0, trailing: 0))
            }
        }
        .sheet(item: $selectedTxDataItem) { item in
            TransactionDetailsSheet(item: item)
        }
        #if DASHPAY
        .sheet(isPresented: $shouldShowMixDialog, onDismiss: {
            viewModel.shouldShowMixDashDialog = false
            finishMixDialogNavigation()
        }) {
            let mixDashDialog = MixDashDialog(
                positiveAction: { self.navigateToCoinJoin = true },
                negativeAction: {
                    if UsernamePrefs.shared.joinDashPayInfoShown {
                        skipToCreateUsername = true
                    } else {
                        UsernamePrefs.shared.joinDashPayInfoShown = true
                        navigateToDashPayFlow = true
                    }
                }
            )

            if #available(iOS 16.0, *) {
                mixDashDialog.presentationDetents([.height(260)])
            } else {
                mixDashDialog
            }
        }
        .sheet(isPresented: $shouldShowJoinDashPayInfo, onDismiss: {
            if navigateToDashPayFlow {
                navigateToDashPayFlow = false
                delegate?.homeViewRequestUsername()
            }
        }) {
            let joinDashPayDialog = JoinDashPayInfoDialog {
                navigateToDashPayFlow = true
            }
            
            if #available(iOS 16.0, *) {
                joinDashPayDialog.presentationDetents([.height(600)])
            } else {
                joinDashPayDialog
            }
        }
        #endif
        .onAppear {
            viewModel.checkTimeSkew()
        }
    }

    @ViewBuilder
    private func SectionHeader(_ dateKey: DateKey) -> some View {
        VStack {
            Spacer()
            
            HStack {
                Text(dateKey.key)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .padding(.leading, 15)
                
                Spacer()
                
                Text(DWDateFormatter.sharedInstance.dayOfWeek(from: dateKey.date))
                    .font(.footnote)
                    .foregroundStyle(Color.tertiaryText)
                    .padding(.trailing, 15)
            }
            .padding(.bottom, 6)
        }
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(Color.secondaryBackground)
        .clipShape(RoundedShape(corners: [.topLeft, .topRight], radii: 10))
        .padding(.horizontal, 15)
    }
    
    @ViewBuilder
    private func TransactionPreviewFrom(
        txItem txDataItem: TransactionListDataItem
    ) -> some View {
        switch txDataItem {
        case .crowdnode(let txItems):
            TransactionPreview(
                title: NSLocalizedString("CrowdNode · Account", comment: "Crowdnode"),
                subtitle: txItems.last?.shortTimeString ?? "",
                topText: String(format: NSLocalizedString("%d transaction(s)", comment: "#bc-ignore!"), txItems.count),
                icon: .custom("tx.item.cn.icon"),
                dashAmount: self.crowdNodeAmount(txItems)
            ) {
                self.selectedTxDataItem = txDataItem
            }
            .frame(height: 80)
            
        case .tx(let txItem):
            TransactionPreview(
                title: txItem.stateTitle,
                subtitle: txItem.shortTimeString,
                icon: .custom(txItem.direction.iconName),
                dashAmount: txItem.signedDashAmount,
                overrideFiatAmount: txItem.fiatAmount
            ) {
                self.selectedTxDataItem = txDataItem
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
    
    #if DASHPAY
    private func finishMixDialogNavigation() {
        if navigateToDashPayFlow {
            navigateToDashPayFlow = false
            shouldShowJoinDashPayInfo = true
        } else if navigateToCoinJoin {
            navigateToCoinJoin = false
            delegate?.homeViewShowCoinJoin()
        } else if skipToCreateUsername {
            skipToCreateUsername = false
            delegate?.homeViewRequestUsername()
        }
    }
    #endif
}

struct TransactionDetailsSheet: View {
    @State private var showBackButton: Bool = false
    @State private var backNavigationRequested: Bool = false
    
    var item: TransactionListDataItem
    
    var body: some View {
        BottomSheet(showBackButton: $showBackButton, onBackButtonPressed: {
            backNavigationRequested = true
        }) {
            TxDetailsDestination(from: item)
        }
        .background(Color.primaryBackground)
    }
    
    @ViewBuilder
    private func TxDetailsDestination(
        from txDataItem: TransactionListDataItem
    ) -> some View {
        switch txDataItem {
        case .crowdnode(let txItems):
            CrowdNodeGroupedTransactionsScreen(
                model: CNCreateAccountTxDetailsModel(transactions: txItems),
                backNavigationRequested: $backNavigationRequested,
                onShowBackButton: { show in
                    showBackButton = show
                }
            )
        case .tx(let txItem):
            TXDetailVCWrapper(tx: txItem, navigateBack: $backNavigationRequested)
        }
    }
}

