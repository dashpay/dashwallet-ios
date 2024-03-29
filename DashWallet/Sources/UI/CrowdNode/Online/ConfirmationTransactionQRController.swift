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

// MARK: - ConfirmationTransactionQRController

final class ConfirmationTransactionQRController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()

    @IBOutlet var qrImage: UIImageView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var messageLabel: UILabel!
    private var paymentRequest: DSPaymentRequest!

    static func controller(_ paymentRequest: DSPaymentRequest) -> ConfirmationTransactionQRController {
        let vc = vc(ConfirmationTransactionQRController.self, from: sb("CrowdNode"))
        vc.modalPresentationStyle = .pageSheet
        vc.paymentRequest = paymentRequest

        if #available(iOS 16.0, *) {
            if let sheet = vc.sheetPresentationController {
                let fitId = UISheetPresentationController.Detent.Identifier("fit")
                let fitDetent = UISheetPresentationController.Detent.custom(identifier: fitId) { _ in
                    420
                }
                sheet.detents = [fitDetent]
            }
        }

        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }
}

extension ConfirmationTransactionQRController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        titleLabel.text = NSLocalizedString("Scan QR", comment: "")
        let confirmationAmount = CrowdNode.apiConfirmationDashAmount.formattedDashAmount
        messageLabel.text = String.localizedStringWithFormat(NSLocalizedString("This QR already contains the payment request for %@", comment: "CrowdNode Confirm"),
                                                             confirmationAmount)
        configureQrImage()
    }

    private func configureQrImage() {
        let rawQRImage = UIImage.dw_image(withQRCodeData: paymentRequest.data!, color: CIColor(color: UIColor.label))

        let overlayImage = UIImage(named: "dash_logo_qr")!.withTintColor(.label)
        let screenWidth = CGRectGetWidth(UIScreen.main.bounds)
        let padding = 38.0
        let side = screenWidth - padding * 2;

        var resizedImage = rawQRImage.dw_resize(CGSizeMake(side, side), with: .none)
        resizedImage = resizedImage.dw_imageByCuttingHoleInCenter(with: CGSizeMake(84.0, 84.0))
        let image = resizedImage.dw_imageByMerging(with: overlayImage)

        qrImage.image = image
    }
}
