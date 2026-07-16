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

@objc(DWTxDetailViewController)
class TXDetailViewController: BaseTxDetailsViewController {
    @objc var model: TxDetailModel!

    var dataSource: UITableViewDiffableDataSource<Section, Item>! = nil
    var currentSnapshot: NSDiffableDataSourceSnapshot<Section, Item>! = nil

    enum Section: CaseIterable {
        case header
        case info
        case taxCategory
        case rawTransaction
        case explorer
    }

    enum Item: Hashable {
        case header
        case receivedAt([DWTitleDetailItem])
        case sentFrom([DWTitleDetailItem])
        case sentTo([DWTitleDetailItem])
        case movedFrom([DWTitleDetailItem])
        case movedTo([DWTitleDetailItem])
        case networkFee(DWTitleDetailItem)
        case date(DWTitleDetailItem)
        case taxCategory(DWTitleDetailItem)
        case shieldedInfo(DWTitleDetailItem)
        case viewTransaction
        case copyRawTransaction
        case explorer

        /// Per-case identity strings — the diffable-identifier content. The
        /// leading case tag keeps two different cases with identical (notably
        /// empty) payloads distinct: `.sentFrom([])` and `.sentTo([])` used to
        /// hash to the same value, which is a duplicate-identifier crash once
        /// both land in one snapshot.
        private var identity: [String] {
            switch self {
            case .header: return ["Header"]
            case .receivedAt(let items): return ["ReceivedAt"] + Self.identity(of: items)
            case .sentFrom(let items): return ["SentFrom"] + Self.identity(of: items)
            case .sentTo(let items): return ["SentTo"] + Self.identity(of: items)
            case .movedFrom(let items): return ["MovedFrom"] + Self.identity(of: items)
            case .movedTo(let items): return ["MovedTo"] + Self.identity(of: items)
            case .networkFee(let item): return ["NetworkFee"] + Self.identity(of: [item])
            case .date(let item): return ["Date"] + Self.identity(of: [item])
            case .taxCategory(let item): return ["TaxCategory"] + Self.identity(of: [item])
            case .shieldedInfo(let item): return ["ShieldedInfo"] + Self.identity(of: [item])
            case .viewTransaction: return ["ViewTransaction"]
            case .copyRawTransaction: return ["CopyRawTransaction"]
            case .explorer: return ["Explorer"]
            }
        }

        private static func identity(of items: [DWTitleDetailItem]) -> [String] {
            items.flatMap { [$0.title ?? "", $0.plainDetail ?? $0.attributedDetail?.string ?? ""] }
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.identity == rhs.identity
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(identity)
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
        let swiftUIView = BottomSheet(
            title: NSLocalizedString("Select block explorer", comment: "Block explorer picker"),
            showBackButton: Binding<Bool>.constant(false)
        ) {
            BlockExplorerSelectionView { [weak self] explorer in
                guard let self = self else { return }
                
                self.dismiss(animated: true) {
                    guard let explorerURL = self.model.getExplorerURL(explorer: explorer) else {
                        return
                    }
                    
                    let vc = SFSafariViewController.dw_controller(with: explorerURL)
                    vc.modalPresentationStyle = .overFullScreen
                    vc.modalPresentationCapturesStatusBarAppearance = true
                    self.present(vc, animated: true)
                }
            }
        }
        
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(240)
        present(hostingController, animated: true, completion: nil)
    }

    /// Full consensus-field inspector for this transaction's stored raw bytes.
    private func viewRawTransaction() {
        let sheet = BottomSheet(
            title: NSLocalizedString("Transaction", comment: "Raw transaction inspector"),
            showBackButton: Binding<Bool>.constant(false)
        ) {
            RawTransactionView(txidWire: self.model.transaction.txHashData)
        }
        let hostingController = UIHostingController(rootView: sheet)
        present(hostingController, animated: true)
    }

