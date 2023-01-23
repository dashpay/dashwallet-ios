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

import CoreLocation
import UIKit

private let kExploreWhereToSpendSectionCount = 5

private let kHandlerHeight: CGFloat = 24.0
internal let kDefaultOpenedMapPosition: CGFloat = 260.0
private let kDefaultClosedMapPosition: CGFloat = -kHandlerHeight

// MARK: - ExplorePointOfUseSections

enum ExplorePointOfUseSections: Int {
    case segments = 0
    case search
    case filters
    case items
    case nextPage
}

// MARK: - ExplorePointOfUseListViewController

@objc
class ExplorePointOfUseListViewController: UIViewController {

    // Change to Notification instead of chaining the property
    @objc var payWithDashHandler: (() -> Void)?
    @objc var sellDashHandler: (()->())?

    internal var model: PointOfUseListModel!
    internal var segmentTitles: [String] { model.segmentTitles }
    internal var currentSegment: PointOfUseListSegment { model.currentSegment }
    internal var items: [ExplorePointOfUse] { model.items }

    internal var radius = 20 // In miles //Move to model
    internal var mapView: ExploreMapView!
    internal var showMapButton: UIButton!

    internal var contentViewTopLayoutConstraint: NSLayoutConstraint!
    internal var contentView: UIView!

    internal var tableView: UITableView!
    internal var filterCell: PointOfUseListFiltersCell?
    internal var searchCell: PointOfUseListSearchCell?
    internal var appliedFiltersLabel: UILabel!

    internal var isFiltered: Bool { model.hasFilters }
    internal var emptyResultsView: PointOfUseListEmptyResultsView!

    internal var locationServicePopupTitle: String { "" }
    internal var locationServicePopupDetails: String { "" }

    // MARK: Map
    internal func updateMapVisibility() {
        if !model.showMap || DWLocationManager.shared.isPermissionDenied {
            hideMapIfNeeded()
        } else {
            showMapIfNeeded()
        }
    }

