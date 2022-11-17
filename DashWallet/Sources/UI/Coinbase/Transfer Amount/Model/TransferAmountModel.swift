//  
//  Created by tkhp
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

protocol TransferAmountModelDelegate: AnyObject {
    func initiatePayment(with input: DWPaymentInput)
}

final class TransferAmountModel: SendAmountModel {
    enum TransferDirection {
        case toWallet
        case toCoinbase
    }
    
    public weak var delegate: TransferAmountModelDelegate?
    
    private var cancellables: Set<AnyCancellable> = []
    
    public var address: String!
    public var direction: TransferDirection = .toCoinbase
    
    override init() {
        super.init()
        
        obtainNewAddress()
    }
   
    func initializeTransfer() {
        if direction == .toCoinbase {
            transferToCoinbase()
        }else{
            transferToWallet()
        }
    }
    
    private func transferToCoinbase() {
        guard let address = self.address else { return }
        
        //TODO: validate
        let amount = UInt64(amount.plainAmount)
        guard let paymentInput = DWPaymentInputBuilder().pay(toAddress: address, amount: amount) else {
            return
        }
        
        delegate?.initiatePayment(with: paymentInput)
    }
    
    private func transferToWallet() {
        //Coinbase.shared.transferFromCoinbaseToDashWallet(verificationCode: <#T##String#>, coinAmountInDash: <#T##String#>, dashWalletAddress: <#T##String#>)
    }
    
    private func obtainNewAddress() {
        Coinbase.shared.createNewCoinbaseDashAddress()
            .receive(on: RunLoop.main)
            .sink { completion in
                print(completion)
            } receiveValue: { address in
                self.address = address
            }
            .store(in: &cancellables)
    }
}
