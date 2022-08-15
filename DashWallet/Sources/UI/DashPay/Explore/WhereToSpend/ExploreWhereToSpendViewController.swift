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

private let kExploreWhereToSpendSectionCount = 4

private let kHandlerHeight: CGFloat = 24.0
private let kDefaultOpenedMapPosition: CGFloat = 260.0
private let kDefaultClosedMapPosition: CGFloat = -kHandlerHeight

private enum ExploreWhereToSpendSections: Int {
    case segments = 0
    case search
    case filters
    case items
}

enum ExploreWhereToSpendSegment: Int {
    case online = 0
    case nearby
    case all
}

@objc class ExploreWhereToSpendViewController: UIViewController {
    
    @objc var payWithDashHandler: (() -> Void)?
    
    let model = ExploreDashWhereToSpendModel()
    
    var merchants: [Merchant] { return isSearchActive ? searchResult : model.merchants(for: currentSegment) }
        
    private var segmentTitles: [String] = [NSLocalizedString("Online", comment: "Online"),
                                           NSLocalizedString("Nearby", comment: "Nearby"),
                                           NSLocalizedString("All", comment: "All")]
    
    private var contentViewTopLayoutConstraint: NSLayoutConstraint!
    private var contentView: UIView!
    private var tableView: UITableView!
    private var mapView: ExploreMapView!
    private var filterCell: DWExploreWhereToSpendFiltersCell?
    private var searchCell: DWExploreWhereToSpendSearchCell?
    
    private var currentSegment: ExploreWhereToSpendSegment = .online
    private var showMapButton: UIButton!
    
    
    private var cancelBarButton: UIBarButtonItem = {
        let infoButton: UIButton = UIButton(type: .infoLight)
        infoButton.addTarget(ExploreWhereToSpendViewController.self, action: #selector(infoButtonAction), for: .touchUpInside)
        return UIBarButtonItem(customView: infoButton)
    }()
    
    private var isSearchActive: Bool = false
    private var lastSearchQuery: String?
    private var searchResult: [Merchant] = []
    
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
        
        self.title = NSLocalizedString("Where to Spend", comment: "");
        self.view.backgroundColor = .dw_background()
        self.navigationItem.rightBarButtonItem = cancelBarButton
        
        model.nearbyMerchantsDidChange = { [weak self] in
            let merchantsToShow: Array<Merchant>
            
            if self?.isSearchActive ?? false {
                merchantsToShow = self?.model.nearbyLastSearchMerchants ?? []
                self?.searchResult = merchantsToShow
                self?.tableView.reloadSections([ExploreWhereToSpendSections.items.rawValue], with: .none)
            }else{
                merchantsToShow = self?.model.cachedNearbyMerchants ?? []
                self?.tableView.reloadData()
            }
            
            self?.mapView.show(merchants: merchantsToShow)
            if let userRadius = self?.mapView.userRadius {
                self?.filterCell?.subtitle = String(format: NSLocalizedString("%d merchant(s) in %@", comment: "#bc-ignore!"),  merchantsToShow.count, App.distanceFormatter.string(from: Measurement(value: floor(userRadius), unit: UnitLength.meters)))
            }else{
                self?.filterCell?.subtitle = String(format: NSLocalizedString("%d merchant(s)", comment: "#bc-ignore!"),  merchantsToShow.count)
            }

        }
        
        currentSegment = DWLocationManager.shared.isAuthorized ? .nearby : .online;
        
        configureHierarchy()
    }
}

extension ExploreWhereToSpendViewController {
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
    
    private func updateMapVisibility() {
        if currentSegment != .nearby || DWLocationManager.shared.isPermissionDenied {
            hideMapIfNeeded()
        }else{
            showMapIfNeeded()
        }
    }
    
