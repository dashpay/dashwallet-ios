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
import SwiftUI

@objc class PortalViewController: UIViewController {
    
    private var coinbaseButton: UIButton!
    
    @objc func coinbaseAction() {
        if DWGlobalOptions.sharedInstance().coinbaseInfoShown {
            let vc = UIHostingController(rootView: CoinbasePortalView())
            navigationController?.pushViewController(vc, animated: true)
        }else{
            let vc = CoinbaseInfoViewController.controller()
            vc.modalPresentationStyle = .overCurrentContext
            vc.modalTransitionStyle = .crossDissolve
            present(vc, animated: true)
            
            DWGlobalOptions.sharedInstance().coinbaseInfoShown = true
        }
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
    }
}

extension PortalViewController {
    private func configureHierarchy() {
        coinbaseButton = UIButton(type: .custom)
        coinbaseButton.translatesAutoresizingMaskIntoConstraints = false
        coinbaseButton.setTitle("Coinbase", for: .normal)
        coinbaseButton.backgroundColor = .dw_dashBlue()
        coinbaseButton.addTarget(self, action: #selector(coinbaseAction), for: .touchUpInside)
        view.addSubview(coinbaseButton)
        
        NSLayoutConstraint.activate([
            coinbaseButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            coinbaseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
        ])
    }
}
