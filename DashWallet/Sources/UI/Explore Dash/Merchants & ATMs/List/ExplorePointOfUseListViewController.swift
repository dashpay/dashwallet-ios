//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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
import CoreLocation
import UIKit
import SwiftUI
import DashUIKit

private let kExploreWhereToSpendSectionCount = 5

private let kHandlerHeight: CGFloat = 24.0
/// Map visible above the opened sheet, below whatever bar covers the map's top.
private let kDefaultOpenedMapPosition: CGFloat = 260.0
private let kDefaultClosedMapPosition: CGFloat = -kHandlerHeight

// MARK: - ExplorePointOfUseSections

enum ExplorePointOfUseSections: Int {
    case segments = 0
    case search
    case filters
    case items
    case nextPage
}

protocol PointOfUseListFiltersViewControllerDelegate: AnyObject {
    func apply(filters: PointOfUseListFilters?)
}

public enum PointOfUseListFiltersGroup {
    case paymentType
    case sortBy
    case denominationType

    case territory
    case radius
    case locationService
}

// MARK: - ExplorePointOfUseListViewController

@objc
class ExplorePointOfUseListViewController: UIViewController, NavigationBarDisplayable {

    /// DashUIKit's `NavigationBar`, drawn over the screen in place of the
    /// system bar. Set before the view loads; `nil` keeps the system bar.
    var customNavBar: CustomNavBarConfiguration?

    struct CustomNavBarConfiguration {
        let title: String
        var leading: ExploreNavigationBarLeading = .back
        let onBack: () -> Void
        let onInfo: (() -> Void)?
    }

    private weak var customNavBarHost: UIHostingController<AnyView>?

    /// Whether this screen draws the DashUIKit bar. The navigation controller
    /// reads it before `viewDidLoad`, so a subclass that sets `customNavBar`
    /// there overrides this to answer up front.
    internal var usesCustomNavBar: Bool { customNavBar != nil }

    var isBackButtonHidden: Bool { usesCustomNavBar }
    var isNavigationBarHidden: Bool { usesCustomNavBar }

    /// The bar's info action; subclasses supply a default for a configuration
    /// without one.
    internal var customNavBarInfoAction: (() -> Void)? { customNavBar?.onInfo }

    // Change to Notification instead of chaining the property
    @objc var payWithDashHandler: (() -> Void)?
    @objc var sellDashHandler: (()->())?
    @objc var onGiftCardPurchased: ((Data)->())?

    /// Created in `viewDidLoad` from `makeConfiguration()`.
    internal var viewModel: PointOfUseListViewModel!
    private var cancellables = Set<AnyCancellable>()
    internal var segmentTitles: [String] { viewModel.segmentTitles }
    internal var currentSegment: PointOfUseListSegment { viewModel.currentSegment }
    internal var items: [ExplorePointOfUse] { viewModel.items }

    internal var mapView: ExploreMapView!
    internal var showMapButton: UIButton!
    internal var syncBannerView: ExploreSyncBannerView?
    internal var syncBannerHeightConstraint: NSLayoutConstraint?
    private var syncBannerTopConstraint: NSLayoutConstraint?

    internal var contentViewTopLayoutConstraint: NSLayoutConstraint!
    internal var contentView: UIView!

    internal var tableView: UITableView!
    internal var filterCell: PointOfUseListFiltersCell?
    internal var searchCell: PointOfUseListSearchCell?
    internal var appliedFiltersLabel: UILabel!
    /// Keeps the expanded list clear of the custom bar and the sync banner,
    /// which overlay it.
    internal var expandedTableTopInset: CGFloat {
        customNavBarHeight + (syncBannerHeightConstraint?.constant ?? 0)
    }

    private var customNavBarHeight: CGFloat {
        guard customNavBar != nil else { return 0 }

        let hostHeight = customNavBarHost?.view.bounds.height ?? 0
        if hostHeight > 0 {
            return hostHeight
        }

        let fittingHeight = customNavBarHost?.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height ?? 0
        return fittingHeight > 0 ? fittingHeight : 74
    }

    /// The opened sheet's top. The custom bar is drawn over the map, so the
    /// sheet sits that much lower to keep `kDefaultOpenedMapPosition` of map
    /// in view.
    private var openedMapPosition: CGFloat {
        kDefaultOpenedMapPosition + customNavBarHeight
    }

