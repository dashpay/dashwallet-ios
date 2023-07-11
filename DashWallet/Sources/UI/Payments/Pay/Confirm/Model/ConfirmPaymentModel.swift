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
}

// MARK: - ConfirmPaymentModel

final class ConfirmPaymentModel {
    private(set) var dataSource: ConfirmPaymentDataSource!
    private(set) var items: [DWTitleDetailItem]!

    public var dataSourceDidChange: (() -> ())?

    private var currencyExchangeToken: CurrencyExchangerObserver!

    init(dataSource: ConfirmPaymentDataSource) {
        update(with: dataSource)

        currencyExchangeToken = CurrencyExchanger.shared.addObserver { [weak self] _ in
            self?.dataSourceDidChange?()
        }
    }

    public func update(with dataSource: ConfirmPaymentDataSource) {
        self.dataSource = dataSource
        items = items(from: dataSource)
        dataSourceDidChange?()
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

        if let item = dataSource.fee(with: font, tintColor: .dw_darkTitle()) {
            arr.append(item)
        }

        arr.append(dataSource.total(with: font, tintColor: .dw_darkTitle()))

        return arr
    }

    deinit {
        CurrencyExchanger.shared.removeObserver(currencyExchangeToken)
    }
}

// MARK: BalanceViewDataSource

extension ConfirmPaymentModel: BalanceViewDataSource {
    var mainAmountString: String {
        dataSource.amountToDisplay.formattedDashAmount
    }

    var supplementaryAmountString: String {
        let fiat: String

        if let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: dataSource.amountToDisplay.dashAmount, to: App.fiatCurrency) {
            fiat = NumberFormatter.fiatFormatter.string(from: fiatAmount as NSNumber)!
        } else {
            fiat = NSLocalizedString("Syncing...", comment: "Balance")
        }

        return fiat
    }
}
