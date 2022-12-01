//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

import UIKit

// MARK: - TxReclassifyTransactionsInfoViewControllerDelegate

@objc
protocol TxReclassifyTransactionsInfoViewControllerDelegate: AnyObject {
    @objc func txReclassifyTransactionsFlowDidClosedWithUnderstanding(controller: TxReclassifyTransactionsInfoViewController,
                                                                      transaction: DSTransaction)
}

// MARK: - TxReclassifyTransactionsInfoViewController

@objc
class TxReclassifyTransactionsInfoViewController: BasePageSheetViewController {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var whereToChangeButton: UIButton!

    @IBOutlet var outgoingTransactionsTitleLabel: UILabel!
    @IBOutlet var outgoingTransactionsSubtitle1Label: UILabel!
    @IBOutlet var outgoingTransactionsSubtitle1TagLabel: UILabel!
    @IBOutlet var outgoingTransactionsSubtitle2Label: UILabel!
    @IBOutlet var outgoingTransactionsSubtitle2TagLabel: UILabel!

    @IBOutlet var incomingTransactionsTitleLabel: UILabel!
    @IBOutlet var incomingTransactionsSubtitle1Label: UILabel!
    @IBOutlet var incomingTransactionsSubtitle1TagLabel: UILabel!
    @IBOutlet var incomingTransactionsSubtitle2Label: UILabel!
    @IBOutlet var incomingTransactionsSubtitle2TagLabel: UILabel!

    @IBOutlet var linkedAccountsTitleLabel: UILabel!
    @IBOutlet var linkedAccountsSubtitleLabel: UILabel!

    // @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var scrollView: UIScrollView!

    @IBOutlet var transactionScreenContainer: UIView!
    private var transactionScreenImage: UIImage!

    @objc var transaction: DSTransaction!

    @objc weak var delegate: TxReclassifyTransactionsInfoViewControllerDelegate?

    @IBAction func iUndersandAction() {
        dismiss(animated: true) {
            self.delegate?.txReclassifyTransactionsFlowDidClosedWithUnderstanding(controller: self, transaction: self.transaction)
        }
    }

    @IBAction func whereCanIChangeAction() {
        let vc = TxReclassifyTransactionsWhereToChangeViewController.controller()
        vc.transactionScreenImage = transactionScreenImage
        present(vc, animated: true, completion: nil)
    }

    @objc static func controller() -> TxReclassifyTransactionsInfoViewController {
        let storyboard = UIStoryboard(name: "Tx", bundle: nil)
        let vc = storyboard
            .instantiateViewController(identifier: "TxReclassifyTransactionsInfoViewController") as! TxReclassifyTransactionsInfoViewController
        return vc
    }

    private func prepareTransactionScreenImage() {
        let vc = TXDetailViewController.controller()
        vc.model = TxDetailModel(transaction: transaction, dataProvider: DWTransactionListDataProvider())
        dw_embedChild(vc, inContainer: transactionScreenContainer)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIGraphicsBeginImageContextWithOptions(self.view.bounds.size, false, UIScreen.main.scale)
            vc.view.drawHierarchy(in: self.view.bounds, afterScreenUpdates: true)
            self.transactionScreenImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
        }
    }

    private func configureHierarchy() {
        titleLabel.font = UIFont.dw_font(forTextStyle: .title1).withWeight(UIFont.Weight.bold.rawValue)
        subtitleLabel.font = UIFont.dw_font(forTextStyle: .subheadline)
        subtitleLabel.font = UIFont.dw_font(forTextStyle: .subheadline)
        whereToChangeButton.titleLabel?.font = UIFont.dw_font(forTextStyle: .footnote).withWeight(UIFont.Weight.semibold.rawValue)

        outgoingTransactionsTitleLabel.font = UIFont.dw_font(forTextStyle: .subheadline)
            .withWeight(UIFont.Weight.semibold.rawValue)
        incomingTransactionsTitleLabel.font = UIFont.dw_font(forTextStyle: .subheadline)
            .withWeight(UIFont.Weight.semibold.rawValue)
        linkedAccountsTitleLabel.font = UIFont.dw_font(forTextStyle: .subheadline).withWeight(UIFont.Weight.semibold.rawValue)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        prepareTransactionScreenImage()
    }
}
