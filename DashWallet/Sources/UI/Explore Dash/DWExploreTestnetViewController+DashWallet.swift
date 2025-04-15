//  
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

import UIKit
import SwiftUI

private let kMerchantTypesShown = "merchantTypesInfoDialogShownKey"

extension DWExploreTestnetViewController {
    @objc
    public func showWhereToSpendViewController() {
        if UserDefaults.standard.bool(forKey: kMerchantTypesShown) != true {
            let hostingController = UIHostingController(rootView: MerchantTypesDialog { [weak self] in
                UserDefaults.standard.setValue(true, forKey: kMerchantTypesShown)
                self?.showMerchants()
            })
            hostingController.setDetent(640)
            self.present(hostingController, animated: true)
        } else {
            showMerchants()
        }
    }
    
    private func showMerchants() {
        let vc = MerchantListViewController()
        vc.payWithDashHandler = { [weak self] in
            guard let self = self else { return }
            self.delegate?.exploreTestnetViewControllerShowSendPayment(self)
        }
        
        self.navigationController?.pushViewController(vc, animated: true)
    }
}
