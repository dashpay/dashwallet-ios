//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

import WatchConnectivity
import WatchKit

// MARK: - WalletStatus

enum WalletStatus {
    case unknown
    case hasSetup
    case notSetup
}

// MARK: - DWWatchDataManager

final class DWWatchDataManager: NSObject {
    static let ApplicationDataDidUpdateNotification = Notification.Name("ApplicationDataDidUpdateNotification")
    static let WalletStatusDidChangeNotification = Notification.Name("WalletStatusDidChangeNotification")
    static let WalletTxReceiveNotification = Notification.Name("WalletTxReceiveNotification")

    static let shared = DWWatchDataManager()
    static let applicationContextDataFileName = "applicationContextData.txt"

    let session = WCSession.default
    let timerFireInterval: TimeInterval = 7 // have iphone app sync with peer every 7 seconds

    var timer: Timer?

    private var appleWatchData: BRAppleWatchData?

    var balance: String? { appleWatchData?.balance }
    var balanceInLocalCurrency: String? { appleWatchData?.balanceInLocalCurrency }
    var receiveMoneyAddress: String? { appleWatchData?.receiveMoneyAddress }
    var receiveMoneyQRCodeImage: UIImage? { appleWatchData?.receiveMoneyQRCodeImage }
    var lastestTransction: String? { appleWatchData?.lastestTransction }
    var transactionHistory: [BRAppleWatchTransactionData] {
        if let unwrappedAppleWatchData: BRAppleWatchData = appleWatchData {
            return unwrappedAppleWatchData.transactions
        }
        else {
            return [BRAppleWatchTransactionData]()
        }
    }

    var walletStatus: WalletStatus {
        guard let appleWatchData else {
            return .unknown
        }

        return appleWatchData.hasWallet ? .hasSetup : .notSetup
    }

    lazy var dataFilePath: URL = {
        let dirPaths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let docsDir = dirPaths[0] as String
        return URL(fileURLWithPath: docsDir).appendingPathComponent(DWWatchDataManager.applicationContextDataFileName)
    }()

    override init() {
        super.init()
        if appleWatchData == nil {
            unarchiveData()
        }
        session.delegate = self
        session.activate()
    }

    func setupTimerAndReloadIfActive() {
        if session.activationState == .activated {
            setupTimer()
            requestAllData()
        }
    }

    func requestQRCodeForBalance(_ bits: String,
                                 responseHandler: @escaping (_ qrImage: UIImage?, _ error: NSError?)
                                     -> Void) {
        if session.isReachable {
            let msg = [
                AW_SESSION_REQUEST_TYPE: NSNumber(value: AWSessionRquestTypeFetchData.rawValue as UInt32),
                AW_SESSION_REQUEST_DATA_TYPE_KEY: NSNumber(value: AWSessionRquestDataTypeQRCodeBits.rawValue as UInt32),
                AW_SESSION_QR_CODE_BITS_KEY: bits,
            ] as [String: Any]
            session.sendMessage(msg,
                                replyHandler: { ctx in
                                    if let dat = ctx[AW_QR_CODE_BITS_KEY],
                                       let datDat = dat as? Data,
                                       let img = UIImage(data: datDat) {
                                        responseHandler(img, nil)
                                        return
                                    }
                                    let error = NSError(domain: "",
                                                        code: 500,
                                                        userInfo: [
                                                            NSLocalizedDescriptionKey:
                                                                "Unable to get new QR code",
                                                        ])
                                    responseHandler(nil, error)
                                }, errorHandler: { _ in
                                    let error = NSError(domain: "",
                                                        code: 500,
                                                        userInfo: [
                                                            NSLocalizedDescriptionKey:
                                                                NSLocalizedString("Unable to get new QR code", comment: ""),
                                                        ])
                                    responseHandler(nil, error)
                                })
        }
    }

    func balanceAttributedString() -> NSAttributedString? {
        if let originalBalanceString = DWWatchDataManager.shared.balance {
            var balanceString = originalBalanceString.replacingOccurrences(of: "DASH", with: "")
            balanceString = balanceString.trimmingCharacters(in: CharacterSet.whitespaces)
            return attributedStringForBalance(balanceString)
        }
        return nil
    }

    func archiveData(_ appleWatchData: BRAppleWatchData) {
        try? NSKeyedArchiver.archivedData(withRootObject: appleWatchData).write(to: dataFilePath, options: [.atomic])
    }

