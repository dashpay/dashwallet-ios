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

import SwiftUI

final class BuyCreditsViewController: SendAmountViewController, NavigationBarDisplayable {
//    override init() {
//        super.init(model: SendAmountModel())
//    }
    
    var isBackButtonHidden: Bool = false
    
    override func configureHierarchy() {
        super.configureHierarchy()
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 26
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        
        let intro = SendIntro(title: NSLocalizedString("Send", comment: ""))
        let swiftUIController = UIHostingController(rootView: intro)
        swiftUIController.view.backgroundColor = UIColor.dw_secondaryBackground()
        
        addChild(swiftUIController)
        stackView.addArrangedSubview(swiftUIController.view)
        swiftUIController.view.translatesAutoresizingMaskIntoConstraints = false
        swiftUIController.didMove(toParent: self)
        
        amountView.removeFromSuperview()
        stackView.addArrangedSubview(amountView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
        
//        let backButton = UIBarButtonItem(
//                    title: "Back",
//                    style: .plain,
//                    target: self,
//                    action: #selector(backButtonTapped)
//                )
//                navigationItem.leftBarButtonItem = backButton
//                
//                // Additional setup if needed
//                view.backgroundColor = .red // Example setup
    }
    
    @objc private func backButtonTapped() {
            dismiss(animated: true, completion: nil)
        }
}
