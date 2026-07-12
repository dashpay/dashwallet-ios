//
//  MayaPortalView.swift
//  DashWallet
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

struct MayaPortalView: View {
    var onBack: () -> Void
    var onConvertDash: (() -> Void)?

    @State private var isOnline: Bool = NetworkStatusService.shared.isOnline

    var body: some View {
        SwapPortalScaffold(
            logoIcon: .custom("maya-illustration"),
            title: NSLocalizedString("Maya", comment: "Dash DEX"),
            description: NSLocalizedString(
                "Convert Dash from Dash Wallet to any crypto that is supported on Maya and send it to any wallet",
                comment: "Dash DEX"
            ),
            isOnline: isOnline,
            onBack: onBack,
            onSellDash: onConvertDash
        )
        .onReceive(NetworkStatusService.shared.statusPublisher) { status in
            isOnline = status == .online
        }
    }
}

#Preview {
    MayaPortalView(onBack: {}, onConvertDash: {})
}
