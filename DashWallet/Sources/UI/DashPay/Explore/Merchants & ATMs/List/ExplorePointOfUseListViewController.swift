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

import UIKit
import CoreLocation

private let kExploreWhereToSpendSectionCount = 5

private let kHandlerHeight: CGFloat = 24.0
private let kDefaultOpenedMapPosition: CGFloat = 260.0
private let kDefaultClosedMapPosition: CGFloat = -kHandlerHeight

enum ExplorePointOfUseSections: Int {
    case segments = 0
    case search
    case filters
    case items
    case nextPage
}

@objc class ExplorePointOfUseListViewController: UIViewController {
    internal var model: ExplorePointOfUseListModel!
    internal var segmentTitles: [String] { return model.segmentTitles }
    internal var currentSegment: ExplorePointOfUseListSegment { return model.currentSegment }
    internal var items: [ExplorePointOfUse] { return model.items }
    
    internal var radius: Int = 20 //In miles //Move to model
    internal var mapView: ExploreMapView!
    internal var showMapButton: UIButton!
    
    internal var contentViewTopLayoutConstraint: NSLayoutConstraint!
    internal var contentView: UIView!
    
    internal var tableView: UITableView!
    internal var filterCell: DWExploreWhereToSpendFiltersCell?
    internal var searchCell: DWExploreWhereToSpendSearchCell?
    internal var locationOffCell: MerchantListLocationOffCell?
    
    //MARK: Map
    internal func updateMapVisibility() {
        if !currentSegment.showMap || DWLocationManager.shared.isPermissionDenied {
            hideMapIfNeeded()
        }else{
            showMapIfNeeded()
        }
    }
    
    internal func showMapIfNeeded() {
        guard currentSegment.showMap else { return }
        
        if DWLocationManager.shared.needsAuthorization {
            DWExploreWhereToSpendLocationServicePopup.show(in: self.view) {
                DWLocationManager.shared.requestAuthorization()
            }
            
        }else if DWLocationManager.shared.isAuthorized && self.contentViewTopLayoutConstraint.constant != kDefaultOpenedMapPosition {
            showMap()
        }
    }
    
