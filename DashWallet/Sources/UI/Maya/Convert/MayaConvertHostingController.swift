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

import SwiftUI
import UIKit

class MayaConvertHostingController: UIViewController {

    private let coin: MayaCryptoCurrency
    private let address: String
    private lazy var viewModel = MayaConvertViewModel(coin: coin, address: address)

    init(coin: MayaCryptoCurrency, address: String) {
        self.coin = coin
        self.address = address
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Convert", comment: "Maya")
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = UIColor.dw_secondaryBackground()

        let swiftUIView = MayaConvertView(
            viewModel: viewModel,
            onContinue: { [weak self] in
                self?.showOrderPreview()
            }
        )

        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func showOrderPreview() {
        guard let previewViewModel = viewModel.makeOrderPreviewViewModel() else {
            return
        }
        let previewController = OrderPreviewHostingController(viewModel: previewViewModel)
        navigationController?.pushViewController(previewController, animated: true)
    }
}
