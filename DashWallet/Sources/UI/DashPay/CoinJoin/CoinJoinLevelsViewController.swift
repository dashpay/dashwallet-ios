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
    private let viewModel = CoinJoinViewModel.shared
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
    
    @objc
    static func controller() -> CoinJoinLevelsViewController {
        vc(CoinJoinLevelsViewController.self, from: sb("CoinJoin"))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureObservers()
    }

    @IBAction
    func continueButtonAction() {
        if viewModel.mixingState == .notStarted {
            self.navigationController?.popViewController(animated: true)
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
    }
    
    @objc
    private func selectIntermediate() {
        if viewModel.selectedMode == .intermediate {
            return
        }
        
        if viewModel.mixingState == .mixing {
            confirmFor(.intermediate)
        } else {
            viewModel.selectedMode = .intermediate
        }
    }
    
    @objc
    private func selectAdvanced() {
        if viewModel.selectedMode == .advanced {
            return
        }
        
        if viewModel.mixingState == .mixing {
            confirmFor(.advanced)
        } else {
            viewModel.selectedMode = .advanced
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
        
        viewModel.$mixingState
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] status in
                guard let self = self else { return }
                
                if status == .notStarted {
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
        }))
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
        alert.addAction(cancelAction)
        present(alert, animated: true)
    }
}
