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

protocol GetStartedViewControllerDelegate: AnyObject {
    func getStartedViewControllerDidContinue(_ controller: GetStartedViewController)
}

class GetStartedViewController: ActionButtonViewController, NavigationFullscreenable {
    let page: DWGetStartedPage
    weak var delegate: GetStartedViewControllerDelegate?

    init(page: DWGetStartedPage) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isActionButtonInNavigationBar: Bool {
        return false
    }

    override var actionButtonTitle: String {
        return NSLocalizedString("Continue", comment: "")
    }

    var requiresNoNavigationBar: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        actionButton?.isEnabled = true
        view.backgroundColor = UIColor.dw_secondaryBackground()

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        setupContentView(contentView)

        let content = DWGetStartedContentViewController(page: page)
        dw_embedChild(content, inContainer: contentView)
    }

    override func actionButtonAction(sender: UIView) {
        delegate?.getStartedViewControllerDidContinue(self)
    }
}
