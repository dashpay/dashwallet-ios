//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

import WatchKit

final class DWMainInterfaceController: WKInterfaceController {
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        let names: [String]
        switch DWWatchDataManager.shared.walletStatus {
        case .unknown, .notSetup:
            names = ["DWSetupInfoInterfaceController"]
        case .hasSetup:
            names = ["BRAWBalanceInterfaceController", "BRAWReceiveMoneyInterfaceController"]
        }

        if #available(watchOSApplicationExtension 4.0, *) {
            WKInterfaceController.reloadRootPageControllers(withNames: names,
                                                            contexts: nil,
                                                            orientation: .horizontal,
                                                            pageIndex: 0)
        }
        else {
            WKInterfaceController.reloadRootControllers(withNames: names, contexts: nil)
        }
    }
}
