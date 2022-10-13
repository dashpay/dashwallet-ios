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

import UIKit
import Combine


class NewAccountViewController: UIViewController {
    private let viewModel = CrowdNodeModel()
    private var cancellableBag = Set<AnyCancellable>()
    
    @IBOutlet var actionButton: UIButton!
    @IBOutlet var outputLabel: UILabel!
    @IBOutlet var copyButton: UIButton!
    @IBOutlet var animationView: UIActivityIndicatorView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
        configureObservers()
    }
    
    @objc static func controller() -> NewAccountViewController {
        let storyboard = UIStoryboard(name: "CrowdNode", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "NewAccountViewController") as! NewAccountViewController
        return vc
    }
    
    @IBAction func createAccountAction() {
        viewModel.signUp()
    }
    
    @IBAction func copyOutput() {
        UIPasteboard.general.string = outputLabel.text
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancellableBag.removeAll()
    }
}

extension NewAccountViewController {
    private func configureHierarchy() {
        self.definesPresentationContext = true
        self.view.backgroundColor = UIColor.dw_secondaryBackground()
        actionButton.setTitle(NSLocalizedString("Sign up to CrowdNode", comment: ""), for: .normal)
        copyButton.isHidden = true
    }

    
    private func configureObservers() {
        viewModel.$outputMessage
            .receive(on: DispatchQueue.main)
            .assign(to: \.text!, on: outputLabel)
            .store(in: &cancellableBag)
        
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] isLoading in
                if (isLoading) {
                    self?.copyButton.isHidden = false
                    self?.animationView.startAnimating()
                } else {
                    self?.animationView.stopAnimating()
                }
            })
            .store(in: &cancellableBag)
    }
}
