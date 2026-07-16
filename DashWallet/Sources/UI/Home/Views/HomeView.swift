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
import DashUIKit

// MARK: - HomeViewDelegate

protocol HomeViewDelegate: AnyObject {
    func homeViewShowSyncingStatus()
    func homeViewShowInternalTransfer(direction: InternalTransferDirection, source: InternalTransferSource)

#if DASHPAY
    func homeView(_ homeView: HomeView, didUpdateProfile identity: DSBlockchainIdentity?, unreadNotifications: UInt)
    func homeViewRequestUsername()
    func homeViewClaimInvitation()
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
            let identity = model.dashPayModel.blockchainIdentity
            let notificationAmount = model.dashPayModel.unreadNotificationsCount
            
            delegate?.homeView(self, didUpdateProfile: identity, unreadNotifications: notificationAmount)
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

struct HomeViewContent<Content: View>: View {
    @State private var selectedTxDataItem: TransactionListDataItem? = nil
    @State private var showFilterDialog: Bool = false
    @State private var shouldShowJoinDashPayInfo: Bool = false
    @State private var navigateToDashPayFlow: Bool = false
    @State private var navigateToClaimInvitation: Bool = false
    @State private var giftCardTxId: Data? = nil
    @State private var pendingShieldedRecovery: Transaction? = nil


    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject private var balanceModel = BalanceModel()
    #if DASHPAY
    @ObservedObject var joinDPViewModel: JoinDashPayViewModel
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
                    HomeBalanceView(
                        viewModel: balanceModel,
                        onLongPress: {
                            let action = ShortcutAction(type: .localCurrency)
                            shortcutsDelegate?.shortcutsView(didSelectAction: action, sender: nil)
                        },
                        onReceive: {
                            let action = ShortcutAction(type: .receive)
                            shortcutsDelegate?.shortcutsView(didSelectAction: action, sender: nil)
                        },
                        onSend: {
                            let action = ShortcutAction(type: .send)
                            shortcutsDelegate?.shortcutsView(didSelectAction: action, sender: nil)
                        },
                        onTransfer: { direction, source in
                            delegate?.homeViewShowInternalTransfer(direction: direction, source: source)
                        })
                    .frame(maxWidth: .infinity)
                    .background(Color.navigationBarColor)
                    .padding(.top, 5)
                    .padding(.bottom, -12)

