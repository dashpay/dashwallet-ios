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

extension UIButton.Configuration {
    public static func image(asset: UIImage) -> UIButton.Configuration {
        var style = UIButton.Configuration.plain()

        var background = style.background
        background.image = asset

        style.background = background
        return style
    }

    public static func dashPlain(title: String? = nil, font: UIFont? = nil) -> UIButton.Configuration {
        configuration(from: .plain(), with: title, and: font)
    }

    public static var tinted: UIButton.Configuration {
        var configuration = configuration(from: .tinted(), with: nil, and: nil)
        configuration.baseForegroundColor = .dw_dashBlue()

        var background = configuration.background
        background.backgroundColor = UIColor.dw_dashBlue().withAlphaComponent(0.08)
        configuration.background = background

        var attributedTitle = configuration.attributedTitle
        attributedTitle?.foregroundColor = configuration.baseForegroundColor
        configuration.attributedTitle = attributedTitle

        return configuration
    }

    public static func action(title: String? = nil, font: UIFont? = nil) -> UIButton.Configuration {
        var configuration = configuration(from: .filled(), with: title, and: font)

        var background = configuration.background
        background.cornerRadius = 8

        configuration.background = background
        return configuration
    }

    public static func configuration(from configuration: UIButton.Configuration, with title: String?, and font: UIFont?) -> UIButton.Configuration {
        var style = configuration
        style.imagePadding = 10

        var background = style.background
        background.cornerRadius = 6

        style.background = background

        if let font {
            var attributes = AttributeContainer()
            attributes.foregroundColor = style.baseForegroundColor
            attributes.font = font

            let attributedString = AttributedString(title ?? "", attributes: attributes)

            style.attributedTitle = attributedString
        } else if let title {
            style.title = title
        }

        return style
    }

    var font: UIFont {
        set {
            var attributes = AttributeContainer()
            attributes.foregroundColor = baseForegroundColor
            attributes.font = font ?? .dw_font(forTextStyle: .body)

            let attributedString = AttributedString(title ?? "", attributes: attributes)
            attributedTitle = attributedString
        }

        get {
            attributedTitle?.font ?? .dw_font(forTextStyle: .footnote)
        }
    }

    public func settingFont(_ font: UIFont) -> UIButton.Configuration {
        var configuration = self

        var attributes = AttributeContainer()
        attributes.foregroundColor = configuration.baseForegroundColor
        attributes.font = font

        let attributedString = AttributedString(configuration.title ?? "", attributes: attributes)
        configuration.attributedTitle = attributedString

        return configuration
    }
}

// MARK: - TintedButton

class TintedButton: DashButton {
    init() {
        super.init(configuration: .tinted)

        tintColor = .dw_dashBlue()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func updateConfiguration() {
        super.updateConfiguration()

        guard let configuration else {
            return
        }

        var updatedConfiguration = configuration

        var background = configuration.background

        var foregroundColor: UIColor?
        var backgroundColor: UIColor?

        switch state {
        case .normal:
            backgroundColor = tintColor.withAlphaComponent(0.08)
            foregroundColor = tintColor
        case .highlighted:
            backgroundColor = tintColor.withAlphaComponent(0.06)
            foregroundColor = tintColor.withAlphaComponent(0.9)
        case .disabled:
            backgroundColor = .dw_disabledButton()
            foregroundColor = .dw_disabledButtonText()
        default:
            backgroundColor = tintColor.withAlphaComponent(0.08)
            foregroundColor = tintColor
        }

        background.backgroundColorTransformer = UIConfigurationColorTransformer { _ in
            backgroundColor ?? .clear
        }

        updatedConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in

            var container = incoming
            container.foregroundColor = foregroundColor

            return container
        }

        updatedConfiguration.background = background
        self.configuration = updatedConfiguration
    }
}

// MARK: - ImageButton

