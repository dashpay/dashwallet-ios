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

// MARK: - AdvancedModeInfoSheetViewModel

/// What the sheet says, so the sheet only draws it.
///
/// The content is fixed rather than fetched, which was the argument for leaving
/// it inline — but "All new UI MUST be built in SwiftUI with a ViewModel" does
/// not carve out static content, and the surfaces named here are the ones the
/// mode gates: when that list changes, it changes in one place that is not a
/// view body.
@MainActor
final class AdvancedModeInfoSheetViewModel: ObservableObject {

    struct Feature: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let icon: DashIconSource
        let iconColor: Color?
    }

    let title = NSLocalizedString("What is advanced mode?", comment: "Settings")
    let subtitle = NSLocalizedString(
        "It unlocks powerful features for managing your Dash across the network",
        comment: "Settings")

    let features: [Feature] = [
        Feature(
            title: NSLocalizedString("Shield", comment: "Settings: advanced mode"),
            description: NSLocalizedString(
                "Move Dash into a private, encrypted balance that can't be traced.",
                comment: "Settings: advanced mode"),
            icon: .custom("feature-shield-purple", bundle: .dashUIKit),
            iconColor: nil),
        Feature(
            title: NSLocalizedString("Identity", comment: "Settings: advanced mode"),
            description: NSLocalizedString(
                "Fund your identity to create a username and use Dash Platform",
                comment: "Settings: advanced mode"),
            icon: .custom("feature-identity", bundle: .dashUIKit),
            iconColor: Color.dash.purple),
        Feature(
            title: NSLocalizedString("Platform", comment: "Settings: advanced mode"),
            description: NSLocalizedString(
                "Keep credits to pay for on-chain actions and Platform apps",
                comment: "Settings: advanced mode"),
            icon: .custom("feature-platform-purple", bundle: .dashUIKit),
            iconColor: nil),
    ]
}

/// What Advanced mode does, shown when the settings row's info glyph is tapped.
///
/// Self-sizing on purpose: the copy is expected to grow as the mode gains the
/// surfaces it gates, and `BottomSheet.selfSizing` pairs `fillsHeight: false`
/// with the sizing modifier so the sheet keeps snapping to it without anything
/// here being re-tuned.
struct AdvancedModeInfoSheet: View {

    @StateObject private var viewModel = AdvancedModeInfoSheetViewModel()

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            showBackButton: .constant(false)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.title)
                        .dashFont(.title1)
                        .foregroundStyle(Color.dash.primaryText)

                    Text(viewModel.subtitle)
                        .dashFont(.body)
                        .foregroundStyle(Color.dash.secondaryText)
                }
                .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.features) { feature in
                        if let iconColor = feature.iconColor {
                            SheetFeature(
                                title: feature.title,
                                description: feature.description,
                                icon: feature.icon,
                                iconColor: iconColor
                            )
                        } else {
                            SheetFeature(
                                title: feature.title,
                                description: feature.description,
                                icon: feature.icon
                            )
                        }
                    }
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
        // Named so a UI test can assert it is NOT presented by a tap that lands
        // on the row's switch.
        .accessibilityIdentifier("advanced_mode_info_sheet")
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
