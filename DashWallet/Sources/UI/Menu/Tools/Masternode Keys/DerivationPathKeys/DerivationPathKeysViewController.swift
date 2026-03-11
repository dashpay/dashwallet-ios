//
//  Created by PT
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

import UIKit
import SwiftUI

// MARK: - DerivationPathKeysViewController

final class DerivationPathKeysViewController: BaseViewController, NavigationStackControllable {
    private let viewModel: DerivationPathKeysViewModel

    convenience init(with key: MNKey, derivationPath: DSAuthenticationKeysDerivationPath) {
        let model = DerivationPathKeysModel(key: key, derivationPath: derivationPath)
        self.init(with: DerivationPathKeysViewModel(model: model))
    }

    init(with viewModel: DerivationPathKeysViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_secondaryBackground()

        let swiftUIView = DerivationPathKeysContentView(viewModel: viewModel) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }

        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applicationWillResignActive() {
        navigationController?.popViewController(animated: false)
    }
}

// MARK: NavigationBarStyleable

extension DerivationPathKeysViewController: NavigationBarStyleable {
    var prefersLargeTitles: Bool { false }
    var largeTitleDisplayMode: UINavigationItem.LargeTitleDisplayMode { .never }
}

// MARK: NavigationBarDisplayable

extension DerivationPathKeysViewController: NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }
}
