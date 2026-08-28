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

/// Warning line under the amount field — an orange triangle and the
/// message. Shared with the Send screen, which validates the same way.
struct TransferAmountValidationNote: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG

/// The real messages, since wrapping is the whole risk here: the triangle is
/// baseline-aligned to the first line and must not drift on a two-line note.
private let shortValidationMessage = "You don't have that much Transparent balance."
private let longValidationMessage = """
    You don't have that much Shielded balance. Transfers from the shielded pool \
    also reserve a fee, so the most you can send right now is 0.78412 DASH.
    """

@available(iOS 17, *)
#Preview("Short") {
    TransferAmountValidationNote(message: shortValidationMessage)
        .padding(20)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Wrapping") {
    TransferAmountValidationNote(message: longValidationMessage)
        .padding(20)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Dark") {
    TransferAmountValidationNote(message: longValidationMessage)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dash.primaryBackground)
        .preferredColorScheme(.dark)
}

@available(iOS 17, *)
#Preview("Large type") {
    TransferAmountValidationNote(message: longValidationMessage)
        .padding(20)
        .background(Color.dash.primaryBackground)
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
