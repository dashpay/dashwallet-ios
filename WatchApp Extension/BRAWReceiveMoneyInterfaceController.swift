//
//  BRAWReceiveMoneyInterfaceController.swift
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

import WatchConnectivity
import WatchKit

final class BRAWReceiveMoneyInterfaceController: WKInterfaceController, BRAWKeypadDelegate {
    @IBOutlet private var loadingIndicator: WKInterfaceGroup!
    @IBOutlet private var qrCodeButton: WKInterfaceButton!
    var customQR: UIImage?

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
    }

    override func willActivate() {
        super.willActivate()
        customQR = nil
        updateReceiveUI()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self,
                                       selector: #selector(BRAWReceiveMoneyInterfaceController.updateReceiveUI),
                                       name: DWWatchDataManager.ApplicationDataDidUpdateNotification,
                                       object: nil)

        subscribeToTxNotifications()
    }

    override func didDeactivate() {
        super.didDeactivate()

        unsubsribeFromTxNotifications()
        NotificationCenter.default.removeObserver(self)
    }

    @objc func updateReceiveUI() {
        if Thread.current != .main {
            DispatchQueue.main.async {
                self.updateReceiveUI()
            }

            return
        }

        if DWWatchDataManager.shared.receiveMoneyQRCodeImage == nil {
            loadingIndicator.setHidden(false)
            qrCodeButton.setHidden(true)
        }
        else {
            loadingIndicator.setHidden(true)
            qrCodeButton.setHidden(false)
            var qrImg = DWWatchDataManager.shared.receiveMoneyQRCodeImage
            if customQR != nil {
                print("Using custom qr image")
                qrImg = customQR
            }
            qrCodeButton.setBackgroundImage(qrImg)
        }
    }

    @IBAction private func qrCodeTap(_ sender: AnyObject?) {
        let ctx = BRAWKeypadModel(delegate: self)
        presentController(withName: "Keypad", context: ctx)
    }

    // - MARK: Keypad delegate

    func keypadDidFinish(_ stringValueBits: String) {
        qrCodeButton.setHidden(true)
        loadingIndicator.setHidden(false)
        DWWatchDataManager.shared.requestQRCodeForBalance(stringValueBits) { qrImage, error in
            if let qrImage {
                self.customQR = qrImage
            }
            self.updateReceiveUI()
            print("Got new qr image: \(String(describing: qrImage)) error: \(String(describing: error))")
        }
        dismiss()
    }
}
