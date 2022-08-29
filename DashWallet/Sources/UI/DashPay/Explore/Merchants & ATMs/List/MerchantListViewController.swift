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
import MapKit

private let kExploreWhereToSpendSectionCount = 5

private let kHandlerHeight: CGFloat = 24.0
private let kDefaultOpenedMapPosition: CGFloat = 260.0
private let kDefaultClosedMapPosition: CGFloat = -kHandlerHeight

private enum ExploreWhereToSpendSections: Int {
    case segments = 0
    case search
    case filters
    case items
    case nextPage
}

@objc class MerchantListViewController: WhereToSpendListViewController {
    //Change to Notification instead of chaining the property
    @objc var payWithDashHandler: (() -> Void)?
    
    private let model = MerchantsListModel()
    private var segmentTitles: [String] { return model.segmentTitles }
    private var merchants: [ExplorePointOfUse] { return model.items }
    private var currentSegment: MerchantsListSegment { return model.currentSegment }
    
    private var radius: Int = 20 //In miles //Move to model
    private var mapView: ExploreMapView!
    private var showMapButton: UIButton!
    
    private var contentViewTopLayoutConstraint: NSLayoutConstraint!
    private var contentView: UIView!
   
    private var tableView: UITableView!
    private var filterCell: DWExploreWhereToSpendFiltersCell?
    private var searchCell: DWExploreWhereToSpendSearchCell?
    private var locationOffCell: ExploreWhereToSpendLocationOffCell?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        DWLocationManager.shared.add(observer: self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        showInfoViewControllerIfNeeded()
        showMapIfNeeded()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        DWLocationManager.shared.remove(observer: self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        model.itemsDidChange = { [weak self] in
            guard let wSelf = self else { return }
            wSelf.refreshFilterCell()
            
            if wSelf.currentSegment == .nearby && DWLocationManager.shared.isPermissionDenied {
                wSelf.tableView.reloadData()
            }else if wSelf.locationOffCell != nil {
                wSelf.locationOffCell = nil
                wSelf.tableView.reloadData()
            }else{
                wSelf.tableView.reloadSections([ExploreWhereToSpendSections.items.rawValue, ExploreWhereToSpendSections.nextPage.rawValue], with: .none)
            }
            
            if wSelf.model.currentSegment != .online
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
                indexPathes.append(.init(row: i, section: ExploreWhereToSpendSections.items.rawValue))
            }
            
            wSelf.tableView.beginUpdates()
            wSelf.tableView.insertRows(at: indexPathes, with: .top)
            wSelf.tableView.reloadSections([ExploreWhereToSpendSections.nextPage.rawValue], with: .none)
            wSelf.tableView.endUpdates()
        }
        
        configureHierarchy()
    }
}

extension MerchantListViewController {
    private func refreshFilterCell() {
        switch currentSegment
        {
        case .online, .all:
            filterCell?.title = segmentTitles[currentSegment.rawValue]
            filterCell?.subtitle = nil
        case .nearby:
            filterCell?.title = segmentTitles[currentSegment.rawValue]
            if Locale.current.usesMetricSystem {
                filterCell?.subtitle = String(format: NSLocalizedString("%d merchant(s) in %@", comment: "#bc-ignore!"),  model.items.count, App.distanceFormatter.string(from: Measurement(value: 32, unit: UnitLength.kilometers)))
            }else{
                filterCell?.subtitle = String(format: NSLocalizedString("%d merchant(s) in %@", comment: "#bc-ignore!"),  model.items.count, App.distanceFormatter.string(from: Measurement(value: 20, unit: UnitLength.miles)))
            }
            
            DWLocationManager.shared.reverseGeocodeLocation(CLLocation(latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude)) { [weak self] location in
                if self?.currentSegment == .nearby {
                    self?.filterCell?.title = location
                }
            }
        }
    }
    
