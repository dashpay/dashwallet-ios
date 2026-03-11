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
    @ObservedObject var viewModel: BalanceModel
    @State private var opacity: Double = 0.3
    var onLongPress: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if !viewModel.isBalanceHidden && viewModel.state == .syncing {
                    Text(NSLocalizedString("Syncing Balance", comment: ""))
                        .font(.caption)
                        .foregroundColor(.white)
                        .opacity(opacity)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 0.8)
                                    .repeatForever(autoreverses: true)
                            ) {
                                opacity = 0.7
                            }
                        }
                }
            }
            .frame(height: 15)
            
            ZStack {
                if viewModel.isBalanceHidden {
                    Image(systemName: "eye.slash.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.2))
                        )
                        .frame(width: 58, height: 58)
                } else {
                    VStack(spacing: 0) {
                        DashAmount(amount: Int64(viewModel.value), font: .largeTitle, dashSymbolFactor: 0.7, showDirection: false)
                            .foregroundColor(.white)
                        Text(viewModel.fiatAmountString())
                            .font(.subhead)
                            .foregroundColor(.white)
                        
                        ZStack {
                            if viewModel.shouldShowTapToHideBalance {
                                Text(NSLocalizedString("Tap to hide balance", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .frame(height: 12)
                        .padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.navigationBarColor)
            .animation(.easeInOut(duration: 0.3), value: viewModel.isBalanceHidden)
            .onTapGesture {
                viewModel.toggleBalanceVisibility()
            }
            .onLongPressGesture {
                onLongPress()
            }
        }
        .onAppear {
            viewModel.reloadBalance()
        }
        .onDisappear {
            viewModel.hideBalanceIfNeeded()
        }
    }
}
