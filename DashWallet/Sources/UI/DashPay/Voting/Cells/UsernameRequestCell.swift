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
    var model: UsernameRequest?
    
    private let dateCreated: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.dw_regularFont(ofSize: 12)
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
    
    private let votes: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.dw_regularFont(ofSize: 12)
        label.textColor = UIColor.dw_tertiaryText()
        return label
    }()
    
    private let votesBadge: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 10
        view.layer.borderWidth = 1
        view.clipsToBounds = true
        view.layer.borderColor = UIColor.dw_separatorLine().cgColor
        return view
    }()
    
    private let approveButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .dw_regularFont(ofSize: 13)
        button.layer.cornerRadius = 15
        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        button.setTitle(NSLocalizedString("Approve", comment: "Voting"), for: .normal)
        return button
    }()
    
    @objc private func approveButtonTapped() {
        guard let model else { return }
        onApproveTapped?(model)
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
        contentView.addSubview(dateCreated)
        contentView.addSubview(linkLabel)
        contentView.addSubview(votesBadge)
        votesBadge.addSubview(votes)
        approveButton.addTarget(self, action: #selector(approveButtonTapped), for: .touchUpInside)
        contentView.addSubview(approveButton)
        
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: 44),
            
            votesBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            votesBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            
            votes.topAnchor.constraint(equalTo: votesBadge.topAnchor, constant: 3),
            votes.leadingAnchor.constraint(equalTo: votesBadge.leadingAnchor, constant: 6),
            votes.trailingAnchor.constraint(equalTo: votesBadge.trailingAnchor, constant: -6),
            votes.bottomAnchor.constraint(equalTo: votesBadge.bottomAnchor, constant: -3),
            
            dateCreated.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            dateCreated.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            linkLabel.topAnchor.constraint(equalTo: dateCreated.bottomAnchor, constant: 2),
            linkLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            linkLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            linkLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            approveButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            approveButton.trailingAnchor.constraint(equalTo: votesBadge.leadingAnchor, constant: -8)
        ])
    }
}

extension UsernameRequestCell {
    func configure(withModel model: UsernameRequest) {
        self.model = model
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
        
        let attachment = NSTextAttachment()
        attachment.image = UIImage(named: "link.badge")?.withRenderingMode(.alwaysTemplate)
        attachment.bounds = CGRect(x: 0, y: -3, width: 14, height: 14)
        let linkAttributedString = NSMutableAttributedString(attachment: attachment)
        linkAttributedString.append(NSAttributedString(string: " link included"))
        linkLabel.attributedText = linkAttributedString
        linkLabel.isHidden = model.link == nil
        votes.text = String(describing: model.votes)
        
        if model.link == nil {
            dateCreated.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        } else {
            dateCreated.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4).isActive = true
        }
        
        if model.isApproved {
            votesBadge.backgroundColor = .dw_dashBlue()
            votesBadge.layer.borderColor = UIColor.dw_dashBlue().cgColor
            votes.textColor = .white
        } else {
            votesBadge.backgroundColor = nil
            votesBadge.layer.borderColor = UIColor.dw_separatorLine().cgColor
            votes.textColor = .dw_tertiaryText()
        }

        approveButton.setTitleColor(model.isApproved ? .white : .dw_dashBlue(), for: .normal)
        approveButton.backgroundColor = model.isApproved ? .dw_dashBlue() : .clear
    }
}
