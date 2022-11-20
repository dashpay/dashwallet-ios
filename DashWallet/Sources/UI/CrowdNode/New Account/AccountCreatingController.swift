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

final class AccountCreatingController: UIViewController {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()

    @IBOutlet var actionButton: UIButton!
    @IBOutlet var statusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel.showNotificationOnResult = false
        configureObservers()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.showNotificationOnResult = true
    }

    @objc static func controller() -> AccountCreatingController {
        let storyboard = UIStoryboard(name: "CrowdNode", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "AccountCreatingController") as! AccountCreatingController
        return vc
    }

    @IBAction func closeAndNotify() {
        dismiss(animated: true, completion: nil)
    }
}

extension AccountCreatingController {
    private func configureObservers() {
        viewModel.$signUpState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .finished {
                    self?.navigationController?.replaceLast(with: CrowdNodePortalController.controller())
                }
            }
            .store(in: &cancellableBag)

        viewModel.$outputMessage
            .receive(on: DispatchQueue.main)
            .assign(to: \.text!, on: statusLabel)
            .store(in: &cancellableBag)
    }
}
