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

// MARK: - ReceiveContentView

@objc(DWReceiveContentView)
final class ReceiveContentView: UIStackView {
    @IBOutlet var qrCodeButton: UIButton!
    @IBOutlet var actionButtonsStackView: UIStackView!
    @IBOutlet var addressButton: UIButton!
    @IBOutlet var specifyAmountButton: UIButton!
    @IBOutlet var secondButton: UIButton!
    
    // DashPay
    @IBOutlet var qrContainer: UIView!
    @IBOutlet var addressContainer: UIView!
    @IBOutlet var usernameContainer: UIView!
    @IBOutlet var addressLabel: UILabel!
    @IBOutlet var usernameLabel: UILabel!

    private var model: DWReceiveModelProtocol!
    private var feedbackGenerator = UINotificationFeedbackGenerator()

    public var specifyAmountHandler: (() -> Void)?

    @objc
    public var shareHandler: ((UIButton) -> Void)?

    @IBAction
    func addressButtonAction() {
        feedbackGenerator.notificationOccurred(.success)
        model.copyAddressToPasteboard()
        dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }

    @IBAction
    func qrButtonAction() {
        feedbackGenerator.notificationOccurred(.success)
        model.copyQRImageToPasteboard()
        dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }
    
#if DASHPAY
    @objc
    private func copyUsernameAction() {
        feedbackGenerator.notificationOccurred(.success)
        model.copyUsernameToPasteboard()
        dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }
#endif

    @IBAction
    func specifyAmountButtonAction() {
        specifyAmountHandler?()
    }

    @IBAction
    func secondButtonAction() {
        shareHandler?(secondButton)
    }

    @objc
    func setSpecifyAmountButtonHidden(_ hidden: Bool) {
        specifyAmountButton.isHidden = hidden
    }

    @objc
    func setSecondButtonHidden(_ hidden: Bool) {
        secondButton.isHidden = hidden
    }

    @objc
    static func view(with model: DWReceiveModelProtocol) -> ReceiveContentView {
        let view = UINib.view(Self.self)
        
        view.model = model

        model.delegate = view

        view.configureHierarchy()
        view.reloadView()

        return view
    }
}

extension ReceiveContentView {
    private func configureHierarchy() {
        specifyAmountButton.setTitle(NSLocalizedString("Specify Amount", comment: "Receive screen"), for: .normal)
        secondButton.setTitle(NSLocalizedString("Share address", comment: "Receive screen"), for: .normal)
        
    #if DASHPAY
        addressContainer.isHidden = false
        usernameContainer.isHidden = false
        addressButton.isHidden = true
        
        let copyAddress = UITapGestureRecognizer(target: self, action: #selector(addressButtonAction))
        addressContainer.addGestureRecognizer(copyAddress)
        
        let copyUsername = UITapGestureRecognizer(target: self, action: #selector(copyUsernameAction))
        usernameContainer.addGestureRecognizer(copyUsername)
        
        if UIScreen.main.bounds.size.height <= 670 {
            NSLayoutConstraint.activate([
                qrContainer.heightAnchor.constraint(equalToConstant: 270),
                qrCodeButton.topAnchor.constraint(equalTo: qrContainer.topAnchor, constant: 10),
                usernameContainer.heightAnchor.constraint(equalToConstant: 45)
            ])
        }
    #else
        addressContainer.isHidden = true
        usernameContainer.isHidden = true
        addressButton.isHidden = false
    #endif
    }

    private func reloadView() {
        let hasAddress = model.paymentAddress != nil

    #if DASHPAY
        let hasUsername = model.username != nil
        addressLabel.text = model.paymentAddress
        usernameLabel.text = model.username
        addressContainer.isHidden = !hasAddress
        usernameContainer.isHidden = !hasUsername
    #else
        addressButton.setTitle(model.paymentAddress, for: .normal)
        addressButton.isHidden = !hasAddress
    #endif

        qrCodeButton.setImage(model.qrCodeImage, for: .normal)
        qrCodeButton.isHidden = model.qrCodeImage == nil

        specifyAmountButton.isEnabled = hasAddress
        secondButton.isEnabled = hasAddress
    }
}

// MARK: DWReceiveModelDelegate

extension ReceiveContentView: DWReceiveModelDelegate {
    func receivingInfoDidUpdate() {
        reloadView()
    }
}
