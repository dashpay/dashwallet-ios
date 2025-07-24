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
import Combine

protocol SettingsMenuViewControllerDelegate: AnyObject {
    func settingsMenuViewControllerDidRescanBlockchain(_ controller: SettingsMenuViewController)
}

extension SettingsMenuViewController {
    // Static helper method for presenting rescan options from other view controllers
    static func presentRescanBlockchainAction(from controller: UIViewController,
                                            sourceView: UIView,
                                            sourceRect: CGRect,
                                            completion: ((Bool) -> Void)? = nil) {
        let actionSheet = UIAlertController(
            title: NSLocalizedString("Rescan Blockchain", comment: ""),
            message: nil,
            preferredStyle: .actionSheet
        )
        
        let viewModel = SettingsMenuViewModel()
        
        let rescanAction = UIAlertAction(
            title: NSLocalizedString("Rescan Transactions (Suggested)", comment: ""),
            style: .default
        ) { _ in
            viewModel.rescanTransactions()
            completion?(true)
        }
        
        let rescanMNLAndBlocksAction = UIAlertAction(
            title: NSLocalizedString("Full Resync", comment: ""),
            style: .default
        ) { _ in
            viewModel.fullResync()
            completion?(true)
        }
        
        #if DEBUG
        let rescanMNLAction = UIAlertAction(
            title: NSLocalizedString("Resync Masternode List", comment: ""),
            style: .default
        ) { _ in
            viewModel.resyncMasternodeList()
            completion?(true)
        }
        #endif
        
        let cancelAction = UIAlertAction(
            title: NSLocalizedString("Cancel", comment: ""),
            style: .cancel
        ) { _ in
            completion?(false)
        }
        
        actionSheet.addAction(rescanAction)
        actionSheet.addAction(rescanMNLAndBlocksAction)
        
        #if DEBUG
        actionSheet.addAction(rescanMNLAction)
        #endif
        
        actionSheet.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            actionSheet.popoverPresentationController?.sourceView = sourceView
            actionSheet.popoverPresentationController?.sourceRect = sourceRect
        }
        
        controller.present(actionSheet, animated: true, completion: nil)
    }
}

class SettingsMenuViewController: UIViewController, DWLocalCurrencyViewControllerDelegate {
    
    weak var delegate: SettingsMenuViewControllerDelegate?
    
    private lazy var viewModel: SettingsMenuViewModel = SettingsMenuViewModel()
    private var cancellables = Set<AnyCancellable>()
    
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
        
