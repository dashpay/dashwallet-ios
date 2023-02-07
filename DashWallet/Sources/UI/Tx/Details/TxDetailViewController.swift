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

// MARK: - TxDetailDisplayType

enum TxDetailDisplayType {
    case moved
    case sent
    case received
    case paid
    case masternodeRegistration
}

// MARK: - BaseTxDetailsViewController

@objc
class BaseTxDetailsViewController: BaseViewController {
    internal var tableView: UITableView!

    // MARK: Actions
    @objc
    internal func closeAction() {
        dismiss(animated: true)
    }

    // MARK: Life cycle
    internal func configureHierarchy() {
        view.backgroundColor = UIColor.dw_secondaryBackground()

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.preservesSuperviewLayoutMargins = true
        tableView.registerNib(for: TxDetailHeaderCell.self)
        tableView.registerNib(for: TxDetailTaxCategoryCell.self)
        tableView.registerNib(for: TxDetailInfoCell.self)
        tableView.registerNib(for: TxDetailActionCell.self)
        tableView.backgroundColor = UIColor.dw_secondaryBackground()
        tableView.delegate = self

        view.addSubview(tableView)
    }

    internal func configureLayout() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        configureLayout()
    }
}

// MARK: UITableViewDelegate

extension BaseTxDetailsViewController: UITableViewDelegate {
    @objc
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // NOP
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        nil
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }

    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        7
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        8
    }
}

// MARK: - TXDetailViewController

@objc
class TXDetailViewController: BaseTxDetailsViewController {
    @objc var model: TxDetailModel!

    var dataSource: UITableViewDiffableDataSource<Section, Item>! = nil
    var currentSnapshot: NSDiffableDataSourceSnapshot<Section, Item>! = nil

    enum Section: CaseIterable {
        case header
        case info
        case taxCategory
        case explorer
    }

    enum Item: Hashable {
        static func == (lhs: TXDetailViewController.Item, rhs: TXDetailViewController.Item) -> Bool {
            lhs.hashValue == rhs.hashValue
        }

        case header
        case receivedAt([DWTitleDetailItem])
        case sentFrom([DWTitleDetailItem])
        case sentTo([DWTitleDetailItem])
        case movedFrom([DWTitleDetailItem])
        case movedTo([DWTitleDetailItem])
        case networkFee(DWTitleDetailItem)
        case date(DWTitleDetailItem)
        case taxCategory(DWTitleDetailItem)
        case explorer

        func hash(into hasher: inout Hasher) {
            switch self {
            case .header:
                hasher.combine("Header")
            case .sentTo(let items), .sentFrom(let items), .movedTo(let items), .movedFrom(let items), .receivedAt(let items):
                for item in items {
                    hasher.combine(item.title)
                    if let value = item.plainDetail ?? item.attributedDetail?.string {
                        hasher.combine(value)
                    }
                }
            case .date(let item), .taxCategory(let item), .networkFee(let item):
                hasher.combine(item.title?.hashValue)
                if let value = item.plainDetail ?? item.attributedDetail?.string {
                    hasher.combine(value.hashValue)
                }

            case .explorer:
                hasher.combine("Explorer")
            }
        }
    }

    @objc
    init(model: TxDetailModel) {
        self.model = model

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        let item = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeAction))
        navigationItem.rightBarButtonItem = item
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        assert(model != nil, "Model must be initiated at this moment")

        configureDataSource()
        reloadDataSource()
    }
}

extension TXDetailViewController {
    private func viewInBlockExplorer() {
        guard let explorerURL = model.explorerURL else {
            return
        }

        let vc = SFSafariViewController.dw_controller(with: explorerURL)

        // The views beneath the presented content are not removed from the view hierarchy when the presentation finishes.
        vc.modalPresentationStyle = .overFullScreen
        vc.modalPresentationCapturesStatusBarAppearance = true
        present(vc, animated: true) { }
    }
}

extension TXDetailViewController {

