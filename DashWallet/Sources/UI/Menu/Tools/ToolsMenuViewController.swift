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

@objc(DWToolsMenuViewControllerDelegate)
protocol ToolsMenuViewControllerDelegate: AnyObject {
    func toolsMenuViewControllerImportPrivateKey(_ controller: ToolsMenuViewController)
}

@objc(DWToolsMenuViewController)
class ToolsMenuViewController: UIViewController, DWImportWalletInfoViewControllerDelegate {
    
    @objc weak var delegate: ToolsMenuViewControllerDelegate?
    private var formController: DWFormTableViewController!
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.title = NSLocalizedString("Tools", comment: "")
        self.hidesBottomBarWhenPushed = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var items: [DWBaseFormCellModel] {
        var items = [DWBaseFormCellModel]()
        
        let importPrivateKeyModel = DWSelectorFormCellModel(title: NSLocalizedString("Import Private Key", comment: ""))
        importPrivateKeyModel.accessoryType = .disclosureIndicator
        importPrivateKeyModel.didSelectBlock = { [weak self] _, _ in
            self?.showImportPrivateKey()
        }
        items.append(importPrivateKeyModel)
        
        let extendedPublicKeysModel = DWSelectorFormCellModel(title: NSLocalizedString("Extended Public Keys", comment: ""))
        extendedPublicKeysModel.accessoryType = .disclosureIndicator
        extendedPublicKeysModel.didSelectBlock = { [weak self] _, _ in
            self?.showExtendedPublicKeys()
        }
        items.append(extendedPublicKeysModel)
        
        let showMasternodeKeysModel = DWSelectorFormCellModel(title: NSLocalizedString("Show Masternode Keys", comment: ""))
        showMasternodeKeysModel.accessoryType = .disclosureIndicator
        showMasternodeKeysModel.didSelectBlock = { [weak self] _, _ in
            self?.showMasternodeKeys()
        }
        items.append(showMasternodeKeysModel)
        
        let csvExportModel = DWSelectorFormCellModel(title: NSLocalizedString("CSV Export", comment: ""))
        csvExportModel.accessoryType = .disclosureIndicator
        csvExportModel.didSelectBlock = { [weak self] _, _ in
            self?.askToExportTransactionsInCSV()
        }
        items.append(csvExportModel)
        
        return items
    }
    
    private var sections: [DWFormSectionModel] {
        return items.map { item in
            let section = DWFormSectionModel()
            section.items = [item]
            return section
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.dw_secondaryBackground()
        
        let formController = DWFormTableViewController(style: .plain)
        formController.setSections(sections, placeholderText: nil)
        
        self.dw_embedChild(formController)
        self.formController = formController
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - DWImportWalletInfoViewControllerDelegate
    
    @objc func importWalletInfoViewControllerScanPrivateKeyAction(_ controller: DWImportWalletInfoViewController) {
        delegate?.toolsMenuViewControllerImportPrivateKey(self)
    }
    
    // MARK: - Private
    
    private func showImportPrivateKey() {
        let controller = DWImportWalletInfoViewController.createController()
        controller.delegate = self
        self.navigationController?.pushViewController(controller, animated: true)
    }
    
    private func showMasternodeKeys() {
        let keysViewController = KeysOverviewViewController()
        keysViewController.hidesBottomBarWhenPushed = true
        self.navigationController?.pushViewController(keysViewController, animated: true)
    }
    
    private func showExtendedPublicKeys() {
        let controller = ExtendedPublicKeysViewController()
        controller.hidesBottomBarWhenPushed = true
        self.navigationController?.pushViewController(controller, animated: true)
    }
    
    private func askToExportTransactionsInCSV() {
        let title = NSLocalizedString("CSV Export", comment: "")
        let message = NSLocalizedString("All payments will be considered as an Expense and all incoming transactions will be Income. The owner of this wallet is responsible for making any cost basis adjustments in their chosen tax reporting system.", comment: "")
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default, handler: { [weak self] _ in
            self?.exportTransactionsInCSV()
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alert.popoverPresentationController?.sourceView = self.view
            alert.popoverPresentationController?.sourceRect = self.view.bounds
        }
        
        self.present(alert, animated: true, completion: nil)
    }
    
    private func exportTransactionsInCSV() {
        self.view.dw_showProgressHUD(withMessage: NSLocalizedString("Generating CSV Report", comment: ""))
        
        TaxReportGenerator.generateCSVReport { [weak self] fileName, file in
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

extension DWImportWalletInfoViewController {
    static func createController() -> DWImportWalletInfoViewController {
        let storyboard = UIStoryboard(name: "ImportWalletInfo", bundle: nil)
        let controller = storyboard.instantiateInitialViewController() as! DWImportWalletInfoViewController
        controller.hidesBottomBarWhenPushed = true
        return controller
    }
}
