//
//  Created by PT
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

import UIKit

// MARK: - SyncingAlertContentViewDelegate

protocol SyncingAlertContentViewDelegate: AnyObject {
    func syncingAlertContentView(_ view: SyncingAlertContentView, okButtonAction sender: UIButton)
}

// MARK: - SyncingAlertContentView

final class SyncingAlertContentView: UIView {

    private(set) var syncingImageView: UIImageView!
    private(set) var titleLabel: UILabel!
    private(set) var subtitleLabel: UILabel!

    weak var delegate: SyncingAlertContentViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.dw_background()

        syncingImageView = UIImageView(image: UIImage(named: "icon_syncing_large"))
        syncingImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(syncingImageView)

        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.dw_font(forTextStyle: .title3)
        titleLabel.textColor = UIColor.dw_darkTitle()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        addSubview(titleLabel)

        subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = UIFont.dw_font(forTextStyle: .callout)
        subtitleLabel.textColor = UIColor.dw_secondaryText()
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        addSubview(subtitleLabel)

        let okButton = DWActionButton()
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.small = true
        okButton.setTitle(NSLocalizedString("OK", comment: ""), for: .normal)
        okButton.addTarget(self, action: #selector(okButtonAction(sender:)), for: .touchUpInside)
        addSubview(okButton)

        syncingImageView.setContentCompressionResistancePriority(.required, for: .vertical)
        syncingImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            syncingImageView.topAnchor.constraint(equalTo: topAnchor),
            syncingImageView.centerXAnchor.constraint(equalTo: centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: syncingImageView.bottomAnchor, constant: 16.0),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8.0),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor),

            okButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 38.0),
            okButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            bottomAnchor.constraint(equalTo: okButton.bottomAnchor),
            okButton.heightAnchor.constraint(equalToConstant: 32.0),
            okButton.widthAnchor.constraint(equalToConstant: 110.0),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func okButtonAction(sender: UIButton) {
        delegate?.syncingAlertContentView(self, okButtonAction: sender)
    }

    func update(with syncState: SyncingActivityMonitor.State) {
        switch syncState {
        case .syncing, .syncDone:
            let environment = DWEnvironment.sharedInstance()
            let chain = environment.currentChain
            let chainManager = environment.currentChainManager
            // We give a 6 block window, just in case a new block comes in
            let atTheEndOfInitialTerminalBlocksAndSyncingMasternodeList = chain.lastTerminalBlockHeight >= chain.estimatedBlockHeight - 6 && chainManager.masternodeManager
                .masternodeListRetrievalQueueCount > 0 && chainManager.syncPhase == .initialTerminalBlocks
            let atTheEndOfSyncBlocksAndSyncingMasternodeList = chain.lastSyncBlockHeight >= chain.estimatedBlockHeight - 6 && chainManager.masternodeManager
                .masternodeListRetrievalQueueCount > 0 && chainManager.syncPhase == .synced
            if atTheEndOfInitialTerminalBlocksAndSyncingMasternodeList || atTheEndOfSyncBlocksAndSyncingMasternodeList {
                subtitleLabel.text = String(format: NSLocalizedString("masternode list #%d of %d", comment: ""),
                                            chainManager.masternodeManager.masternodeListRetrievalQueueMaxAmount - chainManager.masternodeManager.masternodeListRetrievalQueueCount,
                                            chainManager.masternodeManager.masternodeListRetrievalQueueMaxAmount)
            } else {
                if chainManager.syncPhase == .initialTerminalBlocks {
                    subtitleLabel.text = String(format: NSLocalizedString("header #%d of %d", comment: ""), chain.lastTerminalBlockHeight, chain.estimatedBlockHeight)
                } else {
                    subtitleLabel.text = String(format: NSLocalizedString("block #%d of %d", comment: ""), chain.lastSyncBlockHeight, chain.estimatedBlockHeight)
                }
            }

        case .syncFailed:
            subtitleLabel.text = NSLocalizedString("Sync Failed", comment: "")

        case .noConnection:
            subtitleLabel.text = NSLocalizedString("Unable to connect", comment: "")
        case .unknown:
            break
        }

        if syncState == .syncing {
            showAnimation()
        } else {
            hideAnimation()
        }
    }

    func update(with progress: Double) {
        titleLabel.text = String(format: "%@ %.1f%%", NSLocalizedString("Syncing", comment: ""), progress * 100.0)
    }

    func showAnimation() {
        if syncingImageView.layer.animation(forKey: "dw_rotationAnimation") != nil {
            return
        }

        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotationAnimation.fromValue = 0
        rotationAnimation.toValue = Double.pi * 2.0
        rotationAnimation.duration = 1.75
        rotationAnimation.repeatCount = .infinity
        syncingImageView.layer.add(rotationAnimation, forKey: "dw_rotationAnimation")
    }

    func hideAnimation() {
        syncingImageView.layer.removeAllAnimations()
    }
}

