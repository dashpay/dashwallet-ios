//
//  RequestDetailField.swift
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

// MARK: - RequestDetailField

/// A read-only field: a label above a wrapping value on a gray card. The value
/// is any view, so a field can show text, a link, or a spinner.
struct RequestDetailField<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .dashFont(.footnoteMedium)
                .foregroundStyle(Color.dash.tertiaryText)
            value()
                .dashFont(.subhead)
                .foregroundStyle(Color.dash.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.dash.gray300Alpha10, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

extension RequestDetailField where Value == Text {
    init(label: String, text: String) {
        self.init(label: label) { Text(text) }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Text") {
    RequestDetailField(label: "Username", text: "johndoe").padding(20)
}
#Preview("Long value") {
    RequestDetailField(
        label: "Identity",
        text: "90f95ff7bc2438a748dc8470255b888e1a2b3c4d5e6f708192a3b4c5d6e7f809").padding(20)
}
#Preview("Checking") {
    RequestDetailField(label: "Link") { SwiftUI.ProgressView() }.padding(20)
}
#Preview("Link") {
    RequestDetailField(label: "Link") {
        Link("https://x.com/johndoe/status/1234567890123456789", destination: URL(string: "https://x.com/johndoe")!)
    }
    .padding(20)
}
#Preview("Dark") {
    RequestDetailField(label: "Voting period", text: "Not provided – Oct 25, 2026")
        .padding(20)
        .preferredColorScheme(.dark)
}
#endif
