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

import SwiftUI

// MARK: - HomeHeaderView

/// The part of Home between the balance and the transaction list: the
/// shortcut bar, the one-time "customize shortcuts" banner and, when the
/// wallet cannot sync, the sync status card. It sizes itself, so the list
/// below moves when the banner or the card comes and goes.
struct HomeHeaderView: View {
    /// Gap between the shortcut bar and the customize banner.
    static let shortcutBarBannerSpacing: CGFloat = 20

    @ObservedObject var viewModel: HomeViewModel
    let onShortcut: (ShortcutAction) -> Void
    let onShortcutLongPress: (_ position: Int, _ action: ShortcutAction) -> Void
    let onRetrySync: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // The 13pt strip above the bar is navigation blue, so it merges
            // with the balance above instead of showing the page background.
            ShortcutsBarView(
                viewModel: viewModel,
                onSelect: onShortcut,
                onLongPress: onShortcutLongPress
            )
            .padding(.top, 13)
            .background(Color.navigationBarColor)

            if viewModel.shouldShowShortcutBanner {
                ShortcutCustomizeBannerView(onDismiss: {
                    withAnimation(.easeOut(duration: 0.3)) {
                        viewModel.dismissShortcutBanner()
                    }
                })
                .padding(.horizontal, 20)
                .padding(.top, Self.shortcutBarBannerSpacing)
                .transition(.opacity)
            }

            SyncView(onRetry: onRetrySync)
        }
        .onAppear { viewModel.checkShortcutBanner() }
    }
}
