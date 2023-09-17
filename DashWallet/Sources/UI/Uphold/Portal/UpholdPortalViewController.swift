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


// MARK: - UpholdPortalViewController

final class UpholdPortalViewController: BaseViewController {

    public var userSignedOutBlock: ((Bool) -> Void)?

    @IBOutlet var balanceTitleLabel: UILabel!
    @IBOutlet var balanceView: BalanceView!
    @IBOutlet var tableView: UITableView!
    @IBOutlet var signOutButton: UIButton!
    @IBOutlet var mainContentView: UIView!

    private let model = UpholdPortalModel()

    @IBAction
    func signOutAction() {
        model.logOut()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }

    class func controller() -> UpholdPortalViewController {
        vc(UpholdPortalViewController.self, from: sb("UpholdPortal"))
    }
}

extension UpholdPortalViewController {
    private func configureModel() { }

    private func reloadView() {
        // balanceView.dataSource = model
    }

    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never

        balanceTitleLabel.text = NSLocalizedString("Dash balance on Uphold", comment: "Uphold Entry Point")

        balanceView.dashSymbolColor = .dw_dashBlue()

        tableView.isScrollEnabled = false
        tableView.layer.cornerRadius = 10
        tableView.clipsToBounds = true
        tableView.backgroundColor = .dw_background()

        signOutButton.backgroundColor = .dw_background()
        signOutButton.titleLabel?.font = UIFont.dw_font(forTextStyle: .body).withWeight(UIFont.Weight.medium.rawValue)
        signOutButton.layer.cornerRadius = 10
        signOutButton.setTitle(NSLocalizedString("Disconnect Coinbase Account", comment: "Coinbase Entry Point"), for: .normal)

        reloadView()
    }

    private func showNoPaymentMethodsFlow() {
        let title = NSLocalizedString("No payment methods found", comment: "Coinbase/Buy Dash")
        let message = NSLocalizedString("Please add a payment method on Coinbase", comment: "Coinbase/Buy Dash")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let addAction = UIAlertAction(title: NSLocalizedString("Add", comment: ""), style: .default) { [weak self] _ in
            self?.addPaymentMethod()
        }
        alert.addAction(addAction)

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
        alert.addAction(cancelAction)
        present(alert, animated: true)
    }

    private func addPaymentMethod() {
        UIApplication.shared.open(kCoinbaseAddPaymentMethodsURL)
    }
}

// MARK: UITableViewDelegate, UITableViewDataSource

extension UpholdPortalViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let isLastItem = indexPath.item == 1 // (model.items.count - 1)

        let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath) as! ItemCell
        cell.separatorInset = .init(top: 0, left: isLastItem ? 2000 : 63, bottom: 0, right: 0)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        62.0
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

