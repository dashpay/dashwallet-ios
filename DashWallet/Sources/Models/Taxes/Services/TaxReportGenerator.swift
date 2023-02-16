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

import Foundation

// MARK: - TaxReportGeneratorObjcWrapper

@objc(TaxReportGenerator)
class TaxReportGeneratorObjcWrapper: NSObject {
    @objc
    static func generateCSVReport(completionHandler: @escaping (_ fileName: String, _ file: URL) -> Void,
                                  errorHandler: @escaping (_ error: Error) -> Void) {
        TaxReportGenerator.generateCSVReport(completionHandler: completionHandler, errorHandler: errorHandler)
    }
}

// MARK: - TaxReportGenerator

enum TaxReportGenerator {
    private enum ReportColumns: String, CustomStringConvertible, CaseIterable {
        var description: String {
            rawValue
        }

        case dateAndTime = "Date and time"
        case txType = "Transaction Type"
        case sentQuantity = "Sent Quantity"
        case sentCurrency = "Sent Currency"
        case sendingSource = "Sending Source"
        case receivedQuantity = "Received Quantity"
        case receivedCurrency = "Received Currency"
        case receivingDestination = "Receiving Destination"
        case fee = "Fee"
        case feeCurrency = "Fee Currency"
        case exchangeTxId = "Exchange Transaction ID"
        case blockchainTxHash = "Blockchain Transaction Hash"
    }

    static func generateCSVReport(completionHandler: @escaping (_ fileName: String, _ file: URL) -> Void,
                                  errorHandler: @escaping (_ error: Error) -> Void) {
        guard DWEnvironment.sharedInstance().currentChainManager.syncPhase == .synced else {
            let error = NSError(domain: "DashWallet",
                                code: 500,
                                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Please wait until the wallet is fully synced before exporting your transaction history",
                                                                                        comment: "")])
            errorHandler(error)
            return
        }

        DispatchQueue.global(qos: .default).async {
            let transactions = transactions
            let userInfos = TxUserInfoDAOImpl.shared.dictionaryOfAllItems()

            let csv = CSVBuilder<ReportColumns, DSTransaction>()
                .set(columns: ReportColumns.allCases)
                .build(from: transactions) { column, tx in
                    let userInfo = userInfos[tx.txHashData]
                    return value(for: column, transaction: tx, andUserInfo: userInfo)
                }

            guard let documentsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
                errorHandler(NSError(domain: "DashWallet",
                                     code: 500,
                                     userInfo: [NSLocalizedDescriptionKey: "Unable to locate document directory"]))
                return
            }

            let fileName = generateFileName()
            let filePath = URL(fileURLWithPath: documentsDir).appendingPathComponent(fileName)

            do {
                try csv.write(to: filePath, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    completionHandler(fileName, filePath)
                }
            } catch {
                errorHandler(error)
            }
        }
    }

    private static var transactions: [DSTransaction] {
        let wallet = DWEnvironment.sharedInstance().currentWallet
        let transactions = wallet
            .allTransactions
            .filter { $0.direction != .moved && $0.direction != .notAccountFunds }
            .sorted(by: { $0.timestamp < $1.timestamp })

        return transactions
    }

    private static func generateFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.calendar = Calendar(identifier: .gregorian)

        let now = Date()
        let iso8601String = dateFormatter.string(from: now)
        let fileName = "report-\(iso8601String).csv"

        return fileName
    }

    private static func value(for column: ReportColumns, transaction: DSTransaction, andUserInfo userInfo: TxUserInfo?) -> String {
        let transactionDirection = transaction.direction
        let isOutcoming = transactionDirection == .sent

        let kCurrency = "DASH"
        let kSource = "DASH"

        switch column {
        case .dateAndTime:
            return transaction.formattedISO8601TxDate
        case .txType:
            let taxCategoryString = userInfo?.taxCategoryString() ?? transaction.defaultTaxCategoryString()
            return taxCategoryString
        case .sentQuantity:
            let fee = transactionDirection == .sent ? transaction.feeUsed : 0
            let dashAmount = transaction.dashAmount + fee
            let formattedNumber = NumberFormatter.csvDashFormatter.string(from: dashAmount.dashAmount as NSDecimalNumber) ?? ""
            return isOutcoming ? formattedNumber : ""
        case .sentCurrency:
            return isOutcoming ? kCurrency : ""
        case .sendingSource:
            return isOutcoming ? kSource : ""
        case .receivedQuantity:
            let fee = transactionDirection == .sent ? transaction.feeUsed : 0
            let dashAmount = transaction.dashAmount + fee
            let formattedNumber = NumberFormatter.csvDashFormatter.string(from: dashAmount.dashAmount as NSDecimalNumber) ?? ""
            return isOutcoming ? "" : formattedNumber
        case .receivedCurrency:
            return isOutcoming ? "" : kCurrency
        case .receivingDestination:
            return isOutcoming ? "" : kSource
        case .fee:
            return ""
        case .feeCurrency:
            return ""
        case .exchangeTxId:
            return ""
        case .blockchainTxHash:
            return transaction.txHashHexString
        }
    }
}

