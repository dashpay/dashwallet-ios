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

import Foundation

// MARK: - HomeBalanceViewDelegate

@objc(DWHomeBalanceViewDelegate)
protocol HomeBalanceViewDelegate: AnyObject {
    func balanceView(_ view: HomeBalanceView, balanceLongPressAction sender: UIControl)
    func balanceViewDidToggleBalanceVisibility(_ view: HomeBalanceView)
}

// MARK: - HomeBalanceViewDataSource

protocol HomeBalanceViewDataSource: BalanceViewDataSource {
    var isBalanceHidden: Bool { get }
}

// MARK: - HomeBalanceViewState

enum HomeBalanceViewState: Int {
    case `default`
    case syncing
}

// MARK: - HomeBalanceView

final class HomeBalanceView: UIView {
    @IBOutlet private weak var contentView: UIView!
    @IBOutlet private var balanceButton: UIControl!
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var hidingView: UIView!
    @IBOutlet private var eyeSlashImageView: UIImageView!
    @IBOutlet private var tapToUnhideLabel: UIButton!
    @IBOutlet private var amountsView: UIView!
    @IBOutlet private var balanceView: BalanceView!

    weak var dataSource: HomeBalanceViewDataSource? {
        didSet {
            balanceView.dataSource = dataSource
            reloadView()
            reloadData()
        }
    }

    weak var delegate: HomeBalanceViewDelegate?

    var state: HomeBalanceViewState = .default {
        didSet {
            reloadView()
        }
    }

    private var isBalanceHidden: Bool {
        dataSource?.isBalanceHidden ?? false
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    @objc
    func reloadView() {
        var titleString = ""

        let isBalanceHidden = dataSource?.isBalanceHidden ?? false

        if !isBalanceHidden && state == .syncing {
            titleString = NSLocalizedString("Syncing Balance", comment: "")

            titleLabel.alpha = 0.8
            titleLabel.layer.removeAllAnimations()

            UIView.animate(withDuration: 0.8,
                           delay:0.0,
                           options:[.allowUserInteraction, .curveEaseInOut, .autoreverse, .repeat],
                           animations: { self.titleLabel.alpha = 0.3 },
                           completion: nil)

        } else {
            titleLabel.layer.removeAllAnimations()
        }

        titleLabel.text = titleString
        hideBalance(isBalanceHidden)
    }

    @objc
    public func reloadData() {
        balanceView.reloadData()
    }

    private func commonInit() {
        Bundle.main.loadNibNamed("HomeBalanceView", owner: self, options: nil)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: widthAnchor),
        ])

        backgroundColor = UIColor.dw_background()

        titleLabel.font = UIFont.dw_font(forTextStyle: .caption1)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        titleLabel.alpha = 0.8

        eyeSlashImageView.tintColor = UIColor.dw_darkBlue()

        tapToUnhideLabel.titleLabel?.font = UIFont.dw_font(forTextStyle: .caption1)
        tapToUnhideLabel.setTitle(NSLocalizedString("Tap to hide balance", comment: ""), for: .normal)
        tapToUnhideLabel.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .normal)
        tapToUnhideLabel.isUserInteractionEnabled = true

        let tapRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(balanceButtonAction(_:)))
        tapToUnhideLabel.addGestureRecognizer(tapRecognizer)

        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(balanceLongPressAction(_:)))
        balanceButton.addGestureRecognizer(recognizer)

        balanceView.tint = .white

        let isBalanceHidden = isBalanceHidden
        hidingView.alpha = isBalanceHidden ? 1.0 : 0.0
        amountsView.alpha = isBalanceHidden ? 0.0 : 1.0
        tapToUnhideLabel.alpha = isBalanceHidden ? 0.0 : 1.0

        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChangeNotification(_:)), name: UIContentSizeCategory.didChangeNotification,
                                               object: nil)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        reloadData()
    }

    @IBAction
    private func balanceButtonAction(_ sender: UIControl) {
        delegate?.balanceViewDidToggleBalanceVisibility(self)
    }

    @objc
    private func balanceLongPressAction(_ sender: UIControl) {
        delegate?.balanceView(self, balanceLongPressAction: sender)
    }

    @objc
    private func contentSizeCategoryDidChangeNotification(_ notification: Notification) {
        reloadData()
    }

    @objc
    func hideBalance(_ hidden: Bool) {
        let animated = window != nil
        let isAlreadyHidden = amountsView.alpha == 0

        guard isAlreadyHidden != hidden else { return }

        UIView.animate(withDuration: animated ? kAnimationDuration : 0.0) {
            self.hidingView.alpha = hidden ? 1.0 : 0.0
            self.amountsView.alpha = hidden ? 0.0 : 1.0

            self.tapToUnhideLabel.alpha = hidden ? 0.0 : 1.0
            self.reloadData()
        }
    }
}
