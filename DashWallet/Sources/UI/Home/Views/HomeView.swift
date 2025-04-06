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
import Combine

// MARK: - HomeViewDelegate

protocol HomeViewDelegate: AnyObject {
    func homeViewShowTxFilter()
    func homeViewShowSyncingStatus()
    func homeViewShowCoinJoin()
    
#if DASHPAY
    func homeView(_ homeView: HomeView, didUpdateProfile identity: DSIdentity?, unreadNotifications: UInt)
    func homeViewRequestUsername()
    func homeViewEditProfile()
#endif
}

// MARK: - HomeView

final class HomeView: UIView {
    private var cancellableBag = Set<AnyCancellable>()
    weak var delegate: HomeViewDelegate?

    private(set) var headerView: HomeHeaderView!
    let viewModel: HomeViewModel
    #if DASHPAY
    let joinDPViewModel = JoinDashPayViewModel(initialState: .callToAction)
    #endif

    var model: DWHomeProtocol?

    weak var shortcutsDelegate: ShortcutsActionDelegate? {
        get { headerView.shortcutsDelegate }
        set { headerView.shortcutsDelegate = newValue }
    }

    init(frame: CGRect, delegate: HomeViewDelegate?, viewModel: HomeViewModel) {
        self.viewModel = viewModel
        self.delegate = delegate
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = UIColor.dw_secondaryBackground()

        headerView = HomeHeaderView(frame: CGRect.zero, viewModel: viewModel)
        headerView.delegate = self
        
        #if DASHPAY
        let content = HomeViewContent(
            viewModel: self.viewModel,
            joinDPViewModel: self.joinDPViewModel,
            delegate: self.delegate,
            shortcutsDelegate: self.shortcutsDelegate,
            headerView: { UIViewWrapper(uiView: self.headerView) }
        )
        #else
        let content = HomeViewContent(
            viewModel: self.viewModel,
            delegate: self.delegate,
            shortcutsDelegate: self.shortcutsDelegate,
            headerView: { UIViewWrapper(uiView: self.headerView) }
        )
        #endif
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
        joinDPViewModel.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .approved || state == .registered {
                    self?.setIdentity()
                }
            }
            .store(in: &cancellableBag)
        #endif
    }

    // MARK: DWDashPayRegistrationStatusUpdated
    
    #if DASHPAY
    
    private func setIdentity() {
        guard let model = model else { return }
        
        let status = model.dashPayModel.registrationStatus
        let completed = model.dashPayModel.registrationCompleted
        
        if status?.state == .done || completed {
            let identity = model.dashPayModel.identity
            let notificaitonAmount = model.dashPayModel.unreadNotificationsCount
            
            delegate?.homeView(self, didUpdateProfile: identity, unreadNotifications: notificaitonAmount)
        } else {
            delegate?.homeView(self, didUpdateProfile: nil, unreadNotifications: 0)
        }
        
        setNeedsLayout()
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
    #if DASHPAY
    @StateObject var joinDPViewModel: JoinDashPayViewModel
    #endif
    weak var delegate: HomeViewDelegate?
    weak var shortcutsDelegate: ShortcutsActionDelegate?
    @ViewBuilder var headerView: () -> Content
    
    private let topOverscrollSize: CGFloat = 1000 // Fixed value for top overscroll area
    

    var body: some View {
        ZStack {
            ScrollView {
                ZStack { Color.navigationBarColor } // Top overscroll area
                    .frame(height: topOverscrollSize)
                    .padding(EdgeInsets(top: -topOverscrollSize, leading: 0, bottom: 0, trailing: 0))
                
                LazyVStack(pinnedViews: [.sectionHeaders]) {
                    HomeBalanceView {
                        let action = ShortcutAction(type: .localCurrency)
                        shortcutsDelegate?.shortcutsView(didSelectAction: action, sender: nil)
                    }
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .background(Color.dashBlue)
                    .padding(.top, 5)
                    .padding(.bottom, -12)
                    
                    headerView()
                        .frame(height: viewModel.headerHeight)
                    
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
                        JoinDashPayView(
                            viewModel: joinDPViewModel,
                            onTap: { _ in },
                            onActionButton: { state in
                                if state == .approved {
                                    delegate?.homeViewEditProfile()
                                    joinDPViewModel.markAsDismissed()
                                    viewModel.checkJoinDashPay()
                                } else {
                                    // TODO: ? MOCK_DASHPAY if failed, maybe need to call model?.dashPayModel.retry()
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
                            }, onDismissButton: { _ in
                                joinDPViewModel.markAsDismissed()
                                viewModel.checkJoinDashPay()
                            }
                        ).padding(.horizontal, 14)
                         .padding(.bottom, 4)
                    }
                    #endif
                    
                    SyncingHeaderView(onFilterTap: {
                        delegate?.homeViewShowTxFilter()
                    }, onSyncTap: {
                        delegate?.homeViewShowSyncingStatus()
                    })
                    
                    if viewModel.txItems.isEmpty {
                        Text(NSLocalizedString("There are no transactions to display", comment: ""))
                            .font(.caption)
                            .foregroundColor(Color.primary.opacity(0.5))
                            .padding(.top, 20)
                    } else {
                        ForEach(viewModel.txItems) { group in
                            Section(header: SectionHeader(key: group.id, date: group.date)
                                .padding(.bottom, -24)
                            ) {
                                VStack(spacing: 0) {
                                    ForEach(group.items, id: \.id) { txItem in
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
                purposeText: NSLocalizedString("your username", comment: "Usernames"),
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
        .onChange(of: joinDPViewModel.state) { state in
            viewModel.joinDashPayState = state
            viewModel.checkJoinDashPay()
        }
        #endif
        .onAppear {
            viewModel.checkTimeSkew()
            #if DASHPAY
            viewModel.checkJoinDashPay()
            joinDPViewModel.checkUsername()
            #endif
        }
    }

    @ViewBuilder
    private func SectionHeader(key: String, date: Date) -> some View {
        VStack {
            Spacer()
            
            HStack {
                Text(key)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .padding(.leading, 15)
                
                Spacer()
                
                Text(DWDateFormatter.sharedInstance.dayOfWeek(from: date))
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
        case .crowdnode(let set):
            let firstTx = set.transactionMap.values.first
            TransactionPreview(
                title: NSLocalizedString("CrowdNode · Account", comment: "Crowdnode"),
                subtitle: firstTx?.shortTimeString ?? "",
                topText: String(format: NSLocalizedString("%d transaction(s)", comment: "#bc-ignore!"), set.transactionMap.count),
                icon: .custom("tx.item.cn.icon"),
                dashAmount: set.amount
            ) {
                self.selectedTxDataItem = txDataItem
            }
            .frame(height: 80)
    
        case .coinjoin(let set):
            let firstTx = set.transactionMap.values.first
            TransactionPreview(
                title: NSLocalizedString("Mixing Transactions", comment: "CoinJoin"),
                subtitle: firstTx?.shortTimeString ?? "",
                topText: String(format: NSLocalizedString("%d transaction(s)", comment: "#bc-ignore!"), set.transactionMap.count),
                icon: .custom("tx.item.coinjoin.icon"),
                dashAmount: set.amount
            ) {
                self.selectedTxDataItem = txDataItem
            }
            .frame(height: 80)
            
        case .tx(let txItem):
            TransactionPreview(
                title: txItem.stateTitle,
                subtitle: txItem.shortTimeString,
                icon: .custom(txItem.iconName),
                dashAmount: txItem.signedDashAmount,
                overrideFiatAmount: txItem.fiatAmount
            ) {
                self.selectedTxDataItem = txDataItem
            }
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
        case .crowdnode(let set):
            GroupedTransactionsScreen(
                model: set,
                backNavigationRequested: $backNavigationRequested,
                onShowBackButton: { show in
                    showBackButton = show
                }
            )
        case .coinjoin(let set):
            GroupedTransactionsScreen(
                model: set,
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