    private func configureHierarchy() {
        self.title = NSLocalizedString("Where to Spend", comment: "");
        self.view.backgroundColor = .dw_background()
        
        let infoButton: UIButton = UIButton(type: .infoLight)
        infoButton.addTarget(self, action: #selector(infoButtonAction), for: .touchUpInside)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: infoButton)
        
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
        tableView.register(ExploreMerchantItemCell.self, forCellReuseIdentifier: ExploreMerchantItemCell.dw_reuseIdentifier)
        tableView.register(ExploreWhereToSpendLocationOffCell.self, forCellReuseIdentifier: ExploreWhereToSpendLocationOffCell.dw_reuseIdentifier)
        tableView.register(FetchingNextPageCell.self, forCellReuseIdentifier: FetchingNextPageCell.dw_reuseIdentifier)
        
        contentView.addSubview(tableView)
        
        let handlerView = MerchantsListHandlerView(frame: .zero)
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

//MARK: Map related
extension MerchantListViewController {
    private func updateMapVisibility() {
        if currentSegment == .online || DWLocationManager.shared.isPermissionDenied {
            hideMapIfNeeded()
        }else{
            showMapIfNeeded()
        }
    }
    
    private func showMapIfNeeded() {
        guard currentSegment != .online else { return }
        
        if DWLocationManager.shared.needsAuthorization {
            DWExploreWhereToSpendLocationServicePopup.show(in: self.view) {
                DWLocationManager.shared.requestAuthorization()
            }
        
        }else if DWLocationManager.shared.isAuthorized && self.contentViewTopLayoutConstraint.constant != kDefaultOpenedMapPosition {
            showMap()
        }
    }
    
    private func showMap() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveLinear) {
            self.contentViewTopLayoutConstraint.constant = kDefaultOpenedMapPosition
            self.mapView.contentInset = .init(top: 0, left: 0, bottom: self.mapView.frame.height - kDefaultOpenedMapPosition, right: 0)
            self.view.layoutIfNeeded()
        } completion: { [weak self] completed in
            self?.updateShowMapButtonVisibility()
        }
    }
    
    private func hideMapIfNeeded() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveLinear) {
            self.contentViewTopLayoutConstraint.constant = kDefaultClosedMapPosition
            self.mapView.contentInset = .init(top: 0, left: 0, bottom: self.mapView.frame.height - kDefaultClosedMapPosition, right: 0)
            self.view.layoutIfNeeded()
        } completion: { [weak self] completed in
            self?.updateShowMapButtonVisibility()
        }
    }
    
    private func updateShowMapButtonVisibility() {
        let isVisible = (currentSegment == .nearby || currentSegment == .all) &&
                        contentViewTopLayoutConstraint.constant == kDefaultClosedMapPosition &&
                        DWLocationManager.shared.isAuthorized
                
        showMapButton.isHidden = !isVisible
    }
}

//MARK: UITableViewDelegate, UITableViewDataSource

