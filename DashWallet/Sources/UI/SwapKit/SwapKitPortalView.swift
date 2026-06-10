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

struct SwapKitPortalView: View {
    var onBack: () -> Void
    var onConvertDash: (() -> Void)?

    var body: some View {
        SwapPortalScaffold(
            logoAssetName: "swapkit-illustration",
            title: NSLocalizedString("SwapKit", comment: "SwapKit Portal"),
            description: NSLocalizedString(
                "Sell Dash for any supported crypto at the best available price across networks",
                comment: "SwapKit Portal"
            ),
            onBack: onBack,
            onConvertDash: onConvertDash
        )
    }
}

#Preview {
    SwapKitPortalView(onBack: {}, onConvertDash: {})
}
