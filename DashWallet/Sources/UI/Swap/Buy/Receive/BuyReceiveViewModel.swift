//
//  BuyReceiveViewModel.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
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
import UIKit

@MainActor
final class BuyReceiveViewModel: ObservableObject {
    let coin: SwapCryptoCurrency
    let coinCode: String

    @Published var depositAddress: String = ""
    @Published var uri: String = ""
    @Published var memoText: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var qrImage: UIImage?
    @Published private var confirmedSellAmount: String = ""

    init(coin: SwapCryptoCurrency, order: BuyOrder) {
        self.coin = coin
        self.coinCode = coin.code

        let addr = order.depositAddress
        let amount = order.sellAmount

        self.depositAddress = addr
        self.confirmedSellAmount = amount

        let uriString = SwapDepositURIBuilder.uri(
            for: coin,
            address: addr,
            amount: amount,
            memo: order.memo
        )
        self.uri = uriString

        let trimmedMemo = order.memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.memoText = trimmedMemo?.isEmpty == true ? nil : trimmedMemo

        let qrStr = uriString.isEmpty ? addr : uriString
        self.qrImage = Self.generateQRCode(from: qrStr)
    }

    var title: String {
        let network = SwapCryptoCurrency.chainDisplayName(coin.chain)
        guard !network.isEmpty else {
            return String(format: NSLocalizedString("Send %@ to this address", comment: "Dash DEX"), coinCode)
        }
        return String(format: NSLocalizedString("Send %@ (%@) to this address", comment: "Dash DEX"), coinCode, network)
    }

    var subtitle: String {
        NSLocalizedString("Once the network confirms your transfer, we'll convert it to Dash and deposit it in your DashPay wallet", comment: "Dash DEX / dex_receive_description")
    }

    var copyText: String {
        let trimmedURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURI.isEmpty { return trimmedURI }
        return depositAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the deposit URI is a bare address with no amount or memo embedded.
    var isBareURI: Bool {
        if !isLoading, !depositAddress.isEmpty {
            return uri == depositAddress
        }
        return SwapDepositURIBuilder.isBareURI(for: coin)
    }

    /// Amount string to display when the URI cannot carry it (bare-address chains only).
    var displaySendAmount: String? {
        guard isBareURI else { return nil }
        let trimmed = confirmedSellAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let amount = SwapDepositURIBuilder.displaySendAmount(for: coin, amount: trimmed)
        return amount.isEmpty ? nil : "\(amount) \(coinCode)"
    }

    var qrContent: String {
        copyText
    }

    func load() async {
        // Order was created on the Refund Address screen; everything is resolved in init.
    }

    private static func generateQRCode(from string: String) -> UIImage? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else {
            return nil
        }
        return UIImage.dw_image(withQRCodeData: data, color: CIColor(color: UIColor.label))
    }
}
