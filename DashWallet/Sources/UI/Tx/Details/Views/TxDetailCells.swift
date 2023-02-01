//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

// MARK: - TxDetailHeaderCellDataProvider

protocol TxDetailHeaderCellDataProvider {
    var title: String { get }
    var fiatAmount: String { get }
    var icon: UIImage { get }
    var tintColor: UIColor { get }

    func dashAmountString(with font: UIFont) -> NSAttributedString
}

// MARK: - TxDetailHeaderCell

class TxDetailHeaderCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var dashAmountLabel: UILabel!
    @IBOutlet var fiatAmountLabel: UILabel!

    @IBOutlet var iconImageView: UIImageView!

    func updateView(with data: TxDetailHeaderCellDataProvider) {
        let font = UIFont.preferredFont(forTextStyle: .largeTitle).withWeight(UIFont.Weight.medium.rawValue)
        dashAmountLabel.attributedText = data.dashAmountString(with: font)
        fiatAmountLabel.text = data.fiatAmount;

        titleLabel.text = data.title
        iconImageView.image = data.icon
        iconImageView.tintColor = data.tintColor
    }

    override func awakeFromNib() {
        iconImageView.contentMode = .center
        iconImageView.clipsToBounds = false

        titleLabel.font = UIFont.dw_font(forTextStyle: .subheadline).withWeight(UIFont.Weight.medium.rawValue)
        dashAmountLabel.font = UIFont.dw_font(forTextStyle: .largeTitle).withWeight(UIFont.Weight.medium.rawValue)
        fiatAmountLabel.font = UIFont.dw_font(forTextStyle: .footnote)

        titleLabel.textColor = .dw_label()
        dashAmountLabel.textColor = .dw_label()
    }
}

// MARK: - TxDetailActionCell

class TxDetailActionCell: TxDetailTitleCell {
    override func awakeFromNib() {
        super.awakeFromNib()
        titleLabel.textColor = .dw_label()
    }
}

// MARK: - TxDetailInfoCell

class TxDetailInfoCell: TxDetailTitleDetailsCell {
    @IBOutlet var valueLabelsStack: UIStackView!

    override func update(with item: TXDetailViewController.Item) {
        var title: String?

        let valueLabel: ((DWTitleDetailItem) -> UILabel) = { item in
            let view = UILabel()
            view.lineBreakMode = .byTruncatingMiddle
            view.attributedText = item.attributedDetail
            view.textAlignment = .right
            view.font = UIFont.dw_font(forTextStyle: .footnote)

            if let text = item.plainDetail {
                view.text = text
            }

            if let text = item.attributedDetail {
                view.attributedText = text
            }

            return view
        }

        switch item {
        case .sentTo(let items), .sentFrom(let items), .movedTo(let items), .movedFrom(let items), .receivedAt(let items):
            title = items.first?.title
            for item in items {
                let view = valueLabel(item)
                valueLabelsStack.addArrangedSubview(view)
            }
            break
        case .date(let item), .networkFee(let item):
            title = item.title
            let view = valueLabel(item)
            valueLabelsStack.addArrangedSubview(view)
        default:
            break
        }

        titleLabel.text = title
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        let views = valueLabelsStack.arrangedSubviews

        for view in views {
            valueLabelsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

// MARK: - TxDetailTaxCategoryCell

class TxDetailTaxCategoryCell: TxDetailTitleDetailsCell {
    @IBOutlet var categoryLabel: UILabel!

    override func update(with item: TXDetailViewController.Item) {
        switch item {
        case .taxCategory(let item):
            titleLabel.text = item.title
            categoryLabel.text = item.plainDetail
        default:
            break
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        categoryLabel?.font = UIFont.dw_font(forTextStyle: .footnote)
    }
}

// MARK: - TxDetailTitleDetailsCell

class TxDetailTitleDetailsCell: TxDetailTitleCell {
    func update(with item: TXDetailViewController.Item) { }
}

// MARK: - TxDetailTitleCell

class TxDetailTitleCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!

    override func awakeFromNib() {
        titleLabel.font = UIFont.dw_font(forTextStyle: .footnote).withWeight(UIFont.Weight.medium.rawValue)
        titleLabel.textColor = .dw_secondaryText()
    }
}
