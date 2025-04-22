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

private let kChainManagerNotificationChainKey = "DSChainManagerNotificationChainKey"
private let kChainManagerNotificationSyncStateKey = "DSChainManagerNotificationSyncStateKey"

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

        let okButton = ActionButton()
        okButton.translatesAutoresizingMaskIntoConstraints = false
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
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    func okButtonAction(sender: UIButton) {
        delegate?.syncingAlertContentView(self, okButtonAction: sender)
    }

    func update(with syncState: SyncingActivityMonitor.State) {
        switch syncState {
        case .syncing, .syncDone:
            let model = SyncingActivityMonitor.shared.model;
            let kind = model.kind;
            if kind == .headers {
                subtitleLabel.text = localized(
                    template: "header #%d of %d",
                    model.lastTerminalBlockHeight,
                    model.estimatedBlockHeight)
            } else if kind == .masternodes {
                let masternodeListsReceived = model.masternodeListSyncInfo.queueCount
                let masternodeListsTotal = model.masternodeListSyncInfo.queueMaxAmount
                subtitleLabel.text = localized(
                    template: "masternode list #%d of %d",
                    masternodeListsReceived > masternodeListsTotal ? 0 : masternodeListsTotal - masternodeListsTotal,
                    masternodeListsTotal)
            } else if kind == .platform {
                let identitiesKeysCount = model.platformSyncInfo.queueCount
                let identitiesKeysTotal = model.platformSyncInfo.queueMaxAmount
                subtitleLabel.text = localized(
                    template: "platform #%d of %d",
                    identitiesKeysCount > identitiesKeysTotal ? 0 : identitiesKeysTotal - identitiesKeysCount,
                    identitiesKeysTotal)
            } else {
                subtitleLabel.text = localized(
                    template: "block #%d of %d",
                    model.lastSyncBlockHeight,
                    model.estimatedBlockHeight)
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
        titleLabel.text = String(format: "%@ %.1f%%", NSLocalizedString("Syncing", comment: ""), min(max(progress, 0), 1) * 100.0)
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
    
    private func localized(
        template: String,
        _ arguments: any CVarArg...
    ) -> String {
        String(
            format: NSLocalizedString(
                template,
                comment: ""),
            arguments)
    }

    private func addChainObserver(_ aName: NSNotification.Name?, _ aSelector: Selector) {
        NotificationCenter.default.addObserver(self, selector: aSelector, name: aName, object: nil)
    }
    
    private func configureObserver() {
        addChainObserver(.chainManagerSyncStateChanged, #selector(chainManagerSyncStateChangedNotification(notification:)))
    }
    @objc
    func chainManagerSyncStateChangedNotification(notification: Notification) {
        guard let chain = notification.userInfo?[kChainManagerNotificationChainKey], DWEnvironment.sharedInstance().currentChain.isEqual(chain),
            let model = notification.userInfo?[kChainManagerNotificationSyncStateKey] as? DSSyncState else {
            return
        }
        self.update(with: model.progress)
    }

}
