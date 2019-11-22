//
//  BRAWTransactionRowControl.swift
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

final class BRAWTransactionRowControl: NSObject {
    @IBOutlet private var statusIcon: WKInterfaceImage! {
        didSet {
            statusIcon.setImage(nil)
        }
    }

    @IBOutlet private var amountLabel: WKInterfaceLabel!
    @IBOutlet private var dateLabel: WKInterfaceLabel!
    @IBOutlet private var seperatorGroup: WKInterfaceGroup!
    @IBOutlet private var localCurrencyAmount: WKInterfaceLabel!

    var type = BRAWTransactionTypeReceive {
        didSet {
            switch type {
            case BRAWTransactionTypeReceive:
                statusIcon.setImageNamed("ReceiveMoneyIcon")
            case BRAWTransactionTypeSent:
                statusIcon.setImageNamed("SentMoneyIcon")
            case BRAWTransactionTypeMove:
                statusIcon.setImageNamed("MoveMoneyIcon")
            case BRAWTransactionTypeInvalid:
                statusIcon.setImageNamed("InvalidTransactionIcon")
            default:
                statusIcon.setImage(nil)
            }
        }
    }

    func update(with transaction: BRAppleWatchTransactionData) {
        let localCurrencyAmountText = transaction.amountTextInLocalCurrency.count > 2
            ? transaction.amountTextInLocalCurrency
            : " "
        amountLabel.setText(transaction.amountText)
        localCurrencyAmount.setText(localCurrencyAmountText)
        dateLabel.setText(transaction.dateText)
        type = transaction.type
        seperatorGroup.setHeight(0.5)
    }
}
