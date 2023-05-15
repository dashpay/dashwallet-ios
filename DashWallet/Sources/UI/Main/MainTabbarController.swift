////
////  Created by PT
////  Copyright © 2023 Dash Core Group. All rights reserved.
////
////  Licensed under the MIT License (the "License");
////  you may not use this file except in compliance with the License.
////  You may obtain a copy of the License at
////
////  https://opensource.org/licenses/MIT
////
////  Unless required by applicable law or agreed to in writing, software
////  distributed under the License is distributed on an "AS IS" BASIS,
////  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
////  See the License for the specific language governing permissions and
////  limitations under the License.
////
//
// import UIKit
//
// final class MainTabbarController: UITabBarController {
//    static let kAnimationDuration: TimeInterval = 0.35
//
//    weak var homeController: DWHomeViewController?
// }
//
// class DWMainTabbarViewController: UITabBarController, DWHomeViewControllerDelegate, UINavigationControllerDelegate, DWWipeDelegate, DWMainMenuViewControllerDelegate {
//
//    var isDemoMode: Bool = false
//
//
////    var homeNavigationController: DWNavigationController!
////    var contactsNavigationController: DWNavigationController!
////    var menuNavigationController: DWNavigationController!
////
//
//    func performScanQRCodeAction() {
//        dismiss(animated: false, completion: nil)
//
////        transitionToController(homeNavigationController, transitionType: .withoutAnimation)
////        tabBarView?.updateSelectedTabButton(.home)
////        homeController?.performScanQRCodeAction()
//    }
//
//    func performPayToURL(_ url: URL) {
//        dismiss(animated: false, completion: nil)
////        transitionToController(homeNavigationController, transitionType: .withoutAnimation)
////        tabBarView?.updateSelectedTabButton(.home)
////        homeController?.performPayToURL(url)
//    }
//
//    func handleFile(_ file: Data) {
//        dismiss(animated: false, completion: nil)
////        transitionToController(homeNavigationController, transitionType: .withoutAnimation)
////        tabBarView?.updateSelectedTabButton(.home)
////        homeController?.handleFile(file)
//    }
//
//
//
//
//    override func viewDidLoad() {
//        super.viewDidLoad()
//
//        configureHierarchy()
//    }
// }
//
// private extension DWMainTabbarViewController {
//    func configureHierarchy() {
//
//    }
// }
//
//// MARK: Demo mode
// extension DWMainTabbarViewController {
//    func openPaymentsScreen() {
//        assert(isDemoMode, "Invalid usage. Should be used in Demo mode only")
//        //showPaymentsController(withActivePage: .pay)
//    }
//
//    func closePaymentsScreen() {
//        assert(isDemoMode, "Invalid usage. Should be used in Demo mode only")
//        //tabBarViewDidClosePayments(tabBarView)
//    }
// }
//
// extension DWMainTabbarViewController: PaymentsViewControllerDelegate {
//    func paymentsViewControllerWantsToImportPrivateKey(_ controller: PaymentsViewController) {
//
//    }
//
//    func paymentsViewControllerDidCancel(_ controller: PaymentsViewController) {
//
//    }
//
//    func paymentsViewControllerDidFinishPayment(_ controller: PaymentsViewController, contact: DWDPBasicUserItem?) {
//
//    }
//
//
// }
