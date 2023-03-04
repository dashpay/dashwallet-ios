//
//  Created by Andrei Ashikhmin
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

extension UINavigationController {
    func replaceLast(_ n: Int = 1, with controller: UIViewController, animated: Bool = true) {
        var viewControllers = viewControllers
        viewControllers.removeLast(n)
        viewControllers.append(controller)
        setViewControllers(viewControllers, animated: animated)
    }
    
    func toErrorScreen(error: CrowdNode.Error) {
        var headerText = ""
        
        switch error {
        case .deposit, .withdraw:
            headerText = NSLocalizedString("Transfer Error", comment: "CrowdNode")
        case .signUp, .messageStatus(_):
            headerText = NSLocalizedString("Sign up error", comment: "CrowdNode")
        default:
            headerText = NSLocalizedString("Error", comment: "")
        }
        
        let vc = FailedOperationStatusViewController.initiate(from: sb("OperationStatus"))
        vc.headerText = headerText
        let errorDescription = error.errorDescription
        vc.descriptionText = errorDescription
        vc.supportButtonText = NSLocalizedString("Send Report", comment: "Coinbase")
        let backHandler: (() -> ()) = { [weak self] in
            self?.popViewController(animated: true)
        }
        vc.retryHandler = backHandler
        vc.cancelHandler = backHandler
        vc.supportHandler = {
            let url = DWAboutModel.supportURL()
            let safariViewController = SFSafariViewController.dw_controller(with: url)
            self.present(safariViewController, animated: true)
        }
        vc.hidesBottomBarWhenPushed = true
        pushViewController(vc, animated: true)
    }
}
