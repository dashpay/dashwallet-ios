//
//  Created by PT
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

import UIKit

class SheetViewController: BaseViewController, DWModalPresentationControllerDelegate {
    private var modalTransition: DWModalTransition?

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)


        let contentViewHeight = contentViewHeight()
        if contentViewHeight != -1 {
            if #available(iOS 16.0, *) {
                modalPresentationStyle = .pageSheet

                guard let sheet = sheetPresentationController else { return }

                let detents: [UISheetPresentationController.Detent]

                let fitId = UISheetPresentationController.Detent.Identifier("fit")
                detents = [UISheetPresentationController.Detent.custom(identifier: fitId) { _ in
                    contentViewHeight
                }]
                sheet.prefersGrabberVisible = true
                sheet.detents = detents
            } else {
                modalPresentationStyle = .custom

                modalTransition = DWModalTransition()
                modalTransition?.modalPresentationControllerDelegate = self
                transitioningDelegate = modalTransition
            }
        } else {
            modalPresentationStyle = .custom

            modalTransition = DWModalTransition()
            transitioningDelegate = modalTransition
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Returns -1 for default value
    func contentViewHeight() -> CGFloat {
        -1
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 16.0, *) {
        } else {
            view.layer.cornerRadius = 15
            view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        }
    }
}
