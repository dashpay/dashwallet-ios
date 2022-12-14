//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

extension BaseViewController {
    func showSuccessTransactionStatus(text: String) {
        let vc = SuccessfulOperationStatusViewController.initiate(from: sb("Coinbase"))
        vc.closeHandler = { [weak self] in
            guard let wSelf = self else { return }
            wSelf.navigationController?.popToViewController(wSelf.previousControllerOnNavigationStack!, animated: true)
        }
        vc.headerText = NSLocalizedString("Transfer successful", comment: "Coinbase")
        vc.descriptionText = text

        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }

    func showFailedTransactionStatus(text: String) {
        let vc = FailedOperationStatusViewController.initiate(from: sb("Coinbase"))
        vc.headerText = NSLocalizedString("Transfer Failed", comment: "Coinbase")
        vc.descriptionText = text
        vc.retryHandler = { [weak self] in
            guard let wSelf = self else { return }
            wSelf.navigationController?.popToViewController(wSelf, animated: true)
        }
        vc.cancelHandler = { [weak self] in
            guard let wSelf = self else { return }
            wSelf.navigationController?.popToViewController(wSelf.previousControllerOnNavigationStack!, animated: true)
        }
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }
}
