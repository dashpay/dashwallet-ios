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

import Combine
import SwiftUI
import UIKit

@objc(DWRecoverViewControllerDelegate)
protocol RecoverWalletViewControllerDelegate: NSObjectProtocol {
    @objc(recoverViewControllerDidRecoverWallet:recoverCommand:)
    func recoverViewControllerDidRecoverWallet(_ controller: RecoverWalletViewController,
                                               recover recoverCommand: DWRecoverWalletCommand)

    @objc(recoverViewControllerDidWipe:)
    func recoverViewControllerDidWipe(_ controller: RecoverWalletViewController)

    /// Reset PIN only: the phrase matched a stored wallet, which is left as
    /// it is. The caller sets the new PIN.
    @objc(recoverViewControllerDidVerifyPhraseForPinReset:)
    optional func recoverViewControllerDidVerifyPhraseForPinReset(_ controller: RecoverWalletViewController)
}

/// Hosts `RecoverWalletView`. Set `action` before the screen loads.
@objc(DWRecoverViewController)
final class RecoverWalletViewController: SetupScreenViewController {
    @objc var action: DWRecoverAction = .recover
    @objc weak var delegate: RecoverWalletViewControllerDelegate?

    private var viewModel: RecoverWalletViewModel?
    private var repairController: UIViewController?
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()

        let viewModel = RecoverWalletViewModel(model: DWRecoverModel(action: action))
        viewModel.onRecover = { [weak self] command in
            guard let self else { return }
            self.delegate?.recoverViewControllerDidRecoverWallet(self, recover: command)
        }
        viewModel.onVerifyForPinReset = { [weak self] in
            guard let self else { return }
            self.delegate?.recoverViewControllerDidVerifyPhraseForPinReset?(self)
        }
        viewModel.onWipe = { [weak self] in
            guard let self else { return }
            self.delegate?.recoverViewControllerDidWipe(self)
        }
        self.viewModel = viewModel

        // The repair shows over the whole window, as an alert would.
        viewModel.$repair
            .removeDuplicates { $0 === $1 }
            .sink { [weak self] repair in self?.showRepair(repair) }
            .store(in: &cancellables)

        // Confirming a wipe: an action sheet, an alert on iPad.
        viewModel.$isWipeConfirmationPresented
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.confirmWipe() }
            .store(in: &cancellables)

        title = viewModel.title
        view.backgroundColor = UIColor(named: "SecondaryBackgroundColor")
        embedScreen(RecoverWalletView(viewModel: viewModel))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel?.focus()
    }

    private func confirmWipe() {
        guard let viewModel else { return }
        let alert = UIAlertController(title: nil, message: nil,
                                      preferredStyle: UIDevice.isIpad ? .alert : .actionSheet)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel", comment: ""), style: .cancel) { _ in
            viewModel.isWipeConfirmationPresented = false
            viewModel.cancelWipe()
        })
        alert.addAction(UIAlertAction(title: viewModel.wipeTitle, style: .destructive) { _ in
            viewModel.isWipeConfirmationPresented = false
            viewModel.wipe()
        })
        present(alert, animated: true)
    }

    private func showRepair(_ repair: PhraseRepairViewModel?) {
        if let repair {
            let controller = UIHostingController(rootView: PhraseRepairView(viewModel: repair))
            controller.view.backgroundColor = .clear
            controller.modalPresentationStyle = .overFullScreen
            controller.modalTransitionStyle = .crossDissolve
            repairController = controller
            present(controller, animated: true)
        } else if let controller = repairController {
            repairController = nil
            controller.dismiss(animated: true) { [weak self] in self?.viewModel?.focus() }
        }
    }
}
