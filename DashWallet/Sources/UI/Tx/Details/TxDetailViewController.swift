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
import DashUIKit

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
        tableView.registerClass(for: TxDetailContactCell.self)
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
    /// Single-flight guard for the stuck-lock retry action.
    private var isRetryingAssetLock = false

    enum Section: CaseIterable {
        case header
        case info
        case taxCategory
        case recovery
        case rawTransaction
        case explorer
        case swapExplorer
    }

    enum Item: Hashable {
        case header
        case receivedAt([DWTitleDetailItem])
        case sentFrom([DWTitleDetailItem])
        case sentTo([DWTitleDetailItem])
        case movedFrom([DWTitleDetailItem])
        case movedTo([DWTitleDetailItem])
        case contact(String, TxDetailModel.ContactParty)
        case networkFee(DWTitleDetailItem)
        case date(DWTitleDetailItem)
        case taxCategory(DWTitleDetailItem)
        case shieldedInfo(DWTitleDetailItem)
        case rebroadcast(String)
        case removeUnconfirmed
        case viewTransaction
        case copyRawTransaction
        case explorer
        case swapExplorer(String)

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
            case .contact(let title, let party): return ["Contact", title, party.name, party.secondaryName ?? "", party.avatarURL ?? ""]
            case .networkFee(let item): return ["NetworkFee"] + Self.identity(of: [item])
            case .date(let item): return ["Date"] + Self.identity(of: [item])
            case .taxCategory(let item): return ["TaxCategory"] + Self.identity(of: [item])
            case .shieldedInfo(let item): return ["ShieldedInfo"] + Self.identity(of: [item])
            case .rebroadcast(let title): return ["Rebroadcast", title]
            case .removeUnconfirmed: return ["RemoveUnconfirmed"]
            case .viewTransaction: return ["ViewTransaction"]
            case .copyRawTransaction: return ["CopyRawTransaction"]
            case .explorer: return ["Explorer"]
            case .swapExplorer(let title): return ["SwapExplorer", title]
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

        // Dash DEX swap legs get an extra "View NEAR/Maya Explorer" action; the order lookup
        // is async (DAO reads), so resolve then rebuild the rows when it lands.
        model.resolveSwapExplorerLink { [weak self] in
            self?.reloadDataSource()
        }

        // A received transaction whose fee this wallet can't derive asks the
        // block explorer for it; the row reads "Paid by sender" until (and
        // unless) an answer lands.
        model.resolveExplorerFee { [weak self] in
            self?.reloadDataSource()
        }
    }
}

