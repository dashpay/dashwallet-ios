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


@objc class MerchantListViewController: PointOfUseListViewController {
    //Change to Notification instead of chaining the property
    @objc var payWithDashHandler: (() -> Void)?
    
    //MARK: Table View
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = ExploreWhereToSpendSections(rawValue: indexPath.section) else {
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
    
    override func configureModel() {
        model = MerchantsListModel()
    }
    
    override func configureHierarchy() {
        self.title = NSLocalizedString("Where to Spend", comment: "");
        self.view.backgroundColor = .dw_background()
        
        let infoButton: UIButton = UIButton(type: .infoLight)
        infoButton.addTarget(self, action: #selector(infoButtonAction), for: .touchUpInside)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: infoButton)
        
        super.configureHierarchy()
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



