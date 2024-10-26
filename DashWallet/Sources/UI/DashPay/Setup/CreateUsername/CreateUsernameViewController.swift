//
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

class CreateUsernameViewController: UIViewController {
    private let dashPayModel: DWDashPayProtocol
    
    @objc
    init(dashPayModel: DWDashPayProtocol, invitationURL: URL?, definedUsername: String?) {
        // TODO: invites
        self.dashPayModel = dashPayModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.dw_secondaryBackground()

        let content = CreateUsernameView(dashPayModel: dashPayModel)
        let swiftUIController = UIHostingController(rootView: content)
        swiftUIController.view.backgroundColor = UIColor.dw_secondaryBackground()
        self.dw_embedChild(swiftUIController)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.applyOpaqueAppearance(with: UIColor.dw_secondaryBackground(), shadowColor: .clear)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    

//    @objc private func registrationStatusUpdatedNotification() {
//        if MOCK_DASHPAY.boolValue {
//            setCurrentStateController()
//            return
//        }
//
//        if let lastRegistrationError = dashPayModel.lastRegistrationError {
//            dw_displayErrorModally(lastRegistrationError)
//        }
//
//        setCurrentStateController()
//    }
//
//    private func setCurrentStateController() {
//        if let definedUsername = definedUsername {
//            createUsername(definedUsername)
//            return
//        }
//
//        if dashPayModel.registrationStatus == nil || dashPayModel.registrationStatus?.failed == true {
//            showCreateUsernameController()
//            return
//        }
//
//        if dashPayModel.registrationStatus?.state != .done, let username = dashPayModel.username {
//            showPendingController(username)
//        } else {
//            showRegistrationCompletedController(dashPayModel.username)
//        }
//    }
//
//    private func createUsername(_ username: String) {
//        dashPayModel.createUsername(username, invitation: invitationURL)
//        showPendingController(username)
//    }
//
//    private func showPendingController(_ username: String) {
//        if MOCK_DASHPAY.boolValue {
//            DWGlobalOptions.sharedInstance().dashpayUsername = username
//            showRegistrationCompletedController(username)
//            return
//        }
//
//        let controller = DWUsernamePendingViewController()
//        controller.username = username
//        controller.delegate = self
//        headerView.titleBuilder = { controller.attributedTitle() }
//        containerController.transition(to: controller)
//    }
//
//    private func showRegistrationCompletedController(_ username: String?) {
//        guard let username = username else { return }
//        assert(username.count > 1, "Invalid username")
//
//        headerView.configurePlanetsView(withUsername: username)
//
//        let controller = DWRegistrationCompletedViewController()
//        controller.username = username
//        controller.delegate = self
//        headerView.titleBuilder = { NSAttributedString() }
//        containerController.transition(to: controller)
//    }
}

struct CreateUsernameView: View {
    @State var dashPayModel: DWDashPayProtocol
    @State var text: String = ""

    var body: some View {
        HStack {
            TextInput(label: "Username", text: $text)
                .padding()
        }

        // List(items) { item in
        //     MenuItem(
        //         title: item.title,
        //         subtitle: item.subtitle,
        //         details: item.details,
        //         icon: item.icon,
        //         showInfo: item.showInfo,
        //         showChevron: item.showChevron,
        //         isToggled: item.isToggled,
        //         action: {
        //             if item == items.last {
        //                 showZenLedgerSheet = true
        //             } else {
        //                 item.action?()
        //             }
        //         }
        //     )
        //     .background(Color.secondaryBackground)
        //     .cornerRadius(8)
        //     .shadow(color: .shadow, radius: 10, x: 0, y: 5)
        //     .listRowSeparator(.hidden)
        //     .listRowBackground(Color.clear)
        // }
        // .listStyle(.plain)
        // .background(Color.clear)
    }
}