                    VStack(spacing: 0) {
                        Color.navigationBarColor
                            .frame(height: 16)

                        headerView()
                            .frame(height: viewModel.headerHeight)
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
                                    if viewModel.shouldShowDashPayInfo {
                                        UsernamePrefs.shared.joinDashPayInfoShown = true
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
                        showFilterDialog = true
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
        .sheet(item: $giftCardTxId) { txId in
            GiftCardDetailsSheet(txId: txId)
        }
        .sheet(item: $pendingShieldedRecovery) { tx in
            ShieldedRecoverySheet(transaction: tx) {
                pendingShieldedRecovery = nil
            }
        }
        .sheet(isPresented: $showFilterDialog) {
            let dialog = TransactionFilterDialog(
                selectedFilters: $viewModel.selectedFilters,
                showRewards: viewModel.hasRewardsHistory,
                showMasternode: viewModel.hasMasternodeHistory
            )

            if #available(iOS 16.0, *) {
                dialog.presentationDetents([.height(TransactionFilterDialog.height(showRewards: viewModel.hasRewardsHistory, showMasternode: viewModel.hasMasternodeHistory))])
            } else {
                dialog
            }
        }
        #if DASHPAY
        .sheet(isPresented: $shouldShowJoinDashPayInfo, onDismiss: {
            if navigateToDashPayFlow {
                navigateToDashPayFlow = false
                delegate?.homeViewRequestUsername()
            }
            if navigateToClaimInvitation {
                navigateToClaimInvitation = false
                delegate?.homeViewClaimInvitation()
            }
        }) {
            let joinDashPayDialog = JoinDashPayInfoDialog(
                action: {
                    navigateToDashPayFlow = true
                },
                onClaimInvitation: {
                    navigateToClaimInvitation = true
                })
            
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
    
    /// Chooses the transaction row icons. Gift cards without a loaded merchant logo fall back to the
    /// gift card icon instead of the generic send arrow. Reward (masternode/mining) rewards use the
    /// mining icon, since a reward's direction is `.received` and would otherwise show the receive arrow.
    private func transactionRowIcons(txItem: Transaction, metadata: TxRowMetadata?) -> (primary: IconName, secondary: IconName?) {
        if let merchantIcon = metadata?.icon {
            return (.image(merchantIcon, effect: .rounded), metadata?.secondaryIcon ?? .custom(txItem.iconName))
        }

        // Swap and Coinbase rows carry their icon as a name (convert / coinbase), not a bitmap.
        if let iconName = metadata?.iconName {
            return (iconName, metadata?.secondaryIcon)
        }

        if GiftCardMetadataProvider.shared.availableMetadata[txItem.txHashData] != nil {
            return (.custom("image.explore.dash.wts.payment.gift-card"), nil)
        }

        if txItem.transactionType == .reward {
            return (.custom("transaction-mining", bundle: .dashUIKit), nil)
        }

        return (.custom(txItem.iconName), nil)
    }

    @ViewBuilder
    private func TransactionPreviewFrom(
        txItem txDataItem: TransactionListDataItem
    ) -> some View {
        switch txDataItem {
        case .crowdnode(let set):
            let firstTx = set.transactionMap.values.first
            DashUIKit.TransactionView(
                icon: IconName.custom("tx.item.cn.icon").dashIconSource,
                topText: String.localizedStringWithFormat(NSLocalizedString("%d transaction(s)", comment: "#bc-ignore!"), set.transactionMap.count),
                title: NSLocalizedString("CrowdNode · Account", comment: "Crowdnode"),
                subtitle: firstTx?.shortTimeString ?? "",
                dashAmount: set.amount,
                amountSign: .none
            )
            .onTapGesture { self.selectedTxDataItem = txDataItem }
            .frame(height: 80)

        case .coinjoin(let set):
            let firstTx = set.transactionMap.values.first
            DashUIKit.TransactionView(
                icon: IconName.custom("tx.item.coinjoin.icon").dashIconSource,
                topText: String.localizedStringWithFormat(NSLocalizedString("%d transaction(s)", comment: "#bc-ignore!"), set.transactionMap.count),
                title: NSLocalizedString("Mixing Transactions", comment: "CoinJoin"),
                subtitle: firstTx?.shortTimeString ?? "",
                dashAmount: set.amount,
                amountSign: .none
            )
            .onTapGesture { self.selectedTxDataItem = txDataItem }
            .frame(height: 80)

        case .coinjoinWithdrawal(let set):
            let firstTx = set.transactionMap.values.first
            TransactionPreview(
                title: NSLocalizedString("CoinJoin Withdrawals", comment: "CoinJoin"),
                subtitle: firstTx?.shortTimeString ?? "",
                topText: String.localizedStringWithFormat(NSLocalizedString("%d transaction(s)", comment: "#bc-ignore!"), set.transactionMap.count),
                icon: .custom("tx.item.internal.icon"),
                dashAmount: set.amount
            ) {
                self.selectedTxDataItem = txDataItem
            }
            .frame(height: 80)
            
        case .tx(let txItem, let metadata):
            let icons = transactionRowIcons(txItem: txItem, metadata: metadata)

            DashUIKit.TransactionView(
                // A merchant logo is a bitmap and goes through `iconView` so it can be clipped to a
                // circle; every other row resolves to a named icon.
                icon: metadata?.icon == nil ? icons.primary.dashIconSource : nil,
                iconView: metadata?.icon.map {
                    AnyView(Image(uiImage: $0).resizable().scaledToFit().clipShape(Circle()))
                },
                secondaryIcon: icons.secondary?.dashIconSource,
                title: metadata?.title ?? txItem.stateTitle,
                subtitle: txItem.shortTimeString,
                details: txItem.isPendingShieldedTransfer
                    ? NSLocalizedString("Pending — tap to finish", comment: "InternalTransfer recovery")
                    : (metadata?.details?.isEmpty == false ? metadata?.details : nil),
                dashAmount: txItem.signedDashAmount,
                amountSign: .always,
                fiat: txItem.fiatAmount,
                trailingStatusText: txItem.state == .locked ? NSLocalizedString("Locked", comment: "Transaction state: coinbase reward locked until 100 confirmations") : nil
            ) {
                // A stuck "to Shielded" transfer opens the recovery sheet
                // instead of the read-only detail/gift-card sheets.
                if txItem.isPendingShieldedTransfer {
                    self.pendingShieldedRecovery = txItem
                } else if GiftCardMetadataProvider.shared.availableMetadata[txItem.txHashData] != nil {
                    // Check if this is a gift card transaction
                    self.giftCardTxId = txItem.txHashData
                } else {
                    self.selectedTxDataItem = txDataItem
                }
            }
            .frame(minHeight: 66)
        }
    }
}

struct GiftCardDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let txId: Data
    @State private var showBackButton: Bool = false
    @State private var backNavigationRequested: Bool = false
    @State private var selectedCardIndex: Int? = nil
    @State private var txDetailRoute: TxDetailRoute? = nil
    @StateObject private var viewModel: GiftCardDetailsViewModel

    init(txId: Data) {
        self.txId = txId
        _viewModel = StateObject(wrappedValue: GiftCardDetailsViewModel(txId: txId))
    }
    
    var body: some View {
        let showsTxDetailRoute = txDetailRoute != nil
        let dialog = BottomSheet(
            showBackButton: $showBackButton,
            onBackButtonPressed: {
                handleBackNavigation()
            },
            fillsHeight: showsTxDetailRoute
        ) {
            if let txDetailRoute {
                TXDetailVCWrapper(
                    tx: txDetailRoute.tx,
                    navigateBack: $backNavigationRequested,
                    onDismissed: {
                        showBackButton = shouldShowBackButton
                    }
                )
            } else if let selectedCardIndex {
                GiftCardDetailsView(
                    viewModel: viewModel,
                    selectedCardIndex: selectedCardIndex,
                    backNavigationRequested: $backNavigationRequested,
                    onShowBackButton: { show in
                        showBackButton = show
                    },
                    onOpenTransaction: { transaction in
                        txDetailRoute = TxDetailRoute(
                            tx: transaction,
                            selectedCardIndex: selectedCardIndex
                        )
                        showBackButton = true
                    }
                )
            } else {
                GiftCardPurchaseSelectionSheet(
                    merchantIcon: viewModel.uiState.merchantIcon,
                    merchantName: viewModel.uiState.merchantName,
                    provider: viewModel.uiState.provider,
                    cards: viewModel.uiState.cards,
                    isLoadingCardDetails: viewModel.uiState.isLoadingCardDetails,
                    hasBeenPollingForLongTime: viewModel.uiState.hasBeenPollingForLongTime,
                    onSelectCard: { index in
                        selectedCardIndex = index
                        showBackButton = true
                    }
                )
            }
        }

        Group {
            if #available(iOS 16.4, *) {
                if showsTxDetailRoute {
                    dialog
                        .presentationBackground(Color.primaryBackground)
                        .presentationDetents([.large])
                        .presentationCornerRadius(32)
                        .presentationDragIndicator(.hidden)
                } else {
                    dialog
                        .presentationBackground(Color.primaryBackground)
                        .selfSizingSheet(fallback: calculatedSelectionSheetHeight)
                        .presentationCornerRadius(32)
                        .presentationDragIndicator(.hidden)
                }
            } else if #available(iOS 16.0, *) {
                if showsTxDetailRoute {
                    dialog
                        .presentationDetents([.large])
                } else {
                    dialog
                        .selfSizingSheet(fallback: calculatedSelectionSheetHeight)
                }
            } else {
                dialog
            }
        }
        .background(Color.primaryBackground)
        .onAppear {
            viewModel.startObserving()
            showBackButton = shouldShowBackButton
        }
        .onDisappear {
            viewModel.stopObserving()
        }
        .onChange(of: selectedCardIndex) { _ in
            showBackButton = shouldShowBackButton
        }
        .onChange(of: txDetailRoute?.id) { _ in
            showBackButton = shouldShowBackButton
        }
        .onChange(of: viewModel.uiState.cards.count) { cardsCount in
            if selectedCardIndex == nil, txDetailRoute == nil, cardsCount == 1 {
                selectedCardIndex = 0
            }
            showBackButton = shouldShowBackButton
        }
        .onChange(of: backNavigationRequested) { requested in
            guard requested else { return }
            backNavigationRequested = false
            handleBackNavigation()
        }
    }

