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

/// What Advanced mode does, shown when the settings row's info glyph is tapped.
///
/// Self-sizing on purpose: the copy is expected to grow as the mode gains the
/// surfaces it gates, and `BottomSheet.selfSizing` pairs `fillsHeight: false`
/// with the sizing modifier so the sheet keeps snapping to it without anything
/// here being re-tuned.
struct AdvancedModeInfoSheet: View {

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            showBackButton: .constant(false)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("What is advanced mode?", comment: "Settings"))
                        .dashFont(.title1)
                        .foregroundStyle(Color.dash.primaryText)

                    Text(NSLocalizedString("It unlocks powerful features for managing your Dash across the network", comment: "Settings"))
                        .dashFont(.body)
                        .foregroundStyle(Color.dash.secondaryText)
                }
                .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 16) {
                    SheetFeature(
                        title: NSLocalizedString("Shield", comment: "Settings: advanced mode"),
                        description: NSLocalizedString("Move Dash into a private, encrypted balance that can't be traced.", comment: "Settings: advanced mode"),
                        icon: .custom("feature-shield-purple", bundle: .dashUIKit)
                    )
                    SheetFeature(
                        title: NSLocalizedString("Identity", comment: "Settings: advanced mode"),
                        description: NSLocalizedString("Fund your identity to create a username and use Dash Platform", comment: "Settings: advanced mode"),
                        icon: .custom("feature-identity", bundle: .dashUIKit),
                        iconColor: Color.dash.purple
                    )
                    SheetFeature(
                        title: NSLocalizedString("Platform", comment: "Settings: advanced mode"),
                        description: NSLocalizedString("Keep credits to pay for on-chain actions and Platform apps", comment: "Settings: advanced mode"),
                        icon: .custom("feature-platform-purple", bundle: .dashUIKit)
                    )
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
    }
}

#if DEBUG

#Preview {
    Color.dash.primaryBackground
        .sheet(isPresented: .constant(true)) {
            AdvancedModeInfoSheet()
        }
}

#endif
