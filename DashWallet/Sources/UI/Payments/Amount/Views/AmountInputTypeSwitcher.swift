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


private let kItemHeight: CGFloat = 24.0

// MARK: - AmountInputTypeSwitcherDelegate

protocol AmountInputTypeSwitcherDelegate: AnyObject {
    var numberOfInputTypes: Int { get }

    func amountInputTypeSwitcher(_ switcher: AmountInputTypeSwitcher, didSelectItemAt index: Int)
    func amountInputTypeSwitcher(_ switcher: AmountInputTypeSwitcher, valueForItemAt index: Int) -> String
    func amountInputTypeSwitcher(_ switcher: AmountInputTypeSwitcher, isValueSelectedForItemAt index: Int) -> Bool
}

// MARK: - AmountInputTypeSwitcher

class AmountInputTypeSwitcher: UIView {
    public weak var delegate: AmountInputTypeSwitcherDelegate? {
        didSet {
            reloadData()
        }
    }

    private var currentSelectedIndex = 0
    private var containerView: UIStackView!

    override var intrinsicContentSize: CGSize {
        .init(width: AmountInputTypeSwitcher.noIntrinsicMetric, height: CGFloat(delegate?.numberOfInputTypes ?? 0)*kItemHeight)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func reloadData() {
        guard let delegate else { return }

        if containerView.arrangedSubviews.count == delegate.numberOfInputTypes {
            updateItems()
        } else {
            presentItems()
        }

        for view in containerView.arrangedSubviews {
            let button = view as! UIButton

            if button.isSelected {
                currentSelectedIndex = button.tag
                return
            }
        }
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
        delegate?.amountInputTypeSwitcher(self, didSelectItemAt: sender.tag)
    }
}

extension AmountInputTypeSwitcher {
    private func updateItems() {
        guard let delegate else { return }

        for i in 0..<delegate.numberOfInputTypes {
            let button = containerView.arrangedSubviews[i] as! UIButton
            update(button: button, at: i)
        }
    }

    private func presentItems() {
        guard let delegate else { return }

        containerView.removeAllArrangedSubviews()

        for i in 0..<delegate.numberOfInputTypes {
            let button = itemButton()
            update(button: button, at: i)
            containerView.addArrangedSubview(button)
        }
    }

    private func update(button: UIButton, at index: Int) {
        guard let delegate else { return }

        button.tag = index
        button.isSelected = delegate.amountInputTypeSwitcher(self, isValueSelectedForItemAt: index)
        button.setTitle(delegate.amountInputTypeSwitcher(self, valueForItemAt: index), for: .normal)
        button.isUserInteractionEnabled = !button.isSelected
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

    private func itemButton() -> UIButton {
        let button = ItemButton(frame: .zero)
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
