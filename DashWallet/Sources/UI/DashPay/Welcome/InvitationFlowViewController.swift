//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

protocol InvitationFlowViewControllerDelegate: AnyObject {
    func invitationFlowViewControllerDidFinish(_ controller: InvitationFlowViewController)
}

class InvitationFlowViewController: UIViewController, NavigationFullscreenable {
    weak var delegate: InvitationFlowViewControllerDelegate?
    private var navController: BaseNavigationController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.dw_background()
        let welcomeController = WelcomeViewController()
        welcomeController.delegate = self
        navController = BaseNavigationController(rootViewController: welcomeController)
        dw_embedChild(navController)
    }
    
    // MARK: - DWNavigationFullscreenable
    
    var requiresNoNavigationBar: Bool {
        return true
    }
}

// MARK: - WelcomeViewControllerDelegate

extension InvitationFlowViewController: WelcomeViewControllerDelegate {
    func welcomeViewControllerDidFinish(_ controller: WelcomeViewController) {
        let getStarted = GetStartedViewController(page: ._1)
        getStarted.delegate = self
        navController.setViewControllers([getStarted], animated: true)
    }
}

// MARK: - GetStartedViewControllerDelegate

extension InvitationFlowViewController: GetStartedViewControllerDelegate {
    func getStartedViewControllerDidContinue(_ controller: GetStartedViewController) {
        switch controller.page {
        case ._1:
            let getStarted = GetStartedViewController(page: ._2)
            getStarted.delegate = self
            navController.setViewControllers([getStarted], animated: true)
        case ._2:
            let getStarted = GetStartedViewController(page: ._3)
            getStarted.delegate = self
            navController.setViewControllers([getStarted], animated: true)
        case ._3:
            delegate?.invitationFlowViewControllerDidFinish(self)
        @unknown default:
            break
        }
    }
}