    func unarchiveData() {
        if let data = try? Data(contentsOf: dataFilePath) {
            appleWatchData = NSKeyedUnarchiver.unarchiveObject(with: data) as? BRAppleWatchData
        }
    }

    func setupTimer() {
        destroyTimer()
        let weakTimerTarget = BRAWWeakTimerTarget(initTarget: self,
                                                  initSelector: #selector(DWWatchDataManager.requestAllData))
        timer = Timer.scheduledTimer(timeInterval: timerFireInterval, target: weakTimerTarget,
                                     selector: #selector(BRAWWeakTimerTarget.timerDidFire),
                                     userInfo: nil, repeats: true)
    }

    func destroyTimer() {
        guard let timer else {
            return
        }

        timer.invalidate()
    }

    // MARK: Private

    @objc private func requestAllData() {
        if Thread.current != .main {
            DispatchQueue.main.async {
                self.requestAllData()
            }

            return
        }

        if session.isReachable {
            // WKInterfaceDevice.currentDevice().playHaptic(WKHapticType.Click)
            let messageToSend = [
                AW_SESSION_REQUEST_TYPE: NSNumber(value: AWSessionRquestTypeFetchData.rawValue as UInt32),
                AW_SESSION_REQUEST_DATA_TYPE_KEY:
                    NSNumber(value: AWSessionRquestDataTypeApplicationContextData.rawValue as UInt32),
            ]
            session.sendMessage(messageToSend, replyHandler: { [unowned self] replyMessage in
                if let data = replyMessage[AW_SESSION_RESPONSE_KEY] as? Data {
                    if let unwrappedAppleWatchData
                        = NSKeyedUnarchiver.unarchiveObject(with: data) as? BRAppleWatchData {
                        let previousAppleWatchData = self.appleWatchData
                        let previousWalletStatus = self.walletStatus
                        self.appleWatchData = unwrappedAppleWatchData
                        let notificationCenter = NotificationCenter.default
                        if previousAppleWatchData != self.appleWatchData {
                            self.archiveData(unwrappedAppleWatchData)
                            notificationCenter.post(name: DWWatchDataManager.ApplicationDataDidUpdateNotification,
                                                    object: nil)
                        }
                        if self.walletStatus != previousWalletStatus {
                            notificationCenter.post(name: DWWatchDataManager.WalletStatusDidChangeNotification,
                                                    object: nil)
                        }
                    }
                }
            }, errorHandler: { error in
                print(error)
            })
        }
    }

    private func attributedStringForBalance(_ balance: String?) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()

        attributedString
            .append(NSAttributedString(string: "Đ", attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray]))

        attributedString.append(NSAttributedString(string: balance ?? "0", attributes:
            [NSAttributedString.Key.foregroundColor: UIColor.white]))

        return attributedString
    }
}

// MARK: WCSessionDelegate

extension DWWatchDataManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // TODO: proper error handling
        setupTimerAndReloadIfActive()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let applicationContextData = applicationContext[AW_APPLICATION_CONTEXT_KEY] as? Data {
            if let transferedAppleWatchData
                = NSKeyedUnarchiver.unarchiveObject(with: applicationContextData) as? BRAppleWatchData {
                let previousWalletStatus = walletStatus
                appleWatchData = transferedAppleWatchData
                archiveData(transferedAppleWatchData)
                let notificationCenter = NotificationCenter.default
                if walletStatus != previousWalletStatus {
                    notificationCenter.post(name: DWWatchDataManager.WalletStatusDidChangeNotification,
                                            object: nil)
                }
                notificationCenter.post(name: DWWatchDataManager.ApplicationDataDidUpdateNotification,
                                        object: nil)
            }
        }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        print("Handle message from phone \(message)")
        if let noteV = message[AW_PHONE_NOTIFICATION_KEY],
           let noteStr = noteV as? String,
           let noteTypeV = message[AW_PHONE_NOTIFICATION_TYPE_KEY],
           let noteTypeN = noteTypeV as? NSNumber,
           noteTypeN.uint32Value == AWPhoneNotificationTypeTxReceive.rawValue {
            let note = Notification(name: DWWatchDataManager.WalletTxReceiveNotification,
                                    object: nil,
                                    userInfo: [
                                        NSLocalizedDescriptionKey: noteStr,
                                    ])
            NotificationCenter.default.post(note)
        }
    }
}
