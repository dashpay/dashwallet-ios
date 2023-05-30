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

@objc(DWPaymentsButton)
final class PaymentButton: UIButton {
    static let kCenterCircleSize: CGFloat = 48.0

    @objc
    var isOpened = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .dw_dashBlue()
        setImage(UIImage(named: "tabbar_pay_button")!, for: .normal)
        layer.cornerRadius = PaymentButton.kCenterCircleSize / 2.0
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
