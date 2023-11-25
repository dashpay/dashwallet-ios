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

class ConfirmRequestViewController: SheetViewController {
    private var viewModel: RequestUsernameViewModel = RequestUsernameViewModel.shared
    private var proveLink: URL? = nil
    private var continueButton: ActionButton!
    var onResult: ((Bool) -> ())?
    
    static func controller(withProve: URL?) -> ConfirmRequestViewController {
        let vc = ConfirmRequestViewController()
        vc.proveLink = withProve
        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }
    
    override func contentViewHeight() -> CGFloat {
        return 220
    }
}

extension ConfirmRequestViewController {
    private func configureHierarchy() {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.contentMode = .center
        view.addSubview(stackView)
                
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.dw_boldFont(ofSize: 15)
        titleLabel.textColor = UIColor.dw_label()
        titleLabel.text = NSLocalizedString("Confirm Username Request", comment: "Voting")
        titleLabel.textAlignment = .center
        stackView.addArrangedSubview(titleLabel)
        
        let balanceView = BalanceView()
        balanceView.translatesAutoresizingMaskIntoConstraints = false
        balanceView.dataSource = self
        stackView.addArrangedSubview(balanceView)
        stackView.setCustomSpacing(40, after: balanceView)

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
        continueButton.setTitle(NSLocalizedString("Confirm", comment: ""), for: .normal)
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.addAction(.touchUpInside) { [weak self] _ in
            self?.continueAction()
        }
        buttonStack.addArrangedSubview(continueButton)
        self.continueButton = continueButton
        
        view.backgroundColor = .dw_background()

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -15),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            
            cancelButton.heightAnchor.constraint(equalToConstant: 48),
            continueButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
    
    private func showError() {
        let alert = UIAlertController(title: NSLocalizedString("Something went wrong", comment: ""), message: NSLocalizedString("There was a network error, you can try again at no extra cost", comment: "Usernames"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Try Again", comment: ""), style: .default, handler: { [weak self] _ in
            self?.continueAction()
        }))
        let cancelAction = UIAlertAction(title: NSLocalizedString("Close", comment: ""), style: .cancel, handler: { [weak self] _ in
            self?.viewModel.onFlowComplete(withResult: false)
            self?.onResult?(false)
            self?.dismiss(animated: true)
        })
        alert.addAction(cancelAction)
        present(alert, animated: true)
    }
    
    private func continueAction() {
        Task {
            continueButton.showActivityIndicator()
            let result = await self.viewModel.submitUsernameRequest(withProve: self.proveLink)
            continueButton.hideActivityIndicator()
            
            if result {
                self.dismiss(animated: true) {
                    self.onResult?(true)
                    self.viewModel.onFlowComplete(withResult: true)
                }
            } else {
                self.showError()
            }
        }
    }
}

extension ConfirmRequestViewController: BalanceViewDataSource {
    var mainAmountString: String {
        viewModel.minimumRequiredBalance
    }
    
    var supplementaryAmountString: String {
        viewModel.minimumRequiredBalanceFiat
    }
}