    internal var emptyResultsView: PointOfUseListEmptyResultsView!

    private var locationServicePopupTitle: String { viewModel.configuration.locationServicePopupTitle }
    private var locationServicePopupDetails: String { viewModel.configuration.locationServicePopupDetails }

    // MARK: Map
    internal func updateMapVisibility() {
        if !viewModel.showsMap || DWLocationManager.shared.isPermissionDenied {
            hideMapIfNeeded()
        } else {
            showMapIfNeeded()
        }
    }

    internal func showMapIfNeeded() {
        guard viewModel.showsMap else { return }

        if DWLocationManager.shared.needsAuthorization {
            PointOfUseLocationServicePopup
                .show(in: view, title: locationServicePopupTitle, details: locationServicePopupDetails) {
                    DWLocationManager.shared.requestAuthorization()
                }
        } else if DWLocationManager.shared.isAuthorized {
            showMap()
        }
    }

    internal func showMap() {
        guard contentViewTopLayoutConstraint.constant == kDefaultClosedMapPosition else { return }

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveLinear) {
            let openedPosition = self.openedMapPosition
            self.contentViewTopLayoutConstraint.constant = openedPosition
            self.mapView.contentInset = self.mapContentInsets(sheetTop: openedPosition)
            self.view.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.updateTableViewInsetsForCurrentSheetPosition()
            self?.updateShowMapButtonVisibility()
        }
    }

    internal func hideMapIfNeeded() {
        guard contentViewTopLayoutConstraint.constant != kDefaultClosedMapPosition else { return }

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveLinear) {
            self.contentViewTopLayoutConstraint.constant = kDefaultClosedMapPosition
            self.mapView.contentInset = self.mapContentInsets(sheetTop: kDefaultClosedMapPosition)
            self.view.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.updateTableViewInsetsForCurrentSheetPosition()
            self?.updateShowMapButtonVisibility()
        }
    }

    internal func updateShowMapButtonVisibility() {
        let isVisible = viewModel.showsMap && contentViewTopLayoutConstraint.constant == kDefaultClosedMapPosition && DWLocationManager
            .shared.isAuthorized

        showMapButton.isHidden = !isVisible
    }

    private func mapContentInsets(sheetTop: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(
            top: expandedTableTopInset,
            left: 0,
            bottom: max(0, mapView.bounds.height - sheetTop),
            right: 0
        )
    }

    // MARK: Subclass hooks

    /// The screen's segments, defaults and copy; every subclass provides one.
    internal func makeConfiguration() -> PointOfUseListConfiguration {
        preconditionFailure("\(type(of: self)) must override makeConfiguration()")
    }

    /// Redraws the rows after the view model changed them.
    internal func listDidUpdate(_ update: PointOfUseListViewModel.ListUpdate) {
        if update == .replaced {
            refreshFilterCell()
        }

        // The request may finish after a filter, search or location update
        // has replaced the data source. Reconcile from the current rows rather
        // than applying stale pager indexes in a batch update.
        tableView.reloadSections([ExplorePointOfUseSections.items.rawValue, ExplorePointOfUseSections.nextPage.rawValue],
                                 with: .none)

        if update == .replaced {
            updateEmptyResultsForFilters()
        }
    }

    // MARK: life cycle
    internal func show(pointOfUse: ExplorePointOfUse) {
        guard let request = viewModel.detailsRequest(for: pointOfUse) else { return }

        let vc = POIDetailsViewController(pointOfUse: request.pointOfUse,
                                          isShowAllHidden: request.isShowAllHidden,
                                          searchRadius: request.searchRadius,
                                          searchCenterCoordinate: request.searchCenterCoordinate,
                                          currentFilters: request.filters)
        vc.payWithDashHandler = payWithDashHandler
        vc.sellDashHandler = sellDashHandler
        vc.onGiftCardPurchased = onGiftCardPurchased
        navigationController?.pushViewController(vc, animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        showMapIfNeeded()
        DWLocationManager.shared.add(observer: self)

        // The database may have synced while another screen was on top.
        viewModel.refreshSyncBanner()
    }

    override func viewWillDisappear(_ animated: Bool) {
        navigationController?.setToolbarHidden(true, animated: true)

        super.viewWillDisappear(animated)

        DWLocationManager.shared.remove(observer: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel = PointOfUseListViewModel(configuration: makeConfiguration())

        configureHierarchy()
        if let config = customNavBar {
            installCustomNavBar(config: config)
        }
        updateTableViewInsetsForCurrentSheetPosition()

        bindViewModel()
        viewModel.refreshSyncBanner()
    }
}

extension ExplorePointOfUseListViewController {
    private func bindViewModel() {
        viewModel.listUpdates
            .sink { [weak self] update in self?.listDidUpdate(update) }
            .store(in: &cancellables)

        viewModel.$mapItems
            .dropFirst()
            .sink { [weak self] items in self?.mapView.show(merchants: items) }
            .store(in: &cancellables)

        viewModel.$filterTitle
            .sink { [weak self] title in self?.filterCell?.title = title }
            .store(in: &cancellables)

        viewModel.$isSyncBannerVisible
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.showSyncBanner()
                } else {
                    self?.hideSyncBanner()
                }
            }
            .store(in: &cancellables)
    }

    private func showSyncBanner() {
        guard syncBannerView?.isHidden == true else { return }
        
        syncBannerView?.isHidden = false
        syncBannerHeightConstraint?.constant = 30
        
        UIView.animate(withDuration: 0.3) {
            self.updateTableViewInsetsForCurrentSheetPosition()
            self.view.layoutIfNeeded()
        }
    }
    
    private func hideSyncBanner() {
        guard syncBannerView?.isHidden == false else { return }
        
        syncBannerHeightConstraint?.constant = 0
        
        UIView.animate(withDuration: 0.3) {
            self.updateTableViewInsetsForCurrentSheetPosition()
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.syncBannerView?.isHidden = true
        }
    }
}

