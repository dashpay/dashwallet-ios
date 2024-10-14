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

protocol WelcomeViewControllerDelegate: AnyObject {
    func welcomeViewControllerDidFinish(_ controller: WelcomeViewController)
}

class WelcomeViewController: ActionButtonViewController, NavigationFullscreenable {
    weak var delegate: WelcomeViewControllerDelegate?
    private var collection: DWDPWelcomeCollectionViewController!
    
    override var isActionButtonInNavigationBar: Bool {
        return false
    }
    
    override var actionButtonTitle: String {
        return NSLocalizedString("Continue", comment: "")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        actionButton?.isEnabled = true
        view.backgroundColor = UIColor.dw_background()
        
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        setupContentView(contentView)
        
        collection = DWDPWelcomeCollectionViewController()
        dw_embedChild(collection, inContainer: contentView)
    }
    
    override func actionButtonAction(sender: UIView) {
        if collection.canSwitchToNext() {
            collection.switchToNext()
        } else {
            delegate?.welcomeViewControllerDidFinish(self)
        }
    }
    
    // MARK: - NavigationFullscreenable
    
    var requiresNoNavigationBar: Bool {
        return true
    }
}
