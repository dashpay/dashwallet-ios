//  
//  Created by Pavel Tikhonenko
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

import Foundation

@objc class AtmListViewController: PointOfUseListViewController {
    override func configureModel() {
        model = AtmListModel()
    }
    
    override func configureHierarchy() {
        self.title = NSLocalizedString("ATMs", comment: "");
        self.view.backgroundColor = .dw_background()
        
        //let infoButton: UIButton = UIButton(type: .infoLight)
        //infoButton.addTarget(self, action: #selector(infoButtonAction), for: .touchUpInside)
        //self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: infoButton)
        
        super.configureHierarchy()
    }

}
