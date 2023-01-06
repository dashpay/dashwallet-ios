//  
//  Created by Andrei Ashikhmin
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

import Foundation

final class MinimumDepositBanner: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        configureHierarchy()
    }
    
    func configureHierarchy() {
        backgroundColor = .dw_dashBlue()
        translatesAutoresizingMaskIntoConstraints = false
        
        let messageStack = UIStackView()
        messageStack.translatesAutoresizingMaskIntoConstraints = false
        messageStack.axis = .horizontal
        messageStack.spacing = 10
        
        let message = UILabel()
        message.font = .dw_regularFont(ofSize: 12)
        message.textColor = .white
        let minimumDashAmount = DSPriceManager.sharedInstance().string(forDashAmount: Int64(CrowdNode.minimumDeposit))!
        message.text = NSLocalizedString("First deposit should be more than \(minimumDashAmount)", comment: "CrowdNode")
        messageStack.addArrangedSubview(message)
        
        let infoIcon = UIImageView(image: UIImage(systemName: "info.circle"))
        infoIcon.tintColor = .white
        messageStack.addArrangedSubview(infoIcon)
        
        addSubview(messageStack)
        
        NSLayoutConstraint.activate([
            messageStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            infoIcon.heightAnchor.constraint(equalToConstant: 16),
            infoIcon.widthAnchor.constraint(equalToConstant: 16)
        ])
    }
}
