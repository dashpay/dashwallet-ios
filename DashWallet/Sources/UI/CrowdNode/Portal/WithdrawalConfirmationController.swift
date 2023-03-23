//
//  Created by Andrei Ashikhmin
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

import Combine

// MARK: - WithdrawalConfirmationController

final class WithdrawalConfirmationController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private let viewModel = CrowdNodeModel.shared

    @IBOutlet var balanceView: BalanceView!
    @IBOutlet var adjustedTopLabel: UILabel!
    @IBOutlet var adjustedBottomLabel: UILabel!

    private static let smallSheetHeight: CGFloat = 230
    private static let fitSheetHeight: CGFloat = 310
    @IBOutlet var moreInfoView: UIView!
    @IBOutlet var moreInfoButton: UIButton!
    @IBOutlet var moreInfoFirstRow: UILabel!
    @IBOutlet var moreInfoSecondRow: UILabel!
    @IBOutlet var moreInfoThirdRow: UILabel!
    @IBOutlet var showMoreHeightConstraint: NSLayoutConstraint!

    private var requestedAmount: UInt64!
    private var currencyCode: String!
    private var adjustedAmount: UInt64!

    var confirmedHandler: (() -> ())?

    static func controller(amount: UInt64, currency: String) -> WithdrawalConfirmationController {
        let vc = vc(WithdrawalConfirmationController.self, from: sb("CrowdNode"))
        vc.modalPresentationStyle = .pageSheet
        vc.requestedAmount = amount
        vc.currencyCode = currency

        if #available(iOS 16.0, *) {
            setSheetHeight(vc)
        }

        return vc
    }

    @available(iOS 16.0, *)
    static func setSheetHeight(_ vc: WithdrawalConfirmationController) {
        if let sheet = vc.sheetPresentationController {
            vc.adjustedAmount = CrowdNodeModel.shared.adjustedWithdrawalAmount(requestedAmount: vc.requestedAmount)
            let collapsedDetent: UISheetPresentationController.Detent

            if vc.adjustedAmount == vc.requestedAmount {
                // If the adjusted amount the same as requested,
                // we hide the additional info and only show confirm/cancel buttons
                let smallId = UISheetPresentationController.Detent.Identifier("small")
                collapsedDetent = UISheetPresentationController.Detent.custom(identifier: smallId) { _ in
                    smallSheetHeight
                }
            } else {
                let fitId = UISheetPresentationController.Detent.Identifier("fit")
                collapsedDetent = UISheetPresentationController.Detent.custom(identifier: fitId) { _ in
                    fitSheetHeight
                }
            }

            sheet.detents = [collapsedDetent]
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureObservers()
    }

    @IBAction
    func onCancel() {
        dismiss(animated: true)
    }

    @IBAction
    func onContinue() {
        confirmedHandler?()
        dismiss(animated: true)
    }

    @IBAction
    func onShowMore() {
        expandMoreInfoView()
    }
}

extension WithdrawalConfirmationController {
    private func expandMoreInfoView() {
        let textHeight = calculateMoreInfoTextHeight()
        let sheetHeight = WithdrawalConfirmationController.fitSheetHeight + textHeight - 20
        moreInfoView.alpha = 0

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveLinear) {
            if #available(iOS 16.0, *) {
                self.expandSheet(height: sheetHeight)
            }

            self.moreInfoView.alpha = 1
            self.moreInfoButton.isHidden = true
            self.showMoreHeightConstraint.constant = textHeight
            self.view.layoutIfNeeded()
        }
    }

    private func calculateMoreInfoTextHeight() -> CGFloat {
        moreInfoFirstRow.frame.height + moreInfoSecondRow.frame.height +
            moreInfoThirdRow.frame.height + 15
    }

    @available(iOS 16.0, *)
    private func adjustCollapsedSheet() {
        if let sheet = sheetPresentationController {
            sheet.animateChanges {
                WithdrawalConfirmationController.setSheetHeight(self)
            }
        }
    }

    @available(iOS 16.0, *)
    private func expandSheet(height: CGFloat) {
        if let sheet = sheetPresentationController {
            let expandedId = UISheetPresentationController.Detent.Identifier("expanded")
            let expandedDetent = UISheetPresentationController.Detent.custom(identifier: expandedId) { _ in
                height
            }
            sheet.detents = [expandedDetent]
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = expandedId
            }
        }
    }

    private func configureHierarchy() {
        adjustedAmount = viewModel.adjustedWithdrawalAmount(requestedAmount: requestedAmount)
        balanceView.dataSource = self

        let didAdjust = adjustedAmount != requestedAmount
        moreInfoButton.isHidden = !didAdjust
        adjustedTopLabel.isHidden = !didAdjust
        adjustedBottomLabel.isHidden = !didAdjust

        if didAdjust {
            let difference = UInt64(abs(Int64(requestedAmount) - Int64(adjustedAmount)))
            var adjustedText = difference.formattedDashAmount

            if let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: difference.dashAmount, to: currencyCode) {
                let fiat = NumberFormatter.fiatFormatter(currencyCode: currencyCode).string(from: fiatAmount as NSNumber)!

                if !fiat.isEmpty {
                    adjustedText += " ~ \(fiat)"
                }
            }

            adjustedBottomLabel.text = adjustedText
        }
    }

    private func configureObservers() {
        viewModel.$crowdNodeBalance
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink(receiveValue: { [weak self] _ in
                self?.configureHierarchy()

                if #available(iOS 16.0, *) {
                    self?.adjustCollapsedSheet()
                }
            })
            .store(in: &cancellableBag)
    }
}

// MARK: BalanceViewDataSource

extension WithdrawalConfirmationController: BalanceViewDataSource {
    var mainAmountString: String {
        adjustedAmount.formattedDashAmount
    }

    var supplementaryAmountString: String {
        let fiat: String

        if let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: adjustedAmount.dashAmount, to: currencyCode) {
            fiat = NumberFormatter.fiatFormatter(currencyCode: currencyCode).string(from: fiatAmount as NSNumber)!
        } else {
            fiat = NSLocalizedString("Syncing…", comment: "Balance")
        }

        return fiat
    }
}