    internal func showMap() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveLinear) {
            self.contentViewTopLayoutConstraint.constant = kDefaultOpenedMapPosition
            self.mapView.contentInset = .init(top: 0, left: 0, bottom: self.mapView.frame.height - kDefaultOpenedMapPosition, right: 0)
            self.view.layoutIfNeeded()
        } completion: { [weak self] completed in
            self?.updateShowMapButtonVisibility()
        }
    }
    
    internal func hideMapIfNeeded() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveLinear) {
            self.contentViewTopLayoutConstraint.constant = kDefaultClosedMapPosition
            self.mapView.contentInset = .init(top: 0, left: 0, bottom: self.mapView.frame.height - kDefaultClosedMapPosition, right: 0)
            self.view.layoutIfNeeded()
        } completion: { [weak self] completed in
            self?.updateShowMapButtonVisibility()
        }
    }
    
    internal func updateShowMapButtonVisibility() {
        let isVisible = currentSegment.showMap && contentViewTopLayoutConstraint.constant == kDefaultClosedMapPosition && DWLocationManager.shared.isAuthorized
        
        showMapButton.isHidden = !isVisible
    }
    
    //MARK: life cycle
    internal func show(pointOfUse: ExplorePointOfUse) {
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        DWLocationManager.shared.add(observer: self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        showMapIfNeeded()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        DWLocationManager.shared.remove(observer: self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureModel()
        model.itemsDidChange = { [weak self] in
            guard let wSelf = self else { return }
            wSelf.refreshFilterCell()
            
            if wSelf.currentSegment.showLocationServiceSettings && DWLocationManager.shared.isPermissionDenied {
                wSelf.tableView.reloadData()
            }else if wSelf.locationOffCell != nil {
                wSelf.locationOffCell = nil
                wSelf.tableView.reloadData()
            }else{
                wSelf.tableView.reloadSections([ExplorePointOfUseSections.items.rawValue, ExplorePointOfUseSections.nextPage.rawValue], with: .none)
            }
            
            if wSelf.model.currentSegment.showMap
            {
                wSelf.mapView.show(merchants: wSelf.model.items)
            }
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
    @objc internal func configureModel() {
        
    }
}

//MARK: DWLocationObserver
extension ExplorePointOfUseListViewController: DWLocationObserver {
    func locationManagerDidChangeCurrentLocation(_ manager: DWLocationManager, location: CLLocation) {
        mapView.setCenter(location, animated: false)
    }
    
    func locationManagerDidChangeServiceAvailability(_ manager: DWLocationManager) {
        if currentSegment.showMap  {
            updateMapVisibility()
            mapView.showUserLocationInCenter(animated: false)
            model.fetch(query: nil)
        }
    }
    
    func locationManagerDidChangeCurrentReversedLocation(_ manager: DWLocationManager) {
    }
}

extension ExplorePointOfUseListViewController {
    @objc internal func subtitleForFilterCell() -> String? {
        return nil
    }
    
    @objc internal func refreshFilterCell() {
        filterCell?.title = currentSegment.title
        filterCell?.subtitle = subtitleForFilterCell()
        
        if currentSegment.showReversedLocation {
            DWLocationManager.shared.reverseGeocodeLocation(CLLocation(latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude)) { [weak self] location in
                if self?.currentSegment.showMap ?? false {
                    self?.filterCell?.title = location
                }
            }
        }
    }
    
    @objc internal func configureHierarchy() {
        mapView = ExploreMapView(frame: .zero)
        mapView.delegate = self
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)
        
        contentView = UIView()
        contentView.backgroundColor = .dw_background()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.clipsToBounds = false
        contentView.layer.masksToBounds = true
        contentView.layer.cornerRadius = 20
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.addSubview(contentView)
        
        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.showsVerticalScrollIndicator = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.clipsToBounds = false
        tableView.register(DWExploreWhereToSpendSegmentedCell.self, forCellReuseIdentifier: DWExploreWhereToSpendSegmentedCell.dw_reuseIdentifier)
        tableView.register(DWExploreWhereToSpendSearchCell.self, forCellReuseIdentifier: DWExploreWhereToSpendSearchCell.dw_reuseIdentifier)
        tableView.register(DWExploreWhereToSpendFiltersCell.self, forCellReuseIdentifier: DWExploreWhereToSpendFiltersCell.dw_reuseIdentifier)
        tableView.register(MerchantListLocationOffCell.self, forCellReuseIdentifier: MerchantListLocationOffCell.dw_reuseIdentifier)
        tableView.register(FetchingNextPageCell.self, forCellReuseIdentifier: FetchingNextPageCell.dw_reuseIdentifier)
        
        contentView.addSubview(tableView)
        
        let handlerView = ListHandlerView(frame: .zero)
        handlerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(handlerView)
        
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(moveAction(sender:)))
        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.maximumNumberOfTouches = 1
        handlerView.addGestureRecognizer(panRecognizer)
        
        self.showMapButton = UIButton(type: .custom)
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
        
        contentViewTopLayoutConstraint = contentView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: -handlerViewHeight)
        
        NSLayoutConstraint.activate([
            contentViewTopLayoutConstraint,
            
            contentView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            handlerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            handlerView.heightAnchor.constraint(equalToConstant: handlerViewHeight),
            handlerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            handlerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            tableView.topAnchor.constraint(equalTo: handlerView.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            mapView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            showMapButton.widthAnchor.constraint(equalToConstant: showMapButtonWidth),
            showMapButton.heightAnchor.constraint(equalToConstant: showMapButtonHeight),
            showMapButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            showMapButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
        ])
    }
}


//MARK: Actions
extension ExplorePointOfUseListViewController {
    @objc private func showMapAction() {
        showMap()
    }
    
    @objc private func moveAction(sender: UIPanGestureRecognizer) {
        let translatedPoint: CGPoint = sender.translation(in: self.view)
        
        contentViewTopLayoutConstraint.constant += translatedPoint.x
        contentViewTopLayoutConstraint.constant += translatedPoint.y
        
        sender.setTranslation(.zero, in: self.view)
        
        if sender.state == .ended {
            let velocityInView = sender.velocity(in: self.view)
            let velocityY: CGFloat = 0.2*velocityInView.y
            var finalY: CGFloat = contentViewTopLayoutConstraint.constant + velocityY
            
            if finalY < kDefaultOpenedMapPosition/2 {
                finalY = kDefaultClosedMapPosition
            }else if finalY > self.view.frame.size.height/2 {
                finalY = self.mapView.frame.size.height - kHandlerHeight
            }else{
                finalY = kDefaultOpenedMapPosition
            }
            
            let animationDuration: CGFloat = (abs(velocityY)*0.0002)+0.2;
            
            UIView.animate(withDuration: animationDuration, delay: 0, options: .curveEaseOut) {
                self.mapView.contentInset = .init(top: 0, left: 0, bottom: self.mapView.frame.height - finalY, right: 0)
                self.contentViewTopLayoutConstraint.constant = finalY
                self.view.layoutIfNeeded()
            } completion: { completed in
                self.updateShowMapButtonVisibility()
            }
        }
    }
    
    private func segmentedControlDidChange(index: Int) {

        let segment = model.segments[index]
        model.currentSegment = segment
        refreshFilterCell()
        
        if segment.showMap {
            self.showMapIfNeeded()
        }else{
            self.hideMapIfNeeded()
        }
    }
}

//MARK: ExploreMapViewDelegate

extension ExplorePointOfUseListViewController: ExploreMapViewDelegate {
    func exploreMapView(_ mapView: ExploreMapView, didChangeVisibleBounds bounds: ExploreMapBounds) {
        refreshFilterCell()
        model.currentMapBounds = bounds
    }
    
    func exploreMapView(_ mapView: ExploreMapView, didSelectMerchant merchant: ExplorePointOfUse) {
        show(pointOfUse: merchant)
    }
}

//MARK: DWExploreWhereToSpendSearchCellDelegate

extension ExplorePointOfUseListViewController: DWExploreWhereToSpendSearchCellDelegate {
    private func stopSearching() {
        model.fetch(query: nil)
    }
    
    func searchCell(_ searchCell: DWExploreWhereToSpendSearchCell, shouldStartSearchWithQuery query: String) {
        model.fetch(query: query)
    }
    
    func searchCellDidEndSearching(_ searchCell: DWExploreWhereToSpendSearchCell) {
        stopSearching()
    }
}

//MARK: UITableViewDelegate, UITableViewDataSource

extension ExplorePointOfUseListViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        var cell: UITableViewCell!
        
        guard let section = ExplorePointOfUseSections(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .segments:
            let segmentsCell: DWExploreWhereToSpendSegmentedCell = tableView.dequeueReusableCell(withIdentifier: DWExploreWhereToSpendSegmentedCell.dw_reuseIdentifier, for: indexPath) as! DWExploreWhereToSpendSegmentedCell
            segmentsCell.separatorInset = .init(top: 0, left: 2000, bottom: 0, right: 0);
            segmentsCell.segmentDidChangeBlock = { [weak self] index in
                self?.segmentedControlDidChange(index: index)
            }
            segmentsCell.update(withItems: segmentTitles, andSelectedIndex: currentSegment.tag)
            cell = segmentsCell
        case .search:
            if let cell = searchCell {
                return cell
            }
            let searchCell: DWExploreWhereToSpendSearchCell = tableView.dequeueReusableCell(withIdentifier: DWExploreWhereToSpendSearchCell.dw_reuseIdentifier, for: indexPath) as! DWExploreWhereToSpendSearchCell
            searchCell.separatorInset = UIEdgeInsets(top: 0, left: 2000, bottom: 0, right: 0);
            searchCell.delegate = self
            self.searchCell = searchCell
            cell = searchCell
        case .filters:
            let filterCell: DWExploreWhereToSpendFiltersCell = self.filterCell ?? tableView.dequeueReusableCell(withIdentifier: DWExploreWhereToSpendFiltersCell.dw_reuseIdentifier, for: indexPath) as! DWExploreWhereToSpendFiltersCell
            self.filterCell = filterCell
            refreshFilterCell()
            cell = filterCell
        case .items:
            if currentSegment == .nearby && DWLocationManager.shared.isPermissionDenied {
                let itemCell: MerchantListLocationOffCell = tableView.dequeueReusableCell(withIdentifier: MerchantListLocationOffCell.dw_reuseIdentifier, for: indexPath) as! MerchantListLocationOffCell
                cell = itemCell
                cell.separatorInset = UIEdgeInsets(top: 0, left: 2000, bottom: 0, right: 0)
                locationOffCell = itemCell
            }else{
                let merchant = self.items[indexPath.row];
                let itemCell: ExplorePointOfUseItemCell = tableView.dequeueReusableCell(withIdentifier: ExplorePointOfUseItemCell.dw_reuseIdentifier, for: indexPath) as! ExplorePointOfUseItemCell
                itemCell.update(with: merchant)
                cell = itemCell;
            }
        case .nextPage:
            let cell = tableView.dequeueReusableCell(withIdentifier: FetchingNextPageCell.dw_reuseIdentifier, for: indexPath) as! FetchingNextPageCell
            
            return cell
        }
        cell.selectionStyle = .none
        return cell;
        
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = ExplorePointOfUseSections(rawValue: section) else {
            return 0
        }
        
        switch section
        {
        case .filters, .search:
            return currentSegment == .nearby ? (DWLocationManager.shared.isPermissionDenied ? 0 : 1) : 1
        case .items:
            
            if currentSegment == .nearby {
                if(DWLocationManager.shared.isAuthorized){
                    return items.count;
                }else if(DWLocationManager.shared.needsAuthorization) {
                    return 0;
                }else if(DWLocationManager.shared.isPermissionDenied) {
                    return 1;
                }
            }else{
                return items.count
            }
        case .nextPage:
            return model.hasNextPage ? 1 : 0
        default:
            return 1
        }
        
        return 1
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return kExploreWhereToSpendSectionCount
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
            return 60
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
        if let cell = cell as? FetchingNextPageCell {
            cell.start()
            model.fetchNextPage()
        }
    }
    
    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let cell = cell as? FetchingNextPageCell {
            cell.stop()
        }
    }
}

//MARK: Extra UI
class ListHandlerView: UIView {
    private var handler: UIView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configureHierarchy() {
        layer.backgroundColor = UIColor.dw_background().cgColor
        layer.masksToBounds = true
        layer.cornerRadius = 20
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        
        handler = UIView(frame: .init(x: 0, y: 0, width: 40, height: 4))
        handler.layer.backgroundColor = UIColor.dw_separatorLine().cgColor
        handler.layer.cornerRadius = 2
        addSubview(handler)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        handler.center = center
    }
}
