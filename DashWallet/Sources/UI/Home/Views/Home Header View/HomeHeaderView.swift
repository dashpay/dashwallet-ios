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
    func homeHeaderView(_ headerView: HomeHeaderView, profileButtonAction sender: UIControl)
    func homeHeaderView(_ headerView: HomeHeaderView, retrySyncButtonAction sender: UIView)
    func homeHeaderViewDidUpdateContents(_ headerView: HomeHeaderView)
    func homeHeaderViewDidToggleBalanceVisibility(_ headerView: HomeHeaderView)
}

// MARK: - HomeHeaderView

@objc(DWHomeHeaderView)
final class HomeHeaderView: UIView {

    public weak var delegate: HomeHeaderViewDelegate?

    private(set) var profileView: DashPayProfileView!
    private(set) var balanceView: HomeBalanceView!
    private(set) var syncView: SyncView!
    private(set) var shortcutsView: ShortcutsView!
    private(set) var stackView: UIStackView!

    weak var balanceDataSource: HomeBalanceViewDataSource? {
        get {
            balanceView.dataSource
        }
        set {
            balanceView.dataSource = newValue
        }
    }

    weak var shortcutsDelegate: ShortcutsActionDelegate? {
        get {
            shortcutsView.actionDelegate
        }
        set {
            shortcutsView.actionDelegate = newValue
        }
    }

    private let model: HomeHeaderModel

    override init(frame: CGRect) {
        model = HomeHeaderModel()

        super.init(frame: frame)

        profileView = DashPayProfileView(frame: .zero)
        profileView.translatesAutoresizingMaskIntoConstraints = false
        profileView.addTarget(self, action: #selector(profileViewAction(_:)), for: .touchUpInside)
        profileView.isHidden = true

        balanceView = HomeBalanceView(frame: .zero)
        balanceView.delegate = self

        syncView = SyncView.view()
        syncView.delegate = self

        shortcutsView = ShortcutsView(frame: .zero)
        shortcutsView.translatesAutoresizingMaskIntoConstraints = false

        let views: [UIView] = [profileView, balanceView, shortcutsView, syncView]
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

        // TODO: Platform
//        [self mvvm_observe:DW_KEYPATH(self, model.dashPayModel.registrationStatus)
//                      with:^(typeof(self) self, id value) {
//                          [self updateProfileView];
//                      }];
//
//        [self mvvm_observe:DW_KEYPATH(self, model.dashPayModel.username)
//                      with:^(typeof(self) self, id value) {
//                          [self updateProfileView];
//                      }];
//
//        [self mvvm_observe:DW_KEYPATH(self, model.dashPayModel.unreadNotificationsCount)
//                      with:^(typeof(self) self, id value) {
//                          self.profileView.unreadCount = self.model.dashPayModel.unreadNotificationsCount;
//                      }];

        reloadBalance()
        updateProfileView()

        model.stateDidChage = { [weak self] state in
            self?.balanceView.state = state == .syncing ? .syncing : .default

            if state == .syncFailed || state == .noConnection {
                self?.showSyncView()
            } else {
                self?.hideSyncView()
            }

            self?.reloadBalance()
            self?.reloadShortcuts()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func profileViewAction(_ sender: UIControl) {
        delegate?.homeHeaderView(self, profileButtonAction: sender)
    }

    func parentScrollViewDidScroll(_ scrollView: UIScrollView) { }

    func reloadBalance() {
        let isSyncing = SyncingActivityMonitor.shared.state == .syncing

        balanceView.reloadView()
        balanceView.reloadData()
        balanceView.state = isSyncing ? .syncing : .`default`
    }

    func reloadShortcuts() {
        shortcutsView.reloadData()
    }

    private func updateProfileView() {
        profileView.isHidden = true

        // TODO: Platform
//        let status = model?.dashPayModel.registrationStatus
//        let completed = model?.dashPayModel.registrationCompleted ?? false
//        if status?.state == .done || completed {
//            profileView.username = model?.dashPay
//            profileView.isHidden = false
//        } else {
//            profileView.isHidden = true
//        }
//        delegate?.homeHeaderViewDidUpdateContents(self)
    }

    private func hideSyncView() {
        syncView.isHidden = true
        delegate?.homeHeaderViewDidUpdateContents(self)
    }

    private func showSyncView() {
        syncView.isHidden = false
        delegate?.homeHeaderViewDidUpdateContents(self)
    }
}

// MARK: HomeBalanceViewDelegate

extension HomeHeaderView: HomeBalanceViewDelegate {
    func balanceView(_ view: HomeBalanceView, balanceLongPressAction sender: UIControl) {
        let action = ShortcutAction(type: .localCurrency)
        shortcutsDelegate?.shortcutsView(view, didSelectAction: action, sender: sender)
    }

    func balanceViewDidToggleBalanceVisibility(_ view: HomeBalanceView) {
        delegate?.homeHeaderViewDidToggleBalanceVisibility(self)
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
