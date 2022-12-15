//
//  BRAWBalanceInterfaceController.swift
//  DashWallet
//
//  Created by Henry on 10/27/15.
//  Copyright (c) 2015 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import WatchKit

final class BRAWBalanceInterfaceController: WKInterfaceController {
    @IBOutlet private var table: WKInterfaceTable!
    var transactionList = [BRAppleWatchTransactionData]()

    @IBOutlet private var balanceTextContainer: WKInterfaceGroup!
    @IBOutlet private var balanceLoadingIndicator: WKInterfaceGroup!
    @IBOutlet private var balanceLabel: WKInterfaceLabel!
    @IBOutlet private var balanceInLocalCurrencyLabel: WKInterfaceLabel!
    @IBOutlet private var transactionHeaderContainer: WKInterfaceGroup! {
        didSet {
            transactionHeaderContainer.setHidden(true) // hide header as default
        }
    }

    var showBalanceLoadingIndicator = false {
        didSet {
            self.balanceTextContainer.setHidden(showBalanceLoadingIndicator)
            self.balanceLoadingIndicator.setHidden(!showBalanceLoadingIndicator)
        }
    }

    // MARK: View life cycle

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        updateBalance()
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
        updateBalance()
        updateTransactionList()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self,
                                       selector: #selector(BRAWBalanceInterfaceController.updateUI),
                                       name: DWWatchDataManager.ApplicationDataDidUpdateNotification,
                                       object: nil)

        subscribeToTxNotifications()
    }

    override func didDeactivate() {
        super.didDeactivate()

        unsubsribeFromTxNotifications()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: UI update

    @objc func updateUI() {
        if Thread.current != .main {
            DispatchQueue.main.async {
                self.updateUI()
            }

            return
        }

        updateBalance()
        updateTransactionList()
    }

    func updateBalance() {
        if let balanceInLocalizationString = DWWatchDataManager.shared.balanceInLocalCurrency as String? {
            if DWWatchDataManager.shared.balanceAttributedString() != nil {
                balanceLabel.setAttributedText(DWWatchDataManager.shared.balanceAttributedString())
            }
            balanceInLocalCurrencyLabel.setText(balanceInLocalizationString)
            showBalanceLoadingIndicator = false
        }
        else {
            showBalanceLoadingIndicator = true
        }
    }

    func updateTransactionList() {
        transactionList = DWWatchDataManager.shared.transactionHistory
        let currentTableRowCount = table.numberOfRows
        let newTransactionCount = transactionList.count
        let numberRowsToInsertOrDelete = newTransactionCount - currentTableRowCount
        transactionHeaderContainer.setHidden(newTransactionCount == 0)
        // insert or delete rows to match number of transactions
        if numberRowsToInsertOrDelete > 0 {
            let range = Range(NSRange(location: currentTableRowCount,
                                      length: numberRowsToInsertOrDelete))
            let ixs = IndexSet(integersIn: range ?? 0 ..< 0)
            table.insertRows(at: ixs, withRowType: "BRAWTransactionRowControl")
        }
        else {
            let range = Range(NSRange(location: newTransactionCount,
                                      length: abs(numberRowsToInsertOrDelete)))
            let ixs = IndexSet(integersIn: range ?? 0 ..< 0)
            table.removeRows(at: ixs)
        }
        // update row content
        for index in 0 ..< newTransactionCount {
            if let rowControl = table.rowController(at: index) as? BRAWTransactionRowControl {
                updateRow(rowControl, transaction: transactionList[index])
            }
        }
    }

    func updateRow(_ rowControl: BRAWTransactionRowControl, transaction: BRAppleWatchTransactionData) {
        rowControl.update(with: transaction)
    }
}
