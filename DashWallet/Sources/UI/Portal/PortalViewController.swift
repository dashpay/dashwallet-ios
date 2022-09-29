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

extension PortalModel.Service {
    var item: PortalViewController.Item {
        return .init(icon: self.icon, name: self.title, status: self.status ? .connected : .unknown)
    }
}

extension PortalViewController.Item.Status {
    var iconColor: UIColor {
        switch self {
        case .connected: return .systemGreen
        case .disconnected: return .systemRed
        case .unknown: return .label
        }
    }
    
    var labelColor: UIColor {
        switch self {
        case .connected: return .label
        case .disconnected: return .systemRed
        case .unknown: return .label
        }
    }
    
    var statusString: String {
        switch self {
        case .connected: return NSLocalizedString("Connected", comment: "Buy Sell Portal")
        case .disconnected: return NSLocalizedString("Disconnected", comment: "Buy Sell Portal")
        case .unknown: return ""
        }
        
    }
}
extension PortalViewController {
    enum Section: Int {
        case main
    }
    
    class Item: Hashable {
        static func == (lhs: PortalViewController.Item, rhs: PortalViewController.Item) -> Bool {
            lhs.hashValue == rhs.hashValue
        }
        
        enum Status: StringLiteralType {
            case connected
            case disconnected
            case unknown
        }
        
        var icon: String
        var name: String
        var status: Status
         
        init(icon: String, name: String, status: Status) {
            self.icon = icon
            self.name = name
            self.status = status
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(status)
        }
    }
}

@objc class PortalViewController: UIViewController {
    
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var networkStatusView: UIView!
    
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var currentSnapshot: NSDiffableDataSourceSnapshot<Section, Item>!
    
    private var model: PortalModel = PortalModel()
    private var hasNetwork: Bool { model.networkStatus == .online }
    
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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
    }
    
    private func configureModel() {
        model.networkStatusDidChange = { [weak self] status in
            self?.networkStatusView.isHidden = status == .online
            self?.collectionView.reloadData()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.dw_secondaryBackground()
        
        configureModel()
        configureHierarchy()
        configureDataSource()
        
        navigationController?.navigationBar.topItem?.backButtonDisplayMode = .minimal
    }
    
    @objc class func controller() -> PortalViewController {
        return vc(PortalViewController.self, from: sb("Coinbase"))
    }
}

extension PortalViewController {
    private func createLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                              heightDimension: .estimated(64))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .fractionalWidth(1.0))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize,
                                                       subitems: [item])
        group.interItemSpacing = .fixed(10)
        
        let section = NSCollectionLayoutSection(group: group)
        
        let layout = UICollectionViewCompositionalLayout(section: section)
        return layout
    }
    
    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            [weak self] (collectionView: UICollectionView, indexPath: IndexPath, itemIdentifier: Item) -> UICollectionViewCell? in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ItemCell", for: indexPath) as! PortalServiceCell
            cell.update(with: itemIdentifier, isEnabled: self?.hasNetwork ?? true)
            return cell
        }
        
        // initial data
        applySnapshot()
    }
    
    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        
        var items: [Item] = []
        items.reserveCapacity(2)
        
        for s in model.services {
            items.append(.init(icon: s.icon, name: s.title,
                               status: hasNetwork ? (s.status ? .connected : .unknown) : .disconnected))
        }
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    
    private func configureHierarchy() {
        
        title = NSLocalizedString("Select a service", comment: "Buy Sell Dash")
        
        networkStatusView.isHidden = hasNetwork
         
        collectionView.delegate = self
        collectionView.collectionViewLayout = createLayout()
    }
}

extension PortalViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item == 0 {
            coinbaseAction()
        }
    }
}

class PortalServiceCell: UICollectionViewCell {
    @IBOutlet var iconView: UIImageView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    
    @IBOutlet var statusView: UIView!
    @IBOutlet var statusIcon: UIView!
    @IBOutlet var statusLabel: UILabel!
    
    @IBOutlet var balanceView: UIView!
    @IBOutlet var dashBalanceLabel: UILabel!
    @IBOutlet var fiatBalanceLabel: UILabel!
    @IBOutlet var balanceStatusLabel: UILabel!
    
    
    func update(with item: PortalViewController.Item, isEnabled: Bool) {
        iconView.image = UIImage(named: isEnabled ? item.icon : "\(item.icon).disabled" )
        titleLabel.text = item.name
        
        if item.status == .unknown {
            subtitleLabel.text = NSLocalizedString("Link your account", comment: "Buy Sell Portal")
            statusView.isHidden = true
            subtitleLabel.isHidden = false
        }else{
            statusView.isHidden = false
            subtitleLabel.isHidden = true
            statusIcon.backgroundColor = item.status.iconColor
            statusLabel.textColor = item.status.labelColor
            statusLabel.text = item.status.statusString
            balanceView.isHidden = item.status == .disconnected
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .white
        
        statusIcon.layer.cornerRadius = 3
        statusIcon.layer.masksToBounds = true
        
        backgroundColor = .clear
    }
}
