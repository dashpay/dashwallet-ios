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

/// Offered after a contested request is confirmed: the requested name is out
/// for a vote and is not usable meanwhile, so the user can register a second,
/// non-contested name to use right away.
///
/// The same offer Android makes in `createInstantUsernameDialog`, with its
/// copy — which explains the part the user cannot see: if the vote goes their
/// way the requested name replaces the instant one and keeps the contacts and
/// history built on it.
struct CreateInstantUsernameSheet: View {
    let onCreate: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Create an instant username", comment: "Usernames"))
                    .dashFont(.title1)
                    .foregroundStyle(Color.dash.primaryText)

                Text(NSLocalizedString("""
                    Your requested username will be voted on for 2 weeks. For immediate contacts and payments, you can create a similar instant username.
                    If your original request is approved, it replaces the instant one, preserving contacts and history. If not, continue using the instant one uninterrupted.
                    """, comment: "Usernames"))
                    .dashFont(.body)
                    .foregroundStyle(Color.dash.primaryText)
            }
            .padding(.vertical, 20)

            Spacer()
                .frame(maxHeight: 20)

            VStack(spacing: 20) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Create instant username", comment: "Usernames"),
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: onCreate
                )

                DashUIKit.DashButton(
                    text: NSLocalizedString("No, thanks", comment: "Usernames"),
                    fillsWidth: true,
                    size: .large,
                    style: .tintedGray,
                    action: onDecline
                )
            }
            .padding(.vertical, 20)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Create an instant username") {
    CreateInstantUsernameSheet(onCreate: {}, onDecline: {})
        .background(Color.dash.primaryBackground)
}

#endif
