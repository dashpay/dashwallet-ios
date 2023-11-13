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
    var model: UsernameRequest?
    
    private let bullet: UIView = {
        let view = UIView()
        view.backgroundColor = .dw_label()
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
    
    private let linkBadge: UIImageView = {
        let image = UIImageView(image: UIImage(named: "link.badge"))
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false
        return image
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
        contentView.addSubview(bullet)
        contentView.addSubview(linkBadge)
        contentView.addSubview(votesBadge)
        votesBadge.addSubview(votes)
        
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: 44),
            
            bullet.heightAnchor.constraint(equalToConstant: 3),
            bullet.widthAnchor.constraint(equalToConstant: 3),
            bullet.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            bullet.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            
            votesBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            votesBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            
            votes.topAnchor.constraint(equalTo: votesBadge.topAnchor, constant: 3),
            votes.leadingAnchor.constraint(equalTo: votesBadge.leadingAnchor, constant: 6),
            votes.trailingAnchor.constraint(equalTo: votesBadge.trailingAnchor, constant: -6),
            votes.bottomAnchor.constraint(equalTo: votesBadge.bottomAnchor, constant: -3),
            
            linkBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            linkBadge.trailingAnchor.constraint(equalTo: votesBadge.leadingAnchor, constant: -5),
            
            dateCreated.topAnchor.constraint(equalTo: contentView.topAnchor),
            dateCreated.leadingAnchor.constraint(equalTo: bullet.trailingAnchor, constant: 8),
            dateCreated.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dateCreated.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
}

extension UsernameRequestCell {
    func configure(withModel model: UsernameRequest) {
        self.model = model
        let unixTimestamp = TimeInterval(model.createdAt)
        let date = Date(timeIntervalSince1970: unixTimestamp)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd MMM yyyy · H:mm"
        let formattedDate = dateFormatter.string(from: date)
        self.dateCreated.text = formattedDate
        linkBadge.isHidden = model.link == nil
        votes.text = String(describing: model.votes)
        
        if model.isApproved {
            votesBadge.backgroundColor = .dw_dashBlue()
            votesBadge.layer.borderColor = UIColor.dw_dashBlue().cgColor
            votes.textColor = .white
        } else {
            votesBadge.backgroundColor = nil
            votesBadge.layer.borderColor = UIColor.dw_separatorLine().cgColor
            votes.textColor = .dw_tertiaryText()
        }
    }
}
