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

enum TxDetailDisplayType {
    case moved
    case sent
    case received
    case paid
    case masternodeRegistration
}

@objc class TXDetailViewController: UIViewController {
    @objc var model: DWTxDetailModel!
    
    @IBOutlet var tableView: UITableView!
    @IBOutlet var closeButton: DWActionButton!
    
    var dataSource: UITableViewDiffableDataSource<Section, Item>! = nil
    var currentSnapshot: NSDiffableDataSourceSnapshot<Section, Item>! = nil
    
    enum Section: CaseIterable {
        case header, info, explorer
    }
    
    enum Item: Hashable {
        static func == (lhs: TXDetailViewController.Item, rhs: TXDetailViewController.Item) -> Bool {
            lhs.rawValue == rhs.rawValue
        }
        
        case header
        case receivedAt([DWTitleDetailItem])
        case sentFrom([DWTitleDetailItem])
        case sentTo([DWTitleDetailItem])
        case movedFrom([DWTitleDetailItem])
        case movedTo([DWTitleDetailItem])
        case networkFee(DWTitleDetailItem)
        case date(DWTitleDetailItem)
        case explorer
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(rawValue)
        }
        
        var rawValue: Int {
            switch self {
            case .header:
                return 0
            case .receivedAt:
                return 1
            case .sentFrom:
                return 2
            case .sentTo:
                return 3
            case .movedFrom:
                return 4
            case .movedTo:
                return 5
            case .networkFee:
                return 6
            case .date:
                return 7
            case .explorer:
                return 8
                
            }
        }
    }
    
    @IBAction func closeButtonAction(sender: UIButton) {
        dismiss(animated: true)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        assert(model != nil, "Model must be initiated at this moment")
        
        configureHierarchy()
        configureDataSource()
    }
    
    @objc class func controller() -> TXDetailViewController {
        let storyboard = UIStoryboard(name: "Tx", bundle: nil)
        let vc = storyboard.instantiateInitialViewController() as! TXDetailViewController
        return vc
    }
}

extension TXDetailViewController {
    private func viewInBlockExplorer() {
        guard let explorerURL = self.model.explorerURL() else {
            return
        }
        
        let vc = SFSafariViewController.dw_controller(with: explorerURL)
        
        // The views beneath the presented content are not removed from the view hierarchy when the presentation finishes.
        vc.modalPresentationStyle = .overFullScreen
        vc.modalPresentationCapturesStatusBarAppearance = true
        self.present(vc, animated: true) {
            
        }
    }
}

extension TXDetailViewController {
    
    func configureDataSource() {
        self.dataSource = UITableViewDiffableDataSource
        <Section, Item>(tableView: tableView) { [weak self]
            (tableView: UITableView, indexPath: IndexPath, item: Item) -> UITableViewCell? in
            
            guard let wSelf = self else { return UITableViewCell() }
            
            let section = wSelf.currentSnapshot.sectionIdentifiers[indexPath.section]
            
            switch section
            {
            case .header:
                let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailHeaderCell.dw_reuseIdentifier, for: indexPath) as! TxDetailHeaderCell
                cell.model = self?.model
                cell.selectionStyle = .none
                cell.backgroundColor = .clear
                cell.backgroundView?.backgroundColor = .clear
                
                return cell
            case .info:
                let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailInfoCell.dw_reuseIdentifier, for: indexPath) as! TxDetailInfoCell
                cell.update(with: item)
                cell.selectionStyle = .none
                cell.separatorInset = .init(top: 0, left: 2000, bottom: 0, right: 0)
                return cell
                
            case .explorer:
                let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailActionCell.dw_reuseIdentifier, for: indexPath) as! TxDetailActionCell
                cell.titleLabel.text = NSLocalizedString("View in Block Explorer", comment: "")
                return cell
            }
            
        }
        
        let detailFont = UIFont.preferredFont(forTextStyle: .caption1)
        let date: DWTitleDetailItem = model.date()
        
        currentSnapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        currentSnapshot.appendSections([.header, .info, .explorer])
        currentSnapshot.appendItems([.header], toSection: .header)
        
        switch (self.model.direction) {
        case .moved:
            let fee: DWTitleDetailItem = model.fee(with: detailFont, tintColor: UIColor.label)!
            currentSnapshot.appendItems([.movedFrom(model.inputAddresses(with: detailFont)),
                                         .movedTo(model.outputAddresses(with: detailFont))], toSection: .info)
            currentSnapshot.appendItems([.networkFee(fee)], toSection: .info)
        case .sent:
            let fee: DWTitleDetailItem = model.fee(with: detailFont, tintColor: UIColor.label)!
            currentSnapshot.appendItems([.sentFrom(model.inputAddresses(with: detailFont)),
                                         .sentTo(model.outputAddresses(with: detailFont))], toSection: .info)
            currentSnapshot.appendItems([.networkFee(fee)], toSection: .info)
        case .received:
            currentSnapshot.appendItems([.receivedAt(model.outputAddresses(with: detailFont))], toSection: .info)
        case .notAccountFunds:
            break
        default:
            break;
        }
        
        currentSnapshot.appendItems([.date(date)], toSection: .info)
        currentSnapshot.appendItems([.explorer], toSection: .explorer)
        self.dataSource.apply(currentSnapshot, animatingDifferences: false)
        self.dataSource.defaultRowAnimation = .fade
    }

    @objc func configureHierarchy() {
        view.backgroundColor = UIColor.dw_secondaryBackground()
        
        // Make sure we have 20pt padding on the sides
        //tableView.contentInset = .init(top: 0, left: 0, bottom: 0, right: 5)
        tableView.backgroundColor = UIColor.dw_secondaryBackground()
        tableView.delegate = self
    }
}

extension TXDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let section = currentSnapshot.sectionIdentifiers[indexPath.section]
        
        switch section
        {
        case .explorer:
            viewInBlockExplorer()
        default:
            break
        }
    }
    
    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }
    
    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return nil
    }
    
    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 7
    }
    
    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 8
    }
}

@objc protocol SuccessTxDetailViewControllerDelegate: AnyObject {
    func txDetailViewControllerDidFinish(controller: SuccessTxDetailViewController)
}

@objc class SuccessTxDetailViewController: TXDetailViewController {
    
    // TODO: think how we can avoid storing contactItem here
    // passthrough context, not used internally
    @objc var contactItem: DWDPBasicUserItem?
    
    @objc weak var delegate: SuccessTxDetailViewControllerDelegate?
    
    @IBAction override func closeButtonAction(sender: UIButton) {
        dismiss(animated: true) { [weak self] in
            if let wSelf = self {
                wSelf.delegate?.txDetailViewControllerDidFinish(controller: wSelf)
            }
        }
    }
    
    override func configureHierarchy() {
        super.configureHierarchy()
        
        self.closeButton.usedOnDarkBackground = true
        closeButton.small = true
        closeButton.setTitle(NSLocalizedString("Close", comment: ""), for: .normal)
    }
    
    @objc override static func controller() -> SuccessTxDetailViewController {
        let storyboard = UIStoryboard(name: "Tx", bundle: nil)
        let vc = storyboard.instantiateViewController(identifier: "SuccessTxDetailViewController") as! SuccessTxDetailViewController
        return vc
    }
}
