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

final class CoinbaseEntryPointViewController: UIViewController {
    @IBOutlet var connectionStatusLabel: UILabel!
    @IBOutlet var dashBalanceLabel: UILabel!
    @IBOutlet var fiatBalanceLabel: UILabel!
    @IBOutlet var tableView: UITableView!
    @IBOutlet var signOutButton: UIButton!
    @IBOutlet var networkUnavailableView: UIView!
    @IBOutlet var mainContentView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    class func controller() -> CoinbaseEntryPointViewController {
        return vc(CoinbaseEntryPointViewController.self, from: sb("Coinbase"))
    }
}

extension CoinbaseEntryPointViewController {
    private func configureHierarchy() {
        
    }
}
