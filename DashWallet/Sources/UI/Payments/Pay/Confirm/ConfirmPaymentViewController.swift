//  
//  Created by PT
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

final class ConfirmPaymentViewController: BaseViewController {
    private var balanceView: BalanceView!
    private var tableView: UITableView!
    private var confirmButton: ActionButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
    }
}

extension ConfirmPaymentViewController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()
    
        balanceView = BalanceView()
        balanceView.dataSource = self
        balanceView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(balanceView)
        
        tableView = DWCenteredTableView(frame: .zero, style: .insetGrouped)
        tableView.layoutMargins = .init(top: 0.0, left: 15, bottom: 0.0, right: 0)
        tableView.isScrollEnabled = false
        tableView.separatorStyle = .none
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.preservesSuperviewLayoutMargins = true
        tableView.backgroundColor = UIColor.dw_secondaryBackground()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.registerClass(for: TitleValueCell.self)
        view.addSubview(tableView)
        
        let bottomButtonsStack = UIStackView()
        bottomButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        bottomButtonsStack.axis = .horizontal
        bottomButtonsStack.spacing = 10
        bottomButtonsStack.distribution = .fillEqually
        view.addSubview(bottomButtonsStack)
        
        let cancelButton = GrayButton()
        cancelButton.addAction(.touchUpInside) { [weak self] _ in
            self?.dismiss(animated: true)
        }
        cancelButton.setTitle(NSLocalizedString("Cancel", comment: "Payment confirmation"), for: .normal)
        bottomButtonsStack.addArrangedSubview(cancelButton)
        
        confirmButton = ActionButton()
        confirmButton.setTitle(NSLocalizedString("Confirm", comment: "Payment confirmation"), for: .normal)
        bottomButtonsStack.addArrangedSubview(confirmButton)
        
        NSLayoutConstraint.activate([
            balanceView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            tableView.topAnchor.constraint(equalTo: balanceView.bottomAnchor, constant: 20),
            tableView.bottomAnchor.constraint(equalTo: bottomButtonsStack.bottomAnchor, constant: -30),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            bottomButtonsStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            bottomButtonsStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
             
            //bottomButtonsStack.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 30),
            bottomButtonsStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -15),
            bottomButtonsStack.heightAnchor.constraint(equalToConstant: 46)
        ])
    }
}

extension ConfirmPaymentViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(type: TitleValueCell.self, for: indexPath)
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }
}

extension ConfirmPaymentViewController: BalanceViewDataSource {
    var mainAmountString: String {
        "DASH 10.24"
    }
    
    var supplementaryAmountString: String {
        "$1.24"
    }
    
    
}
