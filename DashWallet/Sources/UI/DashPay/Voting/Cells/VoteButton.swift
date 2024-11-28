//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

final class VoteButton: UIButton {
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let numberLabel: UILabel = {
        let label = UILabel()
        label.font = .dw_mediumFont(ofSize: 12)
        label.textAlignment = .center
        return label
    }()
    
    private let textLabel: UILabel = {
        let label = UILabel()
        label.font = .dw_mediumFont(ofSize: 10)
        label.textAlignment = .center
        return label
    }()
    
    var value: Int = 0 {
        didSet {
            numberLabel.text = String(value)
        }
    }
    
    var buttonText: String = "" {
        didSet {
            textLabel.text = buttonText
        }
    }
    
    var selectedBackgroundColor: UIColor = .dw_dashBlue() {
        didSet {
            updateAppearance()
        }
    }
    
    var selectedTitleColor: UIColor = .white {
        didSet {
            updateAppearance()
        }
    }
    
    override var isSelected: Bool {
        didSet {
            updateAppearance()
        }
    }
    
    init() {
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        
        stackView.addArrangedSubview(numberLabel)
        stackView.addArrangedSubview(textLabel)
        addSubview(stackView)
        layer.cornerRadius = 7
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            heightAnchor.constraint(equalToConstant: 50)
        ])
        
        updateAppearance()
    }
    
    private func updateAppearance() {
        textLabel.textColor = isSelected ? selectedTitleColor : selectedBackgroundColor
        numberLabel.textColor = isSelected ? selectedTitleColor : selectedBackgroundColor
        backgroundColor = isSelected ? selectedBackgroundColor : selectedBackgroundColor.withAlphaComponent(0.05)
    }
}
