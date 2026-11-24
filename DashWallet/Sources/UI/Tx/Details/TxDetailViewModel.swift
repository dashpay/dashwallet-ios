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

import Combine
import DashUIKit
import UIKit

// MARK: - TxDetailViewModel

/// What the transaction details screen shows, and the actions it runs: the
/// rows rebuilt from `TxDetailModel` whenever what they read changes, the
/// tax category toggle, the stuck-transfer retry and the local removal of a
/// transaction the network never accepted.
@MainActor
final class TxDetailViewModel: ObservableObject {

    enum Section: Hashable {
        case header
        case info
        case taxCategory
        case recovery
        case rawTransaction
        case explorer
        case swapExplorer
    }

    enum Row: Hashable {
        /// A titled group of values: addresses, fee, date, shielded status.
        case values(title: String, values: [Value])
        case contact(title: String, party: TxDetailModel.ContactParty)
        case taxCategory(title: String, category: String)
        case retry(title: String)
        case removeUnconfirmed
        case viewTransaction
        case copyRawTransaction
        case explorer
        case swapExplorer(title: String)
    }

    /// One value of a row: plain text, or an attributed string carrying the
    /// Dash symbol.
    enum Value: Hashable {
        case plain(String)
        case attributed(NSAttributedString)
    }

    struct SectionContent: Hashable {
        let section: Section
        let rows: [Row]
    }

    /// An alert the screen shows; `onConfirm` is the destructive action of a
    /// confirmation, `onDismiss` runs when the only button is tapped.
    struct Alert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var confirmTitle: String?
        var onConfirm: (() -> Void)?
        var onDismiss: (() -> Void)?
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let style: ToastStyle
        let message: String

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    let model: TxDetailModel
    @Published private(set) var sections: [SectionContent] = []
    /// Bumped with every rebuild, so the header (whose content can change
    /// without its row changing) redraws.
    @Published private(set) var revision = 0
    @Published var alert: Alert?
    @Published var toast: Toast?
    /// The message of the progress overlay while a retry or a removal runs.
    @Published private(set) var progressMessage: String?

    /// Asks the host to close the screen, with a message to show where the
    /// user lands (this screen's own toast would leave with it).
    var onClose: (_ message: Toast?) -> Void = { _ in }

    private let recoveryInputs: AnyPublisher<TxDetailModel.RecoveryInput, Never>
    private var recoveryObservation: AnyCancellable?
    private var started = false
    /// Single-flight guard shared by the retry and the removal.
    private var isBusy = false

    init(model: TxDetailModel,
         recoveryInputs: AnyPublisher<TxDetailModel.RecoveryInput, Never> = TxDetailModel.recoveryInputChanges()) {
        self.model = model
        self.recoveryInputs = recoveryInputs
    }

    /// Builds the rows and starts following what they read. Once; the screen
    /// calls it when it appears.
    func start() {
        guard !started else { return }
        started = true
        rebuild()

        // Dash DEX swap legs get an extra "View NEAR/Maya Explorer" action; the
        // order lookup is async, so the rows are rebuilt when it lands.
        model.resolveSwapExplorerLink { [weak self] in self?.rebuild() }

        // A received transaction whose fee this wallet can't derive asks the
        // block explorer for it; the row reads "Paid by sender" until (and
        // unless) an answer lands.
        model.resolveExplorerFee { [weak self] in self?.rebuild() }

        // The rows are rebuilt on the next main-queue turn after a recovery
        // input changes.
        recoveryObservation = recoveryInputs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }

