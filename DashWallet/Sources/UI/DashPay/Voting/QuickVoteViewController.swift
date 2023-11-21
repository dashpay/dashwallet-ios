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

import Foundation

class QuickVoteViewController: SheetViewController {
    private var viewModel: VotingViewModel = VotingViewModel.shared
    private var totalRequests: Int!
    
    static func controller(_ totalRequests: Int) -> QuickVoteViewController {
        let vc = QuickVoteViewController()
        vc.totalRequests = totalRequests
        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }
    
    override func contentViewHeight() -> CGFloat {
        return 210
    }
}

extension QuickVoteViewController {
    private func configureHierarchy() {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.contentMode = .center
        view.addSubview(stackView)
                
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.dw_boldFont(ofSize: 22)
        titleLabel.textColor = UIColor.dw_label()
        titleLabel.text = NSLocalizedString("Quick Voting", comment: "Voting")
        titleLabel.textAlignment = .center
        stackView.addArrangedSubview(titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = UIFont.dw_regularFont(ofSize: 13)
        subtitleLabel.textColor = UIColor.dw_label()
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.text = String.localizedStringWithFormat(NSLocalizedString("By tapping the \"Vote for All\" button, you will automatically vote for all of the filtered usernames (%ld) that were submitted first", comment: "Voting"), totalRequests)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.setCustomSpacing(35, after: subtitleLabel)

        let buttonStack = UIStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fill
        buttonStack.spacing = 10
        stackView.addArrangedSubview(buttonStack)
        
        let cancelButton = GrayButton()
        cancelButton.setTitle(NSLocalizedString("Cancel", comment: ""), for: .normal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addAction(.touchUpInside) { [weak self] _ in
            self?.dismiss(animated: true)
        }
        buttonStack.addArrangedSubview(cancelButton)
        
        let continueButton = ActionButton()
        continueButton.setTitle(NSLocalizedString("Vote for All", comment: "Voting"), for: .normal)
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.addAction(.touchUpInside) { [weak self] _ in
            self?.viewModel.voteForAllFirstSubmitted()
            self?.dismiss(animated: true)
        }
        buttonStack.addArrangedSubview(continueButton)
        
        view.backgroundColor = .dw_background()

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -15),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 25),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            
            cancelButton.heightAnchor.constraint(equalToConstant: 48),
            continueButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
}
