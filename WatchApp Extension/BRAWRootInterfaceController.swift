//
//  BRAWRootInterfaceController.swift
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

final class BRAWRootInterfaceController: WKInterfaceController {
    @IBOutlet private var setupWalletMessageLabel: WKInterfaceLabel! {
        didSet {
            setupWalletMessageLabel.setHidden(true)
        }
    }

    @IBOutlet private var loadingIndicator: WKInterfaceGroup!

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
        updateUI()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(BRAWRootInterfaceController.updateUI),
            name: BRAWWatchDataManager.WalletStatusDidChangeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(BRAWRootInterfaceController.txReceive(_:)),
            name: BRAWWatchDataManager.WalletTxReceiveNotification,
            object: nil
        )
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    func updateUI() {
        if Thread.current != .main {
            DispatchQueue.main.async {
                self.updateUI()
            }

            return
        }

        switch BRAWWatchDataManager.sharedInstance.walletStatus {
        case .unknown:
            loadingIndicator.setHidden(false)
            setupWalletMessageLabel.setHidden(true)
        case .notSetup:
            loadingIndicator.setHidden(true)
            setupWalletMessageLabel.setHidden(false)
        case .hasSetup:
            WKInterfaceController.reloadRootControllers(
                withNames: ["BRAWBalanceInterfaceController", "BRAWReceiveMoneyInterfaceController"], contexts: []
            )
        }
    }

    @objc
    func txReceive(_ notification: Notification?) {
        if Thread.current != .main {
            DispatchQueue.main.async {
                self.txReceive(notification)
            }

            return
        }

        print("root view controller received notification: \(String(describing: notification))")
        if let userData = (notification as NSNotification?)?.userInfo,
            let noteString = userData[NSLocalizedDescriptionKey] as? String {
            presentAlert(
                withTitle: noteString, message: nil, preferredStyle: .alert, actions: [
                    WKAlertAction(title: NSLocalizedString("OK", comment: ""),
                                  style: .cancel, handler: { self.dismiss() }),
                ]
            )
        }
    }
}
