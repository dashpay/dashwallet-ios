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
import SwiftUI

@objc(DWSettingsMenuViewControllerDelegate)
protocol SettingsMenuViewControllerDelegate: AnyObject {
    func settingsMenuViewControllerDidRescanBlockchain(_ controller: SettingsMenuViewController)
}

@objc(DWSettingsMenuViewController)
class SettingsMenuViewController: UIViewController, DWLocalCurrencyViewControllerDelegate {
    
    @objc weak var delegate: SettingsMenuViewControllerDelegate?
    
    private lazy var model: DWSettingsMenuModel = DWSettingsMenuModel()
    
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
        
        let content = SettingsMenuContent(
            items: menuItems(),
            onLocalCurrencyChange: { [weak self] in
                self?.showCurrencySelector()
            },
            onNetworkChange: { [weak self] in
                self?.showChangeNetwork()
            },
            onRescanBlockchain: { [weak self] in
                self?.showWarningAboutReclassifiedTransactions()
            }
        )
        let swiftUIController = UIHostingController(rootView: content)
        swiftUIController.view.backgroundColor = .dw_secondaryBackground()
        dw_embedChild(swiftUIController)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - LocalCurrencyViewControllerDelegate
    
    func localCurrencyViewController(_ controller: DWLocalCurrencyViewController, didSelectCurrency currencyCode: String) {
        navigationController?.popViewController(animated: true)
    }
    
    func localCurrencyViewControllerDidCancel(_ controller: DWLocalCurrencyViewController) {
        assertionFailure("Not supported")
    }
    
    // MARK: - Private
    
    private func menuItems() -> [MenuItemModel] {
        var items: [MenuItemModel] = [
            MenuItemModel(
                title: NSLocalizedString("Local Currency", comment: ""),
                subtitle: model.localCurrencyCode,
                showChevron: true,
                action: { [weak self] in
                    self?.showCurrencySelector()
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Enable Receive Notifications", comment: ""),
                showToggle: true, 
                isToggled: self.model.notificationsEnabled,
                action: { [weak self] in
                    self?.model.notificationsEnabled.toggle()
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Network", comment: ""),
                subtitle: model.networkName,
                showChevron: true,
                action: { [weak self] in
                    self?.showChangeNetwork()
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Rescan Blockchain", comment: ""),
                showChevron: true,
                action: { [weak self] in
                    self?.showWarningAboutReclassifiedTransactions()
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("About", comment: ""),
                showChevron: true,
                action: { [weak self] in
                    self?.showAboutController()
                }
            )
        ]
        
        #if DASHPAY
        items.append(contentsOf: [
            MenuItemModel(
                title: NSLocalizedString("CoinJoin", comment: ""),
                showChevron: true,
                action: { [weak self] in
                    self?.showCoinJoinController()
                }
            ),
            MenuItemModel(
                title: "Enable Voting",
                showToggle: true,
                isToggled: VotingPrefs.shared.votingEnabled,
                action: {
                    VotingPrefs.shared.votingEnabled.toggle()
                }
            )
        ])
        #endif
        
        return items
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
    
    private func showChangeNetwork() {
        let actionSheet = UIAlertController(title: NSLocalizedString("Network", comment: ""), message: nil, preferredStyle: .actionSheet)
        
        let mainnetAction = UIAlertAction(title: NSLocalizedString("Mainnet", comment: ""), style: .default) { [weak self] _ in
            DWSettingsMenuModel.switchToMainnet { success in
                if success {
                    self?.updateView()
                }
            }
        }
        
        let testnetAction = UIAlertAction(title: NSLocalizedString("Testnet", comment: ""), style: .default) { [weak self] _ in
            DWSettingsMenuModel.switchToTestnet { success in
                if success {
                    self?.updateView()
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        
        actionSheet.addAction(mainnetAction)
        actionSheet.addAction(testnetAction)
        actionSheet.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            actionSheet.popoverPresentationController?.sourceView = view
            actionSheet.popoverPresentationController?.sourceRect = view.bounds
        }
        
        present(actionSheet, animated: true, completion: nil)
    }
    
    private func showWarningAboutReclassifiedTransactions() {
        let actionSheet = UIAlertController(
            title: NSLocalizedString("You will lose all your manually reclassified transactions types", comment: ""),
            message: NSLocalizedString("If you would like to save manually reclassified types for transactions you should export a CSV transaction file.", comment: ""),
            preferredStyle: .actionSheet)
        
        let continueAction = UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default) { [weak self] _ in
            self?.rescanBlockchainAction()
        }
        
        let exportAction = UIAlertAction(title: NSLocalizedString("Export CSV", comment: ""), style: .default) { [weak self] _ in
            self?.exportTransactionsInCSV()
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        
        actionSheet.addAction(exportAction)
        actionSheet.addAction(continueAction)
        actionSheet.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            actionSheet.popoverPresentationController?.sourceView = view
            actionSheet.popoverPresentationController?.sourceRect = view.bounds
        }
        
        present(actionSheet, animated: true, completion: nil)
    }
    
    private func rescanBlockchainAction() {
        DWSettingsMenuModel.rescanBlockchainAction(from: self, sourceView: view, sourceRect: view.bounds) { [weak self] confirmed in
            if confirmed {
                self?.delegate?.settingsMenuViewControllerDidRescanBlockchain(self!)
            }
        }
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
    
    private func updateView() {
        // Trigger a view update
        viewDidLoad()
    }
}

struct SettingsMenuContent: View {
    var items: [MenuItemModel]
    var onLocalCurrencyChange: () -> Void
    var onNetworkChange: () -> Void
    var onRescanBlockchain: () -> Void

    var body: some View {
        List(items) { item in
            MenuItem(
                title: item.title,
                subtitle: item.subtitle,
                details: item.details,
                icon: item.icon,
                showInfo: item.showInfo,
                showChevron: item.showChevron,
                showToggle: item.showToggle,
                isToggled: item.isToggled,
                action: item.action
            )
            .background(Color.secondaryBackground)
            .cornerRadius(8)
            .shadow(color: .shadow, radius: 10, x: 0, y: 5)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .background(Color.clear)
    }
}
