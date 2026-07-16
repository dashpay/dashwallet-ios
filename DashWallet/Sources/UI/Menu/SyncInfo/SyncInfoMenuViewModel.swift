//
//  SyncInfoMenuViewModel.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import Foundation

enum SyncInfoMenuNavigationDestination {
    case swiftDashSDKSPVStatus
    case platformSyncStatus
    #if DASHPAY
    case dashPaySyncInfo
    #endif
    case shieldedSyncInfo
}

@MainActor
class SyncInfoMenuViewModel: ObservableObject {
    @Published var items: [MenuItemModel] = []
    @Published var navigationDestination: SyncInfoMenuNavigationDestination?

    init() {
        setupMenuItems()
    }

    private func setupMenuItems() {
        items = [
            MenuItemModel(
                title: "Core Sync Status",
                icon: .system("arrow.triangle.2.circlepath"),
                action: { [weak self] in
                    self?.navigationDestination = .swiftDashSDKSPVStatus
                }
            ),
            MenuItemModel(
                title: "Platform Sync Status",
                icon: .system("globe"),
                action: { [weak self] in
                    self?.navigationDestination = .platformSyncStatus
                }
            ),
        ]

        #if DASHPAY
        items.append(MenuItemModel(
            title: "DashPay Sync Info",
            icon: .system("person.2"),
            action: { [weak self] in
                self?.navigationDestination = .dashPaySyncInfo
            }
        ))
        #endif

        items.append(MenuItemModel(
            title: "Shielded Sync Info",
            icon: .system("shield"),
            action: { [weak self] in
                self?.navigationDestination = .shieldedSyncInfo
            }
        ))
    }

    func resetNavigation() {
        navigationDestination = nil
    }
}