final class ImageButton: UIButton {
    init(image: UIImage) {
        super.init(frame: .zero)
        configuration = .image(asset: image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


// MARK: - ActionButton

@objc(DWActionButton)
class ActionButton: DashButton {
    final class ActivityIndicatorView: UIView {
        var color: UIColor {
            set {
                activityIndicator.color = newValue
            }
            get {
                activityIndicator.color
            }
        }

        private let activityIndicator: UIActivityIndicatorView!

        override init(frame: CGRect) {
            activityIndicator = UIActivityIndicatorView(style: .medium)
            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
            activityIndicator.hidesWhenStopped = false
            activityIndicator.color = .white

            super.init(frame: frame)

            addSubview(activityIndicator)
            NSLayoutConstraint.activate([
                activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
                activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func start() {
            activityIndicator.startAnimating()
        }

        public func stop() {
            activityIndicator.stopAnimating()
        }
    }

    public var accentColor: UIColor = .dw_dashBlue() {
        didSet {
            setNeedsUpdateConfiguration()
        }
    }

    @objc
    init() {
        super.init(configuration: .action())
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        var actionConfiguration: UIButton.Configuration = .action()

        if let configuration {
            actionConfiguration.title = configuration.title
            actionConfiguration.baseForegroundColor = configuration.baseForegroundColor
            actionConfiguration.baseBackgroundColor = configuration.baseBackgroundColor
        }

        configuration = actionConfiguration
    }

    private var activityIndicatorView: ActivityIndicatorView!
    private var showsActivityIndicator = false

    @objc
    public func showActivityIndicator() {
        if activityIndicatorView == nil {
            activityIndicatorView = ActivityIndicatorView()
        }

        activityIndicatorView.start()

        isEnabled = false
        showsActivityIndicator = true
        setNeedsUpdateConfiguration()
    }

    @objc
    public func hideActivityIndicator() {
        activityIndicatorView?.stop()

        isEnabled = true
        showsActivityIndicator = false
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration() {
        guard let configuration else {
            return
        }

        var updatedConfiguration = configuration

        var background = configuration.background

        var strokeWidth: CGFloat = 0
        var strokeColor: UIColor?
        var foregroundColor: UIColor?
        var backgroundColor: UIColor?

        switch state {
        case .normal:
            backgroundColor = accentColor
            foregroundColor = .white
        case .highlighted:
            strokeWidth = 1
            strokeColor = accentColor
            foregroundColor = accentColor
        case .disabled:
            backgroundColor = .dw_disabledButton()
            foregroundColor = .dw_disabledButtonText()
        default:
            backgroundColor = accentColor
            foregroundColor = .white
        }

        if showsActivityIndicator {
            // Use custom background to show activity indicator instead of updatedConfiguration.showsActivityIndicator property
            // Using updatedConfiguration.showsActivityIndicator doesn't hide the title label and we can't center the activity indicator
            activityIndicatorView.color = state == .normal ? .white : .darkGray
            background.customView = activityIndicatorView
            foregroundColor = .clear
        } else {
            background.customView = nil
        }

        background.strokeWidth = strokeWidth
        background.strokeColor = strokeColor

        background.backgroundColorTransformer = UIConfigurationColorTransformer { _ in
            backgroundColor ?? .clear
        }

        updatedConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in

            var container = incoming
            container.foregroundColor = foregroundColor

            return container
        }

        updatedConfiguration.background = background
        self.configuration = updatedConfiguration
    }
}

// MARK: - DashButton

class DashButton: UIButton {
    /// Configures the title label font.
    /// A nil value uses the default button's font: `UIFont.dw_font(forTextStyle: .body)`
    public var titleLabelFont: UIFont? {
        didSet {
            setNeedsUpdateConfiguration()
        }
    }

    convenience init() {
        self.init(configuration: .dashPlain())
    }

    init(configuration: UIButton.Configuration = UIButton.Configuration.dashPlain()) {
        super.init(frame: .zero)

        self.configuration = configuration
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        if let configuration {
            self.configuration = UIButton.Configuration.configuration(from: configuration, with: nil, and: nil)
        } else {
            configuration = .dashPlain()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureButton()
    }

    override func updateConfiguration() {
        guard let configuration else {
            return
        }

        if let titleLabelFont {
            var updatedConfiguration = configuration

            var attributes = AttributeContainer()
            attributes.foregroundColor = updatedConfiguration.baseForegroundColor
            attributes.font = titleLabelFont

            updatedConfiguration.attributedTitle = AttributedString(updatedConfiguration.title ?? "", attributes: attributes)
            self.configuration = updatedConfiguration
        }
    }

    private func configureButton() {
        // Dynamic type support
        titleLabel?.adjustsFontForContentSizeCategory = true
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.5
        titleLabel?.lineBreakMode = .byClipping

        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsLayout), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