extension MerchantListViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        var cell: UITableViewCell!
        
        guard let section = ExploreWhereToSpendSections(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .segments:
            let segmentsCell: DWExploreWhereToSpendSegmentedCell = tableView.dequeueReusableCell(withIdentifier: DWExploreWhereToSpendSegmentedCell.dw_reuseIdentifier, for: indexPath) as! DWExploreWhereToSpendSegmentedCell
            segmentsCell.separatorInset = .init(top: 0, left: 2000, bottom: 0, right: 0);
            segmentsCell.segmentDidChangeBlock = { [weak self] index in
                self?.segmentedControlDidChange(index: index)
            }
            segmentsCell.update(withItems: segmentTitles, andSelectedIndex: currentSegment.rawValue)
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
                let itemCell: ExploreWhereToSpendLocationOffCell = tableView.dequeueReusableCell(withIdentifier: ExploreWhereToSpendLocationOffCell.dw_reuseIdentifier, for: indexPath) as! ExploreWhereToSpendLocationOffCell
                cell = itemCell
                cell.separatorInset = UIEdgeInsets(top: 0, left: 2000, bottom: 0, right: 0)
                locationOffCell = itemCell
            }else{
                let merchant = self.merchants[indexPath.row];
                let itemCell: ExploreMerchantItemCell = tableView.dequeueReusableCell(withIdentifier: ExploreMerchantItemCell.dw_reuseIdentifier, for: indexPath) as! ExploreMerchantItemCell
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
        guard let section = ExploreWhereToSpendSections(rawValue: section) else {
            return 0
        }
        
        switch section
        {
        case .filters, .search:
            return currentSegment == .nearby ? (DWLocationManager.shared.isPermissionDenied ? 0 : 1) : 1
        case .items:
            
            if currentSegment == .nearby {
                if(DWLocationManager.shared.isAuthorized){
                    return merchants.count;
                }else if(DWLocationManager.shared.needsAuthorization) {
                    return 0;
                }else if(DWLocationManager.shared.isPermissionDenied) {
                    return 1;
                }
            }else{
                return merchants.count
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
        guard let section = ExploreWhereToSpendSections(rawValue: indexPath.section) else {
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
                return (currentSegment == .nearby && DWLocationManager.shared.isPermissionDenied) ? tableView.frame.size.height : 56.0
            case .nextPage:
                return 60
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        
        guard let section = ExploreWhereToSpendSections(rawValue: indexPath.section) else {
            return
        }
        
        if section == .items {
            let merchant = merchants[indexPath.row]
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

//MARK: DWLocationObserver
extension MerchantListViewController: DWLocationObserver {
    func locationManagerDidChangeCurrentLocation(_ manager: DWLocationManager, location: CLLocation) {
        mapView.setCenter(location, animated: false)
    }
    
    func locationManagerDidChangeServiceAvailability(_ manager: DWLocationManager) {
        if currentSegment != .online {
            updateMapVisibility()
            mapView.showUserLocationInCenter(animated: false)
            model.fetch(query: nil)
        }
    }
    
    func locationManagerDidChangeCurrentReversedLocation(_ manager: DWLocationManager) {
        if currentSegment != .online {
        }
    }
}

//MARK: Actions
extension MerchantListViewController {
    private func show(pointOfUse: ExplorePointOfUse) {
        let vc: UIViewController
        
        guard let merchant = pointOfUse.merchant else { return }
        
        if merchant.type == .online {
            let onlineVC = ExploreOnlineMerchantViewController(merchant: pointOfUse)
            onlineVC.payWithDashHandler = self.payWithDashHandler;
            vc = onlineVC;
        }else{
            vc = ExploreOfflineMerchantViewController(merchant: pointOfUse, isShowAllHidden: false)
        }
        
        navigationController?.pushViewController(vc, animated: true)
    }

    
    private func showInfoViewControllerIfNeeded() {
        if !DWGlobalOptions.sharedInstance().dashpayExploreWhereToSpendInfoShown {
            showInfoViewController()
            DWGlobalOptions.sharedInstance().dashpayExploreWhereToSpendInfoShown = true
        }
    }
    
    private func showInfoViewController() {
        let vc = DWExploreWhereToSpendInfoViewController()
        self.present(vc, animated: true, completion: nil)
    }
    
    @objc private func showMapAction() {
        showMap()
    }
    
    @objc private func infoButtonAction() {
        showInfoViewController()
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
        guard currentSegment.rawValue != index,
              let newSegment = MerchantsListSegment(rawValue: index) else {
            return
        }
        
        model.currentSegment = newSegment
        refreshFilterCell()
        
        DispatchQueue.main.async {
            switch newSegment {
            case .nearby, .all:
                self.showMapIfNeeded()
            default:
                self.hideMapIfNeeded()
            }
        }
        
    }
}

extension MerchantListViewController: DWExploreWhereToSpendSearchCellDelegate {
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

//MARK: ExploreMapViewDelegate

extension MerchantListViewController: ExploreMapViewDelegate {
    func exploreMapView(_ mapView: ExploreMapView, didChangeVisibleBounds bounds: ExploreMapBounds) {
        
        refreshFilterCell()
        model.currentMapBounds = bounds
    }
    
    func exploreMapView(_ mapView: ExploreMapView, didSelectMerchant merchant: ExplorePointOfUse) {
        show(pointOfUse: merchant)
    }
}
