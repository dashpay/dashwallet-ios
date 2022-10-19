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

class ConverterView: UIView {
    private var topImageView: UIImageView!
    private var topLabel: UILabel!
    private var walletBallanceLabel: UILabel!
    
    private var hairlineView: UIView!
    
    private var bottomImageView: UIImageView!
    private var bottomLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension ConverterView {
    private func configureHierarchy() {
        backgroundColor = .dw_background()
        layer.cornerRadius = 10
        
        configureLeftSide()
        configureRightSide()
    }
    
    private func configureLeftSide() {
        let leftContainer = UIStackView()
        leftContainer.axis = .vertical
        leftContainer.distribution = .equalSpacing
        leftContainer.translatesAutoresizingMaskIntoConstraints = false
        leftContainer.alignment = .center
        leftContainer.spacing = 22
        addSubview(leftContainer)
        
        let fromLabel = UILabel()
        fromLabel.font = .dw_regularFont(ofSize: 11)
        fromLabel.textColor = .secondaryLabel
        fromLabel.text = NSLocalizedString("FROM", comment: "Coinbase: transfer dash to/from")
        fromLabel.textAlignment = .center
        leftContainer.addArrangedSubview(fromLabel)
        
        let iconView = UIImageView(image: UIImage(named: "coinbase.converter.switch"))
        leftContainer.addArrangedSubview(iconView)
        
        let toLabel = UILabel()
        toLabel.font = .dw_regularFont(ofSize: 11)
        toLabel.textColor = .secondaryLabel
        toLabel.text = NSLocalizedString("TO", comment: "Coinbase: transfer dash to/from")
        toLabel.textAlignment = .center
        leftContainer.addArrangedSubview(toLabel)
        
        NSLayoutConstraint.activate([
            leftContainer.topAnchor.constraint(equalTo: topAnchor, constant: 19),
            leftContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftContainer.widthAnchor.constraint(equalToConstant: 60),
            leftContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -19),
            
            fromLabel.heightAnchor.constraint(equalToConstant: 16),
            toLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
    
    private func configureRightSide() {
        let rightContainer = UIView()
        rightContainer.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.backgroundColor = .clear
        addSubview(rightContainer)
        
        let topStackView = UIStackView()
        topStackView.axis = .horizontal
        topStackView.spacing = 8
        topStackView.alignment = .center
        topStackView.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(topStackView)
        
        topImageView = UIImageView()
        topImageView.translatesAutoresizingMaskIntoConstraints = false
        topImageView.image = UIImage(named: "Coinbase")
        topStackView.addArrangedSubview(topImageView)
        
        topLabel = UILabel()
        topLabel.text = "Coinbase"
        topLabel.font = .dw_font(forTextStyle: .body)
        topLabel.translatesAutoresizingMaskIntoConstraints = false
        topStackView.addArrangedSubview(topLabel)
        
        let walletBalanceStackView = UIStackView()
        walletBalanceStackView.axis = .horizontal
        walletBalanceStackView.spacing = 8
        walletBalanceStackView.alignment = .center
        walletBalanceStackView.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(walletBalanceStackView)
        
        let walletImageView = UIImageView()
        walletImageView.translatesAutoresizingMaskIntoConstraints = false
        walletImageView.image = UIImage(named: "icon.wallet")
        walletBalanceStackView.addArrangedSubview(walletImageView)
        
        let dashStr = "\(2.3) DASH"
        let fiatStr = " ≈ $158.23"
        let fullStr = "\(dashStr)\(fiatStr)"
        let string = NSMutableAttributedString(string: fullStr)
        string.addAttributes([NSAttributedString.Key.foregroundColor: UIColor.secondaryLabel], range: NSMakeRange(dashStr.count, fiatStr.count))
        string.addAttribute(.font, value: UIFont.dw_font(forTextStyle: .footnote), range: NSMakeRange(0, fullStr.count - 1))
        
        walletBallanceLabel = UILabel()
        walletBallanceLabel.attributedText = string
        walletBallanceLabel.font = .dw_font(forTextStyle: .footnote)
        walletBallanceLabel.translatesAutoresizingMaskIntoConstraints = false
        walletBalanceStackView.addArrangedSubview(walletBallanceLabel)
        
        let hairlineView = HairlineView()
        hairlineView.translatesAutoresizingMaskIntoConstraints = false
        hairlineView.alpha = 0.5
        rightContainer.addSubview(hairlineView)
        
        let bottomStackView = UIStackView()
        bottomStackView.axis = .horizontal
        bottomStackView.spacing = 8
        bottomStackView.alignment = .center
        bottomStackView.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(bottomStackView)
        
        bottomImageView = UIImageView()
        bottomImageView.translatesAutoresizingMaskIntoConstraints = false
        bottomImageView.image = UIImage(named: "image.explore.dash.wts.dash")
        bottomStackView.addArrangedSubview(bottomImageView)
        
        bottomLabel = UILabel()
        bottomLabel.text = "Dash Wallet"
        bottomLabel.font = .dw_font(forTextStyle: .body)
        bottomLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomStackView.addArrangedSubview(bottomLabel)
        
        NSLayoutConstraint.activate([
            rightContainer.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            rightContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 62),
            rightContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            rightContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            
            topImageView.widthAnchor.constraint(equalToConstant: 30),
            topImageView.heightAnchor.constraint(equalToConstant: 30),
            
            topStackView.topAnchor.constraint(equalTo: rightContainer.topAnchor),
            topStackView.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            
            walletBalanceStackView.topAnchor.constraint(equalTo: topStackView.bottomAnchor, constant: 5),
            walletBalanceStackView.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor, constant: 40),
            
            hairlineView.topAnchor.constraint(equalTo: walletBalanceStackView.bottomAnchor, constant: 8),
            hairlineView.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            hairlineView.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),
            
            bottomImageView.widthAnchor.constraint(equalToConstant: 30),
            bottomImageView.heightAnchor.constraint(equalToConstant: 30),
            
            bottomStackView.topAnchor.constraint(equalTo: hairlineView.bottomAnchor, constant: 12),
            bottomStackView.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            
        ])
    }
}