// MARK: DWLocationObserver

extension ExplorePointOfUseListViewController: DWLocationObserver {
    func locationManagerDidChangeCurrentLocation(_ manager: DWLocationManager, location: CLLocation) {
        mapView.setCenter(location, animated: false)
        if viewModel.showsMap {
            mapView.searchRadius = viewModel.searchRadius
        }
        viewModel.locationDidChange(to: location, bounds: mapView.mapBounds(with: viewModel.searchRadius))
    }

    func locationManagerDidChangeServiceAvailability(_ manager: DWLocationManager) {
        if viewModel.showsMap {
            updateMapVisibility()
            mapView.showUserLocationInCenter(animated: false)
        }
        viewModel.locationAvailabilityDidChange()
    }

    func locationManagerDidChangeCurrentReversedLocation(_ manager: DWLocationManager) { }
}

extension ExplorePointOfUseListViewController {
    internal func updateEmptyResultsForFilters() {
        if viewModel.showsEmptyResults {
            if emptyResultsView != nil && tableView.tableFooterView == emptyResultsView { return }

            emptyResultsView = PointOfUseListEmptyResultsView()
            emptyResultsView.resetHandler = { [weak self] in
                self?.apply(filters: nil)
            }
            emptyResultsView.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 60)
            tableView.tableFooterView = emptyResultsView
        } else {
            tableView.tableFooterView = nil
            emptyResultsView?.removeFromSuperview()
            emptyResultsView = nil
        }
    }

    @objc
    internal func refreshFilterCell() {
        filterCell?.subtitle = viewModel.resultsSubtitle
        viewModel.refreshFilterTitle(mapCenter: mapView.centerCoordinate)
    }

    @objc
    internal func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        let appliedFiltersStackView = UIStackView()
        appliedFiltersStackView.translatesAutoresizingMaskIntoConstraints = false
        appliedFiltersStackView.alignment = .center
        appliedFiltersStackView.axis = .vertical
        appliedFiltersStackView.spacing = 2

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = NSLocalizedString("Filtered by:", comment: "Explore Dash/Merchants/Filters")
        titleLabel.font = .dw_font(forTextStyle: .footnote)
        appliedFiltersStackView.addArrangedSubview(titleLabel)

        appliedFiltersLabel = UILabel()
        appliedFiltersLabel.translatesAutoresizingMaskIntoConstraints = false
        appliedFiltersLabel.textAlignment = .center
        appliedFiltersLabel.font = .dw_font(forTextStyle: .footnote)
        appliedFiltersLabel.textColor = .dw_dashBlue()
        appliedFiltersStackView.addArrangedSubview(appliedFiltersLabel)

        let appliedFilters = UIBarButtonItem(customView: appliedFiltersStackView)
        let filter = UIBarButtonItem(image: .init(systemName: "line.3.horizontal.decrease.circle.fill"), style: .plain,
                                     target: self, action: #selector(showFiltersAction))
        filter.tintColor = .dw_dashBlue()

        // A clear copy of the filter button keeps the applied filters centred. The
        // toolbar draws a glass circle around every button, visible or not, so the
        // copy opts out of it.
        let filterBalance = UIBarButtonItem(image: .init(systemName: "line.3.horizontal.decrease.circle.fill"), style: .plain,
                                            target: nil, action: nil)
        filterBalance.tintColor = .clear
        filterBalance.isAccessibilityElement = false
        if #available(iOS 26.0, *) {
            filterBalance.hidesSharedBackground = true
        }

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        toolbarItems = [filter, spacer, appliedFilters, spacer, filterBalance]

        let standardAppearance = UIToolbarAppearance()
        standardAppearance.configureWithDefaultBackground()
        standardAppearance.backgroundColor = .dw_secondaryBackground()
        navigationController?.toolbar.standardAppearance = standardAppearance
        if #available(iOS 15.0, *) {
            navigationController?.toolbar.scrollEdgeAppearance = standardAppearance
        }
        navigationController?.setToolbarHidden(true, animated: false)

        mapView = ExploreMapView(frame: .zero)
        mapView.delegate = self
        // This screen searches around mapView.centerCoordinate, so the rendered map is
        // shifted to keep the frame center inside the strip exposed by the list sheet.
        mapView.movesMapWithContentInset = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)

        contentView = UIView()
        contentView.backgroundColor = .dw_secondaryBackground()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.clipsToBounds = false
        contentView.layer.masksToBounds = true
        contentView.layer.cornerRadius = 20
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.addSubview(contentView)
        
        // Add sync banner attached to app bar but overlaying content
        syncBannerView = ExploreSyncBannerView()
        syncBannerView?.translatesAutoresizingMaskIntoConstraints = false
        syncBannerView?.isHidden = true
        view.addSubview(syncBannerView!)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        let handlerView = ListHandlerView(frame: .zero)
        handlerView.layer.zPosition = 1
        handlerView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(handlerView)

        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(moveAction(sender:)))
        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.maximumNumberOfTouches = 1
        handlerView.addGestureRecognizer(panRecognizer)

        tableView = UITableView()
        tableView.backgroundColor = .dw_secondaryBackground()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.keyboardDismissMode = .onDrag
        tableView.showsVerticalScrollIndicator = false
        tableView.delegate = self
        tableView.layer.zPosition = -1
        tableView.dataSource = self
        tableView.clipsToBounds = false
        tableView.estimatedRowHeight = 0
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.register(PointOfUseListSegmentedCell.self,
                           forCellReuseIdentifier: PointOfUseListSegmentedCell.reuseIdentifier)
        tableView.register(PointOfUseListSearchCell.self, forCellReuseIdentifier: PointOfUseListSearchCell.reuseIdentifier)
        tableView.register(PointOfUseListFiltersCell.self, forCellReuseIdentifier: PointOfUseListFiltersCell.reuseIdentifier)
        tableView.register(MerchantListLocationOffCell.self,
                           forCellReuseIdentifier: MerchantListLocationOffCell.reuseIdentifier)
        tableView.register(FetchingNextPageCell.self, forCellReuseIdentifier: FetchingNextPageCell.reuseIdentifier)
        stackView.addArrangedSubview(tableView)

        showMapButton = UIButton(type: .custom)
        showMapButton.translatesAutoresizingMaskIntoConstraints = false
        showMapButton.isHidden = true
        showMapButton.tintColor = .white
        showMapButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
        showMapButton.addTarget(self, action: #selector(showMapAction), for: .touchUpInside)
        showMapButton.setImage(UIImage(systemName: "map.fill"), for: .normal)
        showMapButton.setTitle(NSLocalizedString("Map", comment: ""), for: .normal)
        showMapButton.layer.masksToBounds = true
        showMapButton.layer.cornerRadius = 20
        showMapButton.layer.backgroundColor = UIColor.black.cgColor
        contentView.addSubview(showMapButton)



        let showMapButtonWidth: CGFloat = 92
        let showMapButtonHeight: CGFloat = 40
        let handlerViewHeight: CGFloat = 24

        contentViewTopLayoutConstraint = contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                                                          constant: -handlerViewHeight)
        
        syncBannerHeightConstraint = syncBannerView!.heightAnchor.constraint(equalToConstant: 0)
        syncBannerTopConstraint = syncBannerView!.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        // Set high z-position to overlay content
        syncBannerView!.layer.zPosition = 100

        NSLayoutConstraint.activate([
            contentViewTopLayoutConstraint,

            contentView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Sync banner constraints - attached to app bar, overlaying content
            syncBannerTopConstraint!,
            syncBannerView!.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            syncBannerView!.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            syncBannerHeightConstraint!,

            handlerView.heightAnchor.constraint(equalToConstant: handlerViewHeight),

            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            showMapButton.widthAnchor.constraint(equalToConstant: showMapButtonWidth),
            showMapButton.heightAnchor.constraint(equalToConstant: showMapButtonHeight),
            showMapButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            showMapButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableViewInsetsForCurrentSheetPosition()

        // The inset depends on mapView.bounds.height, so recompute it whenever layout
        // changes (rotation, split view) — not only in the sheet animations.
        if mapView != nil, contentViewTopLayoutConstraint != nil {
            mapView.contentInset = mapContentInsets(sheetTop: contentViewTopLayoutConstraint.constant)
        }
    }

    internal func updateTableViewInsetsForCurrentSheetPosition() {
        guard tableView != nil else { return }

        let topInset = isSheetFullyExpanded ? expandedTableTopInset : 0
        let bottomInset = tableView.contentInset.bottom

        guard tableView.contentInset.top != topInset || tableView.verticalScrollIndicatorInsets.top != topInset else {
            if tableView.contentOffset.y < -topInset {
                tableView.contentOffset.y = -topInset
            }
            return
        }

        tableView.contentInset.top = topInset
        tableView.verticalScrollIndicatorInsets.top = topInset
        tableView.contentInset.bottom = bottomInset

        if tableView.contentOffset.y < -topInset {
            tableView.contentOffset.y = -topInset
        }
    }

    private var isSheetFullyExpanded: Bool {
        contentViewTopLayoutConstraint.constant <= kDefaultClosedMapPosition + 1
    }
}

