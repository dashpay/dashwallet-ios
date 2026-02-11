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

class TopperViewModel {
    private let topper: Topper
    public static let shared = TopperViewModel()
    
    private init() {
        let isSandbox = !DWEnvironment.sharedInstance().currentChain.isMainnet()
        var keyId = ""
        var widgetId = ""
        var privateKey = ""
        
        if let path = Bundle.main.path(forResource: "Topper-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            let prefix = isSandbox ? "SANDBOX_" : ""
            keyId = dict["\(prefix)KEY_ID"] as! String
            widgetId = dict["\(prefix)WIDGET_ID"] as! String
            privateKey = dict["\(prefix)PRIVATE_KEY"] as! String
        }
        
        topper = Topper(keyId: keyId, widgetId: widgetId, privateKey: privateKey, isSandbox: isSandbox)
        topper.refreshSupportedAssets()
        topper.refreshPaymentMethods()
    }
    
    func topperBuyUrl(walletName: String) -> String {
        let address = (try? DWEnvironment.sharedInstance().coreService.getReceiveAddress())
            ?? DWEnvironment.sharedInstance().currentAccount.receiveAddress ?? ""
        return topper.getOnRampUrl(desiredSourceAsset: App.fiatCurrency, receiverAddress: address, walletName: walletName)
    }
}
