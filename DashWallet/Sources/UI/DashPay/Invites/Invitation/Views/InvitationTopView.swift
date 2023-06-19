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

class InvitationTopView: BaseInvitationTopView {
    private var iconView: UIImageView!
    private var titleLabel: UILabel!
    private var dateLabel: UILabel!
    
    private var index: Int = 0
    
    init(index: Int) {
        super.init(frame: .zero)
        
        self.index = index
        
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 5
        self.addSubview(stackView)
        
        iconView = UIImageView(image: UIImage(named: "icon_invitation_unread_big")!)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .center
        stackView.addArrangedSubview(iconView)
        
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.textColor = UIColor.dw_darkTitle()
        title.font = UIFont.dw_font(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.numberOfLines = 0
        stackView.addArrangedSubview(title)
        titleLabel = title
        
        dateLabel = UILabel()
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.textColor = UIColor.dw_secondaryText()
        dateLabel.font = UIFont.dw_font(forTextStyle: .footnote)
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textAlignment = .center
        dateLabel.numberOfLines = 0
        stackView.addArrangedSubview(dateLabel)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: self.centerYAnchor, constant: 0),
            
            iconView.heightAnchor.constraint(equalToConstant: 72),
            iconView.widthAnchor.constraint(equalToConstant: 72),
            
            previewButton.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),
            self.trailingAnchor.constraint(equalTo: previewButton.trailingAnchor, constant: 16),
            self.bottomAnchor.constraint(equalTo: previewButton.bottomAnchor, constant: 4),
            previewButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func update(with blockchainIdentity: DSBlockchainIdentity, invitation: DSBlockchainInvitation) {
        if invitation.identity.isRegistered {
            iconView.image = UIImage(named: "icon_invitation_read_big")!
        }
        
        let tag = invitation.tag.isEmpty ? nil : invitation.tag
        let defaultTitle = NSString.localizedStringWithFormat(NSLocalizedString("Invitation %ld", comment: "") as NSString, index)
        let title = invitation.name ?? (tag ?? String(defaultTitle))
        titleLabel.text = title
            
        
        let transaction: DSTransaction = invitation.identity.registrationCreditFundingTransaction!
        let chain = DWEnvironment.sharedInstance().currentChain
        
        let now = chain.timestamp(forBlockHeight: UInt32(TX_UNCONFIRMED))
        let txTime = (transaction.timestamp > 1) ? transaction.timestamp : now
        let txDate = Date(timeIntervalSince1970: txTime)
        let dateString = DWDateFormatter.sharedInstance().shortString(from: txDate)
        dateLabel.text = dateString
    }
}

class BaseInvitationTopView: UIView {
    
    var previewButton: DWActionButton = DWActionButton()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.backgroundColor = UIColor.dw_background()
        
        previewButton.translatesAutoresizingMaskIntoConstraints = false
        previewButton.inverted = true
        previewButton.setTitle(NSLocalizedString("Preview Invitation", comment: ""), for: .normal)
        self.addSubview(previewButton)
        
        NSLayoutConstraint.activate([
            previewButton.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),
            self.trailingAnchor.constraint(equalTo: previewButton.trailingAnchor, constant: 16),
            self.bottomAnchor.constraint(equalTo: previewButton.bottomAnchor, constant: 4),
            previewButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(with blockchainIdentity: DSBlockchainIdentity, invitation: DSBlockchainInvitation) {
        
    }
    
    func viewWillAppear() {
        
    }
    
    func viewDidAppear() {
        
    }
    
}
