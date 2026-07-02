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

    private let refundAddress: String
    private let sellAmount: String
    private let swapProvider: SwapProvider

    init(coin: SwapCryptoCurrency, refundAddress: String, sellAmount: String, swapProvider: SwapProvider) {
        self.coin = coin
        self.coinCode = coin.code
        self.refundAddress = refundAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sellAmount = sellAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        self.swapProvider = swapProvider
    }

    var title: String {
        let network = SwapCryptoCurrency.chainDisplayName(coin.chain)
        guard !network.isEmpty else {
            return String(format: NSLocalizedString("Send %@ to this address", comment: "Dash DEX"), coinCode)
        }
        return String(format: NSLocalizedString("Send %@ (%@) to this address", comment: "Dash DEX"), coinCode, network)
    }

    var subtitle: String {
        NSLocalizedString("Once the network confirms your transfer, we'll convert it to Dash and deposit it in your Dash Wallet.", comment: "Dash DEX")
    }

    var copyText: String {
        let trimmedURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURI.isEmpty { return trimmedURI }
        return depositAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var qrContent: String {
        // Encode the full payment URI (BIP21 for UTXO, EIP-681 for EVM, bare address elsewhere),
        // matching Android so a scanning wallet auto-fills token + network + recipient + amount.
        copyText
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        depositAddress = ""
        uri = ""
        memoText = nil
        qrImage = nil
        defer { isLoading = false }

        guard !coin.swapAsset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !refundAddress.isEmpty,
              !sellAmount.isEmpty else {
            errorMessage = NSLocalizedString("Missing swap details", comment: "Dash DEX")
            return
        }

        guard let destinationAddress = DWEnvironment.sharedInstance().currentAccount.receiveAddress, !destinationAddress.isEmpty else {
            errorMessage = NSLocalizedString("Missing swap details", comment: "Dash DEX")
            return
        }

        do {
            let order = try await swapProvider.createBuyOrder(
                sellAsset: coin.swapAsset,
                sellAmount: sellAmount,
                destination: destinationAddress,
                refundAddress: refundAddress
            )

            depositAddress = order.depositAddress
            uri = SwapDepositURIBuilder.uri(
                for: coin,
                address: order.depositAddress,
                amount: order.sellAmount,
                memo: order.memo
            )
            let trimmedMemo = order.memo?.trimmingCharacters(in: .whitespacesAndNewlines)
            memoText = trimmedMemo?.isEmpty == true ? nil : trimmedMemo
            qrImage = generateQRCode(from: qrContent)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else {
            return nil
        }

        return UIImage.dw_image(withQRCodeData: data, color: CIColor(color: UIColor.label))
    }
}
