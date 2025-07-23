//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

import SwiftUI

struct MainMenuView: View {
    @StateObject private var viewModel: MainMenuViewModel
    
    #if DASHPAY
    let joinDPViewModel = JoinDashPayViewModel(initialState: .none)
    #endif
    
    init(viewModel: MainMenuViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text(NSLocalizedString("More", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primaryText)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                #if DASHPAY
                // Join DashPay section (if needed)
                if viewModel.userProfileModel?.showJoinDashpay == true {
                    JoinDashPayView(
                        viewModel: joinDPViewModel,
                        onTap: { state in
                            handleJoinDashPayTap(state: state)
                        },
                        onActionButton: { state in
                            handleJoinDashPayAction(state: state)
                        },
                        onDismissButton: { state in
                            joinDPViewModel.markAsDismissed()
                        },
                        onSizeChange: { size in
                            // Handle size changes if needed
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
                #endif
                
                // Menu sections
                ForEach(Array(viewModel.menuSections.enumerated()), id: \.offset) { index, section in
                    MenuSectionView(section: section) { menuItem in
                        viewModel.handleMenuAction(menuItem)
                    }
                }
                
                Spacer(minLength: 60) // Bottom padding for tab bar
            }
        }
        .background(Color.primaryBackground)
        .onAppear {
            viewModel.updateModel()
        }
    }
    
    #if DASHPAY
    private func handleJoinDashPayTap(state: JoinDashPayViewState) {
        switch state {
        case .registered:
            NotificationCenter.default.post(name: .editProfile, object: nil)
        case .voting:
            NotificationCenter.default.post(name: .showRequestDetails, object: nil)
        case .none:
            handleJoinButtonAction()
        default:
            break
        }
    }
    
    private func handleJoinDashPayAction(state: JoinDashPayViewState) {
        switch state {
        case .blocked, .failed, .contested:
            handleJoinButtonAction()
        default:
            NotificationCenter.default.post(name: .editProfile, object: nil)
            joinDPViewModel.markAsDismissed()
        }
    }
    
    private func handleJoinButtonAction() {
        let shouldShowMixDashDialog = CoinJoinService.shared.mode == .none || !UsernamePrefs.shared.mixDashShown
        let shouldShowDashPayInfo = !UsernamePrefs.shared.joinDashPayInfoShown
        
        if shouldShowMixDashDialog {
            NotificationCenter.default.post(name: .showMixDashDialog, object: nil)
        } else if shouldShowDashPayInfo {
            NotificationCenter.default.post(name: .showDashPayInfo, object: nil)
        } else {
            NotificationCenter.default.post(name: .joinDashPay, object: nil)
        }
    }
    #endif
}

struct MenuSectionView: View {
    let section: MenuSection
    let onMenuItemTap: (MenuItemType) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(section.items, id: \.self) { item in
                MenuItemView(item: item) {
                    onMenuItemTap(item)
                }
            }
        }
        .padding(.vertical, 5)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
        .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
        .padding(.horizontal, 20)
    }
}

struct MenuItemView: View {
    let item: MenuItemType
    let action: () -> Void
    
    var body: some View {
        MenuItem(
            title: item.title,
            subtitle: item.subtitle,
            icon: item.iconName,
            showChevron: false,
            action: action
        )
    }
}

// MARK: - Additional Notification Names

extension Notification.Name {
    #if DASHPAY
    static let editProfile = Notification.Name("editProfile")
    static let showRequestDetails = Notification.Name("showRequestDetails")
    static let showMixDashDialog = Notification.Name("showMixDashDialog")
    static let showDashPayInfo = Notification.Name("showDashPayInfo")
    static let joinDashPay = Notification.Name("joinDashPay")
    #endif
}

// MARK: - MenuItemType Hashable

extension MenuItemType: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .joinDashPay:
            hasher.combine("joinDashPay")
        case .buySellDash:
            hasher.combine("buySellDash")
        case .explore:
            hasher.combine("explore")
        case .security:
            hasher.combine("security")
        case .settings:
            hasher.combine("settings")
        case .tools:
            hasher.combine("tools")
        case .support:
            hasher.combine("support")
        #if DASHPAY
        case .invite:
            hasher.combine("invite")
        case .voting:
            hasher.combine("voting")
        #endif
        }
    }
}

#Preview {
    #if DASHPAY
    let viewModel = MainMenuViewModel(
        dashPayModel: nil,
        receiveModel: nil,
        dashPayReady: nil,
        userProfileModel: nil
    )
    #else
    let viewModel = MainMenuViewModel()
    #endif
    
    return MainMenuView(viewModel: viewModel)
}
