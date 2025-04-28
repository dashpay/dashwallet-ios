//  
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

let kMaxChars = 25

class PrivateMemoViewModel: ObservableObject {
    private let initialValue: String
    
    let txId: Data
    @Published var input: String = ""
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    
    init(txHash: Data, initialValue: String) {
        self.txId = txHash
        self.initialValue = initialValue
        self.input = initialValue
    }
    
    func canContinue() -> Bool {
        return (!input.isEmpty || input != initialValue) && input.count <= kMaxChars
    }
    
    func onContinue() -> Bool {
        if (input.isEmpty && initialValue.isEmpty) || input.count > kMaxChars {
            return false
        }
        
        var metadata = TransactionMetadata(txHash: txId)
        metadata.memo = input
        TransactionMetadataDAOImpl.shared.update(dto: metadata)
        
        return true
    }
}
