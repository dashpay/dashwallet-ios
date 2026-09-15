//
//  ConnectionsUnavailableState.swift
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

import DashUIKit
import SwiftUI

/// Shown when DashConnect is not offered on the current network. There is no
/// call to action — the user cannot opt in, only switch networks.
struct ConnectionsUnavailableState: View {
    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    Image("dashconnect-empty")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                .frame(width: 80, height: 80)

                VStack(spacing: 4) {
                    Text(NSLocalizedString("Available on test networks only", comment: "DashConnect"))
                        .dashFont(.title3Medium)
                        .foregroundColor(Color.dash.primaryText)

                    Text(
                        NSLocalizedString(
                            "DashConnect login is not yet available on mainnet",
                            comment: "DashConnect"
                        )
                    )
                    .dashFont(.subhead)
                    .foregroundColor(Color.dash.secondaryText)
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ConnectionsUnavailableState()
        .background(Color.primaryBackground)
}
