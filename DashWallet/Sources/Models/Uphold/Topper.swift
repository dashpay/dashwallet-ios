//  
//  Created by Andrei Ashikhmin
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
import SwiftJWT
import CryptorECC

struct TopperClaims: Claims {
    let jti: String
    let sub: String
    let iat: Date
    let source: [String: String]
    let target: [String: String]
}

class Topper {
    private static let defaultFiatAmount = 100 // Target 100 USD, or similar in other currencies
    private static let baseUrl = "https://app.topperpay.com/"
    private static let sandboxUrl = "https://app.sandbox.topperpay.com/"
    private static let supportedAssetsUrl = "https://api.topperpay.com/assets/crypto-onramp"
    private static let supportedPaymentMethodsUrl = "https://api.topperpay.com/payment-methods/crypto-onramp"
    
    private var keyId: String = ""
    private var widgetId: String = ""
    private var privateKey: String = ""
    private var isSandbox: Bool = false
    private var supportedAssets = Set<String>()
    private var supportedPaymentMethods: [TopperPaymentMethod] = []
    
    var hasValidCredentials: Bool {
        return !keyId.isEmpty && !widgetId.isEmpty && !privateKey.isEmpty
    }
    
    init(keyId: String, widgetId: String, privateKey: String, isSandbox: Bool) {
        self.keyId = keyId
        self.widgetId = widgetId
        self.privateKey = privateKey
        self.isSandbox = isSandbox
    }
    
    func isSupportedAsset(asset: String) -> Bool {
        return supportedAssets.contains(asset)
    }
    
    func getOnRampUrl(desiredSourceAsset: String, receiverAddress: String, walletName: String) -> String {
        let currency = isSupportedAsset(asset: desiredSourceAsset) ? desiredSourceAsset : kDefaultCurrencyCode
        let token = generateToken(
            privateKeyData: Data(privateKey.utf8),
            sourceAsset: currency,
            receiverAddress: receiverAddress,
            walletName: walletName
        )
        
        return "\(isSandbox ? Topper.sandboxUrl : Topper.baseUrl)?bt=\(token)"
    }
    
    func refreshPaymentMethods() {
        URLSession.shared.dataTask(with: URL(string: Topper.supportedPaymentMethodsUrl)!) { [weak self] data, _, error in
            guard let data = data, error == nil else {
                DSLogger.log("Failed to get supported assets from Topper: \(String(describing: error))")
                return
            }
            
            do {
                let root = try JSONDecoder().decode(SupportedTopperPaymentMethods.self, from: data)
                let paymentMethods = root.paymentMethods.filter { $0.type == "credit-card" && $0.billingAsset == "USD" }
                self?.supportedPaymentMethods = paymentMethods
            } catch {
                DSLogger.log("Failed to decode supported assets from Topper: \(String(describing: error))")
            }
        }.resume()
    }
    
    func refreshSupportedAssets() {
        URLSession.shared.dataTask(with: URL(string: Topper.supportedAssetsUrl)!) { [weak self] data, _, error in
            if error != nil || data == nil {
                DSLogger.log("Topper: request failed. \(String(describing: error))")
            } else {
                do {
                    let root = try JSONDecoder().decode(SupportedTopperAssets.self, from: data!)
                    self?.supportedAssets = Set(root.assets.source.map { $0.code })
                } catch {
                    DSLogger.log("Topper: failed to decode JSON. \(error)")
                }
            }
        }.resume()
    }
    
    private func generateToken(privateKeyData: Data, sourceAsset: String, receiverAddress: String, walletName: String) -> String {
        do {
            let defaultValue = getDefaultValue(sourceAsset: sourceAsset, paymentMethods: supportedPaymentMethods)
            let amount = defaultValue.value.string
            let header = Header(kid: keyId)
            let claims = TopperClaims(
                jti: UUID().uuidString,
                sub: widgetId,
                iat: Date(),
                source: [ 
                    "asset": sourceAsset,
                    "amount": amount
                ],
                target: [
                    "address": receiverAddress,
                    "asset": "DASH",
                    "network": "dash",
                    "priority": "fast",
                    "label": walletName
                ]
            )
            
            var jwt = JWT(header: header, claims: claims)
            return try jwt.sign(using: JWTSigner.es256(privateKey: privateKeyData))
        } catch {
            DSLogger.log("Topper: failed to generate a JWT token. \(error)")
            return ""
        }
    }

    private func getDefaultValue(sourceAsset: String, paymentMethods: [TopperPaymentMethod]) -> Int {
        guard let paymentMethod = paymentMethods.first(where: { $0.type == "credit-card" && $0.billingAsset == "USD" }) else {
            return Topper.defaultFiatAmount
        }
        
        guard let minimumUSDString = paymentMethod.limits.first(where: { $0.asset == "USD" })?.minimum,
              let minimumUSD = Decimal(string: minimumUSDString) else {
            return Topper.defaultFiatAmount
        }
        
        let minimumMultiplier = Decimal(Topper.defaultFiatAmount) / minimumUSD
                
        if let minimumString = paymentMethod.limits.first(where: { $0.asset == sourceAsset })?.minimum, let minimum = Decimal(string: minimumString) {
            var amount: Decimal
            
            if minimumMultiplier > Decimal(1) {
                amount = minimum * minimumMultiplier
            } else {
                amount = minimum.rounded(toSignificantDigits: 2, roundingMode: .up)
            }
            
            // This section will round the amount up
            // 1. amounts below 100 will be rounded up to 1 significant digit: 92 becomes 90
            // 2. amounts above 100 will be rounded up to 2 significant digits: 15070 becomes 15000
            let sigDigits = amount > Decimal(100) ? 2 : 1
            amount = amount.rounded(toSignificantDigits: sigDigits, roundingMode: .up)

            return NSDecimalNumber(decimal: amount).intValue
        }
        
        return Topper.defaultFiatAmount
    }
}
