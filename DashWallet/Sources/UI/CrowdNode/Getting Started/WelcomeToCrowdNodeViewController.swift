//  
//  Created by Andrei Ashikhmin
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

import Foundation

import Combine

final class WelcomeToCrowdNodeViewController: UIViewController {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()
    
    @IBOutlet var actionButton: UIButton!
    @IBOutlet var logoWrapper: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        viewModel.showNotificationOnResult = false
        configureHierarchy()
        configureObservers()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.showNotificationOnResult = true
    }
    
    @objc static func controller() -> WelcomeToCrowdNodeViewController {
        let storyboard = UIStoryboard(name: "CrowdNode", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "WelcomeToCrowdNodeViewController") as! WelcomeToCrowdNodeViewController
        return vc
    }
    
    @IBAction func closeAndNotify() {
        self.dismiss(animated: true, completion: nil)
    }
}

extension WelcomeToCrowdNodeViewController {
    private func configureHierarchy() {
        let shadowLayer = CAShapeLayer()
        shadowLayer.path = UIBezierPath(roundedRect: logoWrapper.bounds, cornerRadius: 50).cgPath
        shadowLayer.fillColor = UIColor.white.cgColor

        shadowLayer.shadowColor = CGColor.init(red: 0.72, green: 0.76, blue: 0.8, alpha: 1.0)
        shadowLayer.shadowPath = shadowLayer.path
        shadowLayer.shadowOffset = CGSize(width: 0.0, height: 2.0)
        shadowLayer.shadowOpacity = 0.25
        shadowLayer.shadowRadius = 10

        logoWrapper.layer.insertSublayer(shadowLayer, at: 0)
    }
    
    private func configureObservers() {
//        viewModel.$signUpState
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] state in
//                if state == .finished {
//                    print("CrowdNode: going to portal")
//                    var viewControllers = self?.navigationController?.viewControllers
//                    viewControllers?.removeLast()
//                    viewControllers?.append(CrowdNodePortalController.controller())
//                    self?.navigationController?.setViewControllers(viewControllers!, animated: true)
//                }
//            }
//            .store(in: &cancellableBag)
        
//        viewModel.$outputMessage
//            .receive(on: DispatchQueue.main)
//            .assign(to: \.text!, on: statusLabel)
//            .store(in: &cancellableBag)
    }
}
