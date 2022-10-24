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

final class BalanceView: UIView {
    public var balance: UInt64 = 0 { //In Dash
        didSet {
            reloadView()
        }
    }
    
    public var dashSymbolColor: UIColor? {
        didSet {
            reloadView()
        }
    }
    override var intrinsicContentSize: CGSize {
        return CGSize(width: BalanceView.noIntrinsicMetric, height: 52.0)
    }
    
    private var container: UIStackView!
    private var dashBalanceLabel: UILabel!
    private var fiatBalanceLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        configureHierarchy()
    }
}

private extension BalanceView {
    private func reloadView() {
        let balanceColor = UIColor.label
        let font = UIFont.dw_font(forTextStyle: .title1)
        let balanceString = NSAttributedString.dw_dashAttributedString(forAmount: balance, tintColor: balanceColor, dashSymbolColor: dashSymbolColor ?? balanceColor, font: font)
        dashBalanceLabel.attributedText = balanceString
    
        self.fiatBalanceLabel.text = DSPriceManager.sharedInstance().localCurrencyString(forDashAmount: Int64(balance))
    }
    
    private func configureHierarchy() {
        backgroundColor = .clear
        
        self.container = UIStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        addSubview(container)
        
        self.dashBalanceLabel = UILabel()
        dashBalanceLabel.translatesAutoresizingMaskIntoConstraints = false
        dashBalanceLabel.font = .dw_font(forTextStyle: .title1)
        dashBalanceLabel.textAlignment = .center
        container.addArrangedSubview(dashBalanceLabel)
        
        self.fiatBalanceLabel = UILabel()
        fiatBalanceLabel.translatesAutoresizingMaskIntoConstraints = false
        fiatBalanceLabel.font = .dw_font(forTextStyle: .callout)
        fiatBalanceLabel.textColor = .secondaryLabel
        fiatBalanceLabel.textAlignment = .center
        container.addArrangedSubview(fiatBalanceLabel)
        
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        
        reloadView()
    }
}
