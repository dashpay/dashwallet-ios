//
//  Created by PT
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

import UIKit

let AVATAR_SIZE = CGSize(width: 72.0, height: 72.0)

// MARK: - DashPayProfileView

class DashPayProfileView: UIView {
    private(set) var contentView: UIView
    private(set) var avatarView: DWDPAvatarView
    private(set) var bellImageView: UIImageView
    private(set) var badgeView: BadgeView

    var username: String? {
        didSet {
            avatarView.username = username
        }
    }

    var unreadCount = 0 {
        didSet {
            badgeView.text = "\(unreadCount)"
            bellImageView.isHidden = unreadCount > 0
            badgeView.isHidden = unreadCount == 0
        }
    }

    var isHighlighted = false {
        didSet {
            self.contentView.dw_pressedAnimation(.medium, pressed: isHighlighted)
        }
    }

    override init(frame: CGRect) {
        contentView = UIView()
        avatarView = DWDPAvatarView()
        bellImageView = UIImageView(image: UIImage(named: "icon_bell"))

        badgeView = BadgeView()

        super.init(frame: frame)

        backgroundColor = UIColor.dw_dashBlue()

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = backgroundColor
        contentView.isUserInteractionEnabled = false
        addSubview(contentView)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.backgroundMode = .random
        avatarView.isUserInteractionEnabled = false
        contentView.addSubview(avatarView)

        bellImageView.translatesAutoresizingMaskIntoConstraints = false
        bellImageView.isUserInteractionEnabled = false
        contentView.addSubview(bellImageView)

        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.isHidden = true
        contentView.addSubview(badgeView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: AVATAR_SIZE.width),
            avatarView.heightAnchor.constraint(equalToConstant: AVATAR_SIZE.height),

            bellImageView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            bellImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            badgeView.centerXAnchor.constraint(equalTo: avatarView.trailingAnchor),
            badgeView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


}
