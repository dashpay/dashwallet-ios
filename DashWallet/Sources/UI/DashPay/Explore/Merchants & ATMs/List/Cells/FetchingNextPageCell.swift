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

class FetchingNextPageCell: UITableViewCell
{
    var activity: UIActivityIndicatorView!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        configureLayout()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }
    
    func start() {
        activity.startAnimating()
    }
    
    func stop() {
        activity.stopAnimating()
    }
    
    func configureLayout()
    {
        activity = UIActivityIndicatorView()
        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.tintColor = .secondaryLabel
        activity.color = .secondaryLabel
        contentView.addSubview(activity)
        
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: 60),
            
            activity.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
}

