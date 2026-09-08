//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

/// The amount step of the Receive flow: a title, the dual-currency amount
/// field and the keypad that drives it.
///
/// Driven entirely by `BaseAmountModel` and three closures — the controller
/// owns navigation, the currency list and what "Receive" means.
struct SpecifyAmountView: View {
    @ObservedObject var model: BaseAmountModel
    let onBack: () -> Void
    let onReceive: () -> Void
    let onCurrencyTap: () -> Void

    private func displayAmountString(from formatted: String, locale: Locale) -> String {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        let allowed = CharacterSet.decimalDigits
            .union(CharacterSet(charactersIn: decimalSeparator + groupingSeparator))
        let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return filtered.isEmpty ? trimmed : filtered
    }

    private var primaryAmountNumeric: String {
        displayAmountString(from: model.mainAmountString, locale: model.keyboardLocale)
    }

    private var secondaryAmountNumeric: String {
        displayAmountString(from: model.supplementaryAmountString, locale: model.keyboardLocale)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationBar(leading: {
                NavigationBarElement.back.button { onBack() }
            })

            VStack(alignment: .leading, spacing: 20) {
                Text(NSLocalizedString("Specify Amount", comment: "Specify Amount"))
                    .dashFont(.title1)
                    .foregroundStyle(Color.dash.primaryText)


                DashUIKit.EnterAmountView(
                    primaryAmount: primaryAmountNumeric,
                    secondaryAmount: secondaryAmountNumeric,
                    primaryCurrency: .dash,
                    secondaryCurrency: .fiat(model.localCurrencyCode),
                    isPrimarySelected: model.currentInputItem.isMain,
                    isCurrencySelectorHidden: model.isCurrencySelectorHidden,
                    currencyCodes: model.inputItems.map { $0.currencyCode },
                    selectedCurrencyCode: model.currentInputItem.currencyCode,
                    onMax: nil,
                    onSwap: { model.amountInputControlDidSwapInputs() },
                    onCurrencyTap: onCurrencyTap,
                    onPaste: model.pasteFromClipboard,
                    onSelectInputType: { code in
                        if let index = model.inputItems.firstIndex(where: { $0.currencyCode == code }) {
                            model.selectInputItem(at: index)
                        }
                    }
                )
                // A fixed height, not a minimum: `EnterAmountView` ends in
                // `frame(maxHeight: .infinity)`, so given only a floor it
                // eats the `Spacer` below and centres the amount in the
                // gap between the title and the keypad. 110 is the height
                // its own preview uses.
                .frame(height: 110)


                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)

            HardwareNumericKeyboardView(
                value: Binding(
                    get: { model.currentInputString },
                    set: { model.updateKeyboardInputString($0) }
                ),
                showDecimalSeparator: true,
                locale: model.keyboardLocale,
                actionButtonText: NSLocalizedString("Receive", comment: "Specify Amount"),
                actionEnabled: model.isAllowedToContinue,
                inProgress: false,
                actionHandler: onReceive
            )

        }
        .background(Color.dash.primaryBackground)
    }
}

#if DEBUG

/// `BaseAmountModel()` is what the controller itself builds. Its initializer
/// subscribes to published wallet balance and reads exchange rates, both of
/// which resolve to nothing without a wallet — it does not reach for the FFI,
/// so it stands up in a canvas as-is.
@MainActor
private func specifyAmountSample(typed: String? = nil) -> some View {
    let model = BaseAmountModel()
    if let typed {
        model.updateKeyboardInputString(typed)
    }
    return SpecifyAmountView(
        model: model,
        onBack: {},
        onReceive: {},
        onCurrencyTap: {})
}

@available(iOS 17, *)
#Preview("Empty") {
    specifyAmountSample()
}

/// With an amount the Receive button enables — and this is the layout to watch:
/// the amount belongs directly under the title, not floating in the middle.
@available(iOS 17, *)
#Preview("Amount entered") {
    specifyAmountSample(typed: "1.25")
}

@available(iOS 17, *)
#Preview("Dark") {
    specifyAmountSample(typed: "1.25")
        .preferredColorScheme(.dark)
}

/// The title wraps and the keypad still has to fit above the safe area.
@available(iOS 17, *)
#Preview("Large type") {
    specifyAmountSample()
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
