//
//  Created by Roman Chornyi
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

import SwiftUI
import DashUIKit

struct SwapKitPortalView: View {
    var onBack: () -> Void
    var onBuyDash: (() -> Void)?
    var onSellDash: (() -> Void)?

    @State private var isOnline: Bool = NetworkStatusService.shared.isOnline

    var body: some View {
        SwapPortalScaffold(
            logoIcon: DashIcon.Illustrations.dashDex.source,
            title: NSLocalizedString("Dash DEX", comment: "Dash DEX Portal"),
            description: NSLocalizedString(
                "Swap crypto into Dash, or convert Dash to any crypto supported across SwapKit networks",
                comment: "Dash DEX Portal"
            ),
            showBuy: true,
            isOnline: isOnline,
            onBack: onBack,
            onBuyDash: onBuyDash,
            onSellDash: onSellDash
        )
        .onReceive(NetworkStatusService.shared.statusPublisher) { status in
            isOnline = status == .online
        }
    }
}

#Preview {
    SwapKitPortalView(
        onBack: {},
        onBuyDash: {},
        onSellDash: {}
    )
}
