//
//  Created by tkhp
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

// MARK: - AmountInputTypeItem

struct AmountInputTypeItem {
    let currencySymbol: String
    let currencyCode: String

    var isMain: Bool { currencySymbol == "DASH" }
}

private let kItemHeight: CGFloat = 24.0

// MARK: - AmountInputTypeSwitcher

class AmountInputTypeSwitcher: UIView {
    public var items: [AmountInputTypeItem] = [] {
        didSet {
            reloadData()
        }
    }

    public var selectItemHandler: ((AmountInputTypeItem) -> Void)?

    private var containerView: UIStackView!
    private var currentSelectedIndex = 0

    override var intrinsicContentSize: CGSize {
        .init(width: AmountInputTypeSwitcher.noIntrinsicMetric, height: CGFloat(items.count)*kItemHeight)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func selectedNextItem() {
        var nextTag = currentSelectedIndex + 1

        if nextTag == items.count {
            nextTag = 0
        }

        currentSelectedIndex = nextTag
        reloadData()
    }

    @objc
    func itemAction(sender: UIButton) {
        var currentSelectedItemButton = containerView.arrangedSubviews[currentSelectedIndex] as! UIButton
        currentSelectedItemButton.isSelected = false
        currentSelectedItemButton.isUserInteractionEnabled = true

        currentSelectedItemButton = sender
        currentSelectedItemButton.isSelected = true
        currentSelectedItemButton.isUserInteractionEnabled = false

        currentSelectedIndex = currentSelectedItemButton.tag
        selectItemHandler?(items[sender.tag])
    }
}

extension AmountInputTypeSwitcher {
    private func reloadData() {
        guard !containerView.arrangedSubviews.isEmpty else {
            presentItems()
            return
        }

        for (i, item) in items.enumerated() {
            let button = containerView.arrangedSubviews[i] as! UIButton
            button.isSelected = currentSelectedIndex == i
            button.isUserInteractionEnabled = !button.isSelected
            button.setTitle(item.currencySymbol, for: .normal)
        }
    }

    private func presentItems() {
        for (i, item) in items.enumerated() {
            let button = itemButton(title: item.currencySymbol)
            button.tag = i
            button.isSelected = currentSelectedIndex == i
            button.isUserInteractionEnabled = !button.isSelected
            containerView.addArrangedSubview(button)
        }
    }

    private func configureHierarchy() {
        containerView = UIStackView()
        containerView.axis = .vertical
        containerView.alignment = .center
        containerView.distribution = .fillEqually
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func itemButton(title: String) -> UIButton {
        let button = ItemButton(frame: .zero)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: #selector(itemAction(sender:)), for: .touchUpInside)
        return button
    }
}

// MARK: - ItemButton

private class ItemButton: UIButton {
    override var isSelected: Bool {
        didSet {
            backgroundColor = isSelected ? UIColor(red: 0.098, green: 0.11, blue: 0.122, alpha: 0.05) : .clear
        }
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? UIColor(red: 0.098, green: 0.11, blue: 0.122, alpha: 0.05) : backgroundColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    private func configureHierarchy() {
        layer.cornerRadius = 7
        layer.masksToBounds = true
        contentEdgeInsets = .init(top: 3, left: 6, bottom: 3, right: 6)

        titleLabel?.font = .dw_font(forTextStyle: .footnote)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.5

        let color: UIColor = .dw_label()
        setTitleColor(color.withAlphaComponent(0.8), for: .normal)
        setTitleColor(color, for: .selected)
        setTitleColor(color, for: .highlighted)
        setTitleColor(color.withAlphaComponent(0.4), for: .disabled)
    }
}