// MARK: Actions
extension ExplorePointOfUseListViewController {
    private func showFilters() {
        let effectiveFilters = viewModel.filtersForEditing

        let filtersView = MerchantFiltersView(
            currentFilters: effectiveFilters,
            filterGroups: currentSegment.filterGroups,
            territoriesDataSource: currentSegment.territoriesDataSource,
            sortOptions: currentSegment.sortOptions,
            currentSegment: currentSegment
        ) { [weak self] filters in
            self?.apply(filters: filters)
        }
        
        let hostingController = UIHostingController(
            rootView: NavigationView { filtersView }
        )
        
        present(hostingController, animated: true)
    }

    internal func updateAppliedFiltersView() {
        appliedFiltersLabel.text = viewModel.appliedFiltersText
        // Always show the toolbar so users can access filters
        navigationController?.setToolbarHidden(false, animated: false)
    }

    @objc
    private func showMapAction() {
        showMap()
    }

    @objc
    private func showFiltersAction() {
        showFilters()
    }

    @objc
    private func moveAction(sender: UIPanGestureRecognizer) {
        let translatedPoint: CGPoint = sender.translation(in: view)

        contentViewTopLayoutConstraint.constant += translatedPoint.x
        contentViewTopLayoutConstraint.constant += translatedPoint.y

        sender.setTranslation(.zero, in: view)

        // Keep the map viewport in sync while the finger is still down; otherwise the
        // area uncovered by the sheet renders empty until the gesture ends.
        mapView.contentInset = mapContentInsets(sheetTop: contentViewTopLayoutConstraint.constant)

        if sender.state == .ended {
            let velocityInView = sender.velocity(in: view)
            let velocityY: CGFloat = 0.2*velocityInView.y
            var finalY: CGFloat = contentViewTopLayoutConstraint.constant + velocityY

            if finalY < openedMapPosition/2 {
                finalY = kDefaultClosedMapPosition
            } else if finalY > view.frame.size.height/2 {
                finalY = mapView.frame.size.height - kHandlerHeight
            } else {
                finalY = openedMapPosition
            }

            let animationDuration: CGFloat = (abs(velocityY)*0.0002)+0.2;

            UIView.animate(withDuration: animationDuration, delay: 0, options: .curveEaseOut) {
                self.mapView.contentInset = self.mapContentInsets(sheetTop: finalY)
                self.contentViewTopLayoutConstraint.constant = finalY
                self.view.layoutIfNeeded()
            } completion: { _ in
                self.updateTableViewInsetsForCurrentSheetPosition()
                self.updateShowMapButtonVisibility()
            }
        }
    }

