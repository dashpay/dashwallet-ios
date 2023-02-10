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

// MARK: - ConverterViewDirection

enum ConverterViewDirection {
    case toWallet
    case fromWallet

    private var fromSource: Source {
        self == .fromWallet ? .dash : .coinbase
    }

    private var toSource: Source {
        self == .fromWallet ? .coinbase : .dash
    }

    var next: Self {
        self == .fromWallet ? .toWallet : .fromWallet
    }
}

// MARK: - ConverterViewSourceItem

struct ConverterViewSourceItem: SourceViewDataProvider {
    var image: SourceItemImage
    var title: String
    var subtitle: String?
    var balanceFormatted: String
    var fiatBalanceFormatted: String

    static func dash(subtitle: String? = nil, balanceFormatted: String = "", fiatBalanceFormatted: String = "") -> ConverterViewSourceItem {
        ConverterViewSourceItem(image: .asset("image.explore.dash.wts.dash"),
                                title: "Dash",
                                subtitle: subtitle,
                                balanceFormatted: balanceFormatted,
                                fiatBalanceFormatted: fiatBalanceFormatted)
    }
}

// MARK: - ConverterViewDataSource

protocol ConverterViewDataSource: AnyObject {
    var fromItem: SourceViewDataProvider? { get }
    var toItem: SourceViewDataProvider? { get }
}

// MARK: - ConverterViewDelegate

protocol ConverterViewDelegate: AnyObject {
    func didChangeDirection()
    func didTapOnFromView()
}

// MARK: - ConverterView

class ConverterView: UIView {
    public var hasNetwork = true {
        didSet {
            updateView()
        }
    }

    public var isChevronHidden = true {
        didSet {
            fromView.isChevronHidden = isChevronHidden
        }
    }

    public var isSwappingAllowed = true {
        didSet {
            swapGesture.isEnabled = isSwappingAllowed
        }
    }

    public weak var delegate: ConverterViewDelegate?
    public weak var dataSource: ConverterViewDataSource? {
        didSet {
            updateView()
        }
    }

    private var fromView: SourceItemView!
    private var toView: SourceItemView!
    private var swapImageView: UIImageView!
    private var swapGesture: UIGestureRecognizer!

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func reloadView() {
        updateView()
    }

    @objc
    func fromViewTapAction() {
        delegate?.didTapOnFromView()
    }

    @objc
    func swapAction() {
        delegate?.didChangeDirection()
        updateView()

        UIView.animate(withDuration: 0.2) {
            self.swapImageView.transform = .init(rotationAngle: 0.9999 * CGFloat.pi)
        } completion: { _ in
            self.swapImageView.transform = .identity
        }
    }
}

extension ConverterView {
    private func updateView() {
        guard let dataSource else { return }

        fromView.update(with: dataSource.fromItem, isBalanceHidden: false)
        toView.update(with: dataSource.toItem, isBalanceHidden: true)
    }

    private func configureHierarchy() {
        backgroundColor = .dw_background()
        layer.cornerRadius = 10

        let rightContainer = UIStackView()
        rightContainer.axis = .vertical
        rightContainer.spacing = 12
        rightContainer.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.backgroundColor = .clear
        addSubview(rightContainer)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(fromViewTapAction))
        fromView = SourceItemView(frame: .zero)
        fromView.isChevronHidden = isChevronHidden
        fromView.addGestureRecognizer(tapGesture)
        fromView.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addArrangedSubview(fromView)

        let hairlineView = HairlineView(frame: .zero)
        hairlineView.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addArrangedSubview(hairlineView)

        toView = SourceItemView(frame: .zero)
        toView.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addArrangedSubview(toView)

        swapGesture = UITapGestureRecognizer(target: self, action: #selector(swapAction))
        swapGesture.isEnabled = isSwappingAllowed

        let swapImageContainer = UIView()
        swapImageContainer.translatesAutoresizingMaskIntoConstraints = false
        swapImageContainer.backgroundColor = .dw_background()
        swapImageContainer.layer.cornerRadius = 6
        swapImageContainer.layer.borderWidth = 1
        swapImageContainer.layer.borderColor = UIColor.separator.cgColor
        swapImageContainer.isUserInteractionEnabled = true
        swapImageContainer.addGestureRecognizer(swapGesture)
        addSubview(swapImageContainer)

        swapImageView = UIImageView(image: UIImage(named: "coinbase.converter.switch"))
        swapImageView.translatesAutoresizingMaskIntoConstraints = false
        swapImageView.contentMode = .scaleAspectFit
        swapImageContainer.addSubview(swapImageView)

        NSLayoutConstraint.activate([
            rightContainer.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            rightContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            rightContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            rightContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            swapImageContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            swapImageContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            swapImageContainer.widthAnchor.constraint(equalToConstant: 27),
            swapImageContainer.heightAnchor.constraint(equalToConstant: 30),

            swapImageView.centerXAnchor.constraint(equalTo: swapImageContainer.centerXAnchor),
            swapImageView.centerYAnchor.constraint(equalTo: swapImageContainer.centerYAnchor),
            swapImageView.widthAnchor.constraint(equalToConstant: 13),
            swapImageView.heightAnchor.constraint(equalToConstant: 13),
        ])

        updateView()
    }
}

