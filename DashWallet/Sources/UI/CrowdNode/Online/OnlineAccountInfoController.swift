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

final class OnlineAccountInfoController: UIViewController {
    @objc
    static func controller() -> OnlineAccountInfoController {
        vc(OnlineAccountInfoController.self, from: sb("CrowdNode"))
    }

    @IBAction
    func continueAction() {
        navigationController?.replaceLast(1, with: OnlineAccountEmailController.controller())
    }
}