extension TXDetailViewController {
    private func viewInBlockExplorer() {
        let swiftUIView = DashUIKit.BottomSheet(
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

    /// Opens the Dash DEX (NEAR/Maya) explorer for a swap transaction in an in-app browser.
    private func openSwapExplorer() {
        guard let link = model.swapExplorerLink else { return }
        let vc = SFSafariViewController.dw_controller(with: link.url)
        vc.modalPresentationStyle = .overFullScreen
        vc.modalPresentationCapturesStatusBarAppearance = true
        present(vc, animated: true)
    }

    /// Full consensus-field inspector for this transaction's stored raw bytes.
    private func viewRawTransaction() {
        let sheet = DashUIKit.BottomSheet(
            title: NSLocalizedString("Transaction", comment: "Raw transaction inspector"),
            showBackButton: Binding<Bool>.constant(false)
        ) {
            RawTransactionView(txidWire: self.model.transaction.txHashData)
        }
        let hostingController = UIHostingController(rootView: sheet)
        present(hostingController, animated: true)
    }

    /// Retry the stuck asset-lock transfer on its EXISTING outpoint —
    /// `AssetLockRecoveryService` drives the SDK resume path
    /// (rebroadcast if needed, IS/CL wait, Platform submit). The await
    /// spans the whole recovery, so the HUD honestly covers a
    /// several-minute worst case rather than claiming early success.
    private func retryStuckAssetLock() {
        guard !isRetryingAssetLock, let retry = model.stuckAssetLockRetry else { return }
        isRetryingAssetLock = true
        let txidWire = model.transaction.txHashData
        view.dw_showProgressHUD(withMessage: NSLocalizedString("Retrying transfer…", comment: "Asset-lock retry in progress"))
        Task { [weak self] in
            defer {
                self?.isRetryingAssetLock = false
                self?.view.dw_hideProgressHUD()
            }
            do {
                try await AssetLockRecoveryService().retry(
                    fundingTypeRaw: retry.fundingTypeRaw,
                    txidWire: txidWire,
                    vout: retry.vout)
                self?.view.dw_showInfoHUD(withText: NSLocalizedString("Transfer completed", comment: "Asset-lock retry finished"))
            } catch DWIdentityAuthorizer.AuthError.cancelled {
                // Backing out of the PIN prompt is not an error state.
            } catch {
                self?.presentRetryFailure(error)
            }
            // Re-derive the rows either way — even a failed retry can
            // have advanced the lock (e.g. broadcast landed, Platform
            // submit didn't), and the status row should say so.
            self?.reloadDataSource()
        }
    }

    private func presentRetryFailure(_ error: Error) {
        let alert = UIAlertController(
            title: NSLocalizedString("Couldn't complete the transfer", comment: "Asset-lock retry failed"),
            message: error.localizedDescription,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    /// Spell out exactly what removal does before anything is touched:
    /// a block-explorer check first, local-only deletion, and the
    /// rescan safety net that restores the transaction if the explorer
    /// was wrong.
    private func confirmRemoveUnconfirmed() {
        let alert = UIAlertController(
            title: NSLocalizedString("Remove this transaction?", comment: "Remove never-accepted transaction: confirmation title"),
            message: NSLocalizedString("The wallet first checks a block explorer. A transaction known to the network — whether it is waiting in the mempool or already included in a block — is never removed. If the transaction isn't found, it is deleted from this wallet on this device, and the coins it was trying to spend become available again. The wallet then rescans recent blocks as a safety check. Nothing is sent to the network.", comment: "Remove never-accepted transaction: confirmation body"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Remove Transaction", comment: "Remove never-accepted transaction: destructive confirm button"),
            style: .destructive) { [weak self] _ in
                self?.performRemoveUnconfirmed()
            })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    private func performRemoveUnconfirmed() {
        guard !isRetryingAssetLock else { return }
        isRetryingAssetLock = true
        let txidWire = model.transaction.txHashData
        view.dw_showProgressHUD(withMessage: NSLocalizedString("Removing transaction…", comment: "Remove never-accepted transaction: progress"))
        Task { [weak self] in
            defer {
                self?.isRetryingAssetLock = false
                self?.view.dw_hideProgressHUD()
            }
            do {
                let rescanArmed = try await UnconfirmedTransactionRemover().remove(txidWire: txidWire)
                // Never claim the rescan safety net ran when it didn't —
                // point at the manual Rescan Filters action instead.
                self?.view.dw_showInfoHUD(withText: rescanArmed
                    ? NSLocalizedString("Transaction removed", comment: "Remove never-accepted transaction: success")
                    : NSLocalizedString("Transaction removed — rescan couldn't start, run Rescan Filters in Core Sync Status", comment: "Remove never-accepted transaction: removed but the recovery rescan did not arm"))
                // The row this sheet describes no longer exists.
                self?.closeAction()
            } catch UnconfirmedTransactionRemover.RemovalError.transactionOnChain {
                self?.presentRemovalRefused()
            } catch {
                let alert = UIAlertController(
                    title: NSLocalizedString("Couldn't remove the transaction", comment: "Remove never-accepted transaction: failure title"),
                    message: error.localizedDescription,
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
                self?.present(alert, animated: true)
            }
        }
    }

    /// The explorer knows the transaction, either from the mempool or a
    /// block. Removal is refused until the local wallet catches up.
    private func presentRemovalRefused() {
        let alert = UIAlertController(
            title: NSLocalizedString("Transaction is known to the network", comment: "Remove never-accepted transaction: refused because the explorer found it"),
            message: NSLocalizedString("A block explorer reports that this transaction is known to the Dash network. It may still be waiting in the mempool or may already be included in a block, so it wasn't removed. The wallet will update its confirmation automatically once it is included in a synchronized block.", comment: "Remove never-accepted transaction: refusal body"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        present(alert, animated: true)
        reloadDataSource()
    }

    /// Opens the counterparty's contact profile. The contact is resolved
    /// from the contacts service's live snapshot; a payment whose contact is
    /// no longer in it says so rather than silently doing nothing.
    private func openContactProfile(_ party: TxDetailModel.ContactParty) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let contact = SwiftDashSDKContactsService.shared.contactItem(for: party.identityId) else {
                self.view.dw_showInfoHUD(withText: NSLocalizedString("Contact is no longer available",
                                                                     comment: "DashPay Contacts"))
                return
            }
            self.present(UIHostingController(rootView: ContactProfileSheet(contact: contact)), animated: true)
        }
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
                    if case .contact(let title, let party) = item {
                        let cell = tableView.dequeueReusableCell(type: TxDetailContactCell.self, for: indexPath)
                        cell.update(title: title, contact: party)
                        cell.separatorInset = .init(top: 0, left: 2000, bottom: 0, right: 0)
                        return cell
                    }
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

                case .recovery:
                    let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailActionCell.reuseIdentifier,
                                                             for: indexPath) as! TxDetailActionCell
                    if case .rebroadcast(let title) = item {
                        cell.titleLabel.text = title
                        cell.titleLabel.textColor = .dw_label()
                    } else if item == .removeUnconfirmed {
                        cell.titleLabel.text = NSLocalizedString("Remove if Not on Network", comment: "Delete a never-accepted transaction from local wallet state")
                        cell.titleLabel.textColor = .systemRed
                    }
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

                case .swapExplorer:
                    let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailActionCell.reuseIdentifier,
                                                             for: indexPath) as! TxDetailActionCell
                    if case .swapExplorer(let title) = item {
                        cell.titleLabel.text = title
                    }
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

        // A DashPay payment's counterparty is a contact row rather than an
        // address group, appended in the slot that group would have occupied
        // (see `TxDetailModel.hasSourceUser` / `hasDestinationUser`), so the
        // section still reads source-then-destination.
        let appendContact: () -> Void = { [weak self] in
            guard let self, let party = self.model.contactParty else { return }
            self.currentSnapshot.appendItems([.contact(self.model.contactRowTitle, party)], toSection: .info)
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
            appendContact()
            currentSnapshot.appendItems([.networkFee(fee)], toSection: .info)
        case .received:
            appendContact()
            let receivedAt = model.outputAddresses(with: detailFont)
            if !receivedAt.isEmpty {
                currentSnapshot.appendItems([.receivedAt(receivedAt)], toSection: .info)
            }
            // Incoming rows carry the fee row too — it reads "Paid by sender"
            // unless a real fee was recorded for this transaction.
            currentSnapshot.appendItems([.networkFee(model.fee(with: detailFont, tintColor: UIColor.label))],
                                        toSection: .info)
        case .notAccountFunds:
            break
        }

        currentSnapshot.appendItems([.date(date)], toSection: .info)
        currentSnapshot.appendItems([.taxCategory(taxCategory)], toSection: .taxCategory)
        // A funding asset lock parked mid-transfer gets a retry action.
        // The section is inserted (not pre-appended) so the empty state
        // adds no phantom section spacing.
        if let retry = model.stuckAssetLockRetry {
            currentSnapshot.insertSections([.recovery], afterSection: .taxCategory)
            currentSnapshot.appendItems([.rebroadcast(retry.actionTitle)], toSection: .recovery)
            if retry.supportsRemoval {
                currentSnapshot.appendItems([.removeUnconfirmed], toSection: .recovery)
            }
        } else if model.supportsUnconfirmedRemoval {
            // Any other transaction stuck in mempool context (a
            // network-dropped classic send — e.g. a stalled CoinJoin sweep
            // chunk) gets the removal action alone: there is no retry
            // route for it, but deleting the local row frees its inputs.
            currentSnapshot.insertSections([.recovery], afterSection: .taxCategory)
            currentSnapshot.appendItems([.removeUnconfirmed], toSection: .recovery)
        }
        currentSnapshot.appendItems([.viewTransaction, .copyRawTransaction], toSection: .rawTransaction)
        currentSnapshot.appendItems([.explorer], toSection: .explorer)
        if let swapLink = model.swapExplorerLink {
            currentSnapshot.appendSections([.swapExplorer])
            currentSnapshot.appendItems([.swapExplorer(swapLink.title)], toSection: .swapExplorer)
        }
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
        case .info:
            if case .contact(_, let party)? = dataSource.itemIdentifier(for: indexPath) {
                openContactProfile(party)
            }
        case .taxCategory:
            model.toggleTaxCategoryOnCurrentTransaction()
            reloadDataSource()
            break
        case .recovery:
            if dataSource.itemIdentifier(for: indexPath) == .removeUnconfirmed {
                confirmRemoveUnconfirmed()
            } else {
                retryStuckAssetLock()
            }
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
        case .swapExplorer:
            openSwapExplorer()
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
