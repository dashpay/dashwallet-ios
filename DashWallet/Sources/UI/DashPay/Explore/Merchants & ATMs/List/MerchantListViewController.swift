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

enum MerchantsListSegment: Int {
    case online = 0
    case nearby
    case all
    
    static func ==(lhs: ExplorePointOfUseListSegment, rhs: MerchantsListSegment) -> Bool {
        return lhs.tag == rhs.rawValue
    }
    
    var pointOfUseListSegment: ExplorePointOfUseListSegment {
        switch self {
        case .online:
            return .init(tag: rawValue, title: title, showMap: false, showLocationServiceSettings: false, showReversedLocation: false, dataProvider: OnlineMerchantsDataProvider())
        case .nearby:
            return .init(tag: rawValue, title: title, showMap: true, showLocationServiceSettings: true, showReversedLocation: true, dataProvider: NearbyMerchantsDataProvider())
        case .all:
            return .init(tag: rawValue, title: title, showMap: true, showLocationServiceSettings: false, showReversedLocation: false, dataProvider: AllMerchantsDataProvider())
        }
    }
}

extension MerchantsListSegment {
    var title: String {
        switch self {
        case .online:
            return NSLocalizedString("Online", comment: "Online")
        case .nearby:
            return NSLocalizedString("Nearby", comment: "Nearby")
        case .all:
            return NSLocalizedString("All", comment: "All")
        }
    }
}

@objc class MerchantListViewController: ExplorePointOfUseListViewController {
    
    
    //MARK: Table View
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        var cell: UITableViewCell!
        
        guard let section = ExplorePointOfUseSections(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .items:
            if currentSegment == .nearby && DWLocationManager.shared.isPermissionDenied {
                let itemCell: MerchantListLocationOffCell = tableView.dequeueReusableCell(withIdentifier: MerchantListLocationOffCell.dw_reuseIdentifier, for: indexPath) as! MerchantListLocationOffCell
                cell = itemCell
                cell.separatorInset = UIEdgeInsets(top: 0, left: 2000, bottom: 0, right: 0)
                locationOffCell = itemCell
            }else{
                return super.tableView(tableView, cellForRowAt: indexPath)
            }
        default:
            return super.tableView(tableView, cellForRowAt: indexPath)
        }
        
        cell.selectionStyle = .none
        return cell
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
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
                return super.tableView(tableView, numberOfRowsInSection: section.rawValue)
            }
        default:
            return super.tableView(tableView, numberOfRowsInSection: section.rawValue)
        }

        return super.tableView(tableView, numberOfRowsInSection: section.rawValue)
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = ExplorePointOfUseSections(rawValue: indexPath.section) else {
            return 0
        }
        
        switch section {
        case .items:
            return (currentSegment.showLocationServiceSettings && DWLocationManager.shared.isPermissionDenied) ? tableView.frame.size.height : 56.0
        default:
            return super.tableView(tableView, heightForRowAt: indexPath)
        }
    }
    
    //MARK: Life cycle
    
    override func show(pointOfUse: ExplorePointOfUse) {
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
    
    override func subtitleForFilterCell() -> String? {
        if currentSegment.showMap {
            if Locale.current.usesMetricSystem {
                return String(format: NSLocalizedString("%d merchant(s) in %@", comment: "#bc-ignore!"),  items.count, App.distanceFormatter.string(from: Measurement(value: 32, unit: UnitLength.kilometers)))
            }else{
                return String(format: NSLocalizedString("%d merchant(s) in %@", comment: "#bc-ignore!"),  items.count, App.distanceFormatter.string(from: Measurement(value: 20, unit: UnitLength.miles)))
            }
        }else{
            return nil
        }
    }
    
    override func configureModel() {
        model = ExplorePointOfUseListModel(segments: [MerchantsListSegment.online.pointOfUseListSegment, MerchantsListSegment.nearby.pointOfUseListSegment, MerchantsListSegment.all.pointOfUseListSegment])
        if DWLocationManager.shared.isAuthorized {
            model.currentSegment = model.segments[MerchantsListSegment.nearby.rawValue]
        }
    }
    
    override func configureHierarchy() {
        self.title = NSLocalizedString("Where to Spend", comment: "");
        
        let infoButton: UIButton = UIButton(type: .infoLight)
        infoButton.addTarget(self, action: #selector(infoButtonAction), for: .touchUpInside)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: infoButton)
        
        super.configureHierarchy()
        
        tableView.register(MerchantItemCell.self, forCellReuseIdentifier: MerchantItemCell.dw_reuseIdentifier)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        showInfoViewControllerIfNeeded()
        showMapIfNeeded()
    }
}

//MARK: Actions
extension MerchantListViewController {
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
    
    @objc private func infoButtonAction() {
        showInfoViewController()
    }
}

extension MerchantsListSegment {
    
}

