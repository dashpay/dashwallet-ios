//
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

@objc(DWToolsMenuViewControllerDelegate)
protocol ToolsMenuViewControllerDelegate: AnyObject {
    func toolsMenuViewControllerImportPrivateKey(_ controller: ToolsMenuViewController)
}

@objc(DWToolsMenuViewController)
class ToolsMenuViewController: UIViewController, DWImportWalletInfoViewControllerDelegate {
    @objc weak var delegate: ToolsMenuViewControllerDelegate?
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.title = NSLocalizedString("Tools", comment: "")
        self.hidesBottomBarWhenPushed = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.dw_secondaryBackground()
        
        let items = [
            MenuItemModel(
                title: NSLocalizedString("Import Private Key", comment: ""),
                showChevron: true,
                action: { [weak self] in
                    self?.showImportPrivateKey()
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Extended Public Keys", comment: ""),
                showChevron: true,
                action: { [weak self] in
                    self?.showExtendedPublicKeys()
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Show Masternode Keys", comment: ""),
                showChevron: true,
                action: { [weak self] in
                    self?.showMasternodeKeys()
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("CSV Export", comment: ""),
                showChevron: true,
                action: { [weak self] in
                    self?.askToExportTransactionsInCSV()
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("ZenLedger", comment: ""),
                subtitle: NSLocalizedString("Simplify your crypto taxes", comment: ""),
                icon: .custom("zenledger"),
                action: { [weak self] in
//                    showZL.wrappedValue = true
                }
            )
        ]
        
        let swiftUIController = UIHostingController(rootView: ContentView(items: items))
        swiftUIController.view.backgroundColor = UIColor.dw_secondaryBackground()
        self.dw_embedChild(swiftUIController)
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

struct ContentView: View {
    let items: [MenuItemModel]
    @State private var showingZenLedgerSheet: Bool = false

    var body: some View {
        VStack {
            List(items) {
                MenuItem(model: $0)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .background(Color.clear)
            .sheet(isPresented: $showingZenLedgerSheet) {
                if #available(iOS 16.0, *) {
                    bottomSheet
                        .presentationDetents([.height(430)])
                } else {
                    bottomSheet
                }
            }
            
            Button(action: {
                showingZenLedgerSheet = true
            }, label: { Text("hello") })
        }
    }
    
    var bottomSheet: some View {
        BottomSheet {
            TextIntro(
                icon: .custom("zenledger_large"),
                buttonLabel: NSLocalizedString("Export all transactions", comment: "ZenLedger"),
                action: {
                    print("hello")
                }
            ) {
                FeatureTopText(
                    model: FeatureTopModel(
                        title: NSLocalizedString("Simplify your crypto taxes", comment: "ZenLedger"),
                        text: NSLocalizedString("Connect your crypto wallets to the ZenLedger platform. Learn more and get started with your Dash Wallet transactions.", comment: "ZenLedger"),
                        label: "zenledger.io",
                        labelIcon: .custom("external.link"),
                        linkAction: {
                            print("link action")
                        }
                    )
                )
            }
        }
    }
}
