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

enum DPWelcomeState {
    case approved
    case notApproved
}

@objc
class DPVotingResultView: UIView {
    var state: DPWelcomeState = .approved {
        didSet {
            change(state: self.state)
        }
    }
    
    var onAction: (() -> ())?
    var onClose: (() -> ())?
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        let symbolConfiguration = UIImage.SymbolConfiguration(scale: .small)
        let symbolImage = UIImage(systemName: "xmark", withConfiguration: symbolConfiguration)
        button.setImage(symbolImage, for: .normal)
        button.tintColor = .dw_tabbarInactiveButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    private let actionButton: UIButton = {
        let button = ActionButton()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.dw_mediumFont(ofSize: 15)
        ]
        button.setAttributedTitle(NSAttributedString(string: NSLocalizedString("Create Username", comment: ""), attributes: attributes), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        
        return button
    }()
    
    private let image: UIImageView = {
        let image = UIImageView(image: UIImage(named: "pay_user_accessory"))
        image.translatesAutoresizingMaskIntoConstraints = false
        
        return image
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .dw_background()
        view.layer.cornerRadius = 8.0
        view.layer.masksToBounds = true
        
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .dw_label()
        label.numberOfLines = 0
        label.font = .dw_mediumFont(ofSize: 13)
        label.text = NSLocalizedString("Join DashPay", comment: "")
        
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .dw_secondaryText()
        label.numberOfLines = 0
        label.font = .dw_regularFont(ofSize: 12)
        label.text = NSLocalizedString("Create a username, add your friends.", comment: "")
        
        return label
    }()
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.clear
        layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        let shadowView = ShadowView(frame: .zero)
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.insetsLayoutMarginsFromSafeArea = true
        addSubview(shadowView)

        shadowView.addSubview(contentView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(image)
        contentView.addSubview(closeButton)
        closeButton.addAction(.touchUpInside) { [weak self] _ in
            self?.onClose?()
        }
        contentView.addSubview(actionButton)
        actionButton.addAction(.touchUpInside) { [weak self] _ in
            self?.onAction?()
        }
        
        titleLabel.setContentCompressionResistancePriority(.required - 1, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.required - 2, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required - 1, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.required - 2, for: .vertical)
        
        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            shadowView.topAnchor.constraint(equalTo: topAnchor),
            layoutMarginsGuide.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            bottomAnchor.constraint(equalTo: shadowView.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            contentView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            contentView.trailingAnchor.constraint(equalTo: closeButton.trailingAnchor),
            
            shadowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shadowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 15),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4.0),
            subtitleLabel.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 15),
            subtitleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor),

            image.widthAnchor.constraint(equalToConstant: 32.0),
            image.heightAnchor.constraint(equalToConstant: 32.0),
            image.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            image.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.topAnchor.constraint(equalTo: topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            
            actionButton.heightAnchor.constraint(equalToConstant: 30),
            actionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            actionButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 15),
        ])
        
        change(state: self.state)
    }
    
    private func change(state: DPWelcomeState) {
        actionButton.isHidden = state != .notApproved
        
        
        if state == .notApproved {
            image.image = UIImage(named: "dashpay.welcome.disabled")
            titleLabel.text = NSLocalizedString("Requested username was not approved", comment: "")
            subtitleLabel.text = NSLocalizedString("You can create a different username without paying again", comment: "")
            contentView.bottomAnchor.constraint(equalTo: actionButton.bottomAnchor, constant: 15).isActive = true
        } else {
            image.image = UIImage(named: "dashpay.welcome")
            titleLabel.text = NSLocalizedString("Your username was approved", comment: "")
            subtitleLabel.text = NSLocalizedString("Update your profile and start adding contacts", comment: "")
            contentView.bottomAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16).isActive = true
        }
        
//        setNeedsLayout()
//        layoutIfNeeded()
    }
}
