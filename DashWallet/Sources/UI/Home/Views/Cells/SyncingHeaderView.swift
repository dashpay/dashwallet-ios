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

// MARK: - SyncingHeaderViewDelegate

@objc(DWSyncingHeaderViewDelegate)
protocol SyncingHeaderViewDelegate: AnyObject {
    func syncingHeaderView(_ view: SyncingHeaderView, filterButtonAction sender: UIButton)
    func syncingHeaderView(_ view: SyncingHeaderView, syncingButtonAction sender: UIButton)
}

// MARK: - SyncingHeaderView

@objc(DWSyncingHeaderView)
final class SyncingHeaderView: UITableViewHeaderFooterView {

    @objc
    weak var delegate: SyncingHeaderViewDelegate?

    @objc
    var progress = 0.0 {
        didSet {
            refreshView()
        }
    }

    @objc
    var isSyncing = false {
        didSet {
            refreshView()
        }
    }

    private var syncingButton: UIButton!

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        backgroundColor = UIColor.dw_secondaryBackground()

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.dw_font(forTextStyle: .headline)
        titleLabel.text = NSLocalizedString("History", comment: "")
        titleLabel.textColor = UIColor.dw_darkTitle()
        titleLabel.setContentHuggingPriority(.defaultHigh + 1, for: .horizontal)
        addSubview(titleLabel)

        syncingButton = DWButton()
        syncingButton.translatesAutoresizingMaskIntoConstraints = false
        syncingButton.contentHorizontalAlignment = .right
        syncingButton.setTitleColor(UIColor.dw_darkTitle(), for: .normal)
        syncingButton.setContentHuggingPriority(.defaultHigh - 1, for: .horizontal)
        syncingButton.setContentCompressionResistancePriority(.required - 1, for: .horizontal)
        syncingButton.addTarget(self, action: #selector(syncingButtonAction(_:)), for: .touchUpInside)
        addSubview(syncingButton)

        let filterButton = UIButton(type: .custom)
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        filterButton.setImage(UIImage(named: "icon_filter_button"), for: .normal)
        filterButton.addTarget(self, action: #selector(filterButtonAction(_:)), for: .touchUpInside)
        addSubview(filterButton)

        let padding: CGFloat = 16.0
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: padding),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),

            syncingButton.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: syncingButton.bottomAnchor),
            syncingButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            syncingButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8.0),
            syncingButton.heightAnchor.constraint(equalToConstant: 44.0),

            filterButton.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: filterButton.bottomAnchor),
            filterButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            filterButton.leadingAnchor.constraint(equalTo: syncingButton.trailingAnchor),
            trailingAnchor.constraint(equalTo: filterButton.trailingAnchor, constant: 10.0),
            filterButton.heightAnchor.constraint(equalToConstant: 44.0),
            filterButton.widthAnchor.constraint(equalToConstant: 44.0),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func filterButtonAction(_ sender: UIButton) {
        delegate?.syncingHeaderView(self, filterButtonAction: sender)
    }

    @objc
    func syncingButtonAction(_ sender: UIButton) {
        delegate?.syncingHeaderView(self, syncingButtonAction: sender)
    }
}

extension SyncingHeaderView {
    private func refreshView() {
        syncingButton.isHidden = !isSyncing

        guard isSyncing else {
            return
        }
        let percentString = String(format: "%0.1f%%", progress * 100.0)

        let result = NSMutableAttributedString()

        let str1 = NSAttributedString(string: String(format: "%@ ", NSLocalizedString("Syncing", comment: "")),
                                      attributes: [NSAttributedString.Key.font: UIFont.dw_font(forTextStyle: .body)])
        result.append(str1)

        let str2 = NSAttributedString(string: percentString, attributes: [NSAttributedString.Key.font: UIFont.dw_font(forTextStyle: .headline)])
        result.append(str2)

        syncingButton.setAttributedTitle(result, for: .normal)
    }
}
