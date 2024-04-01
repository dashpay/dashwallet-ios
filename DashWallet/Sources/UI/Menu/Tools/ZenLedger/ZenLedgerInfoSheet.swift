//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

import SwiftUI

struct ZenLedgerInfoSheet: View {
    @State var showingZenLedgerSheet: Bool = false
    @State private var showingSafari: Bool = false
    @Environment(\.openURL) var openURL
    
    var body: some View {
        BottomSheet {
            TextIntro(
                icon: .custom("zenledger_large"),
                buttonLabel: NSLocalizedString("Export all transactions", comment: "ZenLedger"),
                action: {
                    print("submit button tapped")
                }
            ) {
                FeatureTopText(
                    title: NSLocalizedString("Simplify your crypto taxes", comment: "ZenLedger"),
                    text: NSLocalizedString("Connect your crypto wallets to the ZenLedger platform. Learn more and get started with your Dash Wallet transactions.", comment: "ZenLedger"),
                    label: "zenledger.io",
                    labelIcon: .custom("external.link"),
                    linkAction: {
                        openURL(URL(string: "https://app.zenledger.io/new_sign_up/")!)
                    }
                )
            }
        }
    }
}
