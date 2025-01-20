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

// MARK: - SyncingHeaderView

struct SyncingHeaderView: View {
    @ObservedObject private var model = SyncModelImpl()
    var onFilterTap: () -> Void
    var onSyncTap: () -> Void
    
    var body: some View {
        HStack {
            Text(NSLocalizedString("History", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondaryText)
            
            Spacer()
            
            if model.state == .syncing {
                Button(action: onSyncTap) {
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("Syncing", comment: ""))
                            .font(.subheadline)
                        
                        if DWEnvironment.sharedInstance().currentChainManager.peerManager.connected || model.progress > 0 {
                            Text(String(format: "%.1f%%", model.progress * 100.0))
                                .font(.body)
                                .fontWeight(.medium)
                        }
                    }
                    .foregroundColor(.primaryText)
                }
            }
            
            DashButton(
                text: NSLocalizedString("Filter", comment: ""),
                trailingIcon: .custom("icon_filter_button"),
                style: .plain,
                size: .small,
                stretch: false,
                action: onFilterTap
            ).overrideForegroundColor(.dashBlue)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .background(Color.primaryBackground)
    }
}
