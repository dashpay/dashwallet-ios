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
import UIKit

private enum Layout {
    static let horizontalPadding: CGFloat = 20
    static let introTopPadding: CGFloat = 10
    static let introHeight: CGFloat = 100
    static let amountTopPadding: CGFloat = 22
    static let amountSectionSpacing: CGFloat = 10
    static let amountRowHeight: CGFloat = 60
    static let maxButtonSize: CGFloat = 42
    static let maxButtonCornerRadius: CGFloat = 19
    static let smallAmountOpacity: CGFloat = 0.67
    static let keyboardCornerRadius: CGFloat = 10
    static let keyboardTopPadding: CGFloat = 10
    static let keyboardBottomPadding: CGFloat = 15
    static let errorTopPadding: CGFloat = 10
    static let errorHorizontalPadding: CGFloat = 16
    static let switcherItemSpacing: CGFloat = 4
    static let switcherItemHeight: CGFloat = 24
    static let switcherItemCornerRadius: CGFloat = 7
    static let switcherHorizontalPadding: CGFloat = 6
    static let switcherVerticalPadding: CGFloat = 3
    static let supplementaryTrailingSpacing: CGFloat = 2
    static let selectorHitArea: CGFloat = 24
}

struct SendAmountView<AvatarView: View>: View {


    @ObservedObject var model: SendAmountModel
    let onBack: () -> Void
    let destination: String?
    let dashBalance: UInt64
    let balanceLabel: String
    let balanceAuthCallback: ((@escaping (Bool) -> Void) -> Void)?
    let isLoading: Bool
    let onMax: () -> Void
    let onSelectCurrency: () -> Void
    let onSend: () -> Void
    @ViewBuilder var avatarView: () -> AvatarView

    var body: some View {
        ZStack(alignment: .top) {
            Color.primaryBackground
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                NavigationBar(leading: {
                    NavigationBarElement.back.button { onBack() }
                })
                .background(Color.dash.secondaryBackground)

                VStack(spacing: 0) {
                    SendAmountHeader(
                        destination: destination,
                        dashBalance: dashBalance,
                        balanceLabel: balanceLabel,
                        balanceAuthCallback: balanceAuthCallback,
                        avatarView: avatarView
                    )
                    .frame(maxWidth: .infinity, minHeight: Layout.introHeight, alignment: .topLeading)
                    .padding(.horizontal, Layout.horizontalPadding)
                    .padding(.top, Layout.introTopPadding)

                    SendAmountValueSection(
                        model: model,
                        isLoading: isLoading,
                        onMax: onMax,
                        onSelectCurrency: onSelectCurrency
                    )
                    .padding(.horizontal, Layout.horizontalPadding)
                    .padding(.top, Layout.amountTopPadding)

                    Spacer(minLength: 0)

                    SendAmountKeyboardSection(
                        value: Binding(
                            get: { model.currentInputString },
                            set: { model.updateKeyboardInputString($0) }
                        ),
                        locale: model.keyboardLocale,
                        isLoading: isLoading,
                        isEnabled: model.isAllowedToContinue,
                        onSend: onSend
                    )
                }
                .background(Color.secondaryBackground)
            }
        }
    }
}

private struct SendAmountHeader<AvatarView: View>: View {
    let destination: String?
    let dashBalance: UInt64
    let balanceLabel: String
    let balanceAuthCallback: ((@escaping (Bool) -> Void) -> Void)?
    @ViewBuilder var avatarView: () -> AvatarView

    var body: some View {
        SendIntro(
            title: NSLocalizedString("Send", comment: "Send Screen"),
            destination: destination,
            dashBalance: dashBalance,
            balanceLabel: balanceLabel + ":",
            authCallback: balanceAuthCallback,
            avatarView: avatarView
        )
    }
}

private struct SendAmountValueSection: View {
    @ObservedObject var model: SendAmountModel
    let isLoading: Bool
    let onMax: () -> Void
    let onSelectCurrency: () -> Void