    private func segmentedControlDidChange(index: Int) {
        let selection = viewModel.selectSegment(at: index)

        if selection.appliedDefaultFilters {
            updateAppliedFiltersView()
        } else {
            refreshView()
        }

        if selection.needsLocationPrompt {
            PointOfUseLocationServicePopup
                .show(in: view, title: locationServicePopupTitle, details: locationServicePopupDetails) {
                    DWLocationManager.shared.requestAuthorization()
                }
        }
    }
}

// MARK: ExploreMapViewDelegate

extension ExplorePointOfUseListViewController: ExploreMapViewDelegate {
    func exploreMapView(_ mapView: ExploreMapView, didChangeVisibleBounds bounds: ExploreMapBounds) {
        // Don't update bounds if AllMerchantLocationsViewController is currently active
        if let navController = navigationController,
           navController.viewControllers.last is AllMerchantLocationsViewController {
            return
        }

        refreshFilterCell()

        // Search around the map's center, not the device's location.
        mapView.searchRadius = viewModel.searchRadius
        viewModel.mapDidMove(center: mapView.centerCoordinate, bounds: mapView.mapBounds(with: viewModel.searchRadius))
    }

    func exploreMapView(_ mapView: ExploreMapView, didSelectMerchant merchant: ExplorePointOfUse) {
        show(pointOfUse: merchant)
    }
}

