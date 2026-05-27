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

private enum Layout {
    static let hPadding: CGFloat = 6
    static let vPadding: CGFloat = 3
    static let cornerRadius: CGFloat = 6
}

struct DashPickerView<Option: Hashable>: View {

    let options: [Option]
    let title: (Option) -> String
    @Binding var selected: Option

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    selected = option
                } label: {
                    pickerOption(option)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pickerOption(_ option: Option) -> some View {
        Text(title(option))
            .font(.caption2)
            .foregroundColor(selected == option ? .primaryText : Color.black1000Alpha40)
            .padding(.horizontal, Layout.hPadding)
            .padding(.vertical, Layout.vPadding)
            .background(selected == option ? Color.black1000Alpha5 : Color.clear)
            .clipShape(.rect(cornerRadius: Layout.cornerRadius))
    }
}

#if DEBUG
#Preview {
    DashPickerView(
        options: ["US$", "DASH", "BTC"],
        title: { $0 },
        selected: .constant("DASH")
    )
    .padding()
    .background(Color.primaryBackground)
}
#endif
