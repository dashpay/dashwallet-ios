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

import Combine

class RequestDetailsViewController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private let viewModel = CreateUsernameViewModel.shared
    
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var subtitleLabel: UILabel!

    @IBOutlet private var usernameLabel: UILabel!
    @IBOutlet private var usernameText: UILabel!
    @IBOutlet private var linkLabel: UILabel!
    @IBOutlet private var linkText: UILabel!
    @IBOutlet private var verifyLabel: UILabel!
    @IBOutlet private var identityLabel: UILabel!
    @IBOutlet private var identityText: UILabel!
    @IBOutlet private var identityConstraint: NSLayoutConstraint!
    @IBOutlet private var resultsLabel: UILabel!
    @IBOutlet private var resultsDateText: UILabel!

    @IBOutlet private var continueButton: TintedButton!
    
    @objc
    static func controller() -> RequestDetailsViewController {
        vc(RequestDetailsViewController.self, from: sb("UsernameRequests"))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureLayout()
        configureObservers()
        viewModel.fetchUsernameRequestData()
    }
    
    @IBAction
    func continueAction() {
        confirmCancel()
    }
}

extension RequestDetailsViewController {
    private func configureLayout() {
        let buttonImage = UIImage(systemName: "info.circle")
        let button = UIBarButtonItem(image: buttonImage, style: UIBarButtonItem.Style.plain, target: self, action: #selector(infoButtonAction))
        button.tintColor = .dw_dashBlue()
        navigationItem.rightBarButtonItem = button
        
        titleLabel.text = NSLocalizedString("Request details", comment: "Usernames")
        subtitleLabel.text = NSLocalizedString("After the voting ends we will notify you about its results", comment: "Usernames")
        
        usernameLabel.text = NSLocalizedString("Username", comment: "Usernames")
        linkLabel.text = NSLocalizedString("Link", comment: "Usernames")
        identityLabel.text = NSLocalizedString("Identity", comment: "Usernames")
        resultsLabel.text = NSLocalizedString("Results", comment: "Usernames")
        let endDate = Date(timeIntervalSince1970: VotingConstants.votingEndTime) // TODO replace
        let endDateStr = DWDateFormatter.sharedInstance.dateOnly(from: endDate)
        resultsDateText.text = endDateStr
        
        var configuration = UIButton.Configuration.configuration(from: .tinted())
        configuration.baseBackgroundColor = .dw_red().withAlphaComponent(0.08)
        configuration.baseForegroundColor = .dw_red()
        continueButton.configuration = configuration
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.dw_mediumFont(ofSize: 15)
        ]
        continueButton.setAttributedTitle(NSAttributedString(string: NSLocalizedString("Cancel Request", comment: ""), attributes: attributes), for: .normal)
    }
    
    private func configureObservers() {
        viewModel.$currentUsernameRequest
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .filter { $0 != nil }
            .sink { [weak self] request in
                self?.showUsernameRequestInfo(request: request!)
            }
            .store(in: &cancellableBag)
    }
    
    private func showUsernameRequestInfo(request: UsernameRequest) {
        usernameText.text = request.username
        
        if let link = request.link, !link.isEmpty {
            let attributedString = NSAttributedString(string: link, attributes: [NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue])
            linkText.attributedText = attributedString
            linkText.textColor = .dw_dashBlue()
            verifyLabel.isHidden = true
            identityConstraint.constant = 12
        } else {
            linkText.text = NSLocalizedString("None", comment: "")
            linkText.textColor = .dw_label()
            verifyLabel.isHidden = false
            identityConstraint.constant = 24
        }
        
        let linkTap = UITapGestureRecognizer(target: self, action: #selector(onLinkTapped))
        linkText.addGestureRecognizer(linkTap)
        let verifyTap = UITapGestureRecognizer(target: self, action: #selector(onLinkTapped))
        verifyLabel.addGestureRecognizer(verifyTap)
        
        identityText.text = request.identity
    }
}

extension RequestDetailsViewController {
    private func confirmCancel() {
        let alert = UIAlertController(title: NSLocalizedString("Do you really want to cancel the username request?", comment: "Usernames"), message: NSLocalizedString("If you tap “Cancel Request”, you will still have a chance to request another username without paying again", comment: "Usernames"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel Request", comment: "Usernames"), style: .destructive, handler: { [weak self] _ in
            self?.viewModel.cancelRequest()
            self?.navigationController?.popViewController(animated: true)
        }))
        let cancelAction = UIAlertAction(title: NSLocalizedString("Close", comment: ""), style: .cancel)
        alert.addAction(cancelAction)
        present(alert, animated: true)
    }
    
    @objc
    private func onLinkTapped() {
        if let url = viewModel.currentUsernameRequest?.link {
            UIApplication.shared.open(URL(string: url)!)
        } else {
            // TODO
//            self.navigationController?.pushViewController(VerifyIdenityViewController.controller(), animated: true)
        }
    }
    
    @objc
    private func infoButtonAction() {
        // TODO
    }
}
