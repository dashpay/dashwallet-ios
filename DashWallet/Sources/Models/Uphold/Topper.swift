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
    private static let baseUrl = "https://app.topperpay.com/"
    private static let sandboxUrl = "https://app.sandbox.topperpay.com/"
    private static let supportedAssetsUrl = "https://api.topperpay.com/assets/crypto-onramp"
    
    private var keyId: String = ""
    private var widgetId: String = ""
    private var privateKey: String = ""
    private var isSandbox: Bool = false
    private var supportedAssets = Set<String>()
    
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
    
    func refreshSupportedAssets() {
        let task = URLSession.shared.dataTask(with: URL(string: Topper.supportedAssetsUrl)!) { [weak self] (data, _, error) in
            
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
        }
            
        task.resume()
    }
    
    private func generateToken(privateKeyData: Data, sourceAsset: String, receiverAddress: String, walletName: String) -> String {
            
        do {
            let header = Header(kid: keyId)
            let claims = TopperClaims(
                jti: UUID().uuidString,
                sub: widgetId,
                iat: Date(),
                source: [ "asset": sourceAsset ],
                target: [
                    "address": receiverAddress,
                    "amount": "1",
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
}