// MARK: - Source

private enum Source {
    case dash
    case coinbase

    var imageName: String {
        switch self {
        case .dash: return "image.explore.dash.wts.dash"
        case .coinbase: return "Coinbase"
        }
    }

    var title: String {
        switch self {
        case .dash: return "Dash Wallet"
        case .coinbase: return "Coinbase"
        }
    }
}

// MARK: - SourceItemView

private final class SourceItemView: UIView {
    var isChevronHidden = true {
        didSet {
            chevronView?.isHidden = isChevronHidden
        }
    }

    private var sourceView: SourceView!
    private var chevronView: UIImageView!

    override var intrinsicContentSize: CGSize { .init(width: SourceItemView.noIntrinsicMetric, height: 54.0) }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(with item: SourceViewDataProvider?, isBalanceHidden: Bool) {
        sourceView.update(with: item, isBalanceHidden: isBalanceHidden)
    }

    private func configureHierarchy() {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 15
        addSubview(stackView)

        sourceView = SourceView(frame: .zero)
        sourceView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(sourceView)

        chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.tintColor = .dw_secondaryText()
        chevronView.isHidden = isChevronHidden
        stackView.addArrangedSubview(chevronView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

// MARK: - SourceItemImage

enum SourceItemImage {
    case remote(URL)
    case asset(String)
}

// MARK: - SourceViewDataProvider

protocol SourceViewDataProvider {
    var image: SourceItemImage { get }
    var title: String { get }
    var subtitle: String? { get }
    var balanceFormatted: String { get }
    var fiatBalanceFormatted: String { get }
}

// MARK: - SourceView

final class SourceView: UIView {
    private(set) var imageView: UIImageView!
    private(set) var titleLabel: UILabel!
    private(set) var subtitleLabel: UILabel!
    private(set) var balanceLabel: UILabel!
    private(set) var fiatBalanceLabel: UILabel!

    override var intrinsicContentSize: CGSize { .init(width: ConverterView.noIntrinsicMetric, height: 54.0) }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(with item: SourceViewDataProvider?, isBalanceHidden: Bool) {
        guard let item else {
            titleLabel.text = NSLocalizedString("Select the coin", comment: "Coinbase")
            return
        }

        switch item.image {
        case .asset(let name):
            imageView.image = UIImage(named: name)
        case .remote(let url):
            imageView.sd_setImage(with: url)
        }

        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
        balanceLabel.text = item.balanceFormatted
        fiatBalanceLabel.text = item.fiatBalanceFormatted
    }

    private func configureHierarchy() {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.backgroundColor = .clear
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 10
        addSubview(stackView)

        imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.cornerRadius = 17
        imageView.backgroundColor = .dw_secondaryBackground()
        stackView.addArrangedSubview(imageView)

        let labelStackView = UIStackView()
        labelStackView.translatesAutoresizingMaskIntoConstraints = false
        labelStackView.spacing = 2
        labelStackView.axis = .vertical
        stackView.addArrangedSubview(labelStackView)

        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .dw_font(forTextStyle: .body).withWeight(UIFont.Weight.medium.rawValue)
        titleLabel.textColor = .dw_label()
        labelStackView.addArrangedSubview(titleLabel)

        subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .dw_font(forTextStyle: .footnote)
        subtitleLabel.textColor = .dw_secondaryText()
        labelStackView.addArrangedSubview(subtitleLabel)

        let valueStackView = UIStackView()
        valueStackView.translatesAutoresizingMaskIntoConstraints = false
        valueStackView.spacing = 2
        valueStackView.axis = .vertical
        valueStackView.alignment = .trailing
        stackView.addArrangedSubview(valueStackView)

        balanceLabel = UILabel()
        balanceLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceLabel.font = .dw_font(forTextStyle: .footnote)
        balanceLabel.textColor = .dw_label()
        balanceLabel.textAlignment = .right
        valueStackView.addArrangedSubview(balanceLabel)

        fiatBalanceLabel = UILabel()
        fiatBalanceLabel.translatesAutoresizingMaskIntoConstraints = false
        fiatBalanceLabel.font = .dw_font(forTextStyle: .footnote)
        fiatBalanceLabel.textColor = .dw_secondaryText()
        fiatBalanceLabel.textAlignment = .right
        valueStackView.addArrangedSubview(fiatBalanceLabel)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.widthAnchor.constraint(equalToConstant: 34),
            imageView.heightAnchor.constraint(equalToConstant: 34),
        ])
    }
}
