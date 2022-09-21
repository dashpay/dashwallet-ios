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
import SwiftUI

extension PortalViewController {
    enum Section: Int {
        case main
    }
    
    struct Item: Hashable {
        enum Status: StringLiteralType {
            case connected
            case disconnected
            case unknown
        }
        var icon: String
        var name: String
        var status: Status
    }
}

@objc class PortalViewController: UIViewController {
    
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var collectionView: UICollectionView!
    
    private var coinbaseButton: UIButton!
    
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var currentSnapshot: NSDiffableDataSourceSnapshot<Section, Item>!
    
    @objc func coinbaseAction() {
        if DWGlobalOptions.sharedInstance().coinbaseInfoShown {
            let vc = UIHostingController(rootView: CoinbasePortalView())
            navigationController?.pushViewController(vc, animated: true)
        }else{
            let vc = CoinbaseInfoViewController.controller()
            vc.modalPresentationStyle = .overCurrentContext
            vc.modalTransitionStyle = .crossDissolve
            present(vc, animated: true)
            
            DWGlobalOptions.sharedInstance().coinbaseInfoShown = true
        }
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
        //configureDataSource()
    }
    
    @objc class func controller() -> PortalViewController {
        return vc(PortalViewController.self, from: sb("Coinbase"))
    }
}

extension PortalViewController {
    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            (collectionView: UICollectionView, indexPath: IndexPath, itemIdentifier: Item) -> UICollectionViewCell? in
            return UICollectionViewCell()
        }
    }
    
    private func configureHierarchy() {
        coinbaseButton = UIButton(type: .custom)
        coinbaseButton.translatesAutoresizingMaskIntoConstraints = false
        coinbaseButton.setTitle("Coinbase", for: .normal)
        coinbaseButton.backgroundColor = .dw_dashBlue()
        coinbaseButton.addTarget(self, action: #selector(coinbaseAction), for: .touchUpInside)
        view.addSubview(coinbaseButton)
        
        NSLayoutConstraint.activate([
            coinbaseButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            coinbaseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
        ])
    }
}

extension PortalViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
    }
}
