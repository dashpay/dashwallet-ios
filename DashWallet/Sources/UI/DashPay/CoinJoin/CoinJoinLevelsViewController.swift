//
//  Created by Andrei Ashikhmin
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

class CoinJoinLevelsViewController: UIViewController {
    private let viewModel = CoinJoinLevelViewModel.shared
    private var cancellableBag = Set<AnyCancellable>()
    
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var intermediateBox: UIView!
    @IBOutlet private var intermediateTitle: UILabel!
    @IBOutlet private var intermediateDescription: UILabel!
    @IBOutlet private var intermediateTime: UILabel!
    @IBOutlet private var advancedBox: UIView!
    @IBOutlet private var advancedTitle: UILabel!
    @IBOutlet private var advancedDescription: UILabel!
    @IBOutlet private var advancedTime: UILabel!
    @IBOutlet private var continueButton: ActionButton!
    
    var requiresNoNavigationBar: Bool {
        return true
    }
    
    @objc(controllerWithIsFullScreen:)
    static func controller(isFullScreen: Bool = false) -> CoinJoinLevelsViewController {
        let vc = vc(CoinJoinLevelsViewController.self, from: sb("CoinJoin"))
        vc.modalPresentationStyle = isFullScreen ? .fullScreen : .formSheet
        return vc
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureObservers()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.resetSelectedMode()
    }

    @IBAction
    func continueButtonAction() {
        if !viewModel.isMixing {
            if modalPresentationStyle == .fullScreen {
                dismiss(animated: true)
            } else {
                self.navigationController?.popViewController(animated: true)
            }
            viewModel.startMixing()
        } else {
            let alert = UIAlertController(title: NSLocalizedString("Are you sure you want to stop mixing?", comment: "CoinJoin"), message: NSLocalizedString("Any funds that have been mixed will be combined with your un mixed funds", comment: "CoinJoin"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Stop Mixing", comment: "CoinJoin"), style: .destructive, handler: { [weak self] _ in
                self?.viewModel.stopMixing()
            }))
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
            alert.addAction(cancelAction)
            present(alert, animated: true)
        }
    }
}

