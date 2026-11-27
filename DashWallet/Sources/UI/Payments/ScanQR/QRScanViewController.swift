//
//  Created by Dash Core Group
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

/// Presents `QRScanScreen` from UIKit and Objective-C callers.
///
/// A plain `UIViewController` holding the hosting controller as a child,
/// rather than a `UIHostingController` subclass: a class with a generic
/// superclass can't be seen from Objective-C, and `DWBasePayViewController`
/// presents this. Callers set `model.delegate` to hear the result, as they
/// did with the Objective-C scanner it replaces.
@objc(DWQRScanViewController)
final class QRScanViewController: UIViewController {
    @objc let model = DWQRScanModel()

    private lazy var viewModel = QRScanViewModel(model: model)

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        let hosting = UIHostingController(rootView: QRScanScreen(viewModel: viewModel))
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)

        viewModel.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.stop()
    }
}
