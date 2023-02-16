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

final class WithdrawalConfirmationController: UIViewController {
    private let viewModel = CrowdNodeModel.shared
    @IBOutlet var balanceView: BalanceView!
    @IBOutlet var moreInfoView: UIView!
    @IBOutlet var moreInfoButton: UIButton!
    @IBOutlet var showMoreHeightConstraint: NSLayoutConstraint!

    static func controller() -> WithdrawalConfirmationController {
        let vc = vc(WithdrawalConfirmationController.self, from: sb("CrowdNode"))
        vc.modalPresentationStyle = .pageSheet

        if #available(iOS 16.0, *) {
            if let sheet = vc.sheetPresentationController {
                let fitId = UISheetPresentationController.Detent.Identifier("fit")
                let fitDetent = UISheetPresentationController.Detent.custom(identifier: fitId) { context in
                    return 310
                }
                sheet.detents = [fitDetent]
            }
        }

        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }
    
    @IBAction
    func onCancel() {
        dismiss(animated: true)
    }
    
    @IBAction
    func onContinue() {
        print("CrowdNode: onContinue")
    }
    
    @IBAction
    func onShowMore() {
        moreInfoView.alpha = 0
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveLinear) {
            if #available(iOS 16.0, *) {
                self.animateSheet()
            }
            
            self.moreInfoView.alpha = 1
            self.moreInfoButton.isHidden = true
            self.showMoreHeightConstraint.constant = 150
            self.view.layoutIfNeeded()
        }
    }
    
    @available(iOS 16.0, *)
    private func animateSheet() {
        if let sheet = sheetPresentationController {
            let expandedId = UISheetPresentationController.Detent.Identifier("expanded")
            let expandedDetent = UISheetPresentationController.Detent.custom(identifier: expandedId) { context in
                return 440
            }
            sheet.detents = [expandedDetent]
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = expandedId
            }
        }
    }
    
    private func configureHierarchy() {
        balanceView.dataSource = self
    }
}

// MARK: - WithdrawalConfirmationController + BalanceViewDataSource

extension WithdrawalConfirmationController: BalanceViewDataSource {
    var mainAmountString: String {
        viewModel.crowdNodeBalance.formattedDashAmount
    }

    var supplementaryAmountString: String {
        let fiat: String

        if let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: viewModel.crowdNodeBalance.dashAmount, to: App.fiatCurrency) {
            fiat = NumberFormatter.fiatFormatter.string(from: fiatAmount as NSNumber)!
        } else {
            fiat = NSLocalizedString("Syncing…", comment: "Balance")
        }

        return fiat
    }
}
