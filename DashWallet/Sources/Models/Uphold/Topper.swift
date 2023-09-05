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

struct MyClaims: Claims {
    let jti: String
    let sub: String
    let iat: Date
    let source: [String: String]
    let target: [String: String]
}

class Topper {
    public static let shared = Topper()
    
    func generateToken() -> String? {
        if let path = Bundle.main.path(forResource: "Topper-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            let keyId = dict["KEY_ID"] as! String
            let widgetId = dict["WIDGET_ID"] as! String
            let privateKey = dict["PRIVATE_KEY"] as! String
            
            let privateKeyData = Data(privateKey.utf8)
            let header = Header(kid: keyId)
            let claims = MyClaims(
                jti: UUID().uuidString,
                sub: widgetId,
                iat: Date(),
                source: [
                    "asset": "USD",
                    "amount": "10.0"
                ],
                target: [
                    "address": "Xe66CJjSjxdyzpqYMsRPhWuy3gueC5tDTD",
                    "asset": "DASH",
                    "network": "dash",
                    "label": "Dash Wallet"
                ]
            )
            
            var jwt = JWT(header: header, claims: claims)
            
            do {
                let token = try jwt.sign(using: JWTSigner.es256(privateKey: privateKeyData))
                return "https://app.topperpay.com/?bt=\(token)"
            } catch {
                return nil
            }
        }
        
        return nil
    }
}