    /// Copies the serialized transaction hex. A missing row (bytes not
    /// stored on this device) reports itself rather than copying nothing.
    private func copyRawTransaction() {
        if let hex = RawTransactionInspector.rawHex(txidWire: model.transaction.txHashData) {
            UIPasteboard.general.string = hex
            view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
        } else {
            view.dw_showInfoHUD(withText: NSLocalizedString("Raw transaction unavailable", comment: "Raw transaction inspector"))
        }
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

                case .rawTransaction:
                    let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailActionCell.reuseIdentifier,
                                                             for: indexPath) as! TxDetailActionCell
                    cell.titleLabel.text = item == .copyRawTransaction
                        ? NSLocalizedString("Copy Raw Transaction", comment: "Raw transaction inspector")
                        : NSLocalizedString("View Transaction", comment: "Raw transaction inspector")
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
        currentSnapshot.appendSections([.header, .info, .taxCategory, .rawTransaction, .explorer])
        currentSnapshot.appendItems([.header], toSection: .header)

        // Shielded transfers lead with their balance route + lock status.
        for item in model.shieldedInfo() {
            currentSnapshot.appendItems([.shieldedInfo(item)], toSection: .info)
        }

        // Empty address groups are skipped: SDK rows often carry no linked
        // input addresses and a sent row's external outputs may be unknown —
        // an empty .sentFrom/.sentTo would render a blank cell.
        switch model.direction {
        case .moved:
            let fee: DWTitleDetailItem = model.fee(with: detailFont, tintColor: UIColor.label)
            let movedFrom = model.inputAddresses(with: detailFont)
            if !movedFrom.isEmpty {
                currentSnapshot.appendItems([.movedFrom(movedFrom)], toSection: .info)
            }
            let movedTo = model.outputAddresses(with: detailFont)
            if !movedTo.isEmpty {
                currentSnapshot.appendItems([.movedTo(movedTo)], toSection: .info)
            }
            currentSnapshot.appendItems([.networkFee(fee)], toSection: .info)
        case .sent:
            let fee: DWTitleDetailItem = model.fee(with: detailFont, tintColor: UIColor.label)
            let sentFrom = model.inputAddresses(with: detailFont)
            if !sentFrom.isEmpty {
                currentSnapshot.appendItems([.sentFrom(sentFrom)], toSection: .info)
            }
            let sentTo = model.outputAddresses(with: detailFont)
            if !sentTo.isEmpty {
                currentSnapshot.appendItems([.sentTo(sentTo)], toSection: .info)
            }
            currentSnapshot.appendItems([.networkFee(fee)], toSection: .info)
        case .received:
            let receivedAt = model.outputAddresses(with: detailFont)
            if !receivedAt.isEmpty {
                currentSnapshot.appendItems([.receivedAt(receivedAt)], toSection: .info)
            }
        case .notAccountFunds:
            break
        default:
            break;
        }

        currentSnapshot.appendItems([.date(date)], toSection: .info)
        currentSnapshot.appendItems([.taxCategory(taxCategory)], toSection: .taxCategory)
        currentSnapshot.appendItems([.viewTransaction, .copyRawTransaction], toSection: .rawTransaction)
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
        case .rawTransaction:
            if let item = dataSource.itemIdentifier(for: indexPath) {
                switch item {
                case .viewTransaction: viewRawTransaction()
                case .copyRawTransaction: copyRawTransaction()
                default: break
                }
            }
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

    @objc weak var delegate: SuccessTxDetailViewControllerDelegate?

    internal var closeButton: ActionButton!

    override func closeAction() {
        dismiss(animated: true) { [weak self] in
            if let wSelf = self {
                wSelf.delegate?.txDetailViewControllerDidFinish(controller: wSelf)
            }
        }
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        closeButton = ActionButton()
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

// MARK: - SwiftUI wrapper
struct TXDetailVCWrapper: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    
    let tx: Transaction
    @Binding var navigateBack: Bool
    var onDismissed: (() -> Void)? = nil
    
    init(tx: Transaction, navigateBack: Binding<Bool>, onDismissed: (() -> Void)? = nil) {
        self.tx = tx
        self._navigateBack = navigateBack
        self.onDismissed = onDismissed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> some UIViewController {
        let vc = TXDetailViewController(model: .init(transaction: tx))
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        if navigateBack {
            context.coordinator.dismissView()
            navigateBack = false
            onDismissed?()
        }
    }
    
    class Coordinator: NSObject {
        var parent: TXDetailVCWrapper
        
        init(_ parent: TXDetailVCWrapper) {
            self.parent = parent
        }
        
        func dismissView() {
            DispatchQueue.main.async {
                self.parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }
}