// MARK: PointOfUseListSearchCellDelegate

extension ExplorePointOfUseListViewController: PointOfUseListSearchCellDelegate {
    private func stopSearching() {
        viewModel.search(query: nil)
        showMapIfNeeded()
    }

    func searchCell(_ cell: PointOfUseListSearchCell, shouldStartSearchWith query: String) {
        viewModel.search(query: query)
    }

    func searchCellDidEndSearching(searchCell: PointOfUseListSearchCell) {
        stopSearching()
    }

    func searchCellDidBeginEditing() {
        hideMapIfNeeded()
    }
}

// MARK: UITableViewDelegate, UITableViewDataSource

extension ExplorePointOfUseListViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell!

        guard let section = ExplorePointOfUseSections(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .segments:
            let segmentsCell: PointOfUseListSegmentedCell = tableView
                .dequeueReusableCell(withIdentifier: PointOfUseListSegmentedCell.reuseIdentifier,
                                     for: indexPath) as! PointOfUseListSegmentedCell
            segmentsCell.separatorInset = .init(top: 0, left: 2000, bottom: 0, right: 0);
            segmentsCell.segmentDidChangeBlock = { [weak self] index in
                self?.segmentedControlDidChange(index: index)
            }
            segmentsCell.update(with: segmentTitles, selectedIndex: currentSegment.tag)
            cell = segmentsCell
        case .search:
            if let cell = searchCell {
                return cell
            }
            let searchCell: PointOfUseListSearchCell = tableView
                .dequeueReusableCell(withIdentifier: PointOfUseListSearchCell.reuseIdentifier,
                                     for: indexPath) as! PointOfUseListSearchCell
            searchCell.separatorInset = UIEdgeInsets(top: 0, left: 2000, bottom: 0, right: 0);
            searchCell.delegate = self
            self.searchCell = searchCell
            cell = searchCell
        case .filters:
            let filterCell: PointOfUseListFiltersCell = filterCell ?? tableView
                .dequeueReusableCell(withIdentifier: PointOfUseListFiltersCell.reuseIdentifier,
                                     for: indexPath) as! PointOfUseListFiltersCell
            filterCell.filterAction = { [weak self] in
                self?.showFilters()
            }
            self.filterCell = filterCell
            refreshFilterCell()
            cell = filterCell
        case .items:
            let merchant = items[indexPath.row];
            let itemCell: PointOfUseItemCell = tableView
                .dequeueReusableCell(withIdentifier: PointOfUseItemCell.reuseIdentifier,
                                     for: indexPath) as! PointOfUseItemCell
            // Pass search center coordinate to cell for accurate distance calculations
            itemCell.searchCenterCoordinate = viewModel.searchCenterCoordinate
            itemCell.update(with: merchant)
            cell = itemCell;
        case .nextPage:
            let cell = tableView.dequeueReusableCell(withIdentifier: FetchingNextPageCell.reuseIdentifier,
                                                     for: indexPath) as! FetchingNextPageCell
            cell.contentView.backgroundColor = .dw_secondaryBackground()
            return cell
        }

        cell.contentView.backgroundColor = .dw_secondaryBackground()
        cell.selectionStyle = .none
        return cell
    }

    @objc
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = ExplorePointOfUseSections(rawValue: section) else {
            return 0
        }

        switch section {
        case .filters, .search:
            return 1
        case .items:
            return items.count
        case .nextPage:
            return 0 // model.hasNextPage ? 1 : 0
        default:
            return 1
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        kExploreWhereToSpendSectionCount
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = ExplorePointOfUseSections(rawValue: indexPath.section) else {
            return 0
        }

        switch section {
        case .segments:
            return 62.0
        case .search:
            return 50.0
        case .filters:
            return 50.0
        case .items:
            return 56.0
        case .nextPage:
            return 60.0
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard let section = ExplorePointOfUseSections(rawValue: indexPath.section) else {
            return
        }

        if section == .items {
            let merchant = items[indexPath.row]
            show(pointOfUse: merchant)
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard !items.isEmpty else { return }

        let lastSectionIndex = ExplorePointOfUseSections.items.rawValue
        let lastRowIndex = tableView.numberOfRows(inSection: lastSectionIndex) - 1
        if viewModel.hasNextPage && indexPath.section == lastSectionIndex && indexPath.row == lastRowIndex {
            let activity = UIActivityIndicatorView()
            activity.translatesAutoresizingMaskIntoConstraints = false
            activity.tintColor = .dw_secondaryText()
            activity.color = .dw_secondaryText()
            activity.startAnimating()
            activity.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44.0)
            contentView.addSubview(activity)

            tableView.tableFooterView = activity
            tableView.tableFooterView?.isHidden = false

            viewModel.fetchNextPage()
        } else {
            tableView.tableFooterView?.isHidden = true
            tableView.tableFooterView = nil
        }
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let cell = cell as? FetchingNextPageCell {
            cell.stop()
        }
    }
}

