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
import Combine

// MARK: - RequestUsernameViewController

final class RequestUsernameViewController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private var usernameField: DashInputField!
    private var continueButton: ActionButton!
    private var viewModel: RequestUsernameViewModel = RequestUsernameViewModel.shared
    
    private let noteLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.dw_regularFont(ofSize: 12)
        label.textColor = UIColor.dw_secondaryText()
        label.numberOfLines = 0
        label.text = NSLocalizedString("This username has already been requested, but you can request it too and let the network vote to decide if you can have it", comment: "Voting")
        label.isHidden = true
        
        return label
    }()
    
    private let minimumBalanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.dw_regularFont(ofSize: 12)
        label.textColor = UIColor.dw_secondaryText()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        
        return label
    }()
    
    static func controller() -> RequestUsernameViewController {
        RequestUsernameViewController()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
        configureObservers()
        updateView()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        usernameField.becomeFirstResponder()
    }
}

extension RequestUsernameViewController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 15
        view.addSubview(stackView)
                
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.dw_boldFont(ofSize: 28)
        titleLabel.textColor = UIColor.dw_label()
        titleLabel.text = NSLocalizedString("Request your username", comment: "Voting")
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(8, after: titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = UIFont.dw_regularFont(ofSize: 15)
        subtitleLabel.textColor = UIColor.dw_secondaryText()
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = NSLocalizedString("Once the voting ends you can create any username you want as long as it hasn’t already been created", comment: "Voting")
        stackView.addArrangedSubview(subtitleLabel)
        
        let votingTimeline = UILabel()
        votingTimeline.translatesAutoresizingMaskIntoConstraints = false
        votingTimeline.textColor = .dw_label()
        votingTimeline.numberOfLines = 0
        
        let iconImage = UIImage(systemName: "calendar")!.withTintColor(.dw_label())
        let labelText = NSLocalizedString("Voting:", comment: "Voting")
        let startDate = Date(timeIntervalSince1970: VotingConstants.votingStartTime)
        let endDate = Date(timeIntervalSince1970: VotingConstants.votingEndTime)
        let startDateStr = DWDateFormatter.sharedInstance.dateOnly(from: startDate)
        let endDateStr = DWDateFormatter.sharedInstance.dateOnly(from: endDate)
        let regularText = "\(startDateStr) - \(endDateStr)"
        votingTimeline.attributedText = getAttributedTextWith(icon: iconImage, boldText: labelText, regularText: regularText, iconSize: CGSize(width: 16, height: 15), iconOffsetY: -3)
        
        stackView.addArrangedSubview(votingTimeline)
        
        usernameField = DashInputField()
        usernameField.autocorrectionType = .no
        usernameField.spellCheckingType = .no
        usernameField.autocapitalizationType = .none
        usernameField.textDidChange = { [weak self] text in
            self?.updateView()
        }
        usernameField.isEnabled = true
        usernameField.placeholder = NSLocalizedString("Username", comment: "Voting")
        usernameField.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(usernameField)
        stackView.setCustomSpacing(8, after: usernameField)
        
        let noteContainer = UIView()
        noteContainer.translatesAutoresizingMaskIntoConstraints = false
        
        noteContainer.addSubview(noteLabel)
        stackView.addArrangedSubview(noteContainer)
        
        continueButton = ActionButton()
        continueButton.setTitle(NSLocalizedString("Request Username", comment: "Voting"), for: .normal)
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.addAction(.touchUpInside) { [weak self] _ in
            self?.continueButtonAction()
        }
        view.addSubview(continueButton)
        view.addSubview(minimumBalanceLabel)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0),

            noteLabel.topAnchor.constraint(equalTo: noteContainer.topAnchor, constant: 0),
            noteLabel.bottomAnchor.constraint(equalTo: noteContainer.bottomAnchor, constant: 0),
            noteLabel.leadingAnchor.constraint(equalTo: noteContainer.leadingAnchor, constant: 15),
            noteLabel.trailingAnchor.constraint(equalTo: noteContainer.trailingAnchor, constant: -15),
            
            continueButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            continueButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            continueButton.heightAnchor.constraint(equalToConstant: 46),
            view.keyboardLayoutGuide.topAnchor.constraint(equalToSystemSpacingBelow: continueButton.bottomAnchor, multiplier: 1.0),
            
            minimumBalanceLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            minimumBalanceLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            minimumBalanceLabel.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -15)
        ])
    }

    private func updateView() {
        let username = usernameField.text
        continueButton.isEnabled = !username.isEmpty
        
        Task {
            noteLabel.isHidden = !(await viewModel.hasRequests(for: username))
        }
    }
    
    func configureObservers() {
        viewModel.$hasEnoughBalance
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] hasEnough in
                guard let self = self else { return }
                self.refreshBalanceWarning(enoughBalance: hasEnough)
            })
            .store(in: &cancellableBag)
    }
    
    private func refreshBalanceWarning(enoughBalance: Bool) {
        usernameField.isEnabled = enoughBalance
        continueButton.isEnabled = enoughBalance
        minimumBalanceLabel.isHidden = enoughBalance
        minimumBalanceLabel.text = String.localizedStringWithFormat(NSLocalizedString("To request a username on the Dash Network, you need to have more than %@ Dash", comment: "Usernames"), viewModel.minimumRequiredBalance)
    }
}

extension RequestUsernameViewController {
    private func continueButtonAction() {
        self.viewModel.enteredUsername = self.usernameField.text
        
        let alert = UIAlertController(title: NSLocalizedString("Verify your identity to enhance your chances of getting your requested username", comment: "Usernames"), message: NSLocalizedString("If somebody else requests the same username as you, we will let the network decide whom to give this username", comment: "Usernames"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Verify", comment: "Usernames"), style: .default, handler: { [weak self] _ in
            self?.navigationController?.pushViewController(VerifyIdenityViewController.controller(), animated: true)
        }))
        let cancelAction = UIAlertAction(title: NSLocalizedString("Skip", comment: ""), style: .cancel) { [weak self] _ in
            let vc = ConfirmRequestViewController.controller(withProve: nil)
            vc.onResult = { result in
                if result {
                    self?.navigationController?.popToRootViewController(animated: true)
                }
            }
            self?.present(vc, animated: true)
        }
        alert.addAction(cancelAction)
        present(alert, animated: true)
    }
}
