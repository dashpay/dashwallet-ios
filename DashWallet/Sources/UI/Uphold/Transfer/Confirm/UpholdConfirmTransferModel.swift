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

import Foundation

// MARK: - UpholdConfirmTransferModelStateNotifier

protocol UpholdConfirmTransferModelStateNotifier: AnyObject {
    func upholdConfirmTransferModel(_ model: UpholdConfirmTransferModel, didUpdateState state: UpholdConfirmTransferModel.State)
}

// MARK: - UpholdConfirmTransferModel

class UpholdConfirmTransferModel: ConfirmPaymentModel {
    enum State: Int {
        case none
        case loading
        case success
        case fail
        case otp
    }


    private(set) var card: DWUpholdCardObject
    private(set) var transaction: DWUpholdTransactionObject

    var state: UpholdConfirmTransferModel.State {
        didSet {
            assert(Thread.isMainThread, "Main thread is assumed here")

            if oldValue == state {
                return
            }

            stateNotifier?.upholdConfirmTransferModel(self, didUpdateState: state)
        }
    }

    weak var stateNotifier: UpholdConfirmTransferModelStateNotifier?

    init(card: DWUpholdCardObject, transaction: DWUpholdTransactionObject) {
        self.card = card
        self.transaction = transaction
        state = .none

        super.init(dataSource: transaction)
    }

    func confirm(withOTPToken otpToken: String?) {
        assert(stateNotifier != nil, "stateNotifier must be set")

        state = .loading
        confirmPayment()

        let client = DWUpholdClient.sharedInstance()
        client.commitTransaction(transaction, card: card, otpToken: otpToken) { [weak self] success, otpRequired in
            guard let strongSelf = self else { return }

            if otpRequired {
                strongSelf.state = .otp
            } else {
                strongSelf.state = success ? .success : .fail
            }
        }
    }

    func cancel() {
        DWUpholdClient.sharedInstance().cancelTransaction(transaction, card: card)
    }

    func resetState() {
        state = .none
    }
}
