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
import Combine

private let kAvatarSize = CGSize(width: 72.0, height: 72.0)

// MARK: - HomeHeaderViewDelegate

protocol HomeHeaderViewDelegate: AnyObject {
    func homeHeaderView(_ headerView: HomeHeaderView, retrySyncButtonAction sender: UIView)
    func homeHeaderViewDidUpdateContents(_ headerView: HomeHeaderView)
}

// MARK: - HomeHeaderView

final class HomeHeaderView: UIView {

    /// Gap between the shortcut bar and the customize banner. Shared with
    /// `HomeViewModel.recalculateHeight()` so the fixed header height accounts for it.
    static let shortcutBarBannerSpacing: CGFloat = 20

    public weak var delegate: HomeHeaderViewDelegate?

    private(set) var syncView: SyncView!
    private(set) var stackView: UIStackView!

    /// Bridges shortcut taps/long-presses to `HomeViewController`. The SwiftUI bar adapts to it
    /// via plain closures, so the public API used by `HomeView`/`HomeViewController` is unchanged.
    weak var shortcutsDelegate: ShortcutsActionDelegate?

    private let model: HomeHeaderModel
    private var bannerHostingController: UIHostingController<AnyView>?
    private var barHostingController: UIHostingController<AnyView>?
    private var cancellableBag = Set<AnyCancellable>()

    init(frame: CGRect, viewModel: HomeViewModel) {
        model = HomeHeaderModel()

        super.init(frame: frame)

        syncView = SyncView.view()
        syncView.delegate = self

        // SwiftUI shortcut bar, hosted like the banner below. Closures adapt to the existing
        // ShortcutsActionDelegate; the hosting view is clear-backed and self-sizes so the bar's
        // own backgrounds (blue strip / grey content) show and it sits flush to the top.
        let barView = ShortcutsBarView(
            viewModel: viewModel,
            onSelect: { [weak self] action in
                self?.shortcutsDelegate?.shortcutsView(didSelectAction: action, sender: nil)
            },
            onLongPress: { [weak self] position, action in
                self?.shortcutsDelegate?.shortcutsView(didLongPressPosition: position, currentAction: action)
            }
        )
        // Paint the 13pt top-padding strip navigation-blue so it merges with the balance above
        // instead of revealing the white page background (the bar's own grey base background fills
        // the content area, so the blue only shows through this transparent padding).
        let barHosting = UIHostingController(
            rootView: AnyView(barView.padding(.top, 13).background(Color.navigationBarColor))
        )
        barHosting.view.translatesAutoresizingMaskIntoConstraints = false
        barHosting.view.backgroundColor = .clear
        self.barHostingController = barHosting

        // Check if we should show the shortcut customization banner
        viewModel.checkShortcutBanner()

        var views: [UIView] = [barHosting.view]

        if viewModel.shouldShowShortcutBanner {
            let bannerView = ShortcutCustomizeBannerView(onDismiss: { [weak self] in
                viewModel.dismissShortcutBanner()
                self?.hideBanner()
            })
            
            let hosting = UIHostingController(rootView: AnyView(bannerView.padding(.horizontal, 20)))
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            hosting.view.backgroundColor = .clear
            self.bannerHostingController = hosting
            views.append(hosting.view)
        }

        views.append(syncView)

        let stackView = UIStackView(arrangedSubviews: views)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        addSubview(stackView)
        self.stackView = stackView

        // Gap between the shortcut bar and the customize banner (only when the banner shows).
        if bannerHostingController != nil {
            stackView.setCustomSpacing(Self.shortcutBarBannerSpacing, after: barHosting.view)
        }

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

        // Auto-hide banner when user customizes shortcuts (sets shortcuts != nil)
        viewModel.$shouldShowShortcutBanner
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                if !shouldShow {
                    self?.hideBanner()
                }
            }
            .store(in: &cancellableBag)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func parentScrollViewDidScroll(_ scrollView: UIScrollView) { }

    private func hideBanner() {
        guard let hosting = bannerHostingController else { return }
        UIView.animate(withDuration: 0.3, animations: {
            hosting.view.alpha = 0
        }) { _ in
            hosting.view.isHidden = true
            hosting.view.removeFromSuperview()
            self.bannerHostingController = nil
            self.delegate?.homeHeaderViewDidUpdateContents(self)
        }
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

// MARK: SyncViewDelegate

extension HomeHeaderView: SyncViewDelegate {
    func syncViewRetryButtonAction(_ view: SyncView) {
        delegate?.homeHeaderView(self, retrySyncButtonAction: view)
    }
}
