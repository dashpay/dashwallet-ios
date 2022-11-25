//  
//  Created by tkhp
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

protocol ProvideAmountViewControllerDelegate: AnyObject {
    func provideAmountViewControllerDidInput(amount: UInt64)
}

final class ProvideAmountViewController: SendAmountViewController {
    weak var delegate: ProvideAmountViewControllerDelegate?
    
    init(address: String) {
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func actionButtonAction(sender: UIView) {
        guard validateInputAmount() else { return }
        
        if (!self.sendAmountModel.isSendAllowed) {
            showAlert(with: "Please wait for the sync to complete".localized(), message: nil)
            return;
        }
        
        DWGlobalOptions.sharedInstance().selectedPaymentCurrency = sendAmountModel.activeAmountType == .main ? .dash : .fiat
        delegate?.provideAmountViewControllerDidInput(amount: UInt64(model.amount.plainAmount))
    }
    
    override func configureHierarchy() {
        super.configureHierarchy()
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 26
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        
        let titleLabel = UILabel()
        titleLabel.font = .dw_font(forTextStyle: .title1)
        titleLabel.text = NSLocalizedString("Send", comment: "Send Screen")
        stackView.addArrangedSubview(titleLabel)
        
        amountView.removeFromSuperview()
        stackView.addArrangedSubview(amountView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }
}
