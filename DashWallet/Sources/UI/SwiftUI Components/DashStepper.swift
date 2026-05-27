//
//  Created by Roman Chornyi
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

struct DashStepper: View {
    @Binding var count: Int
    var maxCount: Int?

    private var plusEnabled: Bool {
        guard let max = maxCount else { return true }
        return count < max
    }

    var body: some View {
        HStack(spacing: 6) {
            stepperButton(
                systemImage: "minus",
                enabled: count > 0,
                accessibilityLabel: NSLocalizedString("Decrease quantity", comment: "DashSpend")
            ) {
                if count > 0 { count -= 1 }
            }

            Text("\(count)")
                .font(.headline.weight(.semibold))
                .foregroundColor(.primaryText)
                .frame(width: 30)
                .multilineTextAlignment(.center)

            stepperButton(
                systemImage: "plus",
                enabled: plusEnabled,
                accessibilityLabel: NSLocalizedString("Increase quantity", comment: "DashSpend")
            ) {
                count += 1
            }
        }
    }

    private func stepperButton(
        systemImage: String,
        enabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemImage)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 11, height: 11)
            .foregroundColor(enabled ? .primaryText : Color.gray300)
            .frame(width: 34, height: 34)
            .overlay(
                Circle()
                    .stroke(
                        enabled ? Color.black1000Alpha8 : Color.black1000Alpha5,
                        lineWidth: 1.5
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard enabled else { return }
                action()
            }
            .padding(4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(Text("\(count)"))
            .accessibilityHint(
                Text(
                    enabled
                        ? NSLocalizedString("Double tap to change quantity", comment: "DashSpend")
                        : NSLocalizedString("Unavailable at this limit", comment: "DashSpend")
                )
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard enabled else { return }
                action()
            }
    }
}

#Preview {
    DashStepperPreview()
        .padding(20)
}

private struct DashStepperPreview: View {
    @State private var count = 0

    var body: some View {
        DashStepper(count: $count, maxCount: 5)
    }
}
