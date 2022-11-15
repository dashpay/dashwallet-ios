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

import Combine

final class GettingStartedViewController: UIViewController {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()
    
    @IBOutlet var logoWrapper: UIView!
    @IBOutlet var newAccountButton: UITableViewCell!
    @IBOutlet var linkAccountButton: UITableViewCell!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }
    
    @IBAction func newAccountAction() {
        print("CrowdNode: newAccountAction")
    }
    
    @IBAction func linkAccountAction() {
        print("CrowdNode: linkAccountAction")
    }
    
    @objc static func controller() -> GettingStartedViewController {
        let storyboard = UIStoryboard(name: "CrowdNode", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "GettingStartedViewController") as! GettingStartedViewController
        return vc
    }
}

extension GettingStartedViewController {
    private func configureHierarchy() {
        logoWrapper.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.05, x: 0, y: 0, blur: 10)
        
        newAccountButton.selectedBackgroundView = createSelectedBackgroundView()
        newAccountButton.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.1, x: 0, y: 0, blur: 10)

        linkAccountButton.selectedBackgroundView = createSelectedBackgroundView()
        linkAccountButton.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.1, x: 0, y: 0, blur: 10)
    }
    
    private func createSelectedBackgroundView() -> UIView {
        let backgroundView = UIView()
        backgroundView.backgroundColor = .systemGray4
        backgroundView.layer.cornerRadius = 10
        
        return backgroundView
    }
}
