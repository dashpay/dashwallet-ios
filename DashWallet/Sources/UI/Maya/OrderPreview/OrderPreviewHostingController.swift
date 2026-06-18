//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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
import Foundation
import SwiftUI
import UIKit

final class OrderPreviewHostingController: UIViewController, NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }
    private let viewModel: OrderPreviewViewModel

    // Observes swapStatus to push the full-screen status flow once a swap is submitted.
    private var statusCancellable: AnyCancellable?
    private var didPresentStatusScreen = false

    init(viewModel: OrderPreviewViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.dw_secondaryBackground()

        let rootView = OrderPreviewView(
            viewModel: viewModel,
            onCancel: { [weak self] in
                // Pop one level back (convert screen).
                self?.navigationController?.popViewController(animated: true)
            }
        )
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        observeSwapStatus()
    }

    /// Once the swap leaves `.idle` (submission started, or it failed immediately), navigate to
    /// the dedicated full-screen status screen. Guarded so the push happens exactly once.
    private func observeSwapStatus() {
        statusCancellable = viewModel.$swapStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, !self.didPresentStatusScreen, status != .idle else { return }
                self.didPresentStatusScreen = true
                let statusVC = MayaTransactionStatusHostingController(viewModel: self.viewModel)
                self.navigationController?.pushViewController(statusVC, animated: true)
            }
    }
}
