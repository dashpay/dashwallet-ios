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

// MARK: - SyncViewDelegate

protocol SyncViewDelegate: AnyObject {
    func syncViewRetryButtonAction(_ view: SyncView)
}

// MARK: - SyncView

final class SyncView: UIView {
    weak var delegate: SyncViewDelegate?

    var hasNetwork: Bool {
        model.networkStatus == .online
    }

    var syncState: SyncingActivityMonitor.State {
        model.state
    }

    var viewStateSeeingBlocks = false

    @IBOutlet var roundedView: UIView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var descriptionLabel: UILabel!
    @IBOutlet var percentLabel: UILabel!
    @IBOutlet var retryButton: UIButton!
    @IBOutlet var progressView: ProgressView!

    internal lazy var model: SyncModel = SyncModelImpl()

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    private func commonInit() {
        backgroundColor = UIColor.dw_secondaryBackground()

        titleLabel.font = UIFont.dw_font(forTextStyle: .subheadline)
        descriptionLabel.font = UIFont.dw_font(forTextStyle: .footnote)
        percentLabel.font = UIFont.dw_font(forTextStyle: .title1)
        viewStateSeeingBlocks = false

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(changeSeeBlocksStateAction(_:)))
        roundedView.addGestureRecognizer(tapGestureRecognizer)

        model.networkStatusDidChange = { [weak self] _ in
            self?.updateView()
        }

        model.progressDidChange = { [weak self] progress in
            self?.set(progress: Float(progress), animated: true)
        }

        model.stateDidChage = { [weak self] _ in
            self?.updateView()
        }
    }

    private func set(progress: Float, animated: Bool) {
        percentLabel.text = String(format: "%.1f%%", progress * 100.0)
        progressView.setProgress(progress, animated: animated)

        if viewStateSeeingBlocks && syncState == .syncing {
            updateUIForViewStateSeeingBlocks()
        }
    }

    func updateUIForViewStateSeeingBlocks() {
        // TODO: Don't access DashSync directly
        if syncState == .syncing || syncState == .syncDone {
            if viewStateSeeingBlocks {
                let model = SyncingActivityMonitor.shared.model;
                let kind = model.kind;
                if kind == .headers {
                    descriptionLabel.text = String(format: NSLocalizedString("header #%d of %d", comment: ""),
                        model.lastTerminalBlockHeight,
                        model.estimatedBlockHeight)
                } else if kind == .masternodes {
                    let masternodeListsReceived = model.masternodeListSyncInfo.queueCount
                    let masternodeListsTotal = model.masternodeListSyncInfo.queueMaxAmount
                    descriptionLabel.text = String(format: NSLocalizedString("masternode list #%d of %d", comment: ""),
                        masternodeListsReceived > masternodeListsTotal ? 0 : masternodeListsTotal - masternodeListsTotal,
                        masternodeListsTotal)
                } else {
                    descriptionLabel.text = String(format: NSLocalizedString("block #%d of %d", comment: ""),
                        model.lastSyncBlockHeight,
                        model.estimatedBlockHeight)
                }
            }
            else {
                descriptionLabel.text = NSLocalizedString("with Dash blockchain", comment: "")
            }
        }
    }

    @objc
    func changeSeeBlocksStateAction(_ sender: Any) {
        viewStateSeeingBlocks.toggle()
        updateUIForViewStateSeeingBlocks()
    }

    @IBAction
    func retryButtonAction(_ sender: Any) {
        model.forceStartSyncingActivity()

        delegate?.syncViewRetryButtonAction(self)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        commonInit()
        updateView()
    }
}

extension SyncView {
    private func updateView() {
        switch syncState {
        case .syncing, .syncDone:
            roundedView.backgroundColor = UIColor.dw_background()
            percentLabel.isHidden = false
            retryButton.isHidden = true
            progressView.isHidden = false
            titleLabel.text = NSLocalizedString("Syncing", comment: "")
            updateUIForViewStateSeeingBlocks()

        case .syncFailed:
            roundedView.backgroundColor = UIColor.dw_background()
            percentLabel.isHidden = true
            retryButton.tintColor = UIColor.dw_red()
            retryButton.isHidden = false
            progressView.isHidden = false
            titleLabel.text = NSLocalizedString("Sync Failed", comment: "")
            descriptionLabel.text = NSLocalizedString("Please try again", comment: "")
        default:
            break
        }

        if hasNetwork {
            titleLabel.textColor = UIColor.dw_secondaryText()
            descriptionLabel.textColor = UIColor.dw_quaternaryText()
        } else {
            titleLabel.textColor = UIColor.dw_lightTitle()
            descriptionLabel.textColor = UIColor.dw_lightTitle()

            roundedView.backgroundColor = UIColor.dw_red()
            percentLabel.isHidden = true
            retryButton.tintColor = UIColor.dw_background()
            retryButton.isHidden = false
            progressView.isHidden = true
            titleLabel.text = NSLocalizedString("Unable to connect", comment: "")
            descriptionLabel.text = NSLocalizedString("Check your connection", comment: "")
        }
    }
}
