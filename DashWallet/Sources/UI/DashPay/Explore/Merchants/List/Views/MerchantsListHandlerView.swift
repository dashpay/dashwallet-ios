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

class MerchantsListHandlerView: UIView {
    private var handler: UIView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configureHierarchy() {
        layer.backgroundColor = UIColor.dw_background().cgColor
        layer.masksToBounds = true
        layer.cornerRadius = 20
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        
        handler = UIView(frame: .init(x: 0, y: 0, width: 40, height: 4))
        handler.layer.backgroundColor = UIColor.dw_separatorLine().cgColor
        handler.layer.cornerRadius = 2
        addSubview(handler)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        handler.center = center
    }
}