    func configureDataSource() {
        dataSource = UITableViewDiffableDataSource
        <Section, Item>(tableView: tableView) { [weak self]
            (tableView: UITableView, indexPath: IndexPath, item: Item) -> UITableViewCell? in

                guard let wSelf = self else { return UITableViewCell() }

                let section = wSelf.currentSnapshot.sectionIdentifiers[indexPath.section]

                switch section {
                case .header:
                    let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailHeaderCell.reuseIdentifier,
                                                             for: indexPath) as! TxDetailHeaderCell
                    cell.updateView(with: wSelf.model)
                    cell.selectionStyle = .none
                    cell.backgroundColor = .clear
                    cell.backgroundView?.backgroundColor = .clear

                    return cell
                case .info:
                    let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailInfoCell.reuseIdentifier,
                                                             for: indexPath) as! TxDetailInfoCell
                    cell.update(with: item)
                    cell.selectionStyle = .none
                    cell.separatorInset = .init(top: 0, left: 2000, bottom: 0, right: 0)
                    return cell
                case .taxCategory:
                    let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailTaxCategoryCell.reuseIdentifier,
                                                             for: indexPath) as! TxDetailTaxCategoryCell
                    cell.update(with: item)
                    return cell

                case .explorer:
                    let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailActionCell.reuseIdentifier,
                                                             for: indexPath) as! TxDetailActionCell
                    cell.titleLabel.text = NSLocalizedString("View in Block Explorer", comment: "")
                    return cell
                }
        }
    }

    func reloadDataSource() {
        let detailFont = UIFont.preferredFont(forTextStyle: .caption1)
        let date = model.date
        let taxCategory = model.taxCategory

        currentSnapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        currentSnapshot.appendSections([.header, .info, .taxCategory, .explorer])
        currentSnapshot.appendItems([.header], toSection: .header)

        switch model.direction {
        case .moved:
            let fee: DWTitleDetailItem = model.fee(with: detailFont, tintColor: UIColor.label)!
            currentSnapshot.appendItems([
                .movedFrom(model.inputAddresses(with: detailFont)),
                .movedTo(model.outputAddresses(with: detailFont)),
            ], toSection: .info)
            currentSnapshot.appendItems([.networkFee(fee)], toSection: .info)
        case .sent:
            let fee: DWTitleDetailItem = model.fee(with: detailFont, tintColor: UIColor.label)!
            currentSnapshot.appendItems([
                .sentFrom(model.inputAddresses(with: detailFont)),
                .sentTo(model.outputAddresses(with: detailFont)),
            ], toSection: .info)
            currentSnapshot.appendItems([.networkFee(fee)], toSection: .info)
        case .received:
            currentSnapshot.appendItems([.receivedAt(model.outputAddresses(with: detailFont))], toSection: .info)
        case .notAccountFunds:
            break
        default:
            break;
        }

        currentSnapshot.appendItems([.date(date)], toSection: .info)
        currentSnapshot.appendItems([.taxCategory(taxCategory)], toSection: .taxCategory)
        currentSnapshot.appendItems([.explorer], toSection: .explorer)
        dataSource.apply(currentSnapshot, animatingDifferences: false)
        dataSource.defaultRowAnimation = .none
    }
}

// MARK: UITableViewDelegate

extension TXDetailViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let section = currentSnapshot.sectionIdentifiers[indexPath.section]

        switch section {
        case .taxCategory:
            model.toggleTaxCategoryOnCurrentTransaction()
            reloadDataSource()
            break
        case .explorer:
            viewInBlockExplorer()
        default:
            break
        }
    }

}

// MARK: - SuccessTxDetailViewControllerDelegate

@objc
protocol SuccessTxDetailViewControllerDelegate: AnyObject {
    func txDetailViewControllerDidFinish(controller: SuccessTxDetailViewController)
}

// MARK: - SuccessTxDetailViewController

@objc
class SuccessTxDetailViewController: TXDetailViewController, NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }

    // TODO: think how we can avoid storing contactItem here
    // passthrough context, not used internally
    @objc var contactItem: DWDPBasicUserItem?
    @objc weak var delegate: SuccessTxDetailViewControllerDelegate?

    internal var closeButton: DWActionButton!

    override func closeAction() {
        dismiss(animated: true) { [weak self] in
            if let wSelf = self {
                wSelf.delegate?.txDetailViewControllerDidFinish(controller: wSelf)
            }
        }
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        closeButton = DWActionButton(frame: .zero)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle(NSLocalizedString("Close", comment: ""), for: .normal)
        closeButton.addTarget(self, action: #selector(closeAction), for: .touchUpInside)
        view.addSubview(closeButton)
    }

    override func configureLayout() {
        let marginsGuide = view.layoutMarginsGuide

        NSLayoutConstraint.activate([
            closeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -15),
            closeButton.leadingAnchor.constraint(equalTo: marginsGuide.leadingAnchor),
            closeButton.trailingAnchor.constraint(equalTo: marginsGuide.trailingAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: 46),

            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -10),
        ])
    }
}
