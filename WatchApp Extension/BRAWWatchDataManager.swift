//
//  BRAWWatchDataManager.swift
//  BreadWallet
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
import WatchConnectivity

enum WalletStatus {
    case HasSetup
    case NotSetup
    case CannotConnectToPhone
    case Unknown
}

class BRAWWatchDataManager: NSObject, WCSessionDelegate {
    static let sharedInstance = BRAWWatchDataManager()
    static let ApplicationDataDidUpdateNotification = "ApplicationDataDidUpdateNotification"
    static let WalletStatusDidChangeNotification = "WalletStatusDidChangeNotification"
    
    static let applicationContextDataFileName = "applicationContextData.txt"
    private var appleWatchData : BRAppleWatchData?

    var balance : String? {
        return appleWatchData?.balance
    }
    var balanceInLocalCurrency : String? {
        return appleWatchData?.balanceInLocalCurrency
    }
    var receiveMoneyAddress : String? {
        return appleWatchData?.receiveMoneyAddress
    }
    var receiveMoneyQRCodeImage : UIImage? {
        return appleWatchData?.receiveMoneyQRCodeImage
    }
    var transactionHistory : [BRAppleWatchTransactionData] {
        if let unwrappedAppleWatchData: BRAppleWatchData = appleWatchData,
            let transactions :[BRAppleWatchTransactionData] = unwrappedAppleWatchData.transactions{
            return  transactions
        } else {
            return [BRAppleWatchTransactionData]()
        }
    }
    var lastestTransction : String? {
        return appleWatchData?.lastestTransction
    }
    var walletStatus : WalletStatus  {
        if appleWatchData == nil {
            return WalletStatus.NotSetup
        } else if appleWatchData!.hasWallet {
            return WalletStatus.HasSetup
        } else {
            return WalletStatus.NotSetup
        }
    }
    
    lazy var dataFilePath: NSURL = {
            let filemgr = NSFileManager.defaultManager()
            let dirPaths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory,.UserDomainMask, true)
            let docsDir = dirPaths[0] as String
            return NSURL(fileURLWithPath: docsDir).URLByAppendingPathComponent(applicationContextDataFileName)
        }()
    
    let session : WCSession =  WCSession.defaultSession()
    
    override init() {
        super.init()
        if appleWatchData == nil {
            unarchiveData()
        }
        session.delegate = self
        session.activateSession()
    }
    
    func requestAllData() {
        let messageToSend = [AW_SESSION_REQUEST_TYPE: NSNumber(unsignedInt:AWSessionRquestTypeFetchData.rawValue),
            AW_SESSION_REQUEST_DATA_TYPE_KEY:NSNumber(unsignedInt:AWSessionRquestDataTypeAllData.rawValue)]
        session.sendMessage(messageToSend, replyHandler: { [unowned self] replyMessage in
            //handle and present the message on screen
                if let data = replyMessage[AW_SESSION_RESPONSE_KEY] as? NSData {
                    if let unwrappedAppleWatchData = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? BRAppleWatchData {
                        let previousWalletStatus = self.walletStatus
                        self.appleWatchData = unwrappedAppleWatchData
                        NSNotificationCenter.defaultCenter().postNotificationName(BRAWWatchDataManager.ApplicationDataDidUpdateNotification, object: nil)
                        if self.walletStatus != previousWalletStatus {
                            NSNotificationCenter.defaultCenter().postNotificationName(BRAWWatchDataManager.WalletStatusDidChangeNotification, object: nil)
                        }
                    }
                }
            }, errorHandler: {error in
                print(error)
        })
    }
    
    func session(session: WCSession, didReceiveMessage message: [String : AnyObject]) {
        if let requestType = message[AW_SESSION_REQUEST_TYPE] as? NSNumber {
            if requestType.unsignedIntValue == AWSessionRquestTypeDataUpdateNotification.rawValue {
                if session.reachable {
                    requestAllData()
                }
            }
        }
    }
    
    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
        print("BRAWWatchDataManager:didReceiveApplicationContext:\(applicationContext)")
        if let applicationContextData = applicationContext[AW_APPLICATION_CONTEXT_KEY] as? NSData {
            if let transferedAppleWatchData = NSKeyedUnarchiver.unarchiveObjectWithData(applicationContextData) as? BRAppleWatchData {
                print("appleWatchData:\(appleWatchData)")
                appleWatchData = transferedAppleWatchData
                archiveData(transferedAppleWatchData)
                NSNotificationCenter.defaultCenter().postNotificationName(BRAWWatchDataManager.ApplicationDataDidUpdateNotification, object: nil)
            }
        }
    }
    
    func balanceAttributedString() -> NSAttributedString? {
       if let originalBalanceString = BRAWWatchDataManager.sharedInstance.balance {
            var balanceString = originalBalanceString.stringByReplacingOccurrencesOfString("ƀ", withString: "")
            balanceString = balanceString.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
            return attributedStringForBalance(balanceString)
        }
        return nil
    }
    
    private func attributedStringForBalance(balance: String?)-> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        attributedString.appendAttributedString(NSAttributedString(string: "ƀ", attributes: [NSForegroundColorAttributeName : UIColor.grayColor()]))
        attributedString.appendAttributedString(NSAttributedString(string: balance ?? "0", attributes: [NSForegroundColorAttributeName : UIColor.whiteColor()]))
        return attributedString
    }
    
    func archiveData(appleWatchData: BRAppleWatchData){
        NSKeyedArchiver.archivedDataWithRootObject(appleWatchData).writeToURL(dataFilePath, atomically: true)
        print("archive data to :\(dataFilePath)")
    }
    
    func unarchiveData() {
        if let data = NSData(contentsOfURL: dataFilePath) {
            print("read data from :\(dataFilePath)")
            appleWatchData = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? BRAppleWatchData
        }
    }
    
}
