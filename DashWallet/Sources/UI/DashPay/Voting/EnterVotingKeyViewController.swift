//  
//  Created by Andrei Ashikhmin
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

// MARK: - EnterVotingKeyViewController

final class EnterVotingKeyViewController: UIViewController {
    private var votingKeyField: DashInputField!
    private var continueButton: ActionButton!
    private var viewModel: VotingViewModel = VotingViewModel.shared
    private var isBlocking: Bool = false

    override func viewWillDisappear(_ animated: Bool) {
        votingKeyField.resignFirstResponder()

        super.viewWillDisappear(animated)
    }
    
    
    static func controller(blocking: Bool = false) -> EnterVotingKeyViewController {
        let vc = EnterVotingKeyViewController()
        vc.isBlocking = blocking
        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
        updateView()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        votingKeyField.becomeFirstResponder()
    }
}

extension EnterVotingKeyViewController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 8
        view.addSubview(stackView)
                
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.dw_boldFont(ofSize: 28)
        titleLabel.textColor = UIColor.dw_label()
        titleLabel.text = NSLocalizedString("Enter your voting key", comment: "Voting")
        stackView.addArrangedSubview(titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = UIFont.dw_regularFont(ofSize: 15)
        subtitleLabel.textColor = UIColor.dw_secondaryText()
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = NSLocalizedString("You can enter your key in any of the following formats: WIF/base58/base64/hex", comment: "Voting")
        stackView.addArrangedSubview(subtitleLabel)

        stackView.setCustomSpacing(15, after: subtitleLabel)
        votingKeyField = DashInputField()
        votingKeyField.autocorrectionType = .no
        votingKeyField.spellCheckingType = .no
        votingKeyField.autocapitalizationType = .none
        votingKeyField.textDidChange = { [weak self] _ in
            self?.updateView()
        }
        votingKeyField.isEnabled = true
        votingKeyField.placeholder = NSLocalizedString("Masternode Voting Key", comment: "Voting")
        votingKeyField.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(votingKeyField)

        continueButton = ActionButton()
        continueButton.setTitle(NSLocalizedString("Verify", comment: "Voting"), for: .normal)
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.addAction(.touchUpInside) { [weak self] _ in
            self?.continueButtonAction()
        }
        view.addSubview(continueButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -15),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0),

            continueButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            continueButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            continueButton.heightAnchor.constraint(equalToConstant: 46),
            view.keyboardLayoutGuide.topAnchor.constraint(equalToSystemSpacingBelow: continueButton.bottomAnchor, multiplier: 1.0),
        ])
    }

    private func updateView() {
        continueButton.isEnabled = !votingKeyField.text.isEmpty
        votingKeyField.errorMessage = nil
    }
    
    private func continueButtonAction() {
        if viewModel.addMasternodeKey(key: votingKeyField.text) {
            let vc = CastVoteViewController.controller(blocking: self.isBlocking)
            
            if self.navigationController?.previousController is CastVoteViewController {
                self.navigationController?.popViewController(animated: true)
            } else {
                self.navigationController?.replaceLast(with: vc, animated: true)
            }
        } else {
            votingKeyField.errorMessage = NSLocalizedString("You have entered an invalid key", comment: "Voting")
        }
    }
}
