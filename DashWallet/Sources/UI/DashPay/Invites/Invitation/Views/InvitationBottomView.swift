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

class InvitationBottomView: UIView {
    init(invitation: DSBlockchainInvitation) {
        super.init(frame: .zero)
        
        let stackView = UIStackView()
        stackView.isUserInteractionEnabled = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 5
        stackView.alignment = .center
        addSubview(stackView)
        
        let usedByLabel = UILabel()
        usedByLabel.translatesAutoresizingMaskIntoConstraints = false
        usedByLabel.text = NSLocalizedString("Invitation used by", comment: "")
        usedByLabel.font = UIFont.dw_font(forTextStyle: .footnote)
        usedByLabel.textColor = UIColor.dw_secondaryText()
        stackView.addArrangedSubview(usedByLabel)
        
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.dw_dashBlue().withAlphaComponent(0.7)
        containerView.layer.cornerRadius = 8
        stackView.addArrangedSubview(containerView)
        
        let userStackView = UIStackView()
        userStackView.translatesAutoresizingMaskIntoConstraints = false
        userStackView.axis = .horizontal
        userStackView.spacing = 10
        containerView.addSubview(userStackView)
        
        let avatarView = DWDPAvatarView()
        avatarView.isSmall = true
        avatarView.backgroundMode = .random
        avatarView.blockchainIdentity = invitation.identity
        userStackView.addArrangedSubview(avatarView)
        
        let titleStackView = UIStackView()
        titleStackView.translatesAutoresizingMaskIntoConstraints = false
        titleStackView.axis = .vertical
        titleStackView.spacing = 4
        userStackView.addArrangedSubview(titleStackView)
        
        let titleLable = UILabel()
        titleLable.font = UIFont.dw_mediumFont(ofSize: 14)
        titleLable.text = invitation.identity.displayName ?? invitation.identity.currentDashpayUsername
        titleStackView.addArrangedSubview(titleLable)
        
        if let dn = invitation.identity.displayName, !dn.isEmpty {
            let sublabel = UILabel()
            sublabel.font = UIFont.dw_font(forTextStyle: .footnote)
            sublabel.text = invitation.identity.currentDashpayUsername
            titleStackView.addArrangedSubview(sublabel)
        }
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: self.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            
            userStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            userStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            userStackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            containerView.heightAnchor.constraint(equalToConstant: 64),
            
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),
            
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
