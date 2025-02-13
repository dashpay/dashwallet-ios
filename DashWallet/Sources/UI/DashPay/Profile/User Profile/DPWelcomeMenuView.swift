//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

enum DPWelcomState {
    case none
    case voting
}

class DPWelcomeMenuView: UIView {
    private let prefs = VotingPrefs.shared
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .dw_label()
        label.numberOfLines = 1
        label.adjustsFontForContentSizeCategory = true
        label.font = .dw_mediumFont(ofSize: 15)
        label.text = NSLocalizedString("Join DashPay", comment: "")
        
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .dw_tertiaryText()
        label.numberOfLines = 1
        label.adjustsFontForContentSizeCategory = true
        label.font = .dw_regularFont(ofSize: 12)
        label.text = NSLocalizedString("Request your username", comment: "")
        
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    @objc
    func refreshState() {
        changeState(state: prefs.requestedUsernameId != nil ? .voting : .none, username: prefs.requestedUsername)
    }

    private func setupView() {
        backgroundColor = UIColor.clear

        let shadowView = ShadowView(frame: .zero)
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.insetsLayoutMarginsFromSafeArea = true
        addSubview(shadowView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_background()
        contentView.layer.cornerRadius = 8.0
        contentView.layer.masksToBounds = true
        shadowView.addSubview(contentView)
        
        let imageView = UIImageView(image: UIImage(named: "dp_user_generic"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        
        let chevronView = UIImageView(image: UIImage(named: "greyarrow"))
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(chevronView)

        let padding: CGFloat = 20.0
        let horizontalPadding: CGFloat = 12
        
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: 68),
            
            shadowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            shadowView.topAnchor.constraint(equalTo: topAnchor),
            shadowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            shadowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            contentView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            contentView.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 12),
            
            imageView.heightAnchor.constraint(equalToConstant: 34),
            imageView.widthAnchor.constraint(equalToConstant: 34),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: horizontalPadding),
            
            contentView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: horizontalPadding),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: horizontalPadding),
            
            chevronView.heightAnchor.constraint(equalToConstant: 16),
            chevronView.widthAnchor.constraint(equalToConstant: 9),
            chevronView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -25),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        
        refreshState()
    }
    
    private func changeState(state: DPWelcomState, username: String?) {
        switch state {
        case .none:
            titleLabel.text = NSLocalizedString("Join DashPay", comment: "")
            subtitleLabel.text = NSLocalizedString("Request your username", comment: "")
        case .voting:
            titleLabel.text = username ?? ""
            let startDate = Date(timeIntervalSince1970: VotingConstants.votingStartTime)
            let endDate = Date(timeIntervalSince1970: VotingConstants.votingEndTime)
            let startDateStr = DWDateFormatter.sharedInstance.dateOnly(from: startDate)
            let endDateStr = DWDateFormatter.sharedInstance.dateOnly(from: endDate)
            let votingPeriod = "\(startDateStr) - \(endDateStr)"
            subtitleLabel.text = String.localizedStringWithFormat(NSLocalizedString("Requested · Voting: %@", comment: ""), votingPeriod)
        }
    }
}

