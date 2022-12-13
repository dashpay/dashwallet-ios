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

// MARK: - CrowdNodePortalController

final class CrowdNodePortalController: UIViewController {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()

    @IBOutlet var depositInput: UITextField!
    @IBOutlet var withdrawInput: UITextField!
    @IBOutlet var outputLabel: UILabel!
    @IBOutlet var addressLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancellableBag.removeAll()
    }

    @objc func copyAddress() {
        UIPasteboard.general.string = addressLabel.text
    }

    @IBAction func deposit() {
        guard let inputText = depositInput.text else { return }
        let dash = DSPriceManager.sharedInstance().amount(forDashString: inputText)

        Task {
            do {
                try await viewModel.deposit(amount: dash)
                await MainActor.run {
                    dismiss(animated: true, completion: nil)
                }
            } catch {
                outputLabel.text = error.localizedDescription
            }
        }
    }

    @IBAction func withdraw() {
        guard let inputText = withdrawInput.text else { return }
        let permil = UInt(inputText) ?? 0

        Task {
            do {
                try await viewModel.withdraw(permil: permil)
                await MainActor.run {
                    dismiss(animated: true, completion: nil)
                }
            } catch {
                outputLabel.text = error.localizedDescription
            }
        }
    }

    @objc static func controller() -> CrowdNodePortalController {
        let storyboard = UIStoryboard(name: "CrowdNode", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "CrowdNodePortalController") as! CrowdNodePortalController
        return vc
    }
}

extension CrowdNodePortalController {
    func configureLayout() {
        depositInput.delegate = self
        depositInput.keyboardType = .decimalPad

        withdrawInput.delegate = self
        withdrawInput.keyboardType = .numberPad

        addressLabel.text = viewModel.accountAddress
        let tap = UITapGestureRecognizer(target: self, action: #selector(copyAddress))
        addressLabel.addGestureRecognizer(tap)
    }
}

// MARK: UITextFieldDelegate

// TODO: this is a primitive sanitizing of the input. Probably won't be needed and can be removed when UI is done.
extension CrowdNodePortalController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let text = textField.text ?? ""
        guard let range = Range(range, in: text) else { return false }
        let newText = text.replacingCharacters(in: range, with: string)

        if newText.isEmpty {
            return true
        }

        if textField == depositInput {
            if newText == "0" || (newText.starts(with: "0,") && newText.filter { $0 == "," }.count == 1) {
                return true
            }

            let priceManager = DSPriceManager.sharedInstance()
            return priceManager.amount(forDashString: newText) > 0
        } else {
            let int = (Int(newText) ?? -1)
            return int >= 0 && int <= 1000
        }
    }
}
