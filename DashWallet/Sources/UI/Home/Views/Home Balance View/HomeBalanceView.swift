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

// MARK: - HomeBalanceViewState

enum HomeBalanceViewState: Int {
    case `default`
    case syncing
}

// MARK: - HomeBalanceView

struct HomeBalanceView: View {
    @StateObject private var viewModel = BalanceModel()
    var onLongPress: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isBalanceHidden && viewModel.state == .syncing {
                Text(NSLocalizedString("Syncing Balance", comment: ""))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .opacity(0.8)
                    .animation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                        value: viewModel.state
                    )
            }
            
            ZStack {
                if viewModel.isBalanceHidden {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                            .foregroundColor(.white)
                        
                        Button(action: { viewModel.toggleBalanceVisibility() }) {
                            Text(NSLocalizedString("Tap to unhide balance", comment: ""))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .transition(.opacity)
                }
                
                VStack(spacing: 4) {
                    Text(viewModel.mainAmountString)
                        .font(.title)
                        .foregroundColor(.white)
                    
                    Text(viewModel.supplementaryAmountString)
                        .font(.callout)
                        .foregroundColor(.white)
                }
                .opacity(viewModel.isBalanceHidden ? 0 : 1)
                .transition(.opacity)
            }
            .frame(height: 52)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.toggleBalanceVisibility()
            }
            .onLongPressGesture {
                onLongPress()
            }
        }
        .padding()
        .onDisappear {
            viewModel.hideBalanceIfNeeded()
        }
    }
}
