//
//  Created by Dash Core Group
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

/// Hosts `VerifyRecoveryPhraseView`. Once the phrase is verified, it tells the
/// delegate and goes on to "Verified Successfully".
final class VerifyRecoveryPhraseViewController: SetupScreenViewController {
    weak var delegate: DWSecureWalletDelegate?

    private let viewModel: VerifyRecoveryPhraseViewModel
    private let feedback = UINotificationFeedbackGenerator()

    init(seedPhrase: DWSeedPhraseModel) {
        viewModel = VerifyRecoveryPhraseViewModel(seedPhrase: seedPhrase)
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Backup Wallet", comment: "A noun. Used as a title.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(named: "SecondaryBackgroundColor")
        viewModel.onVerified = { [weak self] in self?.didVerify() }
        embedScreen(VerifyRecoveryPhraseView(viewModel: viewModel))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        feedback.prepare()
    }

    private func didVerify() {
        delegate?.secureWalletRoutineDidVerify(self)
        feedback.notificationOccurred(.success)

        let controller = VerifiedSuccessfullyViewController()
        controller.delegate = delegate
        navigationController?.pushViewController(controller, animated: true)
    }
}
