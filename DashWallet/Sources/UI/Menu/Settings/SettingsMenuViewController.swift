//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

@objc(DWSettingsMenuViewControllerDelegate)
protocol SettingsMenuViewControllerDelegate: AnyObject {
    func settingsMenuViewControllerDidRescanBlockchain(_ controller: SettingsMenuViewController)
}

@objc(DWSettingsMenuViewController)
class SettingsMenuViewController: UIViewController, DWLocalCurrencyViewControllerDelegate {
    
    @objc weak var delegate: SettingsMenuViewControllerDelegate?
    
    private lazy var model: DWSettingsMenuModel = DWSettingsMenuModel()
    private var formController: DWFormTableViewController!
    private var localCurrencyCellModel: DWSelectorFormCellModel!
    private var switchNetworkCellModel: DWSelectorFormCellModel!
    
    init() {
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("Settings", comment: "")
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .dw_secondaryBackground()
        
        formController = DWFormTableViewController(style: .plain)
        formController.setSections(sections, placeholderText: nil)
        
        dw_embedChild(formController)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - LocalCurrencyViewControllerDelegate
    
    func localCurrencyViewController(_ controller: DWLocalCurrencyViewController, didSelectCurrency currencyCode: String) {
        updateLocalCurrencyCellModel()
        navigationController?.popViewController(animated: true)
    }
    
    func localCurrencyViewControllerDidCancel(_ controller: DWLocalCurrencyViewController) {
        assertionFailure("Not supported")
    }
    
    // MARK: - Private
    
    private var items: [DWBaseFormCellModel] {
        var items: [DWBaseFormCellModel] = []
        
        let localCurrencyCell = DWSelectorFormCellModel(title: NSLocalizedString("Local Currency", comment: ""))
        localCurrencyCellModel = localCurrencyCell
        updateLocalCurrencyCellModel()
        localCurrencyCell.accessoryType = .disclosureIndicator
        localCurrencyCell.didSelectBlock = { [weak self] _, _ in
            self?.showCurrencySelector()
        }
        items.append(localCurrencyCell)
        
        let notificationsCell = DWSwitcherFormCellModel(title: NSLocalizedString("Enable Receive Notifications", comment: ""))
        notificationsCell.isOn = model.notificationsEnabled
        notificationsCell.didChangeValueBlock = { [weak self] cellModel in
            self?.model.notificationsEnabled = cellModel.isOn
        }
        items.append(notificationsCell)
        
        let networkCell = DWSelectorFormCellModel(title: NSLocalizedString("Network", comment: ""))
        switchNetworkCellModel = networkCell
        updateSwitchNetworkCellModel()
        networkCell.accessoryType = .disclosureIndicator
        networkCell.didSelectBlock = { [weak self] _, indexPath in
            guard let self = self else { return }
            let tableView = self.formController.tableView!
            guard let cell = tableView.cellForRow(at: indexPath) else { return }
            self.showChangeNetwork(from: tableView, sourceRect: cell.frame)
        }
        items.append(networkCell)
        
        let rescanCell = DWSelectorFormCellModel(title: NSLocalizedString("Rescan Blockchain", comment: ""))
        rescanCell.didSelectBlock = { [weak self] _, indexPath in
            guard let self = self else { return }
            let tableView = self.formController.tableView!
            guard let cell = tableView.cellForRow(at: indexPath) else { return }
            self.showWarningAboutReclassifiedTransactions(tableView, sourceRect: cell.frame)
        }
        items.append(rescanCell)
        
        let aboutCell = DWSelectorFormCellModel(title: NSLocalizedString("About", comment: ""))
        aboutCell.accessoryType = .disclosureIndicator
        aboutCell.didSelectBlock = { [weak self] _, _ in
            self?.showAboutController()
        }
        items.append(aboutCell)
        
        #if DASHPAY
        let coinJoinCell = DWSelectorFormCellModel(title: NSLocalizedString("CoinJoin", comment: ""))
        coinJoinCell.didSelectBlock = { [weak self] _, _ in
            self?.showCoinJoinController()
        }
        items.append(coinJoinCell)
        
        let votingCell = DWSwitcherFormCellModel(title: "Enable Voting")
        votingCell.isOn = VotingPrefsWrapper.getIsEnabled()
        votingCell.didChangeValueBlock = { cellModel in
            VotingPrefsWrapper.setIsEnabled(value: cellModel.isOn)
        }
        items.append(votingCell)
        #endif
        
        return items
    }
    
    private var sections: [DWFormSectionModel] {
        return items.map { item in
            let section = DWFormSectionModel()
            section.items = [item]
            return section
        }
    }
    
    private func updateLocalCurrencyCellModel() {
        localCurrencyCellModel.subTitle = model.localCurrencyCode
    }
    
    private func updateSwitchNetworkCellModel() {
        switchNetworkCellModel.subTitle = model.networkName
    }
    
    private func rescanBlockchainAction(from sourceView: UIView, sourceRect: CGRect) {
        DWSettingsMenuModel.rescanBlockchainAction(from: self, sourceView: sourceView, sourceRect: sourceRect) { [weak self] confirmed in
            if confirmed {
                self?.delegate?.settingsMenuViewControllerDidRescanBlockchain(self!)
            }
        }
    }
    
    private func showCurrencySelector() {
        let controller = DWLocalCurrencyViewController(navigationAppearance: .default, presentationMode: .screen, currencyCode: nil)
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }
    
    private func showAboutController() {
        let aboutViewController = DWAboutViewController.create()
        navigationController?.pushViewController(aboutViewController, animated: true)
    }
    
    private func showCoinJoinController() {
        let vc: UIViewController
        
        if CoinJoinViewModel.shared.infoShown {
            vc = CoinJoinLevelsViewController.controller()
        } else {
            vc = CoinJoinInfoViewController.controller()
        }
        
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func showChangeNetwork(from sourceView: UIView, sourceRect: CGRect) {
        let actionSheet = UIAlertController(title: NSLocalizedString("Network", comment: ""), message: nil, preferredStyle: .actionSheet)
        
        let mainnetAction = UIAlertAction(title: NSLocalizedString("Mainnet", comment: ""), style: .default) { [weak self] _ in
            DWSettingsMenuModel.switchToMainnet { success in
                if success {
                    self?.updateSwitchNetworkCellModel()
                }
            }
        }
        
        let testnetAction = UIAlertAction(title: NSLocalizedString("Testnet", comment: ""), style: .default) { [weak self] _ in
            DWSettingsMenuModel.switchToTestnet { success in
                if success {
                    self?.updateSwitchNetworkCellModel()
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        
        actionSheet.addAction(mainnetAction)
        actionSheet.addAction(testnetAction)
        actionSheet.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            actionSheet.popoverPresentationController?.sourceView = sourceView
            actionSheet.popoverPresentationController?.sourceRect = sourceRect
        }
        
        present(actionSheet, animated: true, completion: nil)
    }
    
    private func showWarningAboutReclassifiedTransactions(_ sourceView: UIView, sourceRect: CGRect) {
        let actionSheet = UIAlertController(
            title: NSLocalizedString("You will lose all your manually reclassified transactions types", comment: ""),
            message: NSLocalizedString("If you would like to save manually reclassified types for transactions you should export a CSV transaction file.", comment: ""),
            preferredStyle: .actionSheet)
        
        let continueAction = UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default) { [weak self] _ in
            self?.rescanBlockchainAction(from: sourceView, sourceRect: sourceRect)
        }
        
        let exportAction = UIAlertAction(title: NSLocalizedString("Export CSV", comment: ""), style: .default) { [weak self] _ in
            self?.exportTransactionsInCSV()
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        
        actionSheet.addAction(exportAction)
        actionSheet.addAction(continueAction)
        actionSheet.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            actionSheet.popoverPresentationController?.sourceView = sourceView
            actionSheet.popoverPresentationController?.sourceRect = sourceRect
        }
        
        present(actionSheet, animated: true, completion: nil)
    }
    
    private func exportTransactionsInCSV() {
        view.dw_showProgressHUD(withMessage: NSLocalizedString("Generating CSV Report", comment: ""))
        
        DWSettingsMenuModel.generateCSVReport { [weak self] fileName, file in
            self?.view.dw_hideProgressHUD()
            
            let activityViewController = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            activityViewController.setValue(fileName, forKey: "subject")
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityViewController.popoverPresentationController?.sourceView = self?.view
                activityViewController.popoverPresentationController?.sourceRect = self?.view.bounds ?? .zero
            }
            
            self?.present(activityViewController, animated: true, completion: nil)
        } errorHandler: { [weak self] error in
            self?.view.dw_hideProgressHUD()
            self?.dw_displayErrorModally(error)
        }
    }
}
