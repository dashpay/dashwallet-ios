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

// MARK: - SyncingAlertViewController

@objc(DWSyncingAlertViewController)
final class SyncingAlertViewController: BaseViewController, SyncingAlertContentViewDelegate {

    var modalTransition = DWModalPopupTransition()
    private lazy var childView: SyncingAlertContentView = {
        let childView = SyncingAlertContentView()
        childView.translatesAutoresizingMaskIntoConstraints = false
        childView.delegate = self
        childView.update(with: SyncingActivityMonitor.shared.progress)
        childView.update(with: SyncingActivityMonitor.shared.state)
        return childView
    }()

    internal lazy var model: SyncModel = SyncModelImpl()

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

        model.networkStatusDidChange = { [weak self] _ in
            // TODO: update view based on network connection instead of passing sync state
        }

        model.progressDidChange = { [weak self] progress in
            guard let self else { return }
            self.childView.update(with: progress)
            self.childView.update(with: self.model.state)
        }

        model.stateDidChage = { [weak self] state in
            self?.childView.update(with: state)
        }

        view.backgroundColor = .clear

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = UIColor.dw_background()
        contentView.layer.cornerRadius = 8.0
        contentView.layer.masksToBounds = true
        view.addSubview(contentView)

        contentView.addSubview(childView)

        NSLayoutConstraint.activate([
            contentView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            childView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32.0),
            childView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: childView.bottomAnchor, constant: 32.0),
        ])
    }

    // MARK: - DWSyncingAlertContentViewDelegate

    func syncingAlertContentView(_ view: SyncingAlertContentView, okButtonAction sender: UIButton) {
        dismiss(animated: true, completion: nil)
    }
}