        // A swap order shown before its Dash transaction exists changes status
        // while the screen is up.
        model.observeSwapOrderPlaceholder { [weak self] in self?.rebuild() }
    }

    // MARK: Rows

    func rebuild() {
        let detailFont = UIFont.preferredFont(forTextStyle: .caption1)

        // A swap order shown before its Dash transaction exists has nothing to
        // categorise for tax, no raw transaction to inspect and nothing to look
        // up on a block explorer, so those sections are left out.
        let hasTransaction = model.swapOrderPlaceholder == nil

        var info: [Row] = model.shieldedInfo().map { Self.row($0) }

        // A DashPay payment's counterparty is a contact row rather than an
        // address group, in the slot that group would have occupied, so the
        // section still reads source-then-destination.
        let contact: [Row] = model.contactParty.map { [.contact(title: model.contactRowTitle, party: $0)] } ?? []

        // Empty address groups are skipped: SDK rows often carry no linked
        // input addresses, and a sent row's external outputs may be unknown.
        let inputs = Self.row(model.inputAddresses(with: detailFont))
        let outputs = Self.row(model.outputAddresses(with: detailFont))
        let fee = Self.row(model.fee(with: detailFont, tintColor: .label))
        switch model.direction {
        case .moved:
            info += [inputs, outputs].compactMap { $0 } + [fee]
        case .sent:
            info += [inputs, outputs].compactMap { $0 } + contact + [fee]
        case .received:
            // Incoming rows carry the fee row too: it reads "Paid by sender"
            // unless a real fee was recorded for this transaction.
            info += contact + [outputs].compactMap { $0 } + [fee]
        case .notAccountFunds:
            break
        }
        info.append(Self.row(model.date))

        var sections = [SectionContent(section: .header, rows: []), SectionContent(section: .info, rows: info)]
        if hasTransaction {
            let category = model.taxCategory
            sections.append(SectionContent(section: .taxCategory, rows: [
                .taxCategory(title: category.title ?? "", category: category.plainDetail ?? ""),
            ]))
        }

        // A funding asset lock parked mid-transfer gets a retry action, and the
        // removal applies to some stuck transactions (see
        // `TxDetailModel.offersUnconfirmedRemoval`). A Buy swap placeholder has
        // nothing to recover.
        let actions = hasTransaction ? model.recoveryActions : (retry: nil, offersRemoval: false)
        var recovery: [Row] = actions.retry.map { [.retry(title: $0.actionTitle)] } ?? []
        if actions.offersRemoval {
            recovery.append(.removeUnconfirmed)
        }
        if !recovery.isEmpty {
            sections.append(SectionContent(section: .recovery, rows: recovery))
        }
        if hasTransaction {
            sections.append(SectionContent(section: .rawTransaction, rows: [.viewTransaction, .copyRawTransaction]))
            sections.append(SectionContent(section: .explorer, rows: [.explorer]))
        }
        if let swapLink = model.swapExplorerLink {
            sections.append(SectionContent(section: .swapExplorer, rows: [.swapExplorer(title: swapLink.title)]))
        }

        self.sections = sections
        revision += 1
    }

    private static func value(_ item: DWTitleDetailItem) -> Value {
        if let attributed = item.attributedDetail {
            return .attributed(attributed)
        }
        return .plain(item.plainDetail ?? "")
    }

    private static func row(_ item: DWTitleDetailItem) -> Row {
        .values(title: item.title ?? "", values: [value(item)])
    }

    private static func row(_ items: [DWTitleDetailItem]) -> Row? {
        guard let first = items.first else { return nil }
        return .values(title: first.title ?? "", values: items.map(value))
    }

    // MARK: Actions

    func toggleTaxCategory() {
        model.toggleTaxCategoryOnCurrentTransaction()
        rebuild()
    }

    /// The serialized transaction hex; nil when its bytes are not stored on
    /// this device.
    func rawTransactionHex() -> String? {
        RawTransactionInspector.rawHex(txidWire: model.transaction.txHashData)
    }

    /// Retries the stuck asset-lock transfer on its existing outpoint:
    /// `AssetLockRecoveryService` drives the SDK resume path (rebroadcast if
    /// needed, IS/CL wait, Platform submit). The await spans the whole
    /// recovery, so the progress overlay covers a several-minute worst case
    /// rather than claiming early success.
    func retryStuckAssetLock() {
        guard !isBusy else { return }
        // `currentRetry`, not `stuckAssetLockRetry`: a tap on a row built just
        // before a removal began must not retry during its reload.
        guard let retry = model.currentRetry else {
            // The row was built before a transfer started consuming this lock:
            // say so and drop the row rather than ignore the tap.
            if model.isAssetLockRetryInFlight {
                toast = Toast(style: .info, message: ShieldedTransferCoordinator.CoordinatorError.assetLockInFlight.errorDescription ?? "")
                rebuild()
            } else if ShieldedAssetLocksInFlight.shared.isRemovalInProgress {
                toast = Toast(style: .info, message: ShieldedAssetLocksInFlight.walletReloadingMessage)
                rebuild()
            }
            return
        }
        isBusy = true
        let txidWire = model.transaction.txHashData
        progressMessage = NSLocalizedString("Retrying transfer…", comment: "Asset-lock retry in progress")
        Task { [weak self] in
            // The outcome is shown only after the overlay is down: the retry
            // can run for minutes, and a toast raised underneath it would
            // expire before the user could read it.
            var toast: Toast?
            var failure: Error?
            do {
                let outcome = try await AssetLockRecoveryService().retry(
                    fundingTypeRaw: retry.fundingTypeRaw,
                    txidWire: txidWire,
                    vout: retry.vout)
                AssetLockRetryLog.logOutcome(
                    "outcome=\(outcome)", event: "single", txidWire: txidWire, vout: retry.vout,
                    fundingTypeRaw: retry.fundingTypeRaw, statusBeforeRaw: retry.statusRaw)
                self?.model.recordRecoveryOutcome(outcome)
                switch outcome {
                case .completed:
                    toast = Toast(style: .success, message: NSLocalizedString("Transfer completed", comment: "Asset-lock retry finished"))
                case .addedToOwnShielded:
                    // Finished, but to the wallet's own Shielded address: the
                    // lock had no recorded recipient, so this screen cannot say
                    // the transfer it was built for completed.
                    toast = Toast(style: .info, message: NSLocalizedString(
                        "Funds added to your Shielded balance",
                        comment: "A transfer whose recipient was not on record was finished to the wallet's own Shielded balance"))
                case .completionUnconfirmed:
                    // Platform said the outpoint is already spent, but that
                    // report is not quorum-authenticated: say only what was
                    // reported. The row keeps its retry on purpose.
                    toast = Toast(style: .info, message: NSLocalizedString("Already spent — nothing to transfer", comment: "Asset-lock retry found the lock already consumed"))
                case .submittedAwaitingSync:
                    // Accepted, result not readable yet. Re-submitting risks a
                    // double-spend, so point at the sync rather than inviting
                    // another tap.
                    toast = Toast(style: .info, message: NSLocalizedString("Submitted — waiting for the network to confirm", comment: "Asset-lock retry submitted but its result could not be read back"))
                }
            } catch DWIdentityAuthorizer.AuthError.cancelled {
                // Backing out of the PIN prompt is not an error state.
                AssetLockRetryLog.logOutcome(
                    "outcome=cancelled", event: "single", txidWire: txidWire, vout: retry.vout,
                    fundingTypeRaw: retry.fundingTypeRaw, statusBeforeRaw: retry.statusRaw)
            } catch AssetLockRecoveryService.RecoveryError.inProgress(let message) {
                // Refused because another attempt is consuming the lock or a
                // removal is reloading the wallet: nothing failed.
                toast = Toast(style: .info, message: message)
            } catch {
                failure = error
                // The alert shows only the text; the log keeps the typed case.
                AssetLockRetryLog.logFailure(
                    error, event: "single", txidWire: txidWire, vout: retry.vout,
                    fundingTypeRaw: retry.fundingTypeRaw, statusBeforeRaw: retry.statusRaw)
            }

            guard let self else { return }
            self.isBusy = false
            self.progressMessage = nil
            if let toast { self.toast = toast }
            if let failure {
                self.alert = Alert(
                    title: NSLocalizedString("Couldn't complete the transfer", comment: "Asset-lock retry failed"),
                    message: failure.localizedDescription)
            }
            // Re-derive the rows either way: even a failed retry can have
            // advanced the lock, and the status row should say so.
            self.rebuild()
        }
    }

    /// Spells out what removal does before anything is touched: a
    /// block-explorer check first, local-only deletion, and the rescan safety
    /// net that restores the transaction if the explorer was wrong.
    func confirmRemoveUnconfirmed() {
        alert = Alert(
            title: NSLocalizedString("Remove this transaction?", comment: "Remove never-accepted transaction: confirmation title"),
            message: NSLocalizedString("The wallet first checks a block explorer. A transaction known to the network — whether it is waiting in the mempool or already included in a block — is never removed. If the transaction isn't found, it is deleted from this wallet on this device, and the coins it was trying to spend become available again. The wallet then rescans recent blocks as a safety check. Nothing is sent to the network.", comment: "Remove never-accepted transaction: confirmation body"),
            confirmTitle: NSLocalizedString("Remove Transaction", comment: "Remove never-accepted transaction: destructive confirm button"),
            onConfirm: { [weak self] in self?.removeUnconfirmed() })
    }

    private func removeUnconfirmed() {
        guard !isBusy else { return }
        isBusy = true
        let txidWire = model.transaction.txHashData
        progressMessage = NSLocalizedString("Removing transaction…", comment: "Remove never-accepted transaction: progress")
        Task { [weak self] in
            defer {
                self?.isBusy = false
                self?.progressMessage = nil
            }
            do {
                let outcome = try await UnconfirmedTransactionRemover().remove(txidWire: txidWire)
                switch outcome {
                case .rescanArmed:
                    // The row this screen describes no longer exists.
                    self?.onClose(Toast(style: .success, message: NSLocalizedString("Transaction removed", comment: "Remove never-accepted transaction: success")))
                case .rescanUnavailable:
                    // Never claim the rescan safety net ran when it didn't.
                    self?.onClose(Toast(style: .info, message: NSLocalizedString("Transaction removed — rescan couldn't start, run Rescan Filters in Core Sync Status", comment: "Remove never-accepted transaction: removed but the recovery rescan did not arm")))
                case .runtimeStopped:
                    // Both steps are named, because restarting the runtime does
                    // not replay this removal's rescan; the screen closes only
                    // once the user has read it.
                    self?.alert = Alert(
                        title: NSLocalizedString("Transaction removed, but the wallet stopped", comment: "Remove never-accepted transaction: removed but the runtime reload left the wallet stopped"),
                        message: NSLocalizedString("The transaction was deleted from this device. Reloading the wallet didn't finish, so the wallet is stopped and the rescan that double-checks the blockchain never ran.\n\nRestart the wallet — reopen the app, or tap Sync Now in Sync Info — and then run Rescan Filters in Core Sync Status. Restarting alone does not repeat the rescan.", comment: "Remove never-accepted transaction: both recovery steps after a failed runtime reload"),
                        onDismiss: { [weak self] in self?.onClose(nil) })
                }
            } catch UnconfirmedTransactionRemover.RemovalError.transactionOnChain {
                // The explorer knows the transaction, from the mempool or a
                // block: refused until the local wallet catches up.
                self?.alert = Alert(
                    title: NSLocalizedString("Transaction is known to the network", comment: "Remove never-accepted transaction: refused because the explorer found it"),
                    message: NSLocalizedString("A block explorer reports that this transaction is known to the Dash network. It may still be waiting in the mempool or may already be included in a block, so it wasn't removed. The wallet will update its confirmation automatically once it is included in a synchronized block.", comment: "Remove never-accepted transaction: refusal body"))
                self?.rebuild()
            } catch UnconfirmedTransactionRemover.RemovalError.removalInProgress {
                // Another removal is reloading the wallet: nothing failed.
                self?.toast = Toast(style: .info, message: ShieldedAssetLocksInFlight.walletReloadingMessage)
                self?.rebuild()
            } catch {
                self?.alert = Alert(
                    title: NSLocalizedString("Couldn't remove the transaction", comment: "Remove never-accepted transaction: failure title"),
                    message: error.localizedDescription)
            }
        }
    }
}
