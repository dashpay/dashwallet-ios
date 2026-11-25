//
//  Created by PT
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

// MARK: - ConfirmPaymentDataSource

@objc
public protocol ConfirmPaymentDataSource {
    var hasCommonName: Bool { get }
    var amountToDisplay: UInt64 { get }
    var nameInfo: DWTitleDetailItem? { get }
    var generalInfo: DWTitleDetailItem? { get }

    @objc(addressWithFont:tintColor:)
    func address(with font: UIFont, tintColor: UIColor) -> DWTitleDetailItem?

    @objc(feeWithFont:tintColor:)
    func fee(with font: UIFont, tintColor: UIColor) -> DWTitleDetailItem?

    @objc(totalWithFont:tintColor:)
    func total(with font: UIFont, tintColor: UIColor) -> DWTitleDetailItem

    /// The fee and the all-in debit in duffs.
    ///
    /// The `DWTitleDetailItem`s above carry the same two figures already
    /// formatted, but they carry the Dash symbol as an image attachment — read
    /// back as plain text it is gone, and the row renders a bare number. A
    /// renderer that wants to draw the amount itself needs the number.
    ///
    /// Optional so a data source without duff figures still renders: callers
    /// fall back to the formatted string. Both the L1 payment output and the
    /// Uphold transfer implement them.
    @objc optional var feeDuffs: UInt64 { get }
    @objc optional var totalDuffs: UInt64 { get }
}

// MARK: - ConfirmPaymentModel

/// What the confirmation sheet shows, and the "Sending…" animation of its
/// confirm button. `ConfirmPaymentSheet` observes it directly.
class ConfirmPaymentModel: ObservableObject {
    private(set) var dataSource: ConfirmPaymentDataSource!
    @Published private(set) var items: [DWTitleDetailItem] = []
    /// The members of `items` that carry the fee and the total — handed out so
    /// a renderer can tell those rows apart without matching their titles.
    private(set) var feeItem: DWTitleDetailItem?
    private(set) var totalItem: DWTitleDetailItem?

    /// Off while a payment is in flight: the confirm button locks, Cancel
    /// does not (see `ConfirmPaymentSheet`).
    @Published var isSendingEnabled = true
    @Published public private(set) var period: UInt8 = 0

    private var isSendingNow = false
    private var sendingTimer: Timer?
    private var currencyExchangeToken: CurrencyExchangerObserver!

    private let fiatCurrency: String

    init(dataSource: ConfirmPaymentDataSource, fiatCurrency: String) {
        self.fiatCurrency = fiatCurrency
        update(with: dataSource)

        // The fiat line follows the exchange rate.
        currencyExchangeToken = CurrencyExchanger.shared.addObserver { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public func confirmPayment() {
        objectWillChange.send()
        isSendingNow = true

        sendingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }

            self.period = (self.period + 1) % 4
        }
    }

    public func stopPayment() {
        isSendingNow = false
        period = 0

        sendingTimer?.invalidate()
        sendingTimer = nil
    }

    public func update(with dataSource: ConfirmPaymentDataSource) {
        self.dataSource = dataSource
        items = items(from: dataSource)
    }

    @inline(__always)
    private func items(from dataSource: ConfirmPaymentDataSource) -> [DWTitleDetailItem] {
        var arr = [DWTitleDetailItem]()
        arr.reserveCapacity(3)

        if let item = dataSource.nameInfo {
            arr.append(item)
        }

        if let item = dataSource.generalInfo {
            arr.append(item)
        }

        let font = UIFont.dw_font(forTextStyle: .caption1)

        if let item = dataSource.address(with: font, tintColor: .dw_darkTitle()) {
            arr.append(item)
        }

        feeItem = dataSource.fee(with: font, tintColor: .dw_darkTitle())
        if let item = feeItem {
            arr.append(item)
        }

        let total = dataSource.total(with: font, tintColor: .dw_darkTitle())
        totalItem = total
        arr.append(total)

        return arr
    }

    deinit {
        stopPayment()

        CurrencyExchanger.shared.removeObserver(currencyExchangeToken)
    }
}

extension ConfirmPaymentModel {
    var actionButtonTitle: String {
        if isSendingNow {
            if dataSource.hasCommonName {
                switch period {
                case 1:
                    return NSLocalizedString("Paying.", comment: "2 out of 4 in the Paying Animation")
                case 2:
                    return NSLocalizedString("Paying..", comment: "3 out of 4 in the Paying Animation")
                case 3:
                    return NSLocalizedString("Paying...", comment: "4 out of 4 in the Paying Animation")
                default:
                    return NSLocalizedString("Paying", comment: "1 out of 4 in the Paying Animation")
                }
            } else {
                switch period {
                case 1:
                    return NSLocalizedString("Sending.", comment: "2 out of 4 in the Sending Animation")
                case 2:
                    return NSLocalizedString("Sending..", comment: "3 out of 4 in the Sending Animation")
                case 3:
                    return NSLocalizedString("Sending...", comment: "4 out of 4 in the Sending Animation")
                default:
                    return NSLocalizedString("Sending", comment: "1 out of 4 in the Sending Animation")
                }
            }
        } else {
            return NSLocalizedString("Confirm", comment: "Payment confirmation")
        }
    }
}

// MARK: BalanceViewDataSource

extension ConfirmPaymentModel: BalanceViewDataSource {
    var mainAmountString: String {
        dataSource.amountToDisplay.formattedDashAmount
    }

    var supplementaryAmountString: String {
        let fiat: String

        if let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: dataSource.amountToDisplay.dashAmount, to: fiatCurrency) {
            let nf = NumberFormatter.fiatFormatter(currencyCode: fiatCurrency)
            fiat = nf.string(from: fiatAmount as NSNumber)!
        } else {
            fiat = NSLocalizedString("Syncing...", comment: "Balance")
        }

        return fiat
    }
}
