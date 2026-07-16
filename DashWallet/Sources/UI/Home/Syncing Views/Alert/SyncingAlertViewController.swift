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

import SwiftUI
import UIKit

// MARK: - SyncingAlertViewController

/// Thin modal-popup shell around the SwiftUI `SyncingAlertView`, which
/// renders the overall percentage plus one progress row per SPV sync
/// phase (headers / filter headers / filters / masternode list).
final class SyncingAlertViewController: BaseViewController {

    var modalTransition = DWModalPopupTransition()

    private let viewModel = SyncingAlertViewModel()

    init() {
        super.init(nibName: nil, bundle: nil)
        transitioningDelegate = modalTransition
        modalPresentationStyle = .custom
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = UIColor.dw_background()
        contentView.layer.cornerRadius = 8.0
        contentView.layer.masksToBounds = true
        view.addSubview(contentView)

        let hosting = UIHostingController(rootView: SyncingAlertView(viewModel: viewModel) { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        })
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)
        contentView.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        NSLayoutConstraint.activate([
            contentView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32.0),
            hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: hosting.view.bottomAnchor, constant: 32.0),
        ])
    }
}
