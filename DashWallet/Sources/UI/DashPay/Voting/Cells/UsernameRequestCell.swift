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

import UIKit

final class UsernameRequestCell: UITableViewCell {
    var onApproveTapped: ((UsernameRequest) -> Void)?
    var onBlockTapped: ((UsernameRequest) -> Void)?
    var model: UsernameRequest?
    
    private var dateCenterConstraint: NSLayoutConstraint?
    private var dateTopConstraint: NSLayoutConstraint?
    private var usernameCenterConstraint: NSLayoutConstraint?
    private var usernameTopConstraint: NSLayoutConstraint?
    
    private var containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let dateCreated: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.dw_regularFont(ofSize: 12)
        label.textColor = UIColor.dw_label()
        return label
    }()
    
    private let username: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.dw_mediumFont(ofSize: 13)
        label.textColor = UIColor.dw_label()
        return label
    }()
    
    private let linkLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.dw_regularFont(ofSize: 12)
        label.textColor = .dw_dashBlue()
        return label
    }()
    
    private let approveButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("0", for: .normal)
        button.setImage(UIImage(named: "icon_thumbs_up")!, for: .normal)
        button.tintColor = .dw_label()
        button.backgroundColor = .dw_secondaryBackground()
        button.layer.cornerRadius = 7
        button.semanticContentAttribute = .forceRightToLeft
        button.contentHorizontalAlignment = .center
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)

        return button
    }()
    
    private let blockButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("0", for: .normal)
        let image = UIImage(named: "icon_thumbs_up")!
        button.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.transform = CGAffineTransform(rotationAngle: .pi)
        button.tintColor = .dw_label()
        button.backgroundColor = .dw_secondaryBackground()
        button.layer.cornerRadius = 7
        button.semanticContentAttribute = .forceRightToLeft
        button.contentHorizontalAlignment = .center
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)

        return button
    }()
    
    @objc private func approveButtonTapped() {
        guard let model else { return }
        onApproveTapped?(model)
    }
    
    @objc private func blockButtonTapped() {
        guard let model else { return }
        onBlockTapped?(model)
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }
}

private extension UsernameRequestCell {
    func configureLayout() {
        contentView.addSubview(containerView)

        containerView.addSubview(dateCreated)
        containerView.addSubview(username)
        containerView.addSubview(linkLabel)
        containerView.addSubview(approveButton)
        containerView.addSubview(blockButton)
        approveButton.addTarget(self, action: #selector(approveButtonTapped), for: .touchUpInside)
        blockButton.addTarget(self, action: #selector(blockButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            dateCreated.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 15),
            dateCreated.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            username.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 15),
            
            linkLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 15),
            linkLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            linkLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),

            approveButton.heightAnchor.constraint(equalToConstant: 30),
            approveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            approveButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            approveButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            
            blockButton.heightAnchor.constraint(equalToConstant: 30),
            blockButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            blockButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            blockButton.trailingAnchor.constraint(equalTo: approveButton.leadingAnchor, constant: -10)
        ])
    }
}

extension UsernameRequestCell {
    func configure(withModel model: UsernameRequest, isInGroup: Bool = true) {
        self.model = model
        
        dateCenterConstraint?.isActive = false
        dateTopConstraint?.isActive = false
        usernameCenterConstraint?.isActive = false
        usernameTopConstraint?.isActive = false

        if isInGroup {
            containerView.backgroundColor = .clear
            containerView.layer.cornerRadius = 10
            contentView.backgroundColor = .dw_background()

            containerView.layer.borderWidth = 0.5
            containerView.layer.borderColor = UIColor.dw_separatorLine().cgColor
            
            NSLayoutConstraint.activate([
                contentView.heightAnchor.constraint(equalToConstant: 56),
                containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
                containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
                containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
                containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            ])
            
            if model.link == nil {
                dateCenterConstraint = dateCreated.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
                dateCenterConstraint?.isActive = true
            } else {
                dateTopConstraint = dateCreated.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11)
                dateTopConstraint?.isActive = true
            }
            
            let unixTimestamp = TimeInterval(model.createdAt)
            let date = Date(timeIntervalSince1970: unixTimestamp)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd MMM yyyy"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "H:mm"

            let dateString = dateFormatter.string(from: date)
            let timeString = timeFormatter.string(from: date)
            
            let attributedString = NSMutableAttributedString(string: dateString)
            attributedString.append(NSAttributedString(string: " \(timeString)", attributes: [.foregroundColor: UIColor.dw_tertiaryText()]))
            self.dateCreated.attributedText = attributedString
            self.username.isHidden = true
            self.blockButton.isHidden = true
        } else {
            containerView.backgroundColor = .dw_background()
            containerView.layer.cornerRadius = 10
            contentView.backgroundColor = .dw_secondaryBackground()

            containerView.layer.borderWidth = 0
            containerView.layer.borderColor = nil
            
            NSLayoutConstraint.activate([
                contentView.heightAnchor.constraint(equalToConstant: 64),
                containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
                containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
                containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
                containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
            ])
            
            if model.link == nil {
                usernameCenterConstraint = username.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -8)
                usernameCenterConstraint?.isActive = true
            } else {
                usernameTopConstraint = username.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8)
                usernameTopConstraint?.isActive = true
            }
            
            self.username.text = model.username
            self.username.isHidden = false
            self.dateCreated.isHidden = true
            self.blockButton.setTitle("\(model.blockVotes)", for: .normal)
            self.blockButton.isHidden = false
        }
        
        self.approveButton.setTitle("\(model.votes)", for: .normal)
        let attachment = NSTextAttachment()
        attachment.image = UIImage(named: "link.badge")?.withRenderingMode(.alwaysTemplate)
        attachment.bounds = CGRect(x: 0, y: -3, width: 14, height: 14)
        let linkAttributedString = NSMutableAttributedString(attachment: attachment)
        linkAttributedString.append(NSAttributedString(string: " link included"))
        linkLabel.attributedText = linkAttributedString
        linkLabel.isHidden = model.link == nil
        
        if model.isApproved {
            approveButton.backgroundColor = .dw_dashBlue()
            approveButton.tintColor = .white
        } else if model.votes > 0 {
            approveButton.backgroundColor = .dw_dashBlue().withAlphaComponent(0.05)
            approveButton.tintColor = .dw_dashBlue()
        } else {
            approveButton.backgroundColor = .dw_secondaryBackground()
            approveButton.tintColor = .dw_label()
        }
        
        if model.blockVotes > 0 {
            blockButton.backgroundColor = .dw_red()
            blockButton.tintColor = .white
        } else {
            blockButton.backgroundColor = .dw_secondaryBackground()
            blockButton.tintColor = .dw_label()
        }
        // TODO: pink block button
    }
}