    internal func showMapIfNeeded() {
        guard model.showMap else { return }

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
            self.contentViewTopLayoutConstraint.constant = kDefaultOpenedMapPosition
            self.mapView.contentInset = .init(top: 0, left: 0, bottom: self.mapView.frame.height - kDefaultOpenedMapPosition,
                                              right: 0)
            self.view.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.updateShowMapButtonVisibility()
        }
    }

    internal func hideMapIfNeeded() {
        guard contentViewTopLayoutConstraint.constant != kDefaultClosedMapPosition else { return }

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveLinear) {
            self.contentViewTopLayoutConstraint.constant = kDefaultClosedMapPosition
            self.mapView.contentInset = .init(top: 0, left: 0, bottom: self.mapView.frame.height - kDefaultClosedMapPosition,
                                              right: 0)
            self.view.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.updateShowMapButtonVisibility()
        }
    }

    internal func updateShowMapButtonVisibility() {
        let isVisible = model.showMap && contentViewTopLayoutConstraint.constant == kDefaultClosedMapPosition && DWLocationManager
            .shared.isAuthorized

        showMapButton.isHidden = !isVisible
    }

    // MARK: life cycle
    internal func show(pointOfUse: ExplorePointOfUse) {
        let vc = PointOfUseDetailsViewController(pointOfUse: pointOfUse)
        vc.payWithDashHandler = payWithDashHandler
        vc.sellDashHandler = sellDashHandler
        navigationController?.pushViewController(vc, animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        showMapIfNeeded()
        DWLocationManager.shared.add(observer: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        navigationController?.setToolbarHidden(true, animated: true)

        super.viewWillDisappear(animated)

        DWLocationManager.shared.remove(observer: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureModel()

        model.itemsDidChange = { [weak self] in
            guard let wSelf = self else { return }
            wSelf.refreshFilterCell()
            wSelf.tableView
                .reloadSections([ExplorePointOfUseSections.items.rawValue, ExplorePointOfUseSections.nextPage.rawValue],
                                with: .none)

            if wSelf.model.showMap {
                wSelf.mapView.show(merchants: wSelf.model.items)
            }

            wSelf.updateEmptyResultsForFilters()
        }

        model.nextPageDidLoaded = { [weak self] offset, count in
            guard let wSelf = self else { return }

            var indexPathes: [IndexPath] = Array()
            indexPathes.reserveCapacity(count)

            let start = offset
            let total = (offset+count)
            for i in start..<total {
                indexPathes.append(.init(row: i, section: ExplorePointOfUseSections.items.rawValue))
            }

            wSelf.tableView.beginUpdates()
            wSelf.tableView.insertRows(at: indexPathes, with: .top)
            wSelf.tableView.reloadSections([ExplorePointOfUseSections.nextPage.rawValue], with: .none)
            wSelf.tableView.endUpdates()
        }

        configureHierarchy()
    }
}

extension ExplorePointOfUseListViewController {
    @objc
    internal func configureModel() { }
}

// MARK: DWLocationObserver

extension ExplorePointOfUseListViewController: DWLocationObserver {
    func locationManagerDidChangeCurrentLocation(_ manager: DWLocationManager, location: CLLocation) {
        mapView.setCenter(location, animated: false)
    }

    func locationManagerDidChangeServiceAvailability(_ manager: DWLocationManager) {
        if model.showMap {
            updateMapVisibility()
            mapView.showUserLocationInCenter(animated: false)
            model.fetch(query: nil)
        }
    }

    func locationManagerDidChangeCurrentReversedLocation(_ manager: DWLocationManager) { }
}

extension ExplorePointOfUseListViewController {
    internal func updateEmptyResultsForFilters() {
        if model.showEmptyResults {
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
    internal func subtitleForFilterCell() -> String? {
        nil
    }

    @objc
    internal func refreshFilterCell() {
        filterCell?.title = currentSegment.title
        filterCell?.subtitle = subtitleForFilterCell()

        if DWLocationManager.shared.isAuthorized && currentSegment.showReversedLocation {
            DWLocationManager.shared
                .reverseGeocodeLocation(CLLocation(latitude: mapView.centerCoordinate.latitude,
                                                   longitude: mapView.centerCoordinate.longitude)) { [weak self] location in
                    if self?.model.showMap ?? false {
                        self?.filterCell?.title = location
                    }
                }
        }
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
        let empty = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: self, action: nil)
        let filter = UIBarButtonItem(image: .init(systemName: "line.3.horizontal.decrease.circle.fill"), style: .plain,
                                     target: self, action: nil)
        filter.tintColor = .dw_dashBlue()

        let fakeFilter = UIBarButtonItem(image: .init(systemName: "line.3.horizontal.decrease.circle.fill"), style: .plain,
                                         target: self, action: nil)
        fakeFilter.tintColor = .clear

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        toolbarItems = [filter, spacer, appliedFilters, spacer, fakeFilter]

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
                           forCellReuseIdentifier: PointOfUseListSegmentedCell.dw_reuseIdentifier)
        tableView.register(PointOfUseListSearchCell.self, forCellReuseIdentifier: PointOfUseListSearchCell.dw_reuseIdentifier)
        tableView.register(PointOfUseListFiltersCell.self, forCellReuseIdentifier: PointOfUseListFiltersCell.dw_reuseIdentifier)
        tableView.register(MerchantListLocationOffCell.self,
                           forCellReuseIdentifier: MerchantListLocationOffCell.dw_reuseIdentifier)
        tableView.register(FetchingNextPageCell.self, forCellReuseIdentifier: FetchingNextPageCell.dw_reuseIdentifier)
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

        NSLayoutConstraint.activate([
            contentViewTopLayoutConstraint,

            contentView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

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
}

// MARK: Actions
extension ExplorePointOfUseListViewController {
    private func showFilters() {
        let vc = PointOfUseListFiltersViewController.controller()
        vc.filtersToUse = currentSegment.filterGroups
        vc.territoriesDataSource = currentSegment.territoriesDataSource
        vc.delegate = self
        vc.defaultFilters = model.initialFilters
        vc.filters = model.filters ?? model.initialFilters
        let nvc = UINavigationController(rootViewController: vc)
        present(nvc, animated: true)
    }

    private func updateAppliedFiltersView() {
        let str = model.appliedFiltersLocalizedString
        appliedFiltersLabel.text = str
        let isHidden = str == nil
        navigationController?.setToolbarHidden(isHidden, animated: false)
    }

    @objc
    private func showMapAction() {
        showMap()
    }

    @objc
    private func moveAction(sender: UIPanGestureRecognizer) {
        let translatedPoint: CGPoint = sender.translation(in: view)

        contentViewTopLayoutConstraint.constant += translatedPoint.x
        contentViewTopLayoutConstraint.constant += translatedPoint.y

        sender.setTranslation(.zero, in: view)

        if sender.state == .ended {
            let velocityInView = sender.velocity(in: view)
            let velocityY: CGFloat = 0.2*velocityInView.y
            var finalY: CGFloat = contentViewTopLayoutConstraint.constant + velocityY

            if finalY < kDefaultOpenedMapPosition/2 {
                finalY = kDefaultClosedMapPosition
            } else if finalY > view.frame.size.height/2 {
                finalY = mapView.frame.size.height - kHandlerHeight
            } else {
                finalY = kDefaultOpenedMapPosition
            }

            let animationDuration: CGFloat = (abs(velocityY)*0.0002)+0.2;

            UIView.animate(withDuration: animationDuration, delay: 0, options: .curveEaseOut) {
                self.mapView.contentInset = .init(top: 0, left: 0, bottom: self.mapView.frame.height - finalY, right: 0)
                self.contentViewTopLayoutConstraint.constant = finalY
                self.view.layoutIfNeeded()
            } completion: { _ in
                self.updateShowMapButtonVisibility()
            }
        }
    }

    private func segmentedControlDidChange(index: Int) {
        let segment = model.segments[index]
        model.currentSegment = segment

        searchCell?.stopSearching()
        refreshView()
    }
}

// MARK: ExploreMapViewDelegate

extension ExplorePointOfUseListViewController: ExploreMapViewDelegate {
    func exploreMapView(_ mapView: ExploreMapView, didChangeVisibleBounds bounds: ExploreMapBounds) {
        refreshFilterCell()
        model.currentMapBounds = mapView.mapBounds(with: model.currentRadius)
        model.refreshItems()
    }

    func exploreMapView(_ mapView: ExploreMapView, didSelectMerchant merchant: ExplorePointOfUse) {
        show(pointOfUse: merchant)
    }
}

// MARK: PointOfUseListSearchCellDelegate

extension ExplorePointOfUseListViewController: PointOfUseListSearchCellDelegate {
    private func stopSearching() {
        model.fetch(query: nil)
        showMapIfNeeded()
    }

    func searchCell(_ cell: PointOfUseListSearchCell, shouldStartSearchWith query: String) {
        model.fetch(query: query)
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
                .dequeueReusableCell(withIdentifier: PointOfUseListSegmentedCell.dw_reuseIdentifier,
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
                .dequeueReusableCell(withIdentifier: PointOfUseListSearchCell.dw_reuseIdentifier,
                                     for: indexPath) as! PointOfUseListSearchCell
            searchCell.separatorInset = UIEdgeInsets(top: 0, left: 2000, bottom: 0, right: 0);
            searchCell.delegate = self
            self.searchCell = searchCell
            cell = searchCell
        case .filters:
            let filterCell: PointOfUseListFiltersCell = filterCell ?? tableView
                .dequeueReusableCell(withIdentifier: PointOfUseListFiltersCell.dw_reuseIdentifier,
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
                .dequeueReusableCell(withIdentifier: PointOfUseItemCell.dw_reuseIdentifier,
                                     for: indexPath) as! PointOfUseItemCell
            itemCell.update(with: merchant)
            cell = itemCell;
        case .nextPage:
            let cell = tableView.dequeueReusableCell(withIdentifier: FetchingNextPageCell.dw_reuseIdentifier,
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
        if model.hasNextPage && indexPath.section == lastSectionIndex && indexPath.row == lastRowIndex {
            let activity = UIActivityIndicatorView()
            activity.translatesAutoresizingMaskIntoConstraints = false
            activity.tintColor = .dw_secondaryText()
            activity.color = .dw_secondaryText()
            activity.startAnimating()
            activity.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44.0)
            contentView.addSubview(activity)

            tableView.tableFooterView = activity
            tableView.tableFooterView?.isHidden = false

            model.fetchNextPage()
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
        model.currentMapBounds = mapView.mapBounds(with: filters?.currentRadius ?? kDefaultRadius)
        model.apply(filters: filters)
        updateAppliedFiltersView()
        refreshView()
    }

    func refreshView() {
        refreshFilterCell()
        updateMapVisibility()
    }
}
