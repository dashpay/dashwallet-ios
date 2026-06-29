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
import UIKit

// MARK: - SpecifyAmountViewControllerDelegate

@objc(DWSpecifyAmountViewControllerDelegate)
protocol SpecifyAmountViewControllerDelegate: AnyObject {
    func specifyAmountViewController(_ vc: SpecifyAmountViewController, didInput amount: UInt64)
}

// MARK: - SpecifyAmountViewController

@objc(DWSpecifyAmountViewController)
final class SpecifyAmountViewController: ActionButtonViewController {
    @objc weak var delegate: SpecifyAmountViewControllerDelegate?

    override var showsActionButton: Bool { false }

    private let amountModel: BaseAmountModel

    init(model: BaseAmountModel) {
        self.amountModel = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "SecondaryBackground", in: .dashUIKit, compatibleWith: .current)
        configureHierarchy()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    @objc
    static func controller() -> SpecifyAmountViewController {
        SpecifyAmountViewController(model: BaseAmountModel())
    }

    private func configureHierarchy() {
        let rootView = SpecifyAmountView(
            model: amountModel,
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onReceive: { [weak self] in
                guard let self else { return }
                self.delegate?.specifyAmountViewController(self, didInput: UInt64(self.amountModel.amount.plainAmount))
            },
            onCurrencyTap: { [weak self] in
                self?.showCurrencyList()
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = UIColor(named: "SecondaryBackground", in: .dashUIKit, compatibleWith: .current)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        setupContentView(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    private func showCurrencyList() {
        let currencyController = DWLocalCurrencyViewController(
            navigationAppearance: .white,
            presentationMode: .dialog,
            currencyCode: amountModel.localCurrencyCode
        )
        currencyController.isGlobal = false
        currencyController.delegate = self
        let navigationController = BaseNavigationController(rootViewController: currencyController)
        present(navigationController, animated: true)
    }
}

extension SpecifyAmountViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }

    var isNavigationBarHidden: Bool { true }
}

// MARK: - DWLocalCurrencyViewControllerDelegate

extension SpecifyAmountViewController: DWLocalCurrencyViewControllerDelegate {
    func localCurrencyViewController(_ controller: DWLocalCurrencyViewController, didSelectCurrency currencyCode: String) {
        amountModel.setupCurrencyCode(currencyCode)
        controller.dismiss(animated: true)
    }

    func localCurrencyViewControllerDidCancel(_ controller: DWLocalCurrencyViewController) {
        controller.dismiss(animated: true)
    }
}

private struct SpecifyAmountView: View {
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
        ZStack(alignment: .top) {
            Color.primaryBackground
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                NavigationBar(leading: {
                    NavigationBarElement.back.button { onBack() }
                })
                .background(Color.dash.secondaryBackground)

                VStack(alignment: .leading, spacing: 26) {
                    Text(NSLocalizedString("Specify Amount", comment: "Specify Amount"))
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(Color.primaryText)
                        .padding(.top, 10)

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
                        onSelectInputType: { code in
                            if let index = model.inputItems.firstIndex(where: { $0.currencyCode == code }) {
                                model.selectInputItem(at: index)
                            }
                        }
                    )
                    .frame(minHeight: 90)

                    Spacer(minLength: 0)

                    DashUIKit.NumericKeyboardView(
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
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .background(Color.secondaryBackground)
            }
        }
    }
}