    private var calculatedSelectionSheetHeight: CGFloat {
        // Merchant header + cards/loading + provider + paddings + bottom safe area.
        let baseHeight: CGFloat = 250
        if viewModel.uiState.cards.isEmpty {
            return baseHeight + 120
        }

        let rowHeight: CGFloat = 64
        let dividerHeight: CGFloat = 1
        let cardsCount = CGFloat(viewModel.uiState.cards.count)
        let listHeight = cardsCount * rowHeight + max(0, cardsCount - 1) * dividerHeight
        let cappedListHeight = min(listHeight, 5 * rowHeight + 4 * dividerHeight)

        return baseHeight + cappedListHeight
    }

    private var shouldShowBackButton: Bool {
        txDetailRoute != nil
    }

    private func handleBackNavigation() {
        if let txDetailRoute {
            selectedCardIndex = txDetailRoute.selectedCardIndex
            self.txDetailRoute = nil
            return
        }

        if selectedCardIndex != nil {
            if viewModel.uiState.cards.count > 1 {
                selectedCardIndex = nil
            } else {
                dismiss()
            }
            return
        }

        dismiss()
    }
}

private struct TxDetailRoute: Identifiable {
    let id = UUID()
    let tx: Transaction
    let selectedCardIndex: Int?
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
        case .coinjoinWithdrawal(let set):
            GroupedTransactionsScreen(
                model: set,
                backNavigationRequested: $backNavigationRequested,
                onShowBackButton: { show in
                    showBackButton = show
                }
            )
        case .tx(let txItem, _):
            TXDetailVCWrapper(tx: txItem, navigateBack: $backNavigationRequested)
        }
    }
}

extension Data: Identifiable {
    public var id: String {
        return self.base64EncodedString()
    }
}