        let content = SettingsMenuContent(viewModel: self.viewModel)
        let swiftUIController = UIHostingController(rootView: content)
        swiftUIController.view.backgroundColor = .dw_secondaryBackground()
        dw_embedChild(swiftUIController)
        setupNavigationObserver()
    }
    
    private func setupNavigationObserver() {
        viewModel.$navigationDestination
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dest in
                switch dest {
                case .coinjoin:
                    self?.showCoinJoinController()
                case .currencySelector:
                    self?.showCurrencySelector()
                case .network:
                    self?.showChangeNetwork()
                case .rescan:
                    self?.showWarningAboutReclassifiedTransactions()
                case .about:
                    self?.showAboutController()
                default:
                    break
                }
            }
            .store(in: &cancellables)
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
    
    private func showCurrencySelector() {
        let controller = DWLocalCurrencyViewController(navigationAppearance: .default, presentationMode: .screen, currencyCode: nil)
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }
    
    private func showAboutController() {
        let aboutViewController = DWAboutViewController.create()
        navigationController?.pushViewController(aboutViewController, animated: true)
    }
    
    private func showChangeNetwork() {
        let actionSheet = UIAlertController(title: NSLocalizedString("Network", comment: ""), message: nil, preferredStyle: .actionSheet)
        
        let mainnetAction = UIAlertAction(title: NSLocalizedString("Mainnet", comment: ""), style: .default) { [weak self] _ in
            Task {
                let success = await self?.viewModel.switchToMainnet() ?? false
                if success {
                    await MainActor.run {
                        self?.updateView()
                    }
                }
            }
        }
        
        let testnetAction = UIAlertAction(title: NSLocalizedString("Testnet", comment: ""), style: .default) { [weak self] _ in
            Task {
                let success = await self?.viewModel.switchToTestnet() ?? false
                if success {
                    await MainActor.run {
                        self?.updateView()
                    }
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
        let actionSheet = UIAlertController(
            title: NSLocalizedString("Rescan Blockchain", comment: ""),
            message: nil,
            preferredStyle: .actionSheet
        )
        
        let rescanAction = UIAlertAction(
            title: NSLocalizedString("Rescan Transactions (Suggested)", comment: ""),
            style: .default
        ) { [weak self] _ in
            self?.viewModel.rescanTransactions()
            self?.delegate?.settingsMenuViewControllerDidRescanBlockchain(self!)
        }
        
        let rescanMNLAndBlocksAction = UIAlertAction(
            title: NSLocalizedString("Full Resync", comment: ""),
            style: .default
        ) { [weak self] _ in
            self?.viewModel.fullResync()
            self?.delegate?.settingsMenuViewControllerDidRescanBlockchain(self!)
        }
        
        #if DEBUG
        let rescanMNLAction = UIAlertAction(
            title: NSLocalizedString("Resync Masternode List", comment: ""),
            style: .default
        ) { [weak self] _ in
            self?.viewModel.resyncMasternodeList()
            self?.delegate?.settingsMenuViewControllerDidRescanBlockchain(self!)
        }
        #endif
        
        let cancelAction = UIAlertAction(
            title: NSLocalizedString("Cancel", comment: ""),
            style: .cancel,
            handler: nil
        )
        
        actionSheet.addAction(rescanAction)
        actionSheet.addAction(rescanMNLAndBlocksAction)
        
        #if DEBUG
        actionSheet.addAction(rescanMNLAction)
        #endif
        
        actionSheet.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            actionSheet.popoverPresentationController?.sourceView = view
            actionSheet.popoverPresentationController?.sourceRect = view.bounds
        }
        
        present(actionSheet, animated: true, completion: nil)
    }
    
    private func exportTransactionsInCSV() {
        view.dw_showProgressHUD(withMessage: NSLocalizedString("Generating CSV Report", comment: ""))
        
        Task {
            do {
                let (fileName, file) = try await viewModel.generateCSVReport()
                
                await MainActor.run {
                    self.view.dw_hideProgressHUD()
                    
                    let activityViewController = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                    activityViewController.setValue(fileName, forKey: "subject")
                    
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        activityViewController.popoverPresentationController?.sourceView = self.view
                        activityViewController.popoverPresentationController?.sourceRect = self.view.bounds
                    }
                    
                    self.present(activityViewController, animated: true, completion: nil)
                }
            } catch {
                await MainActor.run {
                    self.view.dw_hideProgressHUD()
                    self.dw_displayErrorModally(error)
                }
            }
        }
    }
    
    private func updateView() {
        cancellables.removeAll()
        viewModel.resetNavigation()
        // Trigger a view update
        viewDidLoad()
    }
}

// MARK: - CoinJoin

extension SettingsMenuViewController {
    private func showCoinJoinController() {
        let vc: UIViewController
        
        if CoinJoinLevelViewModel.shared.infoShown {
            vc = CoinJoinLevelsViewController.controller()
        } else {
            vc = CoinJoinInfoViewController.controller()
        }
        
        navigationController?.pushViewController(vc, animated: true)
    }
}

struct SettingsMenuContent: View {
    @StateObject var viewModel: SettingsMenuViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(viewModel.items) { item in
                    if let cjItem = item as? CoinJoinMenuItemModel {
                        MenuItem(
                            title: cjItem.title,
                            subtitleView: AnyView(CoinJoinSubtitle(cjItem)),
                            icon: .custom("image.coinjoin.menu", maxHeight: 22),
                            badgeText: nil,
                            action: cjItem.action
                        )
                        .frame(minHeight: 60)
                    } else {
                        MenuItem(
                            title: item.title,
                            subtitle: item.subtitle,
                            details: item.details,
                            icon: item.icon,
                            showInfo: item.showInfo,
                            showChevron: false,
                            showToggle: item.showToggle,
                            isToggled: item.isToggled,
                            action: item.action
                        )
                        .frame(minHeight: 60)
                    }
                }
            }
            .padding(.vertical, 5)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    @ViewBuilder
    private func CoinJoinSubtitle(_ cjItem: CoinJoinMenuItemModel) -> some View {
        if cjItem.isOn {
            CoinJoinProgressInfo(state: cjItem.state, progress: cjItem.progress, mixed: cjItem.mixed, total: cjItem.total, textColor: .tertiaryText, font: .caption)
                .padding(.top, 2)
        } else {
            Text(NSLocalizedString("Turned off", comment: "CoinJoin"))
                .font(.caption)
                .foregroundColor(.tertiaryText)
                .padding(.leading, 4)
                .padding(.top, 2)
        }
    }
}
