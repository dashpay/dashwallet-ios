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

import Foundation
import Combine

final class CrowdNodeTransferController: SendAmountViewController, NetworkReachabilityHandling {
    
    internal var mode: TransferDirection = .deposit
    
    /// Conform to NetworkReachabilityHandling
    internal var networkStatusDidChange: ((NetworkStatus) -> ())?
    internal var reachabilityObserver: Any!
    internal var depositWithdrawModel: DepositWithdrawModel {
        model as! DepositWithdrawModel
    }
    
    private var paymentController: PaymentController!
    private var networkUnavailableView: UIView!
    
    override var amountInputStyle: AmountInputControl.Style { .oppositeAmount }
    
    static func controller(mode: TransferDirection) -> CrowdNodeTransferController {
        let vc = CrowdNodeTransferController()
        vc.mode = mode
        
        return vc
    }

    override var actionButtonTitle: String? {
        NSLocalizedString(mode.title, comment: "CrowdNode")
    }

    override func actionButtonAction(sender: UIView) {
        showActivityIndicator()
    }

    override func initializeModel() {
        model = DepositWithdrawModel()
    }

    override func configureModel() {
        super.configureModel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_background()
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never

        networkStatusDidChange = { [weak self] _ in
            self?.reloadView()
        }
        startNetworkMonitoring()
    }

    deinit {
        stopNetworkMonitoring()
    }
}

extension CrowdNodeTransferController {
    override func configureHierarchy() {
        super.configureHierarchy()
        
        configureTitleBar()
        let fromToLabel = configureToFromLabel()
        contentView.addSubview(fromToLabel)
        
        let keyboardHeader = KeyboardHeader(icon: mode.keyboardHeaderIcon, text: mode.keyboardHeader)
        keyboardHeader.translatesAutoresizingMaskIntoConstraints = false
        topKeyboardView = keyboardHeader

        networkUnavailableView = NetworkUnavailableView(frame: .zero)
        networkUnavailableView.translatesAutoresizingMaskIntoConstraints = false
        networkUnavailableView.isHidden = true
        contentView.addSubview(networkUnavailableView)

        NSLayoutConstraint.activate([
            fromToLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            NSLayoutConstraint(item: fromToLabel, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 0.35, constant: 0),
            
            amountView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            amountView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            NSLayoutConstraint(item: amountView!, attribute: .top, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 0.47, constant: 0),
            
            networkUnavailableView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            networkUnavailableView.centerYAnchor.constraint(equalTo: numberKeyboard.centerYAnchor),
        ])
    }
    
    private func configureTitleBar() {
        let titleViewStackView = UIStackView()
        titleViewStackView.alignment = .center
        titleViewStackView.translatesAutoresizingMaskIntoConstraints = false
        titleViewStackView.axis = .vertical
        titleViewStackView.spacing = 1
        navigationItem.titleView = titleViewStackView

        let titleLabel = UILabel()
        titleLabel.font = .dw_mediumFont(ofSize: 16)
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.text = NSLocalizedString(mode.title, comment: "CrowdNode")
        titleViewStackView.addArrangedSubview(titleLabel)

        let dashPriceLabel = UILabel()
        dashPriceLabel.font = .dw_font(forTextStyle: .footnote)
        dashPriceLabel.textColor = .dw_secondaryText()
        dashPriceLabel.minimumScaleFactor = 0.5
        dashPriceLabel.text = depositWithdrawModel.dashPriceDisplayString
        titleViewStackView.addArrangedSubview(dashPriceLabel)
    }
    
    private func configureToFromLabel() -> UIStackView {
        let horizontal = UIStackView()
        horizontal.translatesAutoresizingMaskIntoConstraints = false
        horizontal.spacing = 10
        horizontal.axis = .horizontal
        
        let iconView = UIImageView(image: UIImage(named: mode.imageName))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 32).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        horizontal.addArrangedSubview(iconView)

        let vertical = UIStackView()
        vertical.translatesAutoresizingMaskIntoConstraints = false
        vertical.axis = .vertical
        horizontal.addArrangedSubview(vertical)

        let fromLabel = UILabel()
        fromLabel.textColor = .dw_label()
        fromLabel.font = .dw_regularFont(ofSize: 14)
        fromLabel.text = NSLocalizedString(mode.direction, comment: "CrowdNode")
        vertical.addArrangedSubview(fromLabel)

        let balanceLabel = UILabel()
        balanceLabel.textColor = .dw_tertiaryText()
        balanceLabel.font = .systemFont(ofSize: 12)
        balanceLabel.text = NSLocalizedString("balance: $200", comment: "CrowdNode")
        vertical.addArrangedSubview(balanceLabel)
        