// MARK: PointOfUseListFiltersViewControllerDelegate

extension ExplorePointOfUseListViewController: PointOfUseListFiltersViewControllerDelegate {
    func apply(filters: PointOfUseListFilters?) {
        let radiusToUse = filters?.currentRadius ?? kDefaultRadius

        // Update the map view's search radius
        mapView.searchRadius = radiusToUse

        viewModel.apply(filters: filters, searchBounds: mapView.mapBounds(with: radiusToUse))

        updateAppliedFiltersView()
        refreshView()
    }

    func refreshView() {
        refreshFilterCell()
        updateMapVisibility()
        updateShowMapButtonVisibility()
    }
}

// MARK: - Custom navigation bar

extension ExplorePointOfUseListViewController {
    /// Back for a pushed screen, close for one presented as the root of its
    /// own navigation controller.
    internal var defaultCustomNavBarLeading: ExploreNavigationBarLeading {
        let isModalRoot = navigationController?.viewControllers.first === self
            && navigationController?.presentingViewController != nil
        return isModalRoot ? .close : .back
    }

    /// Pops a pushed screen, dismisses a modal root.
    internal func closeOrPop() {
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func installCustomNavBar(config: CustomNavBarConfiguration) {
        customNavBarHost = installExploreNavigationBar(
            title: config.title,
            leading: config.leading,
            onBack: config.onBack,
            onInfo: customNavBarInfoAction)

        // The custom bar takes the top of the safe area, where the sync banner
        // sits under the system bar; move the banner below it.
        if let syncBannerView, let host = customNavBarHost {
            syncBannerTopConstraint?.isActive = false
            syncBannerTopConstraint = syncBannerView.topAnchor.constraint(equalTo: host.view.bottomAnchor)
            syncBannerTopConstraint?.isActive = true
        }
        view.layoutIfNeeded()
    }
}