extension CoinJoinLevelsViewController {
    private func configureHierarchy() {
        titleLabel.text = NSLocalizedString("Select mixing level", comment: "CoinJoin")
        intermediateTitle.text = NSLocalizedString("Intermediate", comment: "CoinJoin")
        intermediateDescription.text = NSLocalizedString("Advanced users who have a very high level of technical expertise can determine your transaction history", comment: "Coinbase")
        intermediateTime.text = NSLocalizedString("up to 30 minutes", comment: "CoinJoin")
        
        advancedTitle.text = NSLocalizedString("Advanced", comment: "CoinJoin")
        advancedDescription.text = NSLocalizedString("It would be very difficult for advanced users with any level of technical expertise to determine your transaction history", comment: "Coinbase")
        advancedTime.text = NSLocalizedString("Multiple hours", comment: "CoinJoin")
        
        continueButton.setTitle(NSLocalizedString("Start Mixing", comment: "CoinJoin"), for: .normal)
        
        intermediateBox.layer.cornerRadius = 14
        intermediateBox.layer.borderWidth = 1.5
        intermediateBox.layer.borderColor = UIColor.dw_separatorLine().cgColor
        let intermediateTap = UITapGestureRecognizer(target: self, action: #selector(selectIntermediate))
        intermediateBox.addGestureRecognizer(intermediateTap)
        
        advancedBox.layer.cornerRadius = 14
        advancedBox.layer.borderWidth = 1.5
        advancedBox.layer.borderColor = UIColor.dw_separatorLine().cgColor
        let advancedTap = UITapGestureRecognizer(target: self, action: #selector(selectAdvanced))
        advancedBox.addGestureRecognizer(advancedTap)

        if modalPresentationStyle == .fullScreen {
            let backButton = UIButton(type: .system)
            backButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            backButton.addTarget(self, action: #selector(closeButtonAction), for: .touchUpInside)
            backButton.tintColor = .label
            view.addSubview(backButton)
            backButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0),
                backButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                backButton.widthAnchor.constraint(equalToConstant: 44),
                backButton.heightAnchor.constraint(equalToConstant: 44),
                titleLabel.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 0)
            ])
        }
    }
    
    @objc
    private func closeButtonAction() {
        dismiss(animated: true)
    }
    
    @objc
    private func selectIntermediate() {
        selectMode(.intermediate)
    }
    
    @objc
    private func selectAdvanced() {
        selectMode(.advanced)
    }
    
    private func selectMode(_ mode: CoinJoinMode) {
        if viewModel.selectedMode == mode {
            return
        }
        
        if viewModel.selectedMode == .none || !viewModel.isMixing {
            Task {
                if !viewModel.keepOpenInfoShown {
                    await showModalDialog(
                        style: .regular,
                        icon: .system("info"),
                        heading: NSLocalizedString("Mixing is only possible with the app open", comment: "CoinJoin"),
                        textBlock1: NSLocalizedString("When you close the app or lock the screen, the mixing process stops. It will resume when you reopen the app.", comment: "CoinJoin"),
                        positiveButtonText: NSLocalizedString("OK", comment: "")
                    )
                    
                    viewModel.keepOpenInfoShown = true
                }
                
                if !viewModel.hasWiFi {
                    let heading = viewModel.selectedMode == .intermediate ? NSLocalizedString("Intermediate privacy level requires a reliable internet connection", comment: "CoinJoin") : NSLocalizedString("Advanced privacy level requires a reliable internet connection", comment: "CoinJoin")
                    let shouldContinue = await showModalDialog(
                        style: .warning,
                        icon: .system("exclamationmark.triangle.fill"),
                        heading: heading,
                        textBlock1: NSLocalizedString("It is recommended to be on a Wi-Fi network to avoid losing any funds", comment: "CoinJoin"),
                        positiveButtonText: NSLocalizedString("Continue Anyway", comment: ""),
                        negativeButtonText: NSLocalizedString("Cancel", comment: "")
                    )
                    
                    if shouldContinue {
                        viewModel.selectedMode = mode
                    }
                } else if await viewModel.isTimeSkewedForCoinJoin() {
                    let settingsURL = URL(string: UIApplication.openSettingsURLString)
                    let hasSettings = settingsURL != nil && UIApplication.shared.canOpenURL(settingsURL!)
                    let message = String(format: NSLocalizedString("Your device time is off by more than 5 seconds. You cannot use CoinJoin due to this difference.\n\nThe time settings on your device needs to be changed to “Set time automatically” before using CoinJoin.", comment: "TimeSkew"))
                    
                    showModalDialog(
                        icon: .custom("image.coinjoin.menu"),
                        heading: NSLocalizedString("CoinJoin", comment: "CoinJoin"),
                        textBlock1: message,
                        positiveButtonText: NSLocalizedString("Settings", comment: ""),
                        positiveButtonAction: hasSettings ? {
                            if let url = settingsURL {
                                UIApplication.shared.open(url)
                            }
                        } : nil,
                        negativeButtonText: NSLocalizedString("Dismiss", comment: "")
                    )
                } else {
                    viewModel.selectedMode = mode
                }
            }
        } else {
            confirmFor(mode)
        }
    }
    
    private func configureObservers() {
        viewModel.$selectedMode
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] mode in
                guard let self = self else { return }
                
                switch mode {
                case .none:
                    self.removeHighlight()
                case .intermediate:
                    self.highlightIntermediate()
                case .advanced:
                    self.highlightAdvanced()
                }
                
                self.continueButton.isEnabled = mode != .none
            })
            .store(in: &cancellableBag)
        
        viewModel.$isMixing
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] isMixing in
                guard let self = self else { return }
                
                if !isMixing {
                    self.continueButton.accentColor = .dw_dashBlue()
                    self.continueButton.setTitle(NSLocalizedString("Start Mixing", comment: "CoinJoin"), for: .normal)
                } else {
                    self.continueButton.accentColor = .dw_red()
                    self.continueButton.setTitle(NSLocalizedString("Stop Mixing", comment: "CoinJoin"), for: .normal)
                }
            })
            .store(in: &cancellableBag)
    }
    
    private func removeHighlight() {
        intermediateBox.layer.borderColor = UIColor.dw_separatorLine().cgColor
        advancedBox.layer.borderColor = UIColor.dw_separatorLine().cgColor
    }
    
    private func highlightIntermediate() {
        intermediateBox.layer.borderColor = UIColor.dw_dashBlue().cgColor
        advancedBox.layer.borderColor = UIColor.dw_separatorLine().cgColor
    }
    
    private func highlightAdvanced() {
        intermediateBox.layer.borderColor = UIColor.dw_separatorLine().cgColor
        advancedBox.layer.borderColor = UIColor.dw_dashBlue().cgColor
    }
    
    private func confirmFor(_ mode: CoinJoinMode) {
        let title: String
        switch mode {
        case .none:
            return
        case .advanced:
            title = NSLocalizedString("Change to Advanced", comment: "CoinJoin")
        case .intermediate:
            title = NSLocalizedString("Change to Intermediate", comment: "CoinJoin")
        }
        
        let alert = UIAlertController(title: "", message: NSLocalizedString("Are you sure you want to change the privacy level?", comment: "CoinJoin"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
            self?.viewModel.selectedMode = mode
            self?.viewModel.startMixing()
        }))
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
        alert.addAction(cancelAction)
        present(alert, animated: true)
    }
}
