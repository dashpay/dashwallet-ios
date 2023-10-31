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

import UIKit

class SuccessInvitationTopView: BaseInvitationTopView {
    let iconView: DWSuccessInvitationView = DWSuccessInvitationView(frame: .zero)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.transform = CGAffineTransform(scaleX: 0.68, y: 0.68)
        self.addSubview(iconView)
        
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.textColor = UIColor.dw_darkTitle()
        title.font = UIFont.dw_font(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.text = NSLocalizedString("Invitation Created Successfully", comment: "")
        title.textAlignment = .center
        title.numberOfLines = 0
        self.addSubview(title)
        
        title.setContentCompressionResistancePriority(.required, for: .vertical)
    
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: self.topAnchor, constant: 32),
            iconView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            
            title.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),
            self.trailingAnchor.constraint(equalTo: title.trailingAnchor, constant: 16),
            
            previewButton.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func update(with blockchainIdentity: DSBlockchainIdentity, invitation: DSBlockchainInvitation) {
        self.iconView.blockchainIdentity = blockchainIdentity;
    }
    
    override func viewWillAppear() {
        iconView.prepareForAnimation()
    }
    
    override func viewDidAppear() {
        iconView.showAnimated()
    }
}