    private func showMapIfNeeded() {
        guard currentSegment == .nearby else { return }
        
        if DWLocationManager.shared.needsAuthorization {
            DWExploreWhereToSpendLocationServicePopup.show(in: self.view) {
                DWLocationManager.shared.requestAuthorization()
            }
        
        }else if DWLocationManager.shared.isAuthorized {
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
        let isVisible = currentSegment == .nearby &&
                        contentViewTopLayoutConstraint.constant == kDefaultClosedMapPosition &&
                        DWLocationManager.shared.isAuthorized
                
        showMapButton.isHidden = !isVisible
    }
    
    private func show(merchant: Merchant) {
        let vc: UIViewController
        
        if merchant.type == .online {
            let onlineVC = ExploreOnlineMerchantViewController(merchant: merchant)
            onlineVC.payWithDashHandler = self.payWithDashHandler;
            vc = onlineVC;
        }else{
            vc = ExploreOfflineMerchantViewController(merchant: merchant, isShowAllHidden: false)
        }
        
        navigationController?.pushViewController(vc, animated: true)
    }
    private func configureHierarchy() {
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
        contentView.addSubview(tableView)
        
        let handlerView = DWExploreWhereToSpendHandlerView(frame: .zero)
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

extension ExploreWhereToSpendViewController: UITableViewDelegate, UITableViewDataSource {
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
            let searchCell: DWExploreWhereToSpendSearchCell = tableView.dequeueReusableCell(withIdentifier: DWExploreWhereToSpendSearchCell.dw_reuseIdentifier, for: indexPath) as! DWExploreWhereToSpendSearchCell
            searchCell.separatorInset = UIEdgeInsets(top: 0, left: 2000, bottom: 0, right: 0);
            searchCell.delegate = self
            self.searchCell = searchCell
            cell = searchCell
        case .filters:
            let filterCell: DWExploreWhereToSpendFiltersCell = tableView.dequeueReusableCell(withIdentifier: DWExploreWhereToSpendFiltersCell.dw_reuseIdentifier, for: indexPath) as! DWExploreWhereToSpendFiltersCell
            filterCell.title = segmentTitles[currentSegment.rawValue]
            
            if let userRadius = mapView.userRadius {
                filterCell.subtitle = String(format: NSLocalizedString("%d merchant(s) in %@", comment: "#bc-ignore!"),  model.cachedNearbyMerchants.count, App.distanceFormatter.string(from: Measurement(value: floor(userRadius), unit: UnitLength.meters)))
            }else{
                filterCell.subtitle = String(format: NSLocalizedString("%d merchant(s)", comment: "#bc-ignore!"),  model.cachedNearbyMerchants.count)
            }
            
            
            if currentSegment == .nearby {
                let location: String? = DWLocationManager.shared.currentReversedLocation
                filterCell.title = location ?? filterCell.title
                //filterCell.subtitle = NSLocalizedString("2 merchants in 20 miles", comment: "");
            }
            self.filterCell = filterCell
            cell = filterCell
        case .items:
            if currentSegment == .nearby && DWLocationManager.shared.isPermissionDenied {
                let itemCell: ExploreWhereToSpendLocationOffCell = tableView.dequeueReusableCell(withIdentifier: ExploreWhereToSpendLocationOffCell.dw_reuseIdentifier, for: indexPath) as! ExploreWhereToSpendLocationOffCell
                cell = itemCell
                cell.separatorInset = UIEdgeInsets(top: 0, left: 2000, bottom: 0, right: 0)
            }else{
                let merchant = self.merchants[indexPath.row];
                let itemCell: ExploreMerchantItemCell = tableView.dequeueReusableCell(withIdentifier: ExploreMerchantItemCell.dw_reuseIdentifier, for: indexPath) as! ExploreMerchantItemCell
                itemCell.update(with: merchant)
                cell = itemCell;
            }
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
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        
        guard let section = ExploreWhereToSpendSections(rawValue: indexPath.section) else {
            return
        }
        
        if section == .items {
            let merchant = merchants[indexPath.row]
            show(merchant: merchant)
        }
    }
}

extension ExploreWhereToSpendViewController: DWLocationObserver {
    func locationManagerDidChangeCurrentLocation(_ manager: DWLocationManager, location: CLLocation) {
        //mapView.setCenter(location, animated: false)
    }
    
    func locationManagerDidChangeServiceAvailability(_ manager: DWLocationManager) {
        if currentSegment == .nearby {
            tableView.reloadData()
            updateMapVisibility()
        }
    }
    
    func locationManagerDidChangeCurrentReversedLocation(_ manager: DWLocationManager) {
        if currentSegment == .nearby {
            tableView.reloadData()
        }
    }
}

extension ExploreWhereToSpendViewController {
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
              let newSegment = ExploreWhereToSpendSegment(rawValue: index) else {
            return
        }
        
        currentSegment = newSegment
        isSearchActive = false
        searchCell?.resetSearchBar()
        filterCell?.subtitle = nil
        switch newSegment {
        case .nearby:
            self.showMapIfNeeded()
        default:
            self.hideMapIfNeeded()
        }
        
        tableView.reloadData()
    }
}

extension ExploreWhereToSpendViewController: DWExploreWhereToSpendSearchCellDelegate {
    private func stopSearching() {
        isSearchActive = false
        searchResult = []
        
        switch currentSegment {
        case .nearby:
            if let userRadius = mapView.userRadius {
                filterCell?.subtitle = String(format: NSLocalizedString("%d merchant(s) in %@", comment: "#bc-ignore!"),  model.cachedNearbyMerchants.count, App.distanceFormatter.string(from: Measurement(value: floor(userRadius), unit: UnitLength.meters)))
            }else{
                filterCell?.subtitle = String(format: NSLocalizedString("%d merchant(s)", comment: "#bc-ignore!"),  model.cachedNearbyMerchants.count)
            }
            mapView.show(merchants: model.cachedNearbyMerchants)
        default:
            break
        }
        
        tableView.reloadSections([ExploreWhereToSpendSections.items.rawValue], with: .none)
    }
    
    func searchCell(_ searchCell: DWExploreWhereToSpendSearchCell, shouldStartSearchWithQuery query: String) {
        if query.isEmpty {
            stopSearching()
            return
        }
        isSearchActive = true
        
        switch currentSegment {
        case .nearby:
            model.searchMerchants(by: query, in: mapView.mapBounds, userPoint: mapView.userLocation?.coordinate)
        default:
            searchResult = model.search(query: query, for: currentSegment)
            tableView.reloadSections([ExploreWhereToSpendSections.items.rawValue], with: .none)
        }
    }
    
    func searchCellDidEndSearching(_ searchCell: DWExploreWhereToSpendSearchCell) {
        stopSearching()
    }
}

extension ExploreWhereToSpendViewController: ExploreMapViewDelegate {
    func exploreMapView(_ mapView: ExploreMapView, didChangeVisibleBounds bounds: ExploreMapBounds) {
        if let q = lastSearchQuery, isSearchActive {
            model.searchMerchants(by: q, in: bounds, userPoint: mapView.userLocation?.coordinate)
        }else{
            model.fetchMerchants(in: bounds, userPoint: mapView.userLocation?.coordinate)
        }
    }
    
    func exploreMapView(_ mapView: ExploreMapView, didSelectMerchant merchant: Merchant) {
        show(merchant: merchant)
    }
}