        return horizontal
    }
}

extension CrowdNodeTransferController {
    private func reloadView() {
        let isOnline = networkStatus == .online
        networkUnavailableView.isHidden = isOnline
        keyboardContainer.isHidden = !isOnline
        if let btn = actionButton as? UIButton { btn.superview?.isHidden = !isOnline }
    }

    private func showSuccessTransactionStatus() {
        showSuccessTransactionStatus(text: NSLocalizedString("It could take up to 10 minutes to transfer Dash from Coinbase to Dash Wallet on this device", comment: "Coinbase"))
    }
}

extension CrowdNodeTransferController: PaymentControllerDelegate {
    func paymentControllerDidFinishTransaction(_ controller: PaymentController, transaction: DSTransaction) {
        hideActivityIndicator()
        showSuccessTransactionStatus()
    }

    func paymentControllerDidCancelTransaction(_ controller: PaymentController) {
        hideActivityIndicator()
    }

    func paymentControllerDidFailTransaction(_ controller: PaymentController) {
        hideActivityIndicator()
    }
}

extension CrowdNodeTransferController: PaymentControllerPresentationContextProviding {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        self
    }
}


//final class CrowdNodeTransferController: UIViewController {
//    private let viewModel = CrowdNodeModel.shared
//    private var cancellableBag = Set<AnyCancellable>()
//
//    @IBOutlet var depositInput: UITextField!
//    @IBOutlet var withdrawInput: UITextField!
//    @IBOutlet var outputLabel: UILabel!
//    @IBOutlet var addressLabel: UILabel!
//
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        configureLayout()
//    }
//
//    override func viewDidDisappear(_ animated: Bool) {
//        super.viewDidDisappear(animated)
//        cancellableBag.removeAll()
//    }
//
//    @objc func copyAddress() {
//        UIPasteboard.general.string = addressLabel.text
//    }
//
//    @IBAction func deposit() {
//        guard let inputText = depositInput.text else { return }
//        let dash = DSPriceManager.sharedInstance().amount(forDashString: inputText.replacingOccurrences(of: ",", with: "."))
//
//        Task {
//            do {
//                try await viewModel.deposit(amount: dash)
//                navigationController?.popViewController(animated: true)
//            } catch {
//                outputLabel.text = error.localizedDescription
//            }
//        }
//    }
//
//    @IBAction func withdraw() {
//        guard let inputText = withdrawInput.text else { return }
//        let permil = UInt(inputText) ?? 0
//
//        Task {
//            do {
//                try await viewModel.withdraw(permil: permil)
//                navigationController?.popViewController(animated: true)
//            } catch {
//                outputLabel.text = error.localizedDescription
//            }
//        }
//    }
//
//    @objc static func controller() -> CrowdNodeTransferController {
//        let storyboard = UIStoryboard(name: "CrowdNode", bundle: nil)
//        let vc = storyboard.instantiateViewController(withIdentifier: "CrowdNodeTransferController") as! CrowdNodeTransferController
//        return vc
//    }
//}
//
//extension CrowdNodeTransferController {
//    func configureLayout() {
//        depositInput.delegate = self
//        depositInput.keyboardType = .decimalPad
//
//        withdrawInput.delegate = self
//        withdrawInput.keyboardType = .numberPad
//
//        addressLabel.text = viewModel.accountAddress
//        let tap = UITapGestureRecognizer(target: self, action: #selector(copyAddress))
//        addressLabel.addGestureRecognizer(tap)
//    }
//}
//
//// MARK: UITextFieldDelegate
//
//// TODO: this is a primitive sanitizing of the input. Probably won't be needed and can be removed when UI is done.
//extension CrowdNodeTransferController: UITextFieldDelegate {
//    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
//        let text = textField.text ?? ""
//        guard let range = Range(range, in: text) else { return false }
//        let newText = text.replacingCharacters(in: range, with: string)
//
//        if newText.isEmpty {
//            return true
//        }
//
//        if textField == depositInput {
//            if newText == "0" || (newText.starts(with: "0,") && newText.filter { $0 == "," }.count == 1) ||
//                (newText.starts(with: "0.") && newText.filter { $0 == "." }.count == 1) {
//                return true
//            }
//
//            let priceManager = DSPriceManager.sharedInstance()
//            return priceManager.amount(forDashString: newText) > 0
//        } else {
//            let int = (Int(newText) ?? -1)
//            return int >= 0 && int <= 1000
//        }
//    }
//}
