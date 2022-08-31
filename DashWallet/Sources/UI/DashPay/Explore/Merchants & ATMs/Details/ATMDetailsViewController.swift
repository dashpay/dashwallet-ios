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

class ATMDetailsViewController: UIViewController {
    internal let pointOfUse: ExplorePointOfUse
    
    @objc public var payWithDashHandler: (()->())?
    @objc var sellDashHandler: (()->())?
    
    private var detailsView: AtmDetailsView!
    private var mapView: ExploreMapView!
    
    public init(pointOfUse: ExplorePointOfUse) {
        self.pointOfUse = pointOfUse
        super.init(nibName: nil, bundle: nil)
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        mapView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: mapView.frame.height - detailsView.frame.height - 10, right: 0)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = pointOfUse.name
        configureHierarchy()
    }
}

extension ATMDetailsViewController {
    @objc func payAction() {
        payWithDashHandler?()
    }
    
    @objc func callAction() {
        guard let phone = pointOfUse.phone else { return }
        
        let fixedPhone = phone.replacingOccurrences(of: " ", with: "")
        
        guard let url = URL(string: "telprompt://\(fixedPhone)") else { return }
        
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    @objc func websiteAction() {
        guard let website = pointOfUse.website, let url = URL(string: website) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
   
    func configureHierarchy() {
        mapView = ExploreMapView()
        mapView.show(merchants: [pointOfUse])
        mapView.centerRadius = 5
        mapView.initialCenterLocation = .init(latitude: pointOfUse.latitude!, longitude: pointOfUse.longitude!)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)
        
        detailsView = AtmDetailsView(merchant: pointOfUse)
        detailsView.payWithDashHandler = payWithDashHandler
        detailsView.sellDashHandler = sellDashHandler
        detailsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(detailsView)
        
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            //detailsView.heightAnchor.constraint(equalToConstant: 310),
            detailsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            detailsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            detailsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}

