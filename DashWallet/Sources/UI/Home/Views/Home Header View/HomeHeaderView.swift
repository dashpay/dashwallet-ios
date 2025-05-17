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

private let kAvatarSize = CGSize(width: 72.0, height: 72.0)

// MARK: - HomeHeaderViewDelegate

protocol HomeHeaderViewDelegate: AnyObject {
    func homeHeaderView(_ headerView: HomeHeaderView, retrySyncButtonAction sender: UIView)
    func homeHeaderViewDidUpdateContents(_ headerView: HomeHeaderView)
}

// MARK: - HomeHeaderView

final class HomeHeaderView: UIView {

    public weak var delegate: HomeHeaderViewDelegate?

    private(set) var syncView: SyncView!
    private(set) var shortcutsView: ShortcutsView!
    private(set) var stackView: UIStackView!

    weak var shortcutsDelegate: ShortcutsActionDelegate? {
        get {
            shortcutsView.actionDelegate
        }
        set {
            shortcutsView.actionDelegate = newValue
        }
    }

    private let model: HomeHeaderModel

    init(frame: CGRect, viewModel: HomeViewModel) {
        model = HomeHeaderModel()

        super.init(frame: frame)

        syncView = SyncView.view()
        syncView.delegate = self

        shortcutsView = ShortcutsView(frame: .zero, viewModel: viewModel)
        shortcutsView.translatesAutoresizingMaskIntoConstraints = false

        let views: [UIView] = [shortcutsView, syncView]
        let stackView = UIStackView(arrangedSubviews: views)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        addSubview(stackView)
        self.stackView = stackView

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        if model.state == .syncFailed || model.state == .noConnection {
            showSyncView()
        } else {
            hideSyncView()
        }

        model.stateDidChage = { [weak self] state in
            if state == .syncFailed || state == .noConnection {
                self?.showSyncView()
            } else {
                self?.hideSyncView()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func parentScrollViewDidScroll(_ scrollView: UIScrollView) { }

    private func hideSyncView() {
        syncView.isHidden = true
        delegate?.homeHeaderViewDidUpdateContents(self)
    }

    private func showSyncView() {
        syncView.isHidden = false
        delegate?.homeHeaderViewDidUpdateContents(self)
    }
}

// MARK: ShortcutsViewDelegate

extension HomeHeaderView: ShortcutsViewDelegate {
    func shortcutsViewDidUpdateContentSize(_ view: ShortcutsView) {
        delegate?.homeHeaderViewDidUpdateContents(self)
    }
}

// MARK: SyncViewDelegate

extension HomeHeaderView: SyncViewDelegate {
    func syncViewRetryButtonAction(_ view: SyncView) {
        delegate?.homeHeaderView(self, retrySyncButtonAction: view)
    }
}
