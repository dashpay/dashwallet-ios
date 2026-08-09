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
    /// Opens the payments landing on the Receive tab with `network`
    /// preselected — the balance rows' receive arrows land on the QR for
    /// the balance the user tapped, with the Internal tab one tap away.
    func homeViewShowReceive(network: ChainNetwork)
    /// The mirror for the balance rows' send (out) arrows: the send sheet
    /// (Send ↔ Internal) pinned to `network` as the source.
    func homeViewShowSend(network: ChainNetwork)
    /// Scroll-derived chrome: false at the top of the feed (bar hidden,
    /// balance header owns the space), true once the user scrolls down.
    func homeViewDidChangeTopBarVisibility(shouldShow: Bool)

#if DASHPAY
    func homeView(_ homeView: HomeView, didUpdateProfileWithUnreadNotifications unreadNotifications: UInt)
    func homeViewRequestUsername()
    func homeViewClaimInvitation()
    func homeViewEditProfile()
    /// Opens the notifications list (header nav-bar bell).
    func homeViewShowNotifications()
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
        
        // Resolve the shortcuts delegate lazily (through the computed property)
        // rather than passing its current value: it is still nil here —
        // HomeViewController assigns it right after this init returns.
        let performShortcut: (ShortcutAction) -> Void = { [weak self] action in
            self?.shortcutsDelegate?.shortcutsView(didSelectAction: action, sender: nil)
        }
        #if DASHPAY
        let content = HomeViewContent(
            viewModel: self.viewModel,
            joinDPViewModel: self.joinDPViewModel,
            delegate: self.delegate,
            performShortcut: performShortcut,
            headerView: { UIViewWrapper(uiView: self.headerView) }
        )
        #else
        let content = HomeViewContent(
            viewModel: self.viewModel,
            delegate: self.delegate,
            performShortcut: performShortcut,
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

        // Identity recovery completes after Home is already on screen. Re-read
        // the recovered owned/pending username on the canonical event instead
        // of waiting for another Home appearance or app relaunch.
        NotificationCenter.default.publisher(for: .DWDashPayRegistrationStatusUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.joinDPViewModel.checkUsername()
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
            let notificationAmount = model.dashPayModel.unreadNotificationsCount

            delegate?.homeView(self, didUpdateProfileWithUnreadNotifications: notificationAmount)
        } else {
            delegate?.homeView(self, didUpdateProfileWithUnreadNotifications: 0)
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

/// Scroll thresholds (pt scrolled down) for showing/hiding the
/// navigation bar. Two values (hysteresis) so the bar doesn't flicker
/// when the user rests exactly on the boundary. File-scoped because
/// `HomeViewContent` is generic (no static stored properties).
private let kTopBarShowThreshold: CGFloat = 100
private let kTopBarHideThreshold: CGFloat = 60

/// Scroll offset of the home feed's top sentinel in the scroll view's
/// coordinate space — feeds the collapsing top bar.
private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Total scrollable-content height, measured off the same sentinel as
/// `HomeScrollOffsetKey` — feeds the short-feed reveal fallback.
private struct HomeContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The `ScrollView`'s own viewport height — compared against
/// `HomeContentHeightKey` to detect a feed too short to cross
/// `kTopBarShowThreshold` by scrolling.
private struct HomeViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
    /// Balance whose explainer sheet is up (tap on a breakdown row's body).
    @State private var balanceInfoNetwork: ChainNetwork? = nil

    #if DASHPAY
    /// Persistent username-row state (SB-11) — read from the same
    /// app-owned identity snapshot the nav-bar avatar uses. Nil username
    /// hides the row (no identity registered).
    @State private var currentUsername: String? = nil
    @State private var currentAvatarURL: String? = nil
    @State private var currentIdentitySeed: Data = Data()
    /// Drives the header bell's unread state. Read from the same contacts
    /// bridge that feeds the UIKit nav-bar bell, refreshed on the contacts
    /// snapshot-change notification so an incoming request lights it live.
    @State private var currentHasNotifications: Bool = false
    #endif

    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject private var balanceModel = BalanceModel()
    #if DASHPAY
    @ObservedObject var joinDPViewModel: JoinDashPayViewModel
    #endif
    weak var delegate: HomeViewDelegate?
    /// Resolves the shortcuts delegate at tap time. A stored weak delegate
    /// captured here would be permanently nil: this struct is built inside
    /// `HomeView.init`, before `HomeViewController.loadView` assigns
    /// `homeView.shortcutsDelegate` (which forwards into the header view).
    var performShortcut: (ShortcutAction) -> Void = { _ in }
    @ViewBuilder var headerView: () -> Content
    
    private let topOverscrollSize: CGFloat = 1000 // Fixed value for top overscroll area

    @State private var isTopBarShown = false
    /// Measured scrollable-content height vs. the ScrollView's own viewport
    /// height — a short feed can never scroll `kTopBarShowThreshold` pt, so
    /// without this the nav-bar avatar/username row would be permanently
    /// stranded behind an unreachable reveal gesture.
    @State private var scrollContentHeight: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0

    var body: some View {
        ZStack {
            ScrollView {
                ZStack { Color.navigationBarColor } // Top overscroll area
                    .frame(height: topOverscrollSize)
                    .padding(EdgeInsets(top: -topOverscrollSize, leading: 0, bottom: 0, trailing: 0))

                LazyVStack(pinnedViews: [.sectionHeaders]) {
                    // The header nav bar (username · Dash logo · notifications)
                    // lives inside HomeBalanceView so the registered-username
                    // entry point (SB-11) sits in the always-visible balance
                    // header — reachable without scrolling the feed.
                    HomeBalanceView(
                        viewModel: balanceModel,
                        onLongPress: {
                            performShortcut(ShortcutAction(type: .localCurrency))
                        },
                        onReceive: { network in
                            delegate?.homeViewShowReceive(network: network)
                        },
                        onSend: { network in
                            delegate?.homeViewShowSend(network: network)
                        },
                        onInfo: { network in
                            balanceInfoNetwork = network
                        },
                        username: navUsername,
                        avatarURL: navAvatarURL,
                        identitySeed: navIdentitySeed,
                        hasUnreadNotifications: navHasUnreadNotifications,
                        onProfileTap: { openProfileFromNav() },
                        onNotificationsTap: { openNotificationsFromNav() })
                    .frame(maxWidth: .infinity)
                    .background(Color.navigationBarColor)
                    .padding(.top, 5)
                    .padding(.bottom, -12)
                    .sheet(item: $balanceInfoNetwork) { network in
                        BalanceInfoSheet(network: network) {
                            balanceInfoNetwork = nil
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    }

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
                                    // Always open the info dialog. It carries the
                                    // only "Have an invitation?" entry in the app,
                                    // so latching it to the first-ever tap left an
                                    // invited user with no way to reach the redeem
                                    // path once they had dismissed it — which is
                                    // every user whose invitation arrived after
                                    // they first looked at DashPay.
                                    self.shouldShowJoinDashPayInfo = true
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
                        // An empty feed means "nothing yet" only once the first
                        // load has finished; before that it just means the
                        // reload is still running, so show progress rather than
                        // telling the user they have no transactions.
                        if viewModel.hasLoadedInitialTxItems {
                            Text(NSLocalizedString("There are no transactions to display", comment: ""))
                                .font(.caption)
                                .foregroundColor(Color.primary.opacity(0.5))
                                .padding(.top, 20)
                        } else {
                            HStack(spacing: 10) {
                                SwiftUI.ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())

                                Text(NSLocalizedString("Loading transactions", comment: "Home"))
                                    .font(.caption)
                                    .foregroundColor(Color.primary.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                        }
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
                                .background(Color.dash.secondaryBackground)
                                .clipShape(RoundedShape(corners: [.bottomLeft, .bottomRight], radii: 10))
                                .padding(15)
                                .shadow(color: .shadow, radius: 10, x: 0, y: 5)
                            }
                        }
                    }
                }
                .padding(EdgeInsets(top: -20, leading: 0, bottom: 0, trailing: 0))
                // Scroll sentinel as a background so it adds no layout
                // (a zero-height sibling would still get the scroll
                // content's implicit spacing and open a light gap in the
                // blue header). minY is ~0 at rest and goes negative as
                // the user scrolls down; drives the collapsing top bar.
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: HomeScrollOffsetKey.self,
                                value: proxy.frame(in: .named("homeScroll")).minY)
                            .preference(key: HomeContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .coordinateSpace(name: "homeScroll")
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HomeViewportHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(HomeContentHeightKey.self) { scrollContentHeight = $0 }
            .onPreferenceChange(HomeViewportHeightKey.self) { scrollViewportHeight = $0 }
            .onPreferenceChange(HomeScrollOffsetKey.self) { minY in
                // A feed shorter than the viewport can never be scrolled
                // `kTopBarShowThreshold` pt, so the reveal gesture below
                // would never fire — keep the bar shown so the avatar/
                // username row stays reachable instead of stranded.
                // `scrollViewportHeight == 0` means the viewport hasn't
                // reported its size yet (first layout pass) — wait for a
                // real measurement rather than flash the bar on a feed
                // that's actually long enough to scroll normally.
                if scrollViewportHeight > 0,
                   scrollContentHeight - scrollViewportHeight < kTopBarShowThreshold {
                    if !isTopBarShown {
                        isTopBarShown = true
                        delegate?.homeViewDidChangeTopBarVisibility(shouldShow: true)
                    }
                    return
                }

                // minY == 0 at rest; more negative the further down the
                // user has scrolled.
                let scrolled = -minY
                if isTopBarShown {
                    if scrolled < kTopBarHideThreshold {
                        isTopBarShown = false
                        delegate?.homeViewDidChangeTopBarVisibility(shouldShow: false)
                    }
                } else if scrolled > kTopBarShowThreshold {
                    isTopBarShown = true
                    delegate?.homeViewDidChangeTopBarVisibility(shouldShow: true)
                }
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
        .sheet(isPresented: $viewModel.showCoinJoinMoveFundsSheet) {
            CoinJoinMoveFundsSheet(amountDuffs: viewModel.coinJoinSweepAmountDuffs) {
                viewModel.showCoinJoinMoveFundsSheet = false
            }
            .presentationDetents([.medium, .large])
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
        #if DASHPAY
        .onReceive(NotificationCenter.default.publisher(for: .DWDashPayRegistrationStatusUpdated)) { _ in
            refreshUsernameRow()
        }
        // Live-refresh the header bell when the contacts snapshot changes
        // (a new incoming request / established contact), so unread lights
        // up without leaving Home.
        .onReceive(NotificationCenter.default.publisher(for: SwiftDashSDKContactsService.contactsDidChangeNotification)) { _ in
            refreshUsernameRow()
        }
        #endif
        .onAppear {
            viewModel.checkTimeSkew()
            #if DASHPAY
            viewModel.checkJoinDashPay()
            joinDPViewModel.checkUsername()
            refreshUsernameRow()
            #endif
        }
    }

    #if DASHPAY
    /// Refresh the persistent username row from the app-owned identity
    /// snapshot — the same source `HomeViewController.refreshIdentityAvatar()`
    /// reads for the nav-bar avatar, so both surfaces always agree.
    private func refreshUsernameRow() {
        let info = DWCurrentUserIdentityInfo.shared
        currentUsername = info.hasIdentity ? info.username : nil
        currentAvatarURL = info.avatarURL
        currentIdentitySeed = info.identityId ?? Data()
        currentHasNotifications = SwiftDashSDKContactsService.shared.unreadNotificationCount > 0
    }
    #endif

    // Non-`#if`-gated bridges so the (config-agnostic) HomeBalanceView call
    // site stays clean: the header nav-bar inputs and actions resolve to the
    // DashPay identity state when compiled with DASHPAY, and to inert
    // defaults otherwise.
    private var navUsername: String? {
        #if DASHPAY
        return currentUsername
        #else
        return nil
        #endif
    }

    private var navAvatarURL: String? {
        #if DASHPAY
        return currentAvatarURL
        #else
        return nil
        #endif
    }

    private var navIdentitySeed: Data {
        #if DASHPAY
        return currentIdentitySeed
        #else
        return Data()
        #endif
    }

    private var navHasUnreadNotifications: Bool {
        #if DASHPAY
        return currentHasNotifications
        #else
        return false
        #endif
    }

    private func openProfileFromNav() {
        #if DASHPAY
        delegate?.homeViewEditProfile()
        #endif
    }

    private func openNotificationsFromNav() {
        #if DASHPAY
        delegate?.homeViewShowNotifications()
        #endif
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

                // The unknown-date group (restored shielded history with no
                // recoverable date) carries the `.distantPast` sentinel — a
                // weekday for it would be fabricated.
                if date != .distantPast {
                    Text(DWDateFormatter.sharedInstance.dayOfWeek(from: date))
                        .font(.footnote)
                        .foregroundStyle(Color.dash.tertiaryText)
                        .padding(.trailing, 15)
                }
            }
            .padding(.bottom, 6)
        }
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(Color.dash.secondaryBackground)
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

        // A resolved `metadata` that reaches here (no `.icon`, no `.iconName`)
        // can only have come from `GiftCardMetadataProvider` — it's the only
        // provider whose entries carry neither field. Reusing the already-
        // resolved `metadata` instead of hitting the provider's dictionary
        // again avoids a `metadataQueue.sync` round trip per row per render.
        if metadata != nil {
            return (.custom("image.explore.dash.wts.payment.gift-card"), nil)
        }

        if txItem.transactionType == .reward {
            return (.custom("transaction-mining", bundle: .dashUIKit), nil)
        }

        return (.custom(txItem.iconName), nil)
    }

    /// SF-symbol pair for an internal transfer's route: the source balance as
    /// the main icon, the destination as the corner badge. Symbols match the
    /// InternalTransferScreen cards (Core = d.circle, Shielded = shield).
    /// Core → Core self-sends return nil and keep the generic internal icon.
    private func transferRouteSymbols(txItem: Transaction) -> (source: String, destination: String)? {
        switch txItem.internalTransferRoute {
        case .coreToShielded: return ("d.circle.fill", "shield.fill")
        case .shieldedToCore: return ("shield.fill", "d.circle.fill")
        case .coreToPlatform: return ("d.circle.fill", "creditcard.fill")
        case .coreToIdentity: return ("d.circle.fill", "person.crop.circle.fill")
        case .coreToCore, nil: return nil
        }
    }

    /// Route pill text for an internal transfer row ("Transparent →
    /// Platform"), shown in the small badge next to the time. Nil for plain
    /// self-sends and non-transfers.
    private func transferRouteDetails(txItem: Transaction) -> String? {
        switch txItem.internalTransferRoute {
        case .coreToShielded:
            return NSLocalizedString("Transparent → Shielded", comment: "Transfer of own funds into the private shielded balance")
        case .shieldedToCore:
            return NSLocalizedString("Shielded → Transparent", comment: "Transfer of own funds from the private shielded balance back to the transparent wallet")
        case .coreToPlatform:
            return NSLocalizedString("Transparent → Platform", comment: "Transfer of own funds into the Platform balance")
        case .coreToIdentity, .coreToCore, nil:
            // Identity fundings carry their purpose in the title
            // ("Identity registration"), so no route pill.
            return nil
        }
    }

    /// Blue glyph in a tinted circle — the InternalTransferScreen card icon
    /// treatment, scaled to the 30 pt tx-row icon slot.
    private func transferRouteIcon(_ systemName: String) -> AnyView {
        AnyView(
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.dash.blue)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.dash.blue.opacity(0.08)))
        )
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
            // Service/merchant metadata wins over the route pair — such rows
            // are external payments, not transfers of own funds.
            let routeSymbols = metadata == nil ? transferRouteSymbols(txItem: txItem) : nil
            // A DashPay contact payment shows the counterparty's avatar
            // (profile image, or the deterministic initial placeholder the
            // contacts screens use).
            let contactAvatar: AnyView? = metadata == nil
                ? txItem.dashPayPayment.map { payment in
                    AnyView(ContactAvatarView(
                        title: payment.titleName ?? "?",
                        avatarURL: payment.counterpartyAvatarURL,
                        identitySeed: payment.counterpartyIdentityId,
                        size: 30))
                }
                : nil

            DashUIKit.TransactionView(
                // A merchant logo is a bitmap and goes through `iconView` so it can be clipped to a
                // circle; every other row resolves to a named icon.
                icon: metadata?.icon == nil && routeSymbols == nil && contactAvatar == nil ? icons.primary.dashIconSource : nil,
                iconView: metadata?.icon.map {
                    AnyView(Image(uiImage: $0).resizable().scaledToFit().clipShape(Circle()))
                } ?? contactAvatar ?? routeSymbols.map { transferRouteIcon($0.source) },
                secondaryIcon: routeSymbols.map { DashIconSource.system($0.destination) }
                    ?? icons.secondary?.dashIconSource,
                title: metadata?.title ?? txItem.stateTitle,
                subtitle: txItem.shortTimeString,
                details: txItem.isPendingShieldedTransfer
                    ? NSLocalizedString("Pending — tap to finish", comment: "InternalTransfer recovery")
                    : txItem.isPendingIdentityFunding
                        ? NSLocalizedString("Pending — tap to finish", comment: "DashPay registration recovery")
                    : txItem.isPendingPlatformFunding
                        ? NSLocalizedString("Pending", comment: "")
                        : (metadata?.details?.isEmpty == false
                            ? metadata?.details
                            // Alias-titled contact payments show the
                            // counterparty's actual name underneath.
                            : transferRouteDetails(txItem: txItem) ?? txItem.dashPayPaymentDetailsName),
                dashAmount: txItem.signedDashAmount,
                amountSign: .always,
                fiat: txItem.fiatAmount,
                trailingStatusText: txItem.state == .locked ? NSLocalizedString("Locked", comment: "Transaction state: coinbase reward locked until 100 confirmations") : nil
            ) {
                // A stuck "to Shielded" transfer opens the recovery sheet
                // instead of the read-only detail/gift-card sheets.
                if txItem.isPendingShieldedTransfer {
                    self.pendingShieldedRecovery = txItem
                } else if txItem.isPendingIdentityFunding {
                    #if DASHPAY
                    delegate?.homeViewRequestUsername()
                    #else
                    self.selectedTxDataItem = txDataItem
                    #endif
                } else if GiftCardMetadataProvider.shared.availableMetadata[txItem.txHashData] != nil {
                    // Check if this is a gift card transaction
                    self.giftCardTxId = txItem.txHashData
                } else {
                    self.selectedTxDataItem = txDataItem
                }
            }
            .frame(minHeight: 66)

        case .shieldedActivity(let item):
            DashUIKit.TransactionView(
                iconView: transferRouteIcon("shield.fill"),
                secondaryIcon: item.secondarySystemIcon.map { DashIconSource.system($0) },
                title: item.title,
                subtitle: item.shortTimeString,
                details: item.detailsText,
                dashAmount: item.signedDashAmount,
                amountSign: item.showsDirectionSign ? .always : .none,
                fiat: item.fiatAmount,
                trailingStatusText: item.trailingStatusText
            ) {
                self.selectedTxDataItem = txDataItem
            }
            .frame(minHeight: 66)

        case .platformActivity(let item):
            DashUIKit.TransactionView(
                iconView: transferRouteIcon("creditcard.fill"),
                secondaryIcon: DashIconSource.system("arrow.down"),
                title: item.title,
                subtitle: item.shortTimeString,
                details: item.detailsText,
                dashAmount: item.signedDashAmount,
                amountSign: .always,
                fiat: item.fiatAmount
            ) {
                self.selectedTxDataItem = txDataItem
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
                        .presentationBackground(Color.dash.primaryBackground)
                        .presentationDetents([.large])
                        .presentationCornerRadius(32)
                        .presentationDragIndicator(.hidden)
                } else {
                    dialog
                        .presentationBackground(Color.dash.primaryBackground)
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
        .background(Color.dash.primaryBackground)
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
        .background(Color.dash.primaryBackground)
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
        case .shieldedActivity(let item):
            ShieldedActivityDetailsView(item: item)
        case .platformActivity(let item):
            PlatformAddressActivityDetailsView(item: item)
        }
    }
}

extension Data: Identifiable {
    public var id: String {
        return self.base64EncodedString()
    }
}
