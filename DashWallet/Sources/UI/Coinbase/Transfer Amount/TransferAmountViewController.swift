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

import UIKit
import SwiftUI

struct TransferAmountView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TransferAmountViewController {
        return TransferAmountViewController()
    }
    
    func updateUIViewController(_ viewController: TransferAmountViewController, context: Context) {
    }
}

class TransferAmountViewController: BaseAmountViewController {
    
    override var actionButtonTitle: String? {
        return NSLocalizedString("Transfer", comment: "Coinbase")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Transfer Dash", comment: "Coinbase")
    }
}
