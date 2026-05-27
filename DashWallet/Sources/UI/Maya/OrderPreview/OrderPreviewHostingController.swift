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

import Foundation
import SwiftUI
import UIKit

final class OrderPreviewHostingController: UIViewController {
    private let viewModel: OrderPreviewViewModel

    init(viewModel: OrderPreviewViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = UIColor.dw_secondaryBackground()

        let rootView = OrderPreviewContainerView(
            viewModel: viewModel,
            onCancel: { [weak self] in
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
    }
}

private struct OrderPreviewContainerView: View {
    @ObservedObject var viewModel: OrderPreviewViewModel
    let onCancel: () -> Void

    var body: some View {
        OrderPreviewView(viewModel: viewModel, onCancel: onCancel)
            .alert(
                NSLocalizedString("Swap Failed", comment: "Maya"),
                isPresented: Binding(
                    get: { viewModel.submitErrorMessage != nil },
                    set: { visible in
                        if !visible { viewModel.submitErrorMessage = nil }
                    }
                )
            ) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(viewModel.submitErrorMessage ?? "")
            }
            .alert(
                NSLocalizedString("Swap Submitted", comment: "Maya"),
                isPresented: Binding(
                    get: { viewModel.submittedTxId != nil },
                    set: { visible in
                        if !visible { viewModel.submittedTxId = nil }
                    }
                )
            ) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(viewModel.submittedTxId ?? "")
            }
    }
}
