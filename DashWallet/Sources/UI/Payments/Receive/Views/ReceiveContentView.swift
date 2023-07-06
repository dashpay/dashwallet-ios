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
final class ReceiveContentView: UIView {
    @IBOutlet var qrCodeButton: UIButton!
    @IBOutlet var actionButtonsStackView: UIStackView!
    @IBOutlet var addressButton: UIButton!
    @IBOutlet var specifyAmountButton: UIButton!
    @IBOutlet var secondButton: UIButton!

    private var model: DWReceiveModelProtocol!
    private var feedbackGenerator = UINotificationFeedbackGenerator()

    @objc
    public var viewType: ReceiveViewType = .default

    public var specifyAmountHandler: (() -> Void)?

    @objc
    public var shareHandler: ((UIButton) -> Void)?

    @objc
    public var exitHandler: (() -> Void)?

    @IBAction
    func addressButtonAction() {
        feedbackGenerator.notificationOccurred(.success)
        model.copyAddressToPasteboard()
    }

    @IBAction
    func qrButtonAction() {
        feedbackGenerator.notificationOccurred(.success)
        model.copyQRImageToPasteboard()
    }

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
        secondButton.setTitle(viewType.secondButtonTitle, for: .normal)
    }

    private func reloadView() {
        let hasValue = model.paymentAddress != nil

        addressButton.setTitle(model.paymentAddress, for: .normal)
        addressButton.isHidden = !hasValue

        qrCodeButton.setImage(model.qrCodeImage, for: .normal)
        qrCodeButton.isHidden = model.qrCodeImage == nil

        specifyAmountButton.isEnabled = hasValue

        if viewType == .default {
            secondButton.isEnabled = hasValue
        }
    }
}

// MARK: DWReceiveModelDelegate

extension ReceiveContentView: DWReceiveModelDelegate {
    func receivingInfoDidUpdate() {
        reloadView()
    }
}
