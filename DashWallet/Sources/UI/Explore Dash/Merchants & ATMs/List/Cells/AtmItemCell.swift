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
import CoreLocation

class AtmItemCell: PointOfUseItemCell {
    
    private var buyTag: AtmOperationTagView = AtmOperationTagView(operation: .buy)
    private var sellTag: AtmOperationTagView = AtmOperationTagView(operation: .sell)
    
    override func update(with pointOfUse: ExplorePointOfUse) {
        super.update(with: pointOfUse)
        
        guard let atm = pointOfUse.atm else { return }
        
        subLabel.isHidden = false
        
        if let currentLocation = DWLocationManager.shared.currentLocation,
           DWLocationManager.shared.isAuthorized {
            let distance = CLLocation(latitude: pointOfUse.latitude!, longitude: pointOfUse.longitude!).distance(from: currentLocation)
            let distanceText: String = ExploreDash.distanceFormatter.string(from: Measurement(value: floor(distance), unit: UnitLength.meters))
            subLabel.text = "\(distanceText) • \(pointOfUse.source!)"
        }else{
            subLabel.text = pointOfUse.source
        }
        
        buyTag.isHidden = atm.type == .sell
        sellTag.isHidden = atm.type != .buySell
    }
}

extension AtmItemCell {
    override func configureHierarchy() {
        super.configureHierarchy()
        
        buyTag.translatesAutoresizingMaskIntoConstraints = false
        sellTag.translatesAutoresizingMaskIntoConstraints = false
        
        mainStackView.addArrangedSubview(UIView())
        
        let tagsStackView = UIStackView()
        tagsStackView.axis = .horizontal
        tagsStackView.spacing = 5
        tagsStackView.translatesAutoresizingMaskIntoConstraints = false
        tagsStackView.alignment = .center
        tagsStackView.addArrangedSubview(buyTag)
        tagsStackView.addArrangedSubview(sellTag)
        mainStackView.addArrangedSubview(tagsStackView)
        
        NSLayoutConstraint.activate([
            tagsStackView.heightAnchor.constraint(equalToConstant: 20),
            buyTag.heightAnchor.constraint(equalToConstant: 20),
            sellTag.heightAnchor.constraint(equalToConstant: 20),
        ])
    }
}

private class AtmOperationTagView: UIView {
    enum Operation {
        case buy
        case sell
        
        var title: String {
            switch self {
            case .buy: return NSLocalizedString("Buy", comment: "Buy")
            case .sell: return NSLocalizedString("Sell", comment: "Sell")
            }
        }
        
        var color: UIColor {
            switch self {
            case .buy: return .dw_green()
            case .sell: return .dw_dashBlue()
            }
        }
    }
    
    init(operation: Operation) {
        super.init(frame: .zero)
        
        layer.masksToBounds = true
        layer.cornerRadius = 10
        
        backgroundColor = operation.color
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .dw_mediumFont(ofSize: 10)
        label.text = operation.title
        label.textColor = .white
        label.minimumScaleFactor = 0.5
        label.adjustsFontSizeToFitWidth = true
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -6),
            label.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
