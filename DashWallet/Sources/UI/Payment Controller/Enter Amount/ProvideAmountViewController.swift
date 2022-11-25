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
    
    let address: String
    
    init(address: String) {
        self.address = address
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func actionButtonAction(sender: UIView) {
        guard validateInputAmount() else { return }
        
        
        if (!self.sendAmountModel.isSendAllowed) {
            showAlert(with: NSLocalizedString("Please wait for the sync to complete", comment: "Send Screen"), message: nil)
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
        //stackView.alignment = .leading
        contentView.addSubview(stackView)
        
        let textContainer = UIStackView()
        textContainer.axis = .vertical
        textContainer.spacing = 6
        stackView.addArrangedSubview(textContainer)
        
        let topStackView = UIStackView()
        topStackView.axis = .horizontal
        topStackView.spacing = 3
        topStackView.alignment = .bottom
        textContainer.addArrangedSubview(topStackView)
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .dw_font(forTextStyle: .title1).withWeight(UIFont.Weight.bold.rawValue)
        titleLabel.text = NSLocalizedString("Send", comment: "Send Screen")
        topStackView.addArrangedSubview(titleLabel)
        
        let toLabel = UILabel()
        toLabel.translatesAutoresizingMaskIntoConstraints = false
        toLabel.font = .dw_font(forTextStyle: .body)
        toLabel.textColor = .label
        toLabel.text = NSLocalizedString("to", comment: "Send Screen: to address")
        topStackView.addArrangedSubview(toLabel)
        
        let addressLabel = UILabel()
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        addressLabel.font = .dw_font(forTextStyle: .body)
        addressLabel.textColor = .label
        addressLabel.text = address
        addressLabel.lineBreakMode = .byTruncatingMiddle
        topStackView.addArrangedSubview(addressLabel)

        
        let balanceStackView = UIStackView()
        balanceStackView.axis = .horizontal
        balanceStackView.spacing = 2
        balanceStackView.alignment = .center
        textContainer.addArrangedSubview(balanceStackView)
        
        let balanceTitleLabel = UILabel()
        balanceTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceTitleLabel.font = .dw_font(forTextStyle: .footnote)
        balanceTitleLabel.textColor = .secondaryLabel
        balanceTitleLabel.text = NSLocalizedString("Balance", comment: "Send Screen: to address") + ":"
        balanceStackView.addArrangedSubview(balanceTitleLabel)

        let balanceLabel = UILabel()
        balanceLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceLabel.font = .dw_font(forTextStyle: .footnote)
        balanceLabel.textColor = .secondaryLabel
        balanceLabel.text = "5.50 DASH ~ 320.74€"
        balanceStackView.addArrangedSubview(balanceLabel)
        
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.backgroundColor = .clear
        balanceStackView.addArrangedSubview(spacer)
        
        let configuration = UIImage.SymbolConfiguration(pointSize: 13, weight: .regular, scale: .small)
        let showHideBalanceButton = UIButton(type: .custom)
        showHideBalanceButton.translatesAutoresizingMaskIntoConstraints = false
        showHideBalanceButton.backgroundColor = UIColor(red: 0.098, green: 0.11, blue: 0.122, alpha: 0.05)
        showHideBalanceButton.layer.cornerRadius = 12
        showHideBalanceButton.setImage(UIImage(systemName: "eye.fill", withConfiguration: configuration), for: .normal)
        showHideBalanceButton.tintColor = .label.withAlphaComponent(0.8)
        balanceStackView.addArrangedSubview(showHideBalanceButton)
        
        let extraSpaceView = UIView()
        extraSpaceView.backgroundColor = .clear
        balanceStackView.addArrangedSubview(extraSpaceView)
        
        amountView.removeFromSuperview()
        stackView.addArrangedSubview(amountView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            
            toLabel.heightAnchor.constraint(equalToConstant: 27),
            addressLabel.heightAnchor.constraint(equalToConstant: 27),
            
            spacer.widthAnchor.constraint(equalToConstant: 6),
            
            showHideBalanceButton.widthAnchor.constraint(equalToConstant: 24),
            showHideBalanceButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
}