    var body: some View {
        VStack(spacing: Layout.amountSectionSpacing) {
            SendAmountInputRow(
                model: model,
                isLoading: isLoading,
                onMax: onMax,
                onSelectCurrency: onSelectCurrency
            )

            SendAmountErrorRow(error: model.error)
        }
    }

    private enum Layout {
        static let amountSectionSpacing: CGFloat = 10
    }
}

private struct SendAmountInputRow: View {
    @ObservedObject var model: SendAmountModel
    let isLoading: Bool
    let onMax: () -> Void
    let onSelectCurrency: () -> Void

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
        DashUIKit.EnterAmountView(
            primaryAmount: primaryAmountNumeric,
            secondaryAmount: secondaryAmountNumeric,
            primaryCurrency: .dash,
            secondaryCurrency: .fiat(model.localCurrencyCode),
            isPrimarySelected: model.currentInputItem.isMain,
            isCurrencySelectorHidden: model.isCurrencySelectorHidden,
            currencyCodes: model.inputItems.map { $0.currencyCode },
            selectedCurrencyCode: model.currentInputItem.currencyCode,
            onMax: onMax,
            onSwap: { model.amountInputControlDidSwapInputs() },
            onCurrencyTap: onSelectCurrency,
            onSelectInputType: { code in
                if let i = model.inputItems.firstIndex(where: { $0.currencyCode == code }) {
                    model.selectInputItem(at: i)
                }
            }
        )
        .opacity(isLoading ? 0.5 : 1.0)
        .disabled(isLoading)
        .frame(minHeight: 90)
    }
}

private struct SendAmountErrorRow: View {
    let error: Error?

    var body: some View {
        if let error {
            HStack(spacing: 2) {
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundColor(errorColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
        }
    }

    private var errorColor: Color {
        guard let colorizedError = error as? ColorizedText else {
            return .systemRed
        }

        return Color(uiColor: colorizedError.textColor)
    }
}

private struct SendAmountKeyboardSection: View {
    @Binding var value: String
    let locale: Locale
    let isLoading: Bool
    let isEnabled: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NumericKeyboardView(
                value: $value,
                showDecimalSeparator: true,
                locale: locale,
                actionButtonText: NSLocalizedString("Send", comment: "Send Dash"),
                actionEnabled: isEnabled,
                inProgress: isLoading,
                actionHandler: onSend
            )
            .padding(.top, 10)
            .padding(.bottom, 15)
        }
    }
}

#Preview("Dash") {
    SendAmountScreenPreviewContainer(state: .dash)
}

#Preview("Fiat") {
    SendAmountScreenPreviewContainer(state: .fiat)
}

#Preview("Error") {
    SendAmountScreenPreviewContainer(state: .error)
}

#Preview("Loading") {
    SendAmountScreenPreviewContainer(state: .loading)
}

private struct SendAmountScreenPreviewContainer: View {
    enum State {
        case dash
        case fiat
        case error
        case loading
    }

    @StateObject private var model: SendAmountModel
    private let state: State

    init(state: State) {
        self.state = state
        _model = StateObject(wrappedValue: Self.makeModel(state: state))
    }

    var body: some View {
        SendAmountView(
            model: model,
            onBack: {},
            destination: "Xw3zExampleDashAddressOrUsername",
            dashBalance: model.walletBalance,
            balanceLabel: NSLocalizedString("Dash balance", comment: ""),
            balanceAuthCallback: nil,
            isLoading: state == .loading,
            onMax: { model.selectAllFundsWithoutAuth() },
            onSelectCurrency: {},
            onSend: {},
            avatarView: { EmptyView() }
        )
    }

    private static func makeModel(state: State) -> SendAmountModel {
        let model = SendAmountModel()
        model.walletBalance = 12_345_678

        switch state {
        case .dash:
            model.updateKeyboardInputString("0.12345")
        case .fiat:
            model.selectInputItem(at: 0)
            model.updateKeyboardInputString("12.34")
        case .error:
            model.updateKeyboardInputString("1000000")
            model.error = SendAmountError.insufficientFunds
        case .loading:
            model.updateKeyboardInputString("0.5")
        }

        return model
    }
}
