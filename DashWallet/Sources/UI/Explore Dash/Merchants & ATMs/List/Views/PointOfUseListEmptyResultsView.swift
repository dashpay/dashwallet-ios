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

class PointOfUseListEmptyResultsView: UIView {
    var resetHandler: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func resetButtonAction() {
        resetHandler?()
    }
    
    private func configureHierarchy() {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        stackView.axis = .vertical
        stackView.spacing = 5
        addSubview(stackView)
        
        let noResultsLabel = UILabel()
        noResultsLabel.translatesAutoresizingMaskIntoConstraints = false
        noResultsLabel.text = NSLocalizedString("No Results Found", comment: "Explore Dash/Merchants/Filters")
        noResultsLabel.font = .dw_font(forTextStyle: .headline).withWeight(500)
        stackView.addArrangedSubview(noResultsLabel)
        
        let resetFiltersButton = UIButton()
        resetFiltersButton.addTarget(self, action: #selector(resetButtonAction), for: .touchUpInside)
        resetFiltersButton.translatesAutoresizingMaskIntoConstraints = false
        resetFiltersButton.setTitle(NSLocalizedString("Reset Filters", comment: "Explore Dash/Merchants/Filters"), for: .normal)
        resetFiltersButton.tintColor = .dw_red()
        resetFiltersButton.setTitleColor(.dw_red(), for: .normal)
        resetFiltersButton.backgroundColor = .clear
        stackView.addArrangedSubview(resetFiltersButton)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
