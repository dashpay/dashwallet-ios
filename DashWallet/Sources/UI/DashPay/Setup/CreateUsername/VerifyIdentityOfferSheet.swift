//
//  Created by Claude
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

/// Asked on Continue for a contested name, before the request goes out: would
/// you like to publish something that shows the name is yours?
///
/// The same question Android asks at the same moment, with its copy. Timing is
/// the point — masternode owners weigh the link while they vote, so a link
/// added after the request is worth less than one that travels with it.
struct VerifyIdentityOfferSheet: View {
    let onVerify: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString(
                "Verify your identity to enhance your chances of getting your requested username",
                comment: "Usernames"))
                .dashFont(.title1)
                .foregroundStyle(Color.dash.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(NSLocalizedString(
                "If somebody else requests the same username as you, we will let the network decide whom to give this username",
                comment: "Usernames"))
                .dashFont(.subhead)
                .foregroundStyle(Color.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            DashUIKit.DashButton(
                text: NSLocalizedString("Verify", comment: ""),
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: onVerify
            )
            .padding(.top, 28)

            DashUIKit.DashButton(
                text: NSLocalizedString("Skip", comment: ""),
                fillsWidth: true,
                size: .large,
                style: .tintedGray,
                action: onSkip
            )
            .padding(.top, 10)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Verify identity offer") {
    VerifyIdentityOfferSheet(onVerify: {}, onSkip: {})
        .background(Color.dash.primaryBackground)
}

#endif
